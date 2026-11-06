extends Node3D

func _ready() -> void:
	$Smoke.finished.connect(queue_free)

	var tween := create_tween()
	tween.tween_property($Flash, "light_energy", 0.0, 0.45)

	var path := ProjectSettings.globalize_path("res://assets/sounds/hit.ogg")
	var stream := AudioStreamOggVorbis.load_from_file(path)
	if stream:
		var snd := AudioStreamPlayer3D.new()
		add_child(snd)
		snd.stream      = stream
		snd.max_distance = 600.0
		snd.unit_size   = 50.0
		snd.play()
