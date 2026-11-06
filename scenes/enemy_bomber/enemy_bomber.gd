extends CharacterBody3D

@export var speed        : float = 38.0
@export var turn_rate    : float = 0.14   # muy torpe
@export var health       : int   = 60
@export var score_value  : int   = 400
@export var fire_rate    : float = 6.0
@export var attack_range : float = 180.0

var bullet_scene    := preload("res://scenes/bullet/bullet.tscn")
var explosion_scene := preload("res://scenes/explosion/explosion.tscn")
var target       : Node3D = null
var fire_timer   : float
var patrol_pt    : Vector3
var _wobble_seed : float

signal destroyed(score: int)

func _ready() -> void:
	add_to_group("enemy")
	fire_timer   = randf_range(2.0, fire_rate)
	patrol_pt    = global_position + Vector3(randf_range(-300, 300), 0, randf_range(-300, 300))
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
		fire_timer = fire_rate + randf_range(0.0, 3.0)

func _patrol(delta: float) -> void:
	if global_position.distance_to(patrol_pt) < 40.0:
		patrol_pt = global_position + Vector3(randf_range(-350, 350), randf_range(-15, 15), randf_range(-350, 350))
	_steer(patrol_pt, delta)

func _steer(pos: Vector3, delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001 + _wobble_seed
	var wobble := Vector3(sin(t * 0.4) * 30.0, sin(t * 0.3) * 8.0, cos(t * 0.5) * 30.0)
	var aim := pos + wobble
	var dir  := (aim - global_position).normalized()
	var fwd  := -transform.basis.z
	var axis := fwd.cross(dir)
	if axis.length_squared() > 0.001:
		var angle := fwd.angle_to(dir)
		rotate(axis.normalized(), min(angle, turn_rate * delta))
	global_position -= transform.basis.z * speed * delta
	if global_position.y < 25.0:
		global_position.y = lerp(global_position.y, 70.0, delta * 0.4)

func _fire() -> void:
	# Dispara 3 balas en abanico
	for offset in [Vector3(-2, 0, 0), Vector3(0, 0, 0), Vector3(2, 0, 0)]:
		var b := bullet_scene.instantiate()
		get_tree().root.add_child(b)
		b.global_transform = global_transform
		b.global_position += transform.basis * offset
		b.set("is_enemy", true)

func set_target(t: Node3D) -> void:
	target = t

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		for i in 3:
			var exp := explosion_scene.instantiate()
			get_tree().root.add_child(exp)
			exp.global_position = global_position + Vector3(
				randf_range(-8, 8), randf_range(-3, 3), randf_range(-8, 8))
		destroyed.emit(score_value)
		queue_free()

func _build_model() -> void:
	var mat_body  := _mat(Color(0.35, 0.38, 0.30), 0.40, 0.75)   # verde oliva
	var mat_dark  := _mat(Color(0.22, 0.24, 0.18), 0.35, 0.80)
	var mat_metal := _mat(Color(0.52, 0.50, 0.44), 0.70, 0.35)
	var mat_glass := _mat(Color(0.4, 0.65, 0.9, 0.7), 0.0, 0.05)

	# ── Fuselaje gordo ──
	_add_mesh(BoxMesh.new(), Vector3.ZERO, Vector3.ZERO, mat_body,
			  func(m: BoxMesh): m.size = Vector3(3.5, 3.2, 18.0))

	# ── Morro acristalado (bombardero) ──
	_add_mesh(BoxMesh.new(), Vector3(0, -0.4, -9.0), Vector3.ZERO, mat_glass,
			  func(m: BoxMesh): m.size = Vector3(2.5, 2.2, 1.0))

	# ── Alas principales (muy largas) ──
	_add_mesh(BoxMesh.new(), Vector3(0, -0.5, 1.0), Vector3.ZERO, mat_body,
			  func(m: BoxMesh): m.size = Vector3(30.0, 0.55, 7.0))

	# ── Góndola central bajo ala ──
	_add_mesh(BoxMesh.new(), Vector3(0, -2.4, 1.0), Vector3.ZERO, mat_dark,
			  func(m: BoxMesh): m.size = Vector3(2.0, 1.2, 10.0))

	# ── 4 Motores bajo las alas ──
	for mx : float in [-11.0, -5.0, 5.0, 11.0]:
		_add_mesh(CylinderMesh.new(), Vector3(mx, -1.5, 0.0),
				  Vector3(deg_to_rad(90), 0, 0), mat_metal,
				  func(m: CylinderMesh): m.top_radius = 0.95; m.bottom_radius = 0.95; m.height = 4.5)
		# Hélice
		_add_mesh(BoxMesh.new(), Vector3(mx, -1.5, -2.4), Vector3.ZERO, mat_dark,
				  func(m: BoxMesh): m.size = Vector3(4.5, 0.22, 0.14))
		_add_mesh(BoxMesh.new(), Vector3(mx, -1.5, -2.4), Vector3.ZERO, mat_dark,
				  func(m: BoxMesh): m.size = Vector3(0.22, 4.5, 0.14))

	# ── Estabilizador horizontal de cola ──
	_add_mesh(BoxMesh.new(), Vector3(0, 0.0, 8.5), Vector3.ZERO, mat_body,
			  func(m: BoxMesh): m.size = Vector3(10.0, 0.42, 3.5))

	# ── Aleta vertical de cola ──
	_add_mesh(BoxMesh.new(), Vector3(0, 2.4, 8.5), Vector3.ZERO, mat_body,
			  func(m: BoxMesh): m.size = Vector3(0.42, 4.8, 3.5))

	# ── Torreta dorsal (artillero) ──
	_add_mesh(BoxMesh.new(), Vector3(0, 2.0, 2.0), Vector3.ZERO, mat_dark,
			  func(m: BoxMesh): m.size = Vector3(1.5, 1.2, 1.5))
	_add_mesh(CylinderMesh.new(), Vector3(0, 2.8, 2.0),
			  Vector3(0, 0, 0), mat_metal,
			  func(m: CylinderMesh): m.top_radius = 0.5; m.bottom_radius = 0.65; m.height = 1.0)

	# ── Luces de posición ──
	for lx in [-15.0, 15.0]:
		var lt := OmniLight3D.new(); add_child(lt)
		lt.position = Vector3(lx, -1.0, 0.0)
		lt.light_color = Color(0.1, 0.4, 1.0) if lx < 0 else Color(1.0, 0.1, 0.1)
		lt.light_energy = 2.5; lt.omni_range = 14.0; lt.shadow_enabled = false

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
