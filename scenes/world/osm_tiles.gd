extends Node3D

## Carga tiles de OpenStreetMap centrados en la ubicación real del usuario.
## Detecta coordenadas automáticamente vía IP (ip-api.com, gratis, sin clave).
## Caché en disco: user://osm_cache/   — evita re-descargar en partidas futuras.

signal initialized(lat: float, lon: float)

# ── Constantes ────────────────────────────────────────────────────────────────
const ZOOM      : int    = 16         # detalle: ~540m/tile a lat 28°
const GRID_SZ   : int    = 7          # 7×7 tiles activos (3 anillos alrededor del jugador)
const TILE_Y    : float  = 0.5        # altura sobre el océano
const MAX_HTTP  : int    = 4          # peticiones HTTP simultáneas
const GEO_URL   : String = "http://ip-api.com/json/?fields=lat,lon,status"
const TILE_HOST : String = "https://tile.openstreetmap.org"
const CACHE_DIR : String = "user://osm_cache"
const UA        : String = "CombateAereoGame/1.0 (Godot4)"

# ── Estado ────────────────────────────────────────────────────────────────────
var _lat        : float = 28.0
var _lon        : float = -15.4
var _origin_tx  : int   = 0
var _origin_ty  : int   = 0
var _tile_m     : float = 540.0   # unidades de mundo por tile (calculado)
var _ready_flag : bool  = false

# Malla de MeshInstance3D — [row][col]
var _meshes : Array = []
var _shown  : Array = []          # Vector2i(tx, ty) mostrado en cada celda

# Centro actual de la rejilla (en coordenadas de tile OSM)
var _cx : int = 0
var _cy : int = 0

# Pool HTTP reutilizable
var _pool     : Array[HTTPRequest] = []
var _busy     : Array[bool]        = []
var _queue    : Array              = []   # Array de Dictionary {tx,ty,row,col}
var _inflight : Dictionary         = {}   # clave → true  (evita duplicados)
var _tex_mem  : Dictionary         = {}   # clave → ImageTexture  (caché en RAM)

var _placeholder : StandardMaterial3D

# ── _ready ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("osm_tiles")
	_placeholder = StandardMaterial3D.new()
	_placeholder.albedo_color = Color(0.30, 0.38, 0.28)
	_placeholder.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Crear malla de tiles (ocultos hasta saber la escala)
	for row in GRID_SZ:
		_meshes.append([])
		_shown.append([])
		for col in GRID_SZ:
			var pm   := PlaneMesh.new()
			pm.size   = Vector2(1.0, 1.0)
			var mi   := MeshInstance3D.new()
			mi.mesh   = pm
			mi.visible = false
			mi.set_surface_override_material(0, _placeholder)
			add_child(mi)
			_meshes[row].append(mi)
			_shown[row].append(Vector2i(-999999, -999999))

	# Pool HTTP
	for i in MAX_HTTP:
		var h := HTTPRequest.new()
		h.use_threads = true
		h.timeout      = 12.0
		add_child(h)
		_pool.append(h)
		_busy.append(false)

	# Crear directorio de caché
	var dir := DirAccess.open("user://")
	if dir:
		dir.make_dir_recursive("osm_cache")

	# Pedir coordenadas
	_fetch_location()

# ── Geolocalización por IP ────────────────────────────────────────────────────
func _fetch_location() -> void:
	var geo := HTTPRequest.new()
	geo.use_threads = true
	geo.timeout      = 8.0
	add_child(geo)
	geo.request_completed.connect(_on_geo.bind(geo))
	if geo.request(GEO_URL, PackedStringArray(["User-Agent: " + UA])) != OK:
		_init_map()   # sin internet → coordenadas por defecto

func _on_geo(result: int, code: int, _h: PackedStringArray,
			 body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var d = json.get_data()
			if d is Dictionary and d.get("status", "") == "success":
				_lat = float(d.get("lat", 28.0))
				_lon = float(d.get("lon", -15.4))
				print("OSM: posición detectada → lat=%.4f lon=%.4f" % [_lat, _lon])
			else:
				print("OSM: geolocalización no disponible, usando lat=%.1f lon=%.1f" % [_lat, _lon])
	_init_map()

# ── Inicializar mapa ──────────────────────────────────────────────────────────
func _init_map() -> void:
	var n      : float = pow(2.0, float(ZOOM))
	_origin_tx = int(floor((_lon + 180.0) / 360.0 * n))
	var lat_r  : float = deg_to_rad(_lat)
	_origin_ty = int(floor((1.0 - log(tan(lat_r) + (1.0 / cos(lat_r))) / PI) / 2.0 * n))

	# Metros de mundo por tile (mercator web)
	var mpp : float = 156543.03392 * cos(lat_r) / n
	_tile_m = mpp * 256.0

	_cx = _origin_tx
	_cy = _origin_ty
	_ready_flag = true
	initialized.emit(_lat, _lon)
	_refresh_all()

# ── Proceso ───────────────────────────────────────────────────────────────────
func _process(_dt: float) -> void:
	if not _ready_flag:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if not is_instance_valid(player):
		return

	# Tile del jugador (centro del tile = floor de pos / tile_m)
	var ptx : int = _origin_tx + int(floor(player.global_position.x / _tile_m))
	var pty : int = _origin_ty + int(floor(player.global_position.z / _tile_m))
	if ptx != _cx or pty != _cy:
		_cx = ptx
		_cy = pty
		_refresh_all()

	_pump_queue()

func _pump_queue() -> void:
	for i in MAX_HTTP:
		if not _busy[i] and not _queue.is_empty():
			var req : Dictionary = _queue.pop_front()
			_fetch_tile(req["tx"], req["ty"], req["row"], req["col"], i)

# ── Rejilla ───────────────────────────────────────────────────────────────────
func _refresh_all() -> void:
	var half : int = GRID_SZ / 2
	for row in GRID_SZ:
		for col in GRID_SZ:
			var tx : int = _cx + col - half
			var ty : int = _cy + row - half
			var cur      = _shown[row][col]
			if cur == Vector2i(tx, ty):
				continue

			var mi : MeshInstance3D = _meshes[row][col]
			mi.scale    = Vector3(_tile_m, 1.0, _tile_m)
			mi.position = Vector3(
				(float(tx - _origin_tx) + 0.5) * _tile_m,
				TILE_Y,
				(float(ty - _origin_ty) + 0.5) * _tile_m
			)
			mi.visible  = true
			_shown[row][col] = Vector2i(tx, ty)

			var key := _key(tx, ty)

			# 1. Caché en memoria
			if _tex_mem.has(key):
				_apply_tex(mi, _tex_mem[key])
				continue

			# 2. Caché en disco
			var cpath := "%s/%s.png" % [CACHE_DIR, key]
			if FileAccess.file_exists(cpath):
				var img : Image = Image.load_from_file(cpath)
				if img:
					var tex := ImageTexture.create_from_image(img)
					_tex_mem[key] = tex
					_apply_tex(mi, tex)
					continue

			# 3. Descargar
			mi.set_surface_override_material(0, _placeholder)
			if not _inflight.has(key):
				_inflight[key] = true
				_queue.append({"tx": tx, "ty": ty, "row": row, "col": col})

# ── HTTP ──────────────────────────────────────────────────────────────────────
func _fetch_tile(tx: int, ty: int, row: int, col: int, idx: int) -> void:
	_busy[idx] = true
	var url     := "%s/%d/%d/%d.png" % [TILE_HOST, ZOOM, tx, ty]
	var headers := PackedStringArray(["User-Agent: " + UA])
	_pool[idx].request_completed.connect(
		_on_tile.bind(tx, ty, row, col, idx), CONNECT_ONE_SHOT)
	_pool[idx].request(url, headers)

func _on_tile(result: int, code: int, _h: PackedStringArray, body: PackedByteArray,
			  tx: int, ty: int, row: int, col: int, idx: int) -> void:
	_busy[idx] = false
	var key := _key(tx, ty)
	_inflight.erase(key)

	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return

	var img := Image.new()
	if img.load_png_from_buffer(body) != OK:
		return

	# Guardar en disco
	img.save_png("%s/%s.png" % [CACHE_DIR, key])

	# Guardar en RAM
	var tex := ImageTexture.create_from_image(img)
	_tex_mem[key] = tex

	# Aplicar si la celda sigue mostrando este tile
	if row < GRID_SZ and col < GRID_SZ:
		if _shown[row][col] == Vector2i(tx, ty):
			_apply_tex(_meshes[row][col], tex)

func _apply_tex(mi: MeshInstance3D, tex: ImageTexture) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mi.set_surface_override_material(0, mat)

func _key(tx: int, ty: int) -> String:
	return "%d_%d_%d" % [ZOOM, tx, ty]

# ── API pública ───────────────────────────────────────────────────────────────
func get_coords() -> Vector2:
	return Vector2(_lat, _lon)

func get_tile_meters() -> float:
	return _tile_m
