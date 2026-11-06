extends Node3D

var enemy_scene    := preload("res://scenes/enemy/enemy.tscn")
var paper_scene    := preload("res://scenes/enemy_paper/enemy_paper.tscn")
var biplane_scene  := preload("res://scenes/enemy_biplane/enemy_biplane.tscn")
var bomber_scene   := preload("res://scenes/enemy_bomber/enemy_bomber.tscn")
var balloon_scene  := preload("res://scenes/balloon/balloon.tscn")
var zeppelin_scene := preload("res://scenes/zeppelin/zeppelin.tscn")
var ship_scene     := preload("res://scenes/ship/ship.tscn")

# Distribución del spawn continuo: 10 papeles, 6 jets, 5 biplanos, 4 bombarderos
var _enemy_pool    : Array = []

const MAX_ENEMIES    := 50
const SPAWN_INTERVAL := 2.0
const SPAWN_RADIUS   := 600.0

var player         : Node3D
var spawn_timer    : float = SPAWN_INTERVAL
var active_enemies : Array[Node3D] = []
var _osm           : Node3D = null
var total_kills    : int   = 0

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	player = $Player
	player.health_changed.connect($HUD.update_health)
	player.score_changed.connect($HUD.update_score)
	player.aircraft_destroyed.connect(_on_player_destroyed)

	var joypads := Input.get_connected_joypads()
	if joypads.size() > 0:
		print("Joystick conectado: %s" % Input.get_joy_name(0))
	else:
		print("Sin joystick – controles de teclado activos (↑↓←→ + W/S + Espacio)")

	_setup_ocean()
	_spawn_runway()
	# _spawn_islands() — reemplazado por mapa OSM real
	_spawn_clouds()

	# Sistema de tiles OpenStreetMap
	_osm = preload("res://scenes/world/osm_tiles.gd").new()
	_osm.name = "OSMTiles"
	add_child(_osm)
	_osm.initialized.connect(_on_osm_ready)

	# Pool de tipos para spawn continuo (ponderado)
	for _i in 10: _enemy_pool.append("paper")
	for _i in 6:  _enemy_pool.append("jet")
	for _i in 5:  _enemy_pool.append("biplane")
	for _i in 4:  _enemy_pool.append("bomber")

	# Spawn inicial: 25 enemigos distribuidos uniformemente
	var init_types := ["paper","paper","paper","paper","paper",
					   "paper","paper","paper","paper","paper",
					   "jet","jet","jet","jet","jet","jet",
					   "biplane","biplane","biplane","biplane","biplane",
					   "bomber","bomber","bomber","bomber"]
	for i in init_types.size():
		_spawn_enemy_typed(init_types[i], i * TAU / float(init_types.size()))
	for i in 8:
		_spawn_balloon()
	for i in 6:
		_spawn_zeppelin()
	for i in 4:
		_spawn_ship()

func _on_osm_ready(_lat: float, _lon: float) -> void:
	# Ocultar océano una vez que los tiles OSM están listos
	var gm := $Ground/GroundMesh as MeshInstance3D
	if is_instance_valid(gm):
		gm.visible = false

func _process(delta: float) -> void:
	_follow_camera(delta)
	spawn_timer -= delta
	if spawn_timer <= 0.0 and active_enemies.size() < MAX_ENEMIES:
		var t : String = _enemy_pool[randi() % _enemy_pool.size()]
		_spawn_enemy_typed(t, -1.0)
		spawn_timer = SPAWN_INTERVAL

func _follow_camera(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var behind     := player.global_transform.basis.z * 16.0
	var target_pos := player.global_position + behind + Vector3(0.0, 4.5, 0.0)
	camera.global_position = camera.global_position.lerp(target_pos, delta * 5.0)
	camera.look_at(player.global_position + Vector3(0.0, 1.5, 0.0), Vector3.UP)

func _setup_ocean() -> void:
	var plane := $Ground/GroundMesh as MeshInstance3D
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(4000, 4000)
	mesh.subdivide_width = 80
	mesh.subdivide_depth = 80
	plane.mesh = mesh

	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float wave_speed  : hint_range(0.0, 2.0)  = 0.5;
uniform float wave_height : hint_range(0.0, 10.0) = 2.5;
uniform float wave_scale  : hint_range(0.001, 0.05) = 0.012;
uniform vec4  water_deep    : source_color = vec4(0.02, 0.15, 0.40, 1.0);
uniform vec4  water_shallow : source_color = vec4(0.08, 0.50, 0.82, 1.0);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.06;

void vertex() {
	float t  = TIME * wave_speed;
	float px = VERTEX.x;
	float pz = VERTEX.z;
	float w  = sin(px * wave_scale + t) * cos(pz * wave_scale * 0.7 + t * 0.8)
	         + sin(px * wave_scale * 1.3 - t * 0.9) * cos(pz * wave_scale + t * 0.6)
	         + sin((px + pz) * wave_scale * 0.6 + t * 1.3) * 0.5;
	VERTEX.y += w * wave_height;
}

void fragment() {
	float t   = TIME * wave_speed;
	vec2  uv1 = UV * 150.0;
	vec2  uv2 = UV * 60.0;
	float nx  = sin(uv1.x + t * 1.6) * 0.22 + sin(uv2.x + uv2.y * 0.7 + t * 0.9) * 0.18;
	float nz  = cos(uv1.y - t * 1.2) * 0.22 + cos(uv2.y - uv2.x * 0.5 - t * 0.7) * 0.18;
	NORMAL_MAP       = normalize(vec3(nx, nz, 1.0));
	NORMAL_MAP_DEPTH = 1.5;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	ALBEDO    = mix(water_deep.rgb, water_shallow.rgb, fresnel * 0.6 + 0.08);
	ROUGHNESS = roughness_val;
	METALLIC  = 0.1;
	SPECULAR  = 0.9;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	plane.set_surface_override_material(0, mat)

func _spawn_runway() -> void:
	# Base de tierra / roca
	var base_mi   := MeshInstance3D.new()
	add_child(base_mi)
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(260, 8, 700)
	base_mi.mesh   = base_mesh
	base_mi.global_position = Vector3(0, -1.0, 0)
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.52, 0.47, 0.40)
	base_mat.roughness    = 0.95
	base_mi.set_surface_override_material(0, base_mat)

	# Asfalto
	var asph_mi   := MeshInstance3D.new()
	add_child(asph_mi)
	var asph_mesh := BoxMesh.new()
	asph_mesh.size = Vector3(50, 0.5, 660)
	asph_mi.mesh   = asph_mesh
	asph_mi.global_position = Vector3(0, 3.25, 0)
	var asph_mat := StandardMaterial3D.new()
	asph_mat.albedo_color = Color(0.13, 0.13, 0.15)
	asph_mat.roughness    = 0.92
	asph_mi.set_surface_override_material(0, asph_mat)

	# Líneas centrales (rayas blancas)
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(2.0, 0.1, 25.0)
	var stripe_mat := StandardMaterial3D.new()
	stripe_mat.albedo_color = Color(0.95, 0.95, 0.9)
	for i in 12:
		var s := MeshInstance3D.new()
		add_child(s)
		s.mesh = stripe_mesh
		s.set_surface_override_material(0, stripe_mat)
		s.global_position = Vector3(0, 3.55, -275.0 + i * 50.0)

func _spawn_islands() -> void:
	var positions : Array[Vector3] = [
		Vector3( 500, 0,  300), Vector3(-400, 0,  500),
		Vector3( 800, 0, -200), Vector3(-600, 0, -400),
		Vector3( 300, 0, -700), Vector3(-800, 0,  100),
		Vector3( 200, 0,  900), Vector3(-300, 0, -800),
		Vector3(1000, 0,  500), Vector3(-900, 0,  600),
		Vector3( 600, 0, -900), Vector3(-500, 0, 1000),
	]
	for pos in positions:
		_create_island(pos)

func _create_island(pos: Vector3) -> void:
	var island := Node3D.new()
	add_child(island)
	island.global_position = pos

	var rx : float = randf_range(40.0, 90.0)
	var ry : float = randf_range(15.0, 35.0)

	# Rocky base
	var rock_mi   := MeshInstance3D.new()
	island.add_child(rock_mi)
	var rock_mesh := CylinderMesh.new()
	rock_mesh.top_radius    = rx * 0.25
	rock_mesh.bottom_radius = rx
	rock_mesh.height        = ry
	rock_mi.mesh = rock_mesh
	rock_mi.position.y = ry * 0.5
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.44, 0.38, 0.30)
	rock_mi.set_surface_override_material(0, rock_mat)

	# Vegetation cap
	var top_mi   := MeshInstance3D.new()
	island.add_child(top_mi)
	var top_mesh := SphereMesh.new()
	top_mesh.radius = rx * 0.38
	top_mesh.height = rx * 0.5
	top_mi.mesh = top_mesh
	top_mi.position.y = ry
	var top_mat := StandardMaterial3D.new()
	top_mat.albedo_color = Color(0.18, 0.52, 0.12)
	top_mi.set_surface_override_material(0, top_mat)

func _spawn_clouds() -> void:
	var cloud_node := GPUParticles3D.new()
	add_child(cloud_node)
	cloud_node.position     = Vector3(0, 290, 0)
	cloud_node.amount       = 60
	cloud_node.lifetime     = 90.0
	cloud_node.one_shot     = false
	cloud_node.explosiveness = 0.0
	cloud_node.randomness   = 0.5

	var ppm := ParticleProcessMaterial.new()
	ppm.emission_shape      = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	ppm.emission_box_extents = Vector3(1500, 15, 1500)
	ppm.direction           = Vector3(1, 0, 0)
	ppm.spread              = 5.0
	ppm.initial_velocity_min = 1.5
	ppm.initial_velocity_max = 4.0
	ppm.gravity             = Vector3.ZERO
	ppm.scale_min           = 50.0
	ppm.scale_max           = 120.0
	cloud_node.process_material = ppm

	var cloud_mesh := SphereMesh.new()
	cloud_mesh.radius          = 1.0
	cloud_mesh.height          = 0.5
	cloud_mesh.radial_segments = 8
	cloud_mesh.rings           = 4
	var cloud_mat := StandardMaterial3D.new()
	cloud_mat.albedo_color  = Color(1.0, 1.0, 1.0, 0.65)
	cloud_mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	cloud_mat.cull_mode     = BaseMaterial3D.CULL_DISABLED
	cloud_mesh.material     = cloud_mat
	cloud_node.draw_pass_1  = cloud_mesh
	cloud_node.emitting     = true

func _spawn_enemy_typed(type: String, forced_angle: float) -> void:
	if not is_instance_valid(player):
		return
	var scene : PackedScene
	match type:
		"paper":   scene = paper_scene
		"biplane": scene = biplane_scene
		"bomber":  scene = bomber_scene
		_:         scene = enemy_scene
	var enemy : Node3D = scene.instantiate()
	add_child(enemy)
	var angle := forced_angle if forced_angle >= 0.0 else randf() * TAU
	var alt_min := 10.0 if type == "paper" else 40.0
	var alt_max := 60.0 if type == "paper" else 150.0
	enemy.global_position = player.global_position + Vector3(
		cos(angle) * SPAWN_RADIUS,
		randf_range(alt_min, alt_max),
		sin(angle) * SPAWN_RADIUS
	)
	enemy.set_target(player)
	enemy.destroyed.connect(_on_enemy_destroyed)
	active_enemies.append(enemy)

func _on_enemy_destroyed(pts: int) -> void:
	if is_instance_valid(player):
		player.add_score(pts)
	active_enemies = active_enemies.filter(func(e): return is_instance_valid(e))
	total_kills += 1
	$HUD.update_kills(total_kills)

func _on_target_destroyed(pts: int) -> void:
	if is_instance_valid(player):
		player.add_score(pts)
	total_kills += 1
	$HUD.update_kills(total_kills)

func _spawn_balloon() -> void:
	if not is_instance_valid(player):
		return
	var b : Node3D = balloon_scene.instantiate()
	add_child(b)
	var angle := randf() * TAU
	var radius := randf_range(150.0, 600.0)
	b.global_position = player.global_position + Vector3(
		cos(angle) * radius, randf_range(70.0, 220.0), sin(angle) * radius)
	b.destroyed.connect(_on_target_destroyed)

func _spawn_zeppelin() -> void:
	if not is_instance_valid(player):
		return
	var z : Node3D = zeppelin_scene.instantiate()
	add_child(z)
	var angle := randf() * TAU
	var radius := randf_range(300.0, 700.0)
	z.global_position = player.global_position + Vector3(
		cos(angle) * radius, randf_range(140.0, 300.0), sin(angle) * radius)
	z.destroyed.connect(_on_target_destroyed)

func _spawn_ship() -> void:
	if not is_instance_valid(player):
		return
	var s : Node3D = ship_scene.instantiate()
	add_child(s)
	var angle := randf() * TAU
	var radius := randf_range(400.0, 1000.0)
	s.global_position = Vector3(
		player.global_position.x + cos(angle) * radius,
		2.5,
		player.global_position.z + sin(angle) * radius)
	s.destroyed.connect(_on_target_destroyed)

func _on_player_destroyed() -> void:
	$HUD.show_game_over()
	await get_tree().create_timer(3.0).timeout
	get_tree().reload_current_scene()
