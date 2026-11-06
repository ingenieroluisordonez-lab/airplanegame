extends CharacterBody3D

@export var speed        : float = 32.0
@export var turn_rate    : float = 1.1    # gira rápido pero errático
@export var health       : int   = 1
@export var score_value  : int   = 50

var explosion_scene := preload("res://scenes/explosion/explosion.tscn")
var target       : Node3D = null
var patrol_pt    : Vector3
var _wobble_seed : float

signal destroyed(score: int)

func _ready() -> void:
	add_to_group("enemy")
	patrol_pt    = global_position + Vector3(randf_range(-200, 200), 0, randf_range(-200, 200))
	_wobble_seed = randf() * 100.0
	_build_model()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		_patrol(delta)
		return
	_steer(target.global_position, delta)

func _patrol(delta: float) -> void:
	if global_position.distance_to(patrol_pt) < 25.0:
		patrol_pt = global_position + Vector3(randf_range(-250, 250), randf_range(-20, 20), randf_range(-250, 250))
	_steer(patrol_pt, delta)

func _steer(pos: Vector3, delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001 + _wobble_seed
	# Movimiento muy errático — como papel en el viento
	var wobble := Vector3(
		sin(t * 1.8) * 90.0 + cos(t * 3.1) * 50.0,
		sin(t * 2.2) * 35.0,
		cos(t * 1.5) * 90.0 + sin(t * 2.7) * 50.0
	)
	var aim := pos + wobble
	var dir  := (aim - global_position).normalized()
	var fwd  := -transform.basis.z
	var axis := fwd.cross(dir)
	if axis.length_squared() > 0.001:
		var angle := fwd.angle_to(dir)
		rotate(axis.normalized(), min(angle, turn_rate * delta))
	global_position -= transform.basis.z * speed * delta
	if global_position.y < 10.0:
		global_position.y = lerp(global_position.y, 30.0, delta * 1.5)

func set_target(t: Node3D) -> void:
	target = t

func take_damage(_amount: int) -> void:
	var exp := explosion_scene.instantiate()
	get_tree().root.add_child(exp)
	exp.global_position = global_position
	destroyed.emit(score_value)
	queue_free()

func _build_model() -> void:
	# Papel arrugado / ligeramente amarillento
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.96, 0.95, 0.88)
	mat.roughness    = 0.95; mat.metallic = 0.0

	var mat_crease := StandardMaterial3D.new()
	mat_crease.albedo_color = Color(0.72, 0.70, 0.60)
	mat_crease.roughness    = 0.95

	# ── Ala izquierda (panel inclinado hacia atrás) ──
	var wl := MeshInstance3D.new(); add_child(wl)
	var wlm := BoxMesh.new(); wlm.size = Vector3(6.0, 0.07, 6.5)
	wl.mesh = wlm; wl.position = Vector3(-2.2, 0.0, 0.8)
	wl.rotation_degrees = Vector3(0, 14.0, 4.0)
	wl.set_surface_override_material(0, mat)

	# ── Ala derecha (espejo) ──
	var wr := MeshInstance3D.new(); add_child(wr)
	var wrm := BoxMesh.new(); wrm.size = Vector3(6.0, 0.07, 6.5)
	wr.mesh = wrm; wr.position = Vector3(2.2, 0.0, 0.8)
	wr.rotation_degrees = Vector3(0, -14.0, -4.0)
	wr.set_surface_override_material(0, mat)

	# ── Pliegue central (crease) ──
	var cr := MeshInstance3D.new(); add_child(cr)
	var crm := BoxMesh.new(); crm.size = Vector3(0.22, 0.60, 8.0)
	cr.mesh = crm; cr.position = Vector3(0.0, 0.28, 0.5)
	cr.set_surface_override_material(0, mat_crease)

	# ── Aleta trasera izquierda (vertical) ──
	var fl := MeshInstance3D.new(); add_child(fl)
	var flm := BoxMesh.new(); flm.size = Vector3(0.07, 1.1, 1.8)
	fl.mesh = flm; fl.position = Vector3(-3.0, 0.5, 2.8)
	fl.rotation_degrees.z = 8.0
	fl.set_surface_override_material(0, mat)

	# ── Aleta trasera derecha ──
	var fr := MeshInstance3D.new(); add_child(fr)
	var frm := BoxMesh.new(); frm.size = Vector3(0.07, 1.1, 1.8)
	fr.mesh = frm; fr.position = Vector3(3.0, 0.5, 2.8)
	fr.rotation_degrees.z = -8.0
	fr.set_surface_override_material(0, mat)

	# ── Punta de nariz (pliegue en V) ──
	var nose := MeshInstance3D.new(); add_child(nose)
	var nm := BoxMesh.new(); nm.size = Vector3(0.14, 0.42, 1.5)
	nose.mesh = nm; nose.position = Vector3(0.0, 0.18, -4.5)
	nose.set_surface_override_material(0, mat_crease)
