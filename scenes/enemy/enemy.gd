extends CharacterBody3D

@export var speed        : float = 70.0
@export var turn_rate    : float = 0.32   # torpe – era 0.9
@export var health       : int   = 30
@export var score_value  : int   = 200
@export var fire_rate    : float = 3.8    # dispara poco
@export var attack_range : float = 130.0

var bullet_scene    := preload("res://scenes/bullet/bullet.tscn")
var explosion_scene := preload("res://scenes/explosion/explosion.tscn")
var target       : Node3D = null
var fire_timer   : float
var patrol_pt    : Vector3
var _wobble_seed : float   # cada enemigo tiene fase distinta de oscilación

var _afterburner_light : OmniLight3D

signal destroyed(score: int)

func _ready() -> void:
	add_to_group("enemy")
	fire_timer   = randf_range(1.0, fire_rate)
	patrol_pt    = global_position + Vector3(randf_range(-200, 200), 0, randf_range(-200, 200))
	_wobble_seed = randf() * 100.0
	_setup_visual_effects()
	_setup_model_detail()

# ───────── Efectos ─────────
func _setup_visual_effects() -> void:
	_afterburner_light = OmniLight3D.new()
	add_child(_afterburner_light)
	_afterburner_light.position       = Vector3(0, 0, 5.2)
	_afterburner_light.light_color    = Color(1.0, 0.25, 0.05)
	_afterburner_light.light_energy   = 7.0
	_afterburner_light.omni_range     = 22.0
	_afterburner_light.shadow_enabled = false

# ───────── Modelo detallado ─────────
func _setup_model_detail() -> void:
	var mat_body  := _mat(Color(0.52, 0.06, 0.06), 0.78, 0.18)
	var mat_dark  := _mat(Color(0.18, 0.04, 0.04), 0.72, 0.28)
	var mat_acc   := _mat(Color(0.95, 0.72, 0.05), 0.45, 0.30)
	var mat_wep   := _mat(Color(0.14, 0.14, 0.17), 0.92, 0.10)

	# ── Alas canard delanteras (da aspecto más agresivo) ──
	for s in [-1.0, 1.0]:
		_add_mesh(BoxMesh.new(), Vector3(s * 2.0, -0.1, -2.6),
				  Vector3(0.0, s * deg_to_rad(-35.0), 0.0), mat_body,
				  func(m: BoxMesh): m.size = Vector3(2.8, 0.2, 1.2))

	# ── Delta sweep – extensiones de ala hacia atrás ──
	for s in [-1.0, 1.0]:
		_add_mesh(BoxMesh.new(), Vector3(s * 4.5, -0.18, 2.5),
				  Vector3(0.0, s * deg_to_rad(22.0), 0.0), mat_dark,
				  func(m: BoxMesh): m.size = Vector3(4.0, 0.2, 2.0))

	# ── Segunda aleta de cola (twin tail) ──
	_add_mesh(BoxMesh.new(), Vector3(-1.1, 0.9, 3.6),
			  Vector3.ZERO, mat_body,
			  func(m: BoxMesh): m.size = Vector3(0.22, 1.9, 2.0))

	# ── Lomo dorsal ──
	_add_mesh(BoxMesh.new(), Vector3(0.0, 0.76, 0.5),
			  Vector3.ZERO, mat_dark,
			  func(m: BoxMesh): m.size = Vector3(0.45, 0.28, 7.5))

	# ── Aleta ventral ──
	_add_mesh(BoxMesh.new(), Vector3(0.0, -1.3, 3.5),
			  Vector3.ZERO, mat_dark,
			  func(m: BoxMesh): m.size = Vector3(0.22, 1.4, 1.8))

	# ── Pilones + cohetes bajo las alas ──
	for px : float in [-5.0, -3.0, 3.0, 5.0]:
		_add_mesh(BoxMesh.new(), Vector3(px, -0.6, 1.2),
				  Vector3.ZERO, mat_dark,
				  func(m: BoxMesh): m.size = Vector3(0.26, 0.5, 0.65))
		_add_mesh(CylinderMesh.new(), Vector3(px, -1.05, 1.2),
				  Vector3(deg_to_rad(90.0), 0.0, 0.0), mat_wep,
				  func(m: CylinderMesh): m.top_radius = 0.12; m.bottom_radius = 0.14; m.height = 1.8)

	# ── Cabeza del misil (cono rojo en la punta) ──
	for px : float in [-5.0, -3.0, 3.0, 5.0]:
		_add_mesh(CylinderMesh.new(), Vector3(px, -1.05, 0.2),
				  Vector3(deg_to_rad(90.0), 0.0, 0.0), _mat(Color(0.8, 0.1, 0.05), 0.5, 0.4),
				  func(m: CylinderMesh): m.top_radius = 0.0; m.bottom_radius = 0.12; m.height = 0.4)

	# ── Labios de toma de aire ──
	for sx : float in [-1.45, 1.45]:
		_add_mesh(BoxMesh.new(), Vector3(sx, -0.65, -1.8),
				  Vector3.ZERO, mat_dark,
				  func(m: BoxMesh): m.size = Vector3(0.06, 0.70, 0.28))

	# ── Franja de acento (amarillo) ──
	_add_mesh(BoxMesh.new(), Vector3(0.0, 0.0, -1.5),
			  Vector3.ZERO, mat_acc,
			  func(m: BoxMesh): m.size = Vector3(1.42, 1.22, 0.28))

	# ── Luz de navegación roja (mala) ──
	var nl := OmniLight3D.new(); add_child(nl)
	nl.position = Vector3(0.0, 0.0, -5.0)
	nl.light_color = Color(1.0, 0.0, 0.0); nl.light_energy = 1.5
	nl.omni_range = 12.0; nl.shadow_enabled = false

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

# ───────── IA torpe ─────────
func _physics_process(delta: float) -> void:
	fire_timer -= delta
	if not is_instance_valid(target):
		_patrol(delta)
		return
	_steer_toward_dumb(target.global_position, delta)
	if global_position.distance_to(target.global_position) < attack_range and fire_timer <= 0.0:
		_fire()
		fire_timer = fire_rate + randf_range(0.0, 1.5)  # variación aleatoria extra

func _patrol(delta: float) -> void:
	if global_position.distance_to(patrol_pt) < 30.0:
		patrol_pt = global_position + Vector3(randf_range(-300, 300), randf_range(-30, 30), randf_range(-300, 300))
	_steer_toward_dumb(patrol_pt, delta)

func _steer_toward_dumb(pos: Vector3, delta: float) -> void:
	# Oscilación sinusoidal → vuelo impreciso
	var t : float = Time.get_ticks_msec() * 0.001 + _wobble_seed
	var wobble := Vector3(sin(t * 0.7) * 65.0, sin(t * 0.5) * 22.0, cos(t * 0.9) * 65.0)
	var aim := pos + wobble

	var dir  := (aim - global_position).normalized()
	var fwd  := -transform.basis.z
	var axis := fwd.cross(dir)
	if axis.length_squared() > 0.001:
		var angle := fwd.angle_to(dir)
		rotate(axis.normalized(), min(angle, turn_rate * delta))

	global_position -= transform.basis.z * speed * delta

	if global_position.y < 15.0:
		global_position.y = lerp(global_position.y, 50.0, delta * 0.5)

func _fire() -> void:
	var b := bullet_scene.instantiate()
	get_tree().root.add_child(b)
	b.global_transform = global_transform
	b.set("is_enemy", true)

func set_target(t: Node3D) -> void:
	target = t

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		_spawn_explosion()
		destroyed.emit(score_value)
		queue_free()

func _spawn_explosion() -> void:
	var exp := explosion_scene.instantiate()
	get_tree().root.add_child(exp)
	exp.global_position = global_position
