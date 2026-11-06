extends Node3D

@export var speed      : float = 320.0
@export var turn_rate  : float = 2.5
@export var damage     : int   = 80
@export var lifetime   : float = 8.0

var target         : Node3D = null
var _armed         : bool   = false
var explosion_scene := preload("res://scenes/explosion/explosion.tscn")

func _ready() -> void:
	_build_visual()
	get_tree().create_timer(0.3).timeout.connect(func(): _armed = true)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)

func _build_visual() -> void:
	# Cuerpo del misil
	var mi := MeshInstance3D.new()
	add_child(mi)
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.9
	sm.radial_segments = 6
	sm.rings = 3
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(0.9, 0.85, 0.5)
	mat.emission_enabled           = true
	mat.emission                   = Color(1.0, 0.8, 0.3)
	mat.emission_energy_multiplier = 3.0
	mat.metallic                   = 0.6
	mat.roughness                  = 0.3
	mi.set_surface_override_material(0, mat)

	# Luz de llama
	var light := OmniLight3D.new()
	add_child(light)
	light.light_color  = Color(1.0, 0.5, 0.1)
	light.light_energy = 6.0
	light.omni_range   = 20.0
	light.shadow_enabled = false

	# Estela de humo/fuego
	var ppm := ParticleProcessMaterial.new()
	ppm.direction            = Vector3(0, 0, 1)
	ppm.spread               = 6.0
	ppm.initial_velocity_min = 15.0
	ppm.initial_velocity_max = 35.0
	ppm.gravity              = Vector3.ZERO
	ppm.scale_min            = 0.15
	ppm.scale_max            = 0.45
	ppm.color                = Color(1.0, 0.6, 0.1, 0.9)

	var trail_mesh := SphereMesh.new()
	trail_mesh.radius = 0.12
	trail_mesh.height = 0.24
	var trail_mat := StandardMaterial3D.new()
	trail_mat.albedo_color               = Color(1.0, 0.5, 0.1, 0.6)
	trail_mat.emission_enabled           = true
	trail_mat.emission                   = Color(1.0, 0.3, 0.0)
	trail_mat.emission_energy_multiplier = 4.0
	trail_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.cull_mode                  = BaseMaterial3D.CULL_DISABLED
	trail_mesh.material                  = trail_mat

	var particles := GPUParticles3D.new()
	add_child(particles)
	particles.amount          = 20
	particles.lifetime        = 0.35
	particles.local_coords    = false
	particles.one_shot        = false
	particles.process_material = ppm
	particles.draw_pass_1     = trail_mesh
	particles.emitting        = true

func _physics_process(delta: float) -> void:
	var fwd := -transform.basis.z

	if _armed and is_instance_valid(target):
		var dir  := (target.global_position - global_position).normalized()
		var axis := fwd.cross(dir)
		if axis.length_squared() > 0.001:
			var angle := fwd.angle_to(dir)
			rotate(axis.normalized(), min(angle, turn_rate * delta))

	global_position -= transform.basis.z * speed * delta

	# Detección de impacto
	if is_instance_valid(target):
		if global_position.distance_to(target.global_position) < 15.0:
			_hit(target)
			return
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and global_position.distance_to((e as Node3D).global_position) < 12.0:
			_hit(e as Node3D)
			return
	for t in get_tree().get_nodes_in_group("target"):
		if is_instance_valid(t) and global_position.distance_to((t as Node3D).global_position) < 22.0:
			_hit(t as Node3D)
			return

func _hit(body: Node3D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage)
	var exp := explosion_scene.instantiate()
	get_tree().root.add_child(exp)
	exp.global_position = global_position
	queue_free()

func set_target(t: Node3D) -> void:
	target = t
