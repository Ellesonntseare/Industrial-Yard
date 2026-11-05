extends Node

var wind: AudioStreamPlayer
var canopy: AudioStreamPlayer
var rotor: AudioStreamPlayer3D
var deploy: AudioStreamPlayer
var touchdown: AudioStreamPlayer
var previous := ""
var landing_index := 0

func _ready() -> void:
	wind = make_loop("freefall_wind_loop.ogg")
	canopy = make_loop("parachute_canopy_loop.ogg")
	deploy = AudioStreamPlayer.new()
	deploy.stream = load("res://audio/sky/parachute_deploy.wav")
	deploy.volume_db = -8
	add_child(deploy)
	touchdown = AudioStreamPlayer.new()
	touchdown.volume_db = -6
	add_child(touchdown)
	rotor = AudioStreamPlayer3D.new()
	var stream := load("res://audio/sky/helicopter_rotor_loop.ogg") as AudioStreamOggVorbis
	stream.loop = true
	rotor.stream = stream
	rotor.unit_size = 18
	rotor.max_distance = 250
	rotor.volume_db = -10
	add_child(rotor)
	rotor.play()

func make_loop(file: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	var stream := load("res://audio/sky/" + file) as AudioStreamOggVorbis
	stream.loop = true
	player.stream = stream
	player.volume_db = -70
	add_child(player)
	player.play()
	return player

func update(phase: String, delta: float, aircraft_position: Vector3, enabled: bool) -> void:
	rotor.position = aircraft_position
	rotor.stream_paused = not enabled
	if enabled and phase != previous:
		if phase == "parachute" and previous == "fall": deploy.play()
		if phase == "ground" and previous in ["fall", "parachute"]:
			landing_index = (landing_index % 3) + 1
			touchdown.stream = load("res://audio/sky/landing_boots_0%s.wav" % landing_index)
			touchdown.play()
	previous = phase if enabled else ""
	var wind_target := -12.0 if enabled and phase == "fall" else -70.0
	var canopy_target := -15.0 if enabled and phase == "parachute" else -70.0
	wind.volume_db = move_toward(wind.volume_db, wind_target, delta * 80)
	canopy.volume_db = move_toward(canopy.volume_db, canopy_target, delta * 80)
