extends CharacterBody3D

@export var health      : int   = 1
@export var score_value : int   = 100

var explosion_scene := preload("res://scenes/explosion/explosion.tscn")
signal destroyed(score: int)

var _drift_seed : float
var _drift_dir  : Vector2

func _ready() -> void:
	add_to_group("target")
	_drift_seed = randf() * 100.0
	var angle := randf() * TAU
	_drift_dir  = Vector2(cos(angle), sin(angle))
	_build_model()

func _physics_process(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001 + _drift_seed
	velocity = Vector3(
		_drift_dir.x * 4.0 + sin(t * 0.3) * 2.5,
		sin(t * 0.18) * 1.8,
		_drift_dir.y * 4.0 + cos(t * 0.25) * 2.5
	)
	move_and_slide()
	if global_position.y < 60.0:
		global_position.y = 60.0

func take_damage(_amount: int) -> void:
	var exp := explosion_scene.instantiate()
	get_tree().root.add_child(exp)
	exp.global_position = global_position
	destroyed.emit(score_value)
	queue_free()

func _build_model() -> void:
	var palettes := [
		[Color(0.95, 0.10, 0.10), Color(1.00, 0.88, 0.00)],
		[Color(0.10, 0.45, 0.95), Color(1.00, 1.00, 1.00)],
		[Color(0.10, 0.75, 0.15), Color(1.00, 0.52, 0.00)],
		[Color(0.75, 0.10, 0.80), Color(1.00, 1.00, 0.10)],
	]
	var pal   := palettes[randi() % palettes.size()]
	var col_a : Color = pal[0]
	var col_b : Color = pal[1]

	# ── Esfera principal ──
	var mi := MeshInstance3D.new(); add_child(mi)
	var sm := SphereMesh.new()
	sm.radius = 5.5; sm.height = 7.5; sm.radial_segments = 16; sm.rings = 8
	mi.mesh = sm; mi.position = Vector3(0, 3.0, 0)
	var mat_a := StandardMaterial3D.new()
	mat_a.albedo_color = col_a; mat_a.roughness = 0.78
	mi.set_surface_override_material(0, mat_a)

	# ── Paneles de color alternado (efecto de rayas) ──
	for i in 6:
		var pm := MeshInstance3D.new(); add_child(pm)
		var bm := BoxMesh.new(); bm.size = Vector3(3.2, 8.2, 0.35)
		pm.mesh = bm; pm.position = Vector3(0, 3.0, 0)
		pm.rotation_degrees.y = i * 60.0
		var mat_p := StandardMaterial3D.new()
		mat_p.albedo_color = col_b if i % 2 == 0 else col_a
		mat_p.roughness = 0.75
		pm.set_surface_override_material(0, mat_p)

	# ── Cuerdas (4 cables finos) ──
	for i in 4:
		var r := MeshInstance3D.new(); add_child(r)
		var rm := CylinderMesh.new()
		rm.top_radius = 0.045; rm.bottom_radius = 0.045; rm.height = 7.5
		r.mesh = rm
		var ang := i * PI * 0.5
		r.position = Vector3(sin(ang) * 2.6, -1.5, cos(ang) * 2.6)
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.60, 0.50, 0.28); rmat.roughness = 0.92
		r.set_surface_override_material(0, rmat)

	# ── Canasta ──
	var bk := MeshInstance3D.new(); add_child(bk)
	var bkm := BoxMesh.new(); bkm.size = Vector3(3.0, 2.0, 3.0)
	bk.mesh = bkm; bk.position = Vector3(0, -5.8, 0)
	var bkmat := StandardMaterial3D.new()
	bkmat.albedo_color = Color(0.60, 0.44, 0.18); bkmat.roughness = 0.95
	bk.set_surface_override_material(0, bkmat)

	# ── Quemador (luz cálida) ──
	var lt := OmniLight3D.new(); add_child(lt)
	lt.position = Vector3(0, -4.0, 0)
	lt.light_color = Color(1.0, 0.65, 0.20)
	lt.light_energy = 3.5; lt.omni_range = 18.0; lt.shadow_enabled = false
