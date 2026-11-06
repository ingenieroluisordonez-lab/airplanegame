extends Area3D

@export var speed   : float = 650.0
@export var damage  : int   = 25
@export var lifetime: float = 2.5
var is_enemy: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)

func _physics_process(delta: float) -> void:
	global_position -= transform.basis.z * speed * delta

func _on_body_entered(body: Node3D) -> void:
	if is_enemy and body.is_in_group("player"):
		body.take_damage(damage)
		queue_free()
	elif not is_enemy and (body.is_in_group("enemy") or body.is_in_group("target")):
		body.take_damage(damage)
		queue_free()
