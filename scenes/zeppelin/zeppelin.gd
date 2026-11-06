extends CharacterBody3D

@export var health      : int   = 5
@export var score_value : int   = 600

var explosion_scene := preload("res://scenes/explosion/explosion.tscn")
signal destroyed(score: int)

var _move_dir  : Vector3
var _hit_flash : float = 0.0
var _body_mi   : MeshInstance3D

func _ready() -> void:
	add_to_group("target")
	var angle := randf() * TAU
	_move_dir = Vector3(cos(angle), 0.0, sin(angle)) * 7.0
	_build_model()

func _physics_process(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	velocity = _move_dir + Vector3(0.0, sin(t * 0.12) * 1.5, 0.0)
	move_and_slide()
	if _hit_flash > 0.0:
		_hit_flash -= delta
		if is_instance_valid(_body_mi):
			var mat := _body_mi.get_surface_override_material(0) as StandardMaterial3D
			if mat:
				mat.emission_energy_multiplier = max(0.0, _hit_flash * 10.0)

func take_damage(amount: int) -> void:
	health -= amount
	_hit_flash = 0.4
	if health <= 0:
		for i in 3:
			var exp := explosion_scene.instantiate()
			get_tree().root.add_child(exp)
			exp.global_position = global_position + Vector3(
				randf_range(-10.0, 10.0), randf_range(-3.0, 3.0), randf_range(-10.0, 10.0))
		destroyed.emit(score_value)
		queue_free()

func _build_model() -> void:
	var mat_hull := StandardMaterial3D.new()
	mat_hull.albedo_color = Color(0.88, 0.84, 0.72)
	mat_hull.roughness    = 0.80
	mat_hull.emission_enabled = true
	mat_hull.emission = Color(1.0, 0.5, 0.2)
	mat_hull.emission_energy_multiplier = 0.0

	var mat_dark := StandardMaterial3D.new()
	mat_dark.albedo_color = Color(0.28, 0.28, 0.32)
	mat_dark.roughness = 0.60; mat_dark.metallic = 0.45

	var mat_stripe := StandardMaterial3D.new()
	mat_stripe.albedo_color = Color(0.90, 0.10, 0.10)
	mat_stripe.roughness = 0.80

	# ── Casco (esfera alargada) ──
	_body_mi = MeshInstance3D.new(); add_child(_body_mi)
	var sm := SphereMesh.new()
	sm.radius = 5.5; sm.height = 32.0; sm.radial_segments = 16; sm.rings = 8
	_body_mi.mesh = sm
	_body_mi.rotation_degrees.x = 90.0
	_body_mi.set_surface_override_material(0, mat_hull)

	# ── Franja roja horizontal ──
	for zz : float in [-4.0, 4.0]:
		var stripe := MeshInstance3D.new(); add_child(stripe)
		var stm := CylinderMesh.new()
		stm.top_radius = 5.52; stm.bottom_radius = 5.52; stm.height = 1.0
		stripe.mesh = stm; stripe.rotation_degrees.x = 90.0
		stripe.position = Vector3(0.0, 0.0, zz)
		stripe.set_surface_override_material(0, mat_stripe)

	# ── Aletas de cola (4 aletas cruzadas) ──
	for i in 4:
		var fin := MeshInstance3D.new(); add_child(fin)
		var fm := BoxMesh.new(); fm.size = Vector3(0.4, 5.0, 4.0)
		fin.mesh = fm
		var ang := i * PI * 0.5
		fin.position = Vector3(sin(ang) * 5.5, cos(ang) * 5.5, 14.5)
		fin.rotation.z = ang
		fin.set_surface_override_material(0, mat_hull)

	# ── Góndola de pasajeros ──
	var gond := MeshInstance3D.new(); add_child(gond)
	var gm := BoxMesh.new(); gm.size = Vector3(5.0, 3.0, 12.0)
	gond.mesh = gm; gond.position = Vector3(0.0, -7.2, 2.0)
	gond.set_surface_override_material(0, mat_dark)

	# ── Ventanas de la góndola (emisión suave) ──
	for wz : float in [-4.0, -1.5, 1.0, 3.5]:
		var wmi := MeshInstance3D.new(); add_child(wmi)
		var wm := BoxMesh.new(); wm.size = Vector3(5.1, 0.9, 1.0)
		wmi.mesh = wm; wmi.position = Vector3(0.0, -6.6, wz)
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color(0.55, 0.78, 1.0, 0.8)
		wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wmat.emission_enabled = true
		wmat.emission = Color(0.7, 0.9, 1.0)
		wmat.emission_energy_multiplier = 1.2
		wmi.set_surface_override_material(0, wmat)

	# ── Motores (2 nacelas) ──
	for nx : float in [-2.8, 2.8]:
		var nm := MeshInstance3D.new(); add_child(nm)
		var nmm := CylinderMesh.new()
		nmm.top_radius = 0.9; nmm.bottom_radius = 0.9; nmm.height = 6.0
		nm.mesh = nmm; nm.position = Vector3(nx, -8.2, -1.5)
		nm.rotation_degrees.x = 90.0
		nm.set_surface_override_material(0, mat_dark)

	# ── Luces de navegación ──
	for lp : Vector3 in [Vector3(0, 0, -15.0), Vector3(0, 0, 15.0)]:
		var lt := OmniLight3D.new(); add_child(lt)
		lt.position = lp
		lt.light_color = Color(1.0, 0.0, 0.0) if lp.z < 0 else Color(0.0, 0.5, 1.0)
		lt.light_energy = 2.5; lt.omni_range = 18.0; lt.shadow_enabled = false
