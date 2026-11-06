extends CharacterBody3D

@export var speed        : float = 52.0
@export var turn_rate    : float = 0.50
@export var health       : int   = 20
@export var score_value  : int   = 150
@export var fire_rate    : float = 4.5
@export var attack_range : float = 120.0

var bullet_scene    := preload("res://scenes/bullet/bullet.tscn")
var explosion_scene := preload("res://scenes/explosion/explosion.tscn")
var target       : Node3D = null
var fire_timer   : float
var patrol_pt    : Vector3
var _wobble_seed : float

signal destroyed(score: int)

func _ready() -> void:
	add_to_group("enemy")
	fire_timer   = randf_range(1.5, fire_rate)
	patrol_pt    = global_position + Vector3(randf_range(-200, 200), 0, randf_range(-200, 200))
	_wobble_seed = randf() * 100.0
	_build_model()

func _physics_process(delta: float) -> void:
	fire_timer -= delta
	if not is_instance_valid(target):
		_patrol(delta)
		return
	_steer(target.global_position, delta)
	if global_position.distance_to(target.global_position) < attack_range and fire_timer <= 0.0:
		_fire()
		fire_timer = fire_rate + randf_range(0.0, 2.0)

func _patrol(delta: float) -> void:
	if global_position.distance_to(patrol_pt) < 30.0:
		patrol_pt = global_position + Vector3(randf_range(-250, 250), randf_range(-20, 20), randf_range(-250, 250))
	_steer(patrol_pt, delta)

func _steer(pos: Vector3, delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001 + _wobble_seed
	var wobble := Vector3(sin(t * 1.1) * 55.0, sin(t * 0.7) * 18.0, cos(t * 1.3) * 55.0)
	var aim := pos + wobble
	var dir  := (aim - global_position).normalized()
	var fwd  := -transform.basis.z
	var axis := fwd.cross(dir)
	if axis.length_squared() > 0.001:
		var angle := fwd.angle_to(dir)
		rotate(axis.normalized(), min(angle, turn_rate * delta))
	global_position -= transform.basis.z * speed * delta
	if global_position.y < 15.0:
		global_position.y = lerp(global_position.y, 45.0, delta * 0.6)

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
		var exp := explosion_scene.instantiate()
		get_tree().root.add_child(exp)
		exp.global_position = global_position
		destroyed.emit(score_value)
		queue_free()

func _build_model() -> void:
	var mat_body  := _mat(Color(0.52, 0.28, 0.08), 0.20, 0.90)  # madera oscura
	var mat_canvas := _mat(Color(0.78, 0.68, 0.45), 0.05, 0.95)  # tela/lona
	var mat_metal := _mat(Color(0.60, 0.55, 0.45), 0.65, 0.40)
	var mat_prop  := _mat(Color(0.35, 0.20, 0.06), 0.15, 0.85)

	# ── Fuselaje ──
	_add_mesh(BoxMesh.new(), Vector3.ZERO, Vector3.ZERO, mat_body,
			  func(m: BoxMesh): m.size = Vector3(1.4, 1.5, 9.0))

	# ── Morro redondeado (motor radial) ──
	_add_mesh(CylinderMesh.new(), Vector3(0, 0, -5.0),
			  Vector3(deg_to_rad(90), 0, 0), mat_metal,
			  func(m: CylinderMesh): m.top_radius = 0.9; m.bottom_radius = 0.9; m.height = 1.8)

	# ── Cabina (cúpula) ──
	_add_mesh(BoxMesh.new(), Vector3(0, 1.1, -0.5), Vector3.ZERO, mat_body,
			  func(m: BoxMesh): m.size = Vector3(1.0, 0.9, 2.0))

	# ── Ala inferior ──
	_add_mesh(BoxMesh.new(), Vector3(0, -0.4, 0.5), Vector3.ZERO, mat_canvas,
			  func(m: BoxMesh): m.size = Vector3(16.0, 0.22, 3.2))

	# ── Ala superior ──
	_add_mesh(BoxMesh.new(), Vector3(0, 2.2, 0.5), Vector3.ZERO, mat_canvas,
			  func(m: BoxMesh): m.size = Vector3(16.0, 0.22, 3.0))

	# ── Montantes entre alas (4 struts) ──
	for sx : float in [-5.5, -1.5, 1.5, 5.5]:
		_add_mesh(BoxMesh.new(), Vector3(sx, 0.9, 0.5), Vector3.ZERO, mat_metal,
				  func(m: BoxMesh): m.size = Vector3(0.18, 2.6, 0.18))

	# ── Estabilizador horizontal de cola ──
	_add_mesh(BoxMesh.new(), Vector3(0, 0.0, 4.0), Vector3.ZERO, mat_canvas,
			  func(m: BoxMesh): m.size = Vector3(5.5, 0.18, 2.0))

	# ── Aleta vertical de cola ──
	_add_mesh(BoxMesh.new(), Vector3(0, 1.1, 4.0), Vector3.ZERO, mat_body,
			  func(m: BoxMesh): m.size = Vector3(0.22, 2.2, 1.8))

	# ── Hélice (cruz estática) ──
	_add_mesh(BoxMesh.new(), Vector3(0, 0, -6.0), Vector3.ZERO, mat_prop,
			  func(m: BoxMesh): m.size = Vector3(5.5, 0.28, 0.14))
	_add_mesh(BoxMesh.new(), Vector3(0, 0, -6.0), Vector3.ZERO, mat_prop,
			  func(m: BoxMesh): m.size = Vector3(0.28, 5.5, 0.14))

	# ── Luz delantera ──
	var lt := OmniLight3D.new(); add_child(lt)
	lt.position = Vector3(0, 0, -6.5)
	lt.light_color = Color(1.0, 0.95, 0.75)
	lt.light_energy = 2.0; lt.omni_range = 14.0; lt.shadow_enabled = false

func _add_mesh(mesh: Mesh, pos: Vector3, rot: Vector3,
			   mat: StandardMaterial3D, cfg: Callable) -> void:
	cfg.call(mesh)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh; mi.position = pos; mi.rotation = rot
	mi.set_surface_override_material(0, mat)
	add_child(mi)

func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color; m.metallic = metallic; m.roughness = roughness
	return m
