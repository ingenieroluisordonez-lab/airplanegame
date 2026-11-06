extends CharacterBody3D

@export var health       : int   = 10
@export var score_value  : int   = 1000
@export var fire_rate    : float = 4.5
@export var attack_range : float = 350.0

var bullet_scene    := preload("res://scenes/bullet/bullet.tscn")
var explosion_scene := preload("res://scenes/explosion/explosion.tscn")
signal destroyed(score: int)

var _fire_timer : float
var _move_dir   : Vector3

func _ready() -> void:
	add_to_group("target")
	_fire_timer = randf_range(2.0, fire_rate)
	var angle := randf() * TAU
	_move_dir = Vector3(cos(angle), 0.0, sin(angle)) * 3.5
	_build_model()

func _physics_process(delta: float) -> void:
	_fire_timer -= delta
	velocity = _move_dir
	velocity.y = 0.0
	move_and_slide()
	global_position.y = 2.5

	var player := _get_player()
	if is_instance_valid(player):
		var dist := global_position.distance_to(player.global_position)
		if dist < attack_range and _fire_timer <= 0.0:
			_fire_at(player)
			_fire_timer = fire_rate + randf_range(0.0, 2.5)

func _get_player() -> Node3D:
	var group := get_tree().get_nodes_in_group("player")
	return group[0] as Node3D if group.size() > 0 else null

func _fire_at(tgt: Node3D) -> void:
	var b := bullet_scene.instantiate()
	get_tree().root.add_child(b)
	b.global_position = global_position + Vector3(0.0, 9.0, 0.0)
	b.set("is_enemy", true)
	if is_instance_valid(tgt):
		b.look_at(tgt.global_position, Vector3.UP)

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		for i in 4:
			var exp := explosion_scene.instantiate()
			get_tree().root.add_child(exp)
			exp.global_position = global_position + Vector3(
				randf_range(-12.0, 12.0), randf_range(0.0, 8.0), randf_range(-12.0, 12.0))
		destroyed.emit(score_value)
		queue_free()

func _build_model() -> void:
	var mat_hull := StandardMaterial3D.new()
	mat_hull.albedo_color = Color(0.22, 0.24, 0.28); mat_hull.roughness = 0.80; mat_hull.metallic = 0.55

	var mat_deck := StandardMaterial3D.new()
	mat_deck.albedo_color = Color(0.38, 0.36, 0.32); mat_deck.roughness = 0.90

	var mat_sup := StandardMaterial3D.new()
	mat_sup.albedo_color = Color(0.48, 0.46, 0.40); mat_sup.roughness = 0.78

	var mat_gun := StandardMaterial3D.new()
	mat_gun.albedo_color = Color(0.28, 0.28, 0.32); mat_gun.metallic = 0.75; mat_gun.roughness = 0.25

	# ── Casco ──
	var hull := MeshInstance3D.new(); add_child(hull)
	var hm := BoxMesh.new(); hm.size = Vector3(18.0, 5.5, 50.0)
	hull.mesh = hm; hull.set_surface_override_material(0, mat_hull)

	# ── Proa (cono frontal) ──
	var bow := MeshInstance3D.new(); add_child(bow)
	var bwm := CylinderMesh.new()
	bwm.top_radius = 0.0; bwm.bottom_radius = 9.0; bwm.height = 10.0
	bow.mesh = bwm; bow.rotation_degrees.z = 90.0
	bow.position = Vector3(0.0, 0.0, -29.0)
	bow.set_surface_override_material(0, mat_hull)

	# ── Cubierta ──
	var deck := MeshInstance3D.new(); add_child(deck)
	var dm := BoxMesh.new(); dm.size = Vector3(16.0, 0.6, 46.0)
	deck.mesh = dm; deck.position = Vector3(0.0, 3.1, 0.0)
	deck.set_surface_override_material(0, mat_deck)

	# ── Superestructura principal ──
	var bridge := MeshInstance3D.new(); add_child(bridge)
	var brm := BoxMesh.new(); brm.size = Vector3(11.0, 8.0, 14.0)
	bridge.mesh = brm; bridge.position = Vector3(0.0, 7.4, -4.0)
	bridge.set_surface_override_material(0, mat_sup)

	# ── Puente de mando (nivel superior) ──
	var top := MeshInstance3D.new(); add_child(top)
	var tm := BoxMesh.new(); tm.size = Vector3(7.5, 5.0, 9.0)
	top.mesh = tm; top.position = Vector3(0.0, 13.0, -4.0)
	top.set_surface_override_material(0, mat_sup)

	# ── Chimeneas ──
	for cx : float in [-2.0, 2.0]:
		var ch := MeshInstance3D.new(); add_child(ch)
		var chm := CylinderMesh.new()
		chm.top_radius = 1.4; chm.bottom_radius = 1.6; chm.height = 7.0
		ch.mesh = chm; ch.position = Vector3(cx, 18.5, -3.5)
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(0.18, 0.18, 0.20); cmat.metallic = 0.70; cmat.roughness = 0.30
		ch.set_surface_override_material(0, cmat)

		# Humo de chimenea
		var ppm := ParticleProcessMaterial.new()
		ppm.direction = Vector3(0, 1, 0); ppm.spread = 20.0
		ppm.initial_velocity_min = 6.0; ppm.initial_velocity_max = 14.0
		ppm.gravity = Vector3.ZERO; ppm.scale_min = 2.0; ppm.scale_max = 5.0
		ppm.color = Color(0.50, 0.50, 0.50, 0.55)
		var smesh := SphereMesh.new(); smesh.radius = 1.0; smesh.height = 2.0
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.6, 0.6, 0.6, 0.45)
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.cull_mode = BaseMaterial3D.CULL_DISABLED
		smesh.material = smat
		var smoke := GPUParticles3D.new(); add_child(smoke)
		smoke.position = Vector3(cx, 22.5, -3.5)
		smoke.amount = 18; smoke.lifetime = 3.5; smoke.local_coords = false
		smoke.process_material = ppm; smoke.draw_pass_1 = smesh; smoke.emitting = true

	# ── Torreta antiaérea ──
	var turret := MeshInstance3D.new(); add_child(turret)
	var trm := CylinderMesh.new()
	trm.top_radius = 1.8; trm.bottom_radius = 2.2; trm.height = 2.5
	turret.mesh = trm; turret.position = Vector3(0.0, 4.8, 17.0)
	turret.set_surface_override_material(0, mat_gun)

	# ── Cañón AA ──
	var barrel := MeshInstance3D.new(); add_child(barrel)
	var brr := CylinderMesh.new()
	brr.top_radius = 0.22; brr.bottom_radius = 0.28; brr.height = 6.0
	barrel.mesh = brr; barrel.position = Vector3(0.0, 8.5, 17.0)
	barrel.rotation_degrees.x = 55.0
	barrel.set_surface_override_material(0, mat_gun)

	# ── Luz de navegación ──
	var lt := OmniLight3D.new(); add_child(lt)
	lt.position = Vector3(0.0, 16.0, -22.0)
	lt.light_color = Color(1.0, 0.92, 0.75)
	lt.light_energy = 3.5; lt.omni_range = 35.0; lt.shadow_enabled = false
