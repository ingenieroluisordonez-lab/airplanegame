extends CharacterBody3D

# --- Mapeo de ejes del AV8R-01 ---
const JOY_DEVICE    := 0
const JOY_AILERON   := 0
const JOY_ELEVATOR  := 1
const JOY_RUDDER    := 2
const JOY_THROTTLE  := 3
const JOY_DEADZONE  := 0.08

# --- Parámetros de vuelo ---
@export var max_speed      : float = 250.0
@export var min_speed      : float = 45.0
@export var pitch_rate     : float = 1.3
@export var roll_rate      : float = 2.2
@export var yaw_rate       : float = 0.5
@export var throttle_speed : float = 1.2

# --- Armas: cañón ---
@export var fire_cooldown : float = 0.11
var _fire_timer           : float = 0.0
var bullet_scene     := preload("res://scenes/bullet/bullet.tscn")
var explosion_scene  := preload("res://scenes/explosion/explosion.tscn")

# --- Armas: misiles ---
@export var max_missiles      : int   = 4
@export var missile_lock_time : float = 1.5
@export var missile_cooldown  : float = 1.2
var missile_scene    := preload("res://scenes/missile/missile.tscn")
var _missiles_left   : int   = 4
var _lock_timer      : float = 0.0
var _missile_cd      : float = 0.0
var _locked_target   : Node3D = null
var _missile_mounts  : Array[Node3D] = []
var _mount_index     : int = 0

# --- Audio ---
var _snd_engine  : AudioStreamPlayer
var _snd_shoot   : AudioStreamPlayer
var _snd_hit     : AudioStreamPlayer
var _snd_missile : AudioStreamPlayer

# --- Efectos visuales ---
var _afterburner_light : OmniLight3D
var _exhaust_particles : GPUParticles3D

# --- Estado ---
const TAKEOFF_SPEED       : float = 65.0
const RUNWAY_Y            : float = 4.1
const ENGINE_START_DELAY  : float = 1.5

var speed        : float = 0.0
var throttle     : float = 0.0
var health       : int   = 100
var score        : int   = 0
var on_ground    : bool  = true
var engine_on    : bool  = false
var _eng_startup : float = 0.0
var _start_held  : bool  = false  # debounce arranque

signal health_changed(value: int)
signal score_changed(value: int)
signal aircraft_destroyed

func _ready() -> void:
	add_to_group("player")
	_setup_sounds()
	_setup_visual_effects()
	_setup_missiles()
	_setup_model_detail()

func _setup_sounds() -> void:
	var base := ProjectSettings.globalize_path("res://assets/sounds/")

	var eng_stream := AudioStreamOggVorbis.load_from_file(base + "engine.ogg")
	if eng_stream:
		eng_stream.loop = true
		_snd_engine = AudioStreamPlayer.new()
		_snd_engine.stream      = eng_stream
		_snd_engine.pitch_scale = 0.3
		_snd_engine.volume_db   = -80.0  # silencioso hasta arrancar
		add_child(_snd_engine)
		# No se reproduce aún — _start_engine() lo activa

	var shoot_stream := AudioStreamOggVorbis.load_from_file(base + "shoot.ogg")
	if shoot_stream:
		_snd_shoot = AudioStreamPlayer.new()
		_snd_shoot.stream    = shoot_stream
		_snd_shoot.volume_db = -4.0
		add_child(_snd_shoot)

	var hit_stream := AudioStreamOggVorbis.load_from_file(base + "hit.ogg")
	if hit_stream:
		_snd_hit = AudioStreamPlayer.new()
		_snd_hit.stream    = hit_stream
		_snd_hit.volume_db = 0.0
		add_child(_snd_hit)

	var m_path   := base + "shoot2.ogg"
	var m_stream := AudioStreamOggVorbis.load_from_file(m_path)
	if not m_stream:
		m_stream = AudioStreamOggVorbis.load_from_file(base + "shoot.ogg")
	if m_stream:
		_snd_missile = AudioStreamPlayer.new()
		_snd_missile.stream    = m_stream
		_snd_missile.volume_db = 2.0
		add_child(_snd_missile)

func _setup_visual_effects() -> void:
	_afterburner_light = OmniLight3D.new()
	add_child(_afterburner_light)
	_afterburner_light.position      = Vector3(0, 0, 5.5)
	_afterburner_light.light_color   = Color(1.0, 0.5, 0.1)
	_afterburner_light.light_energy  = 0.0  # apagado al inicio
	_afterburner_light.omni_range    = 15.0
	_afterburner_light.shadow_enabled = false

	var ppm := ParticleProcessMaterial.new()
	ppm.direction            = Vector3(0, 0, 1)
	ppm.spread               = 10.0
	ppm.initial_velocity_min = 20.0
	ppm.initial_velocity_max = 45.0
	ppm.gravity              = Vector3.ZERO
	ppm.scale_min            = 0.25
	ppm.scale_max            = 0.7
	ppm.color                = Color(1.0, 0.55, 0.1, 0.8)

	var ex_mesh := SphereMesh.new()
	ex_mesh.radius = 0.2
	ex_mesh.height = 0.4
	var ex_mat := StandardMaterial3D.new()
	ex_mat.albedo_color               = Color(1.0, 0.5, 0.1, 0.5)
	ex_mat.emission_enabled           = true
	ex_mat.emission                   = Color(1.0, 0.4, 0.0)
	ex_mat.emission_energy_multiplier = 5.0
	ex_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	ex_mat.cull_mode                  = BaseMaterial3D.CULL_DISABLED
	ex_mesh.material                  = ex_mat

	_exhaust_particles = GPUParticles3D.new()
	add_child(_exhaust_particles)
	_exhaust_particles.position         = Vector3(0, 0, 5.5)
	_exhaust_particles.amount           = 15
	_exhaust_particles.lifetime         = 0.4
	_exhaust_particles.local_coords     = false
	_exhaust_particles.one_shot         = false
	_exhaust_particles.process_material = ppm
	_exhaust_particles.draw_pass_1      = ex_mesh
	_exhaust_particles.emitting         = false  # apagado al inicio

func _setup_missiles() -> void:
	var offsets := [Vector3(-3.5, -0.4, 0.0), Vector3(3.5, -0.4, 0.0),
	                Vector3(-2.5, -0.4, 0.0), Vector3(2.5, -0.4, 0.0)]
	for off in offsets:
		var mount := Node3D.new()
		add_child(mount)
		mount.position = off
		_missile_mounts.append(mount)

# ───────── Bucle principal ─────────

func _physics_process(delta: float) -> void:
	if not engine_on:
		var p := _start_input_pressed()
		if p and not _start_held:
			_start_engine()
		_start_held = p
		_update_engine_startup(delta)
		return
	_start_held = false
	_read_input(delta)
	_move(delta)
	_fire_timer -= delta
	_missile_cd -= delta
	_update_lock(delta)

func _start_input_pressed() -> bool:
	if Input.is_physical_key_pressed(KEY_ENTER):   return true
	if Input.is_physical_key_pressed(KEY_KP_ENTER): return true
	if Input.is_physical_key_pressed(KEY_SPACE):   return true
	var jpads := Input.get_connected_joypads().size()
	if jpads > 0:
		for i in 8:
			if Input.is_joy_button_pressed(JOY_DEVICE, i):
				return true
	return false

# ───────── Motor ─────────

func _start_engine() -> void:
	if engine_on or _eng_startup > 0.0:
		return
	_eng_startup = 0.001
	if is_instance_valid(_snd_engine):
		_snd_engine.pitch_scale = 0.3
		_snd_engine.volume_db   = -18.0
		_snd_engine.play()

func _update_engine_startup(delta: float) -> void:
	if _eng_startup <= 0.0:
		return
	_eng_startup += delta
	var t : float = clamp(_eng_startup / ENGINE_START_DELAY, 0.0, 1.0)
	if is_instance_valid(_snd_engine):
		_snd_engine.pitch_scale = lerp(0.3, 0.8, t)
		_snd_engine.volume_db   = lerp(-18.0, -6.0, t)
	if _eng_startup >= ENGINE_START_DELAY:
		engine_on    = true
		_eng_startup = 0.0
		if is_instance_valid(_exhaust_particles):
			_exhaust_particles.emitting = true

# ───────── Entrada ─────────

func _update_lock(delta: float) -> void:
	if on_ground:
		_locked_target = null
		_lock_timer    = 0.0
		return
	var camera := get_viewport().get_camera_3d()
	if not is_instance_valid(camera):
		return
	var vp_size   := get_viewport().get_visible_rect().size
	var best      : Node3D = null
	var best_dist := INF
	var all_targets : Array = get_tree().get_nodes_in_group("enemy") + get_tree().get_nodes_in_group("target")
	for e in all_targets:
		if not is_instance_valid(e):
			continue
		var ep := e as Node3D
		if not camera.is_position_in_frustum(ep.global_position):
			continue
		var sp   := camera.unproject_position(ep.global_position)
		var dist := (sp - vp_size * 0.5).length()
		var d3   := ep.global_position.distance_to(global_position)
		if dist < 90.0 and d3 < best_dist:
			best_dist = d3
			best      = ep
	if is_instance_valid(best):
		if best == _locked_target:
			_lock_timer += delta
		else:
			_locked_target = best
			_lock_timer    = 0.0
	else:
		_locked_target = null
		_lock_timer    = 0.0

func _read_input(delta: float) -> void:
	var has_joy := Input.get_connected_joypads().size() > 0
	var aileron  := 0.0
	var elevator := 0.0
	var rudder   := 0.0

	if has_joy:
		aileron  = _dz(Input.get_joy_axis(JOY_DEVICE, JOY_AILERON))
		elevator = _dz(Input.get_joy_axis(JOY_DEVICE, JOY_ELEVATOR))
		rudder   = _dz(Input.get_joy_axis(JOY_DEVICE, JOY_RUDDER))
		var raw_thr := Input.get_joy_axis(JOY_DEVICE, JOY_THROTTLE)
		throttle = (1.0 - raw_thr) * 0.5
		if Input.is_joy_button_pressed(JOY_DEVICE, JoyButton.JOY_BUTTON_A):
			_fire()
	else:
		elevator = float(Input.is_action_pressed("pitch_up"))   - float(Input.is_action_pressed("pitch_down"))
		aileron  = float(Input.is_action_pressed("roll_right")) - float(Input.is_action_pressed("roll_left"))
		rudder   = float(Input.is_action_pressed("yaw_right"))  - float(Input.is_action_pressed("yaw_left"))
		if Input.is_action_pressed("fire_primary"):
			_fire()

	# Velocidad: funciona siempre (joystick y teclado)
	if Input.is_action_pressed("throttle_up") or Input.is_physical_key_pressed(KEY_PAGEUP):
		throttle = min(throttle + throttle_speed * delta, 1.0)
	if Input.is_action_pressed("throttle_down") or Input.is_physical_key_pressed(KEY_PAGEDOWN):
		throttle = max(throttle - throttle_speed * delta, 0.0)
	if Input.is_action_pressed("throttle_boost"):
		throttle = min(throttle + throttle_speed * 3.0 * delta, 1.0)

	# Misil: funciona desde joystick Y teclado
	if Input.is_action_just_pressed("fire_missile"):
		_fire_missile()

	if not on_ground:
		rotate_object_local(Vector3.RIGHT,   -elevator * pitch_rate * delta)
		rotate_object_local(Vector3.FORWARD, -aileron  * roll_rate  * delta)
		rotate_object_local(Vector3.UP,      -rudder   * yaw_rate   * delta)
		var bank := transform.basis.x.dot(Vector3.DOWN)
		rotate_object_local(Vector3.UP, bank * yaw_rate * 0.5 * delta)

# ───────── Movimiento ─────────

func _move(delta: float) -> void:
	var accel : float = 0.25 if on_ground else 1.8
	var t_min : float = 0.0  if on_ground else min_speed
	var t_spd : float = lerp(t_min, max_speed, throttle)
	speed = lerp(speed, t_spd, delta * accel) as float

	global_position -= transform.basis.z * speed * delta

	if on_ground:
		global_position.y = RUNWAY_Y
		if speed >= TAKEOFF_SPEED:
			on_ground = false
			rotate_object_local(Vector3.RIGHT, -0.12)
	else:
		var lift := smoothstep(min_speed, max_speed * 0.65, speed)
		global_position.y -= 9.8 * (1.0 - lift) * delta
		if global_position.y < RUNWAY_Y:
			global_position.y = RUNWAY_Y

	if is_instance_valid(_snd_engine):
		_snd_engine.pitch_scale = lerp(0.65, 1.5, throttle)

	if is_instance_valid(_afterburner_light):
		_afterburner_light.light_energy = lerp(2.0, 12.0, throttle)
		_afterburner_light.omni_range   = lerp(10.0, 28.0, throttle)
		var hot := throttle > 0.75
		_afterburner_light.light_color  = Color(1.0, lerp(0.4, 0.6, throttle), lerp(0.0, 0.2, throttle) if not hot else lerp(0.3, 0.6, (throttle - 0.75) * 4.0))

# ───────── Armas ─────────

func _fire() -> void:
	if _fire_timer > 0.0:
		return
	_fire_timer = fire_cooldown
	if is_instance_valid(_snd_shoot):
		_snd_shoot.play()
	for gun in [$GunLeft, $GunRight]:
		var b := bullet_scene.instantiate()
		get_tree().root.add_child(b)
		b.global_transform = gun.global_transform

func _fire_missile() -> void:
	if _missiles_left <= 0 or _missile_cd > 0.0:
		return
	_missiles_left -= 1
	_missile_cd     = missile_cooldown
	var mount := _missile_mounts[_mount_index % _missile_mounts.size()]
	_mount_index += 1
	var m := missile_scene.instantiate()
	get_tree().root.add_child(m)
	m.global_transform = mount.global_transform
	var tgt := _locked_target if is_instance_valid(_locked_target) else _find_nearest_enemy()
	if is_instance_valid(tgt):
		m.set_target(tgt)
	if is_instance_valid(_snd_missile):
		_snd_missile.play()

func _find_nearest_enemy() -> Node3D:
	var best   : Node3D = null
	var best_d := INF
	var all_t : Array = get_tree().get_nodes_in_group("enemy") + get_tree().get_nodes_in_group("target")
	for e in all_t:
		if not is_instance_valid(e):
			continue
		var d := global_position.distance_to((e as Node3D).global_position)
		if d < best_d:
			best_d = d
			best   = e as Node3D
	return best

func _dz(v: float) -> float:
	if abs(v) < JOY_DEADZONE:
		return 0.0
	return sign(v) * (abs(v) - JOY_DEADZONE) / (1.0 - JOY_DEADZONE)

# ───────── Daño / puntuación ─────────

func take_damage(amount: int) -> void:
	health = max(health - amount, 0)
	health_changed.emit(health)
	if is_instance_valid(_snd_hit) and not _snd_hit.playing:
		_snd_hit.play()
	if health == 0:
		_spawn_explosion()
		aircraft_destroyed.emit()
		queue_free()

func _spawn_explosion() -> void:
	var exp := explosion_scene.instantiate()
	get_tree().root.add_child(exp)
	exp.global_position = global_position

func add_score(pts: int) -> void:
	score += pts
	score_changed.emit(score)

# ───────── Detalle del modelo ─────────
func _setup_model_detail() -> void:
	var mat_gray := _mat(Color(0.70, 0.74, 0.80), 0.85, 0.12)
	var mat_dark := _mat(Color(0.22, 0.25, 0.30), 0.70, 0.30)
	var mat_mid  := _mat(Color(0.52, 0.57, 0.65), 0.75, 0.22)
	var mat_wep  := _mat(Color(0.16, 0.16, 0.19), 0.92, 0.10)
	var mat_acc  := _mat(Color(0.18, 0.40, 0.80), 0.50, 0.35)

	# ── Tubo de pitot ──
	_add_mesh(CylinderMesh.new(), Vector3(0.0, 0.08, -9.0),
			  Vector3(deg_to_rad(90.0), 0.0, 0.0), mat_dark,
			  func(m: CylinderMesh): m.top_radius = 0.025; m.bottom_radius = 0.045; m.height = 1.4)

	# ── LERX – extensiones de raíz de ala (barredan hacia adelante) ──
	for s in [-1.0, 1.0]:
		_add_mesh(BoxMesh.new(), Vector3(s * 2.5, -0.18, -1.2),
				  Vector3(0.0, s * deg_to_rad(28.0), 0.0), mat_mid,
				  func(m: BoxMesh): m.size = Vector3(2.6, 0.18, 2.4))

	# ── Cañón (pod bajo la nariz) ──
	_add_mesh(BoxMesh.new(), Vector3(-0.45, -0.52, -4.0),
			  Vector3.ZERO, mat_dark,
			  func(m: BoxMesh): m.size = Vector3(0.28, 0.22, 2.0))

	# ── Lomo dorsal (spine) ──
	_add_mesh(BoxMesh.new(), Vector3(0.0, 0.76, 0.5),
			  Vector3.ZERO, mat_mid,
			  func(m: BoxMesh): m.size = Vector3(0.42, 0.26, 7.0))

	# ── Marco de cabina ──
	_add_mesh(BoxMesh.new(), Vector3(0.0, 1.32, 0.3),
			  Vector3.ZERO, mat_dark,
			  func(m: BoxMesh): m.size = Vector3(0.72, 0.18, 0.4))

	# ── Aleta ventral (keel) ──
	_add_mesh(BoxMesh.new(), Vector3(0.0, -1.3, 3.6),
			  Vector3.ZERO, mat_dark,
			  func(m: BoxMesh): m.size = Vector3(0.22, 1.5, 1.6))

	# ── Segunda aleta de cola (twin tail) ──
	_add_mesh(BoxMesh.new(), Vector3(0.9, 0.95, 3.8),
			  Vector3.ZERO, mat_mid,
			  func(m: BoxMesh): m.size = Vector3(0.22, 2.0, 2.0))

	# ── Pilones y misiles bajo las alas ──
	for px : float in [-4.2, -2.6, 2.6, 4.2]:
		_add_mesh(BoxMesh.new(), Vector3(px, -0.62, 0.8),
				  Vector3.ZERO, mat_dark,
				  func(m: BoxMesh): m.size = Vector3(0.26, 0.5, 0.65))
		_add_mesh(CylinderMesh.new(), Vector3(px, -1.08, 0.8),
				  Vector3(deg_to_rad(90.0), 0.0, 0.0), mat_wep,
				  func(m: CylinderMesh): m.top_radius = 0.11; m.bottom_radius = 0.11; m.height = 1.5)
		# Aleta del misil
		_add_mesh(BoxMesh.new(), Vector3(px, -1.08, 1.4),
				  Vector3.ZERO, mat_dark,
				  func(m: BoxMesh): m.size = Vector3(0.42, 0.06, 0.28))

	# ── Lanzadores en las puntas de ala ──
	for wx : float in [-6.4, 6.4]:
		_add_mesh(CylinderMesh.new(), Vector3(wx, -0.22, 1.0),
				  Vector3(deg_to_rad(90.0), 0.0, 0.0), mat_wep,
				  func(m: CylinderMesh): m.top_radius = 0.1; m.bottom_radius = 0.1; m.height = 1.8)
		_add_mesh(BoxMesh.new(), Vector3(wx, -0.22, 1.7),
				  Vector3.ZERO, mat_dark,
				  func(m: BoxMesh): m.size = Vector3(0.35, 0.06, 0.26))

	# ── Labios de tomas de aire ──
	for sx : float in [-1.52, 1.52]:
		_add_mesh(BoxMesh.new(), Vector3(sx, -0.65, -1.6),
				  Vector3.ZERO, mat_dark,
				  func(m: BoxMesh): m.size = Vector3(0.06, 0.70, 0.28))

	# ── Franja de acento (azul) en fuselaje ──
	_add_mesh(BoxMesh.new(), Vector3(0.0, 0.0, -2.0),
			  Vector3.ZERO, mat_acc,
			  func(m: BoxMesh): m.size = Vector3(1.42, 1.22, 0.3))

	# ── Luces de navegación ──
	var nl := OmniLight3D.new(); add_child(nl)
	nl.position = Vector3(-6.4, 0.0, 1.0)
	nl.light_color = Color(0.1, 0.4, 1.0); nl.light_energy = 2.5; nl.omni_range = 10.0; nl.shadow_enabled = false
	var nr := OmniLight3D.new(); add_child(nr)
	nr.position = Vector3(6.4, 0.0, 1.0)
	nr.light_color = Color(1.0, 0.1, 0.1); nr.light_energy = 2.5; nr.omni_range = 10.0; nr.shadow_enabled = false

func _add_mesh(mesh: Mesh, pos: Vector3, rot: Vector3,
			   mat: StandardMaterial3D, cfg: Callable) -> void:
	cfg.call(mesh)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.set_surface_override_material(0, mat)
	add_child(mi)

func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic     = metallic
	m.roughness    = roughness
	return m
