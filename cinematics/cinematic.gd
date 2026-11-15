class_name Cinematic
extends Node
## Lightweight cutscene director. Owns a cinematic camera, letterbox,
## dialogue playback (voice-ready: plays audio/voice/<line_id> if present)
## and camera moves. Skippable line-by-line with Enter / Space / (A).

signal finished

var cam: Camera3D
var dialogue := {}
var speakers := {}
var active := false
var _skip_requested := false
var _player: Player
var _speaker_nodes := {}
var _cam_tween: Tween


func _init(dialogue_path := "") -> void:
	if dialogue_path != "":
		load_dialogue(dialogue_path)


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 45.0
	cam.near = 0.05
	cam.name = "CinematicCamera"
	add_child(cam)


func load_dialogue(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Dialogue not found: " + path)
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) == TYPE_DICTIONARY:
		dialogue = data.get("lines", {})
		speakers = data.get("speakers", {})


func bind_speaker(speaker_key: String, npc: Node) -> void:
	## Links a speaker key in the dialogue file to a character so its mouth moves.
	_speaker_nodes[speaker_key] = npc


func begin(player: Player = null) -> void:
	active = true
	_player = player
	GameState.in_cutscene = true
	if player:
		player.set_controls(false)
	cam.make_current()
	UI.letterbox(true)
	if not GameState.touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func end() -> void:
	active = false
	GameState.in_cutscene = false
	UI.hide_subtitle()
	UI.letterbox(false)
	if _player:
		_player.camera.make_current()
		_player.set_controls(true)
		_player.snap_camera_behind()
	GameState.capture_mouse(true)
	finished.emit()


func _unhandled_input(event: InputEvent) -> void:
	if active and event.is_action_pressed("skip") and not UI.is_paused():
		_skip_requested = true
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- camera
func _kill_cam_tween() -> void:
	if _cam_tween and _cam_tween.is_valid():
		_cam_tween.kill()


func cut(pos: Vector3, look: Vector3, fov := 45.0) -> void:
	_kill_cam_tween()
	cam.global_position = pos
	cam.fov = fov
	if pos.distance_to(look) > 0.01:
		cam.look_at(look, Vector3.UP)


func move(to_pos: Vector3, to_look: Vector3, dur: float, fov := -1.0) -> Tween:
	## Smoothly dollies the camera; returns the tween (await .finished if needed).
	var start_t := cam.global_transform
	var end_t := Transform3D(Basis(), to_pos).looking_at(to_look, Vector3.UP)
	_kill_cam_tween()
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var d := dur * (0.01 if GameState.fast_mode else 1.0)
	tw.tween_method(func(x: float): cam.global_transform = start_t.interpolate_with(end_t, x), 0.0, 1.0, d)
	if fov > 0.0:
		tw.parallel().tween_property(cam, "fov", fov, d)
	_cam_tween = tw
	return tw


func orbit(center: Vector3, radius: float, height: float, from_angle: float, to_angle: float, dur: float) -> Tween:
	_kill_cam_tween()
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var d := dur * (0.01 if GameState.fast_mode else 1.0)
	_cam_tween = tw
	tw.tween_method(_orbit_step.bind(center, radius, height), from_angle, to_angle, d)
	return tw


func _orbit_step(a: float, center: Vector3, radius: float, height: float) -> void:
	cam.global_position = center + Vector3(sin(a) * radius, height, cos(a) * radius)
	cam.look_at(center + Vector3(0, height * 0.6, 0), Vector3.UP)


# ---------------------------------------------------------------- dialogue
func line(line_id: String, extra_hold := 0.0) -> void:
	## Plays one dialogue line by id and waits for it (or for a skip).
	var entry: Dictionary = dialogue.get(line_id, {"speaker": "", "text": line_id})
	var spk: String = entry.get("speaker", "")
	var text := Story.fill(entry.get("text", ""))
	var spk_info: Dictionary = speakers.get(spk, {})
	var display := Story.fill(spk_info.get("name", spk))
	var color := Color.from_string(spk_info.get("color", "#f2c773"), Color(0.95, 0.78, 0.45))
	await say(display, text, line_id, color, spk, extra_hold)


func say(display: String, text: String, line_id := "", color := Color(0.95, 0.78, 0.45), speaker_key := "", extra_hold := 0.0) -> void:
	var voice_len := Audio.play_voice(line_id) if line_id != "" else 0.0
	var dur := maxf(voice_len + 0.3, 1.6 + text.split(" ").size() * 0.3) + extra_hold
	UI.show_subtitle(display, text, color)
	var npc = _speaker_nodes.get(speaker_key)
	if npc and npc.has_method("set_talking"):
		npc.set_talking(true)
	elif npc is Humanoid:
		npc.talking = true
	await wait(dur, true)
	if npc and npc.has_method("set_talking"):
		npc.set_talking(false)
	elif npc is Humanoid:
		npc.talking = false
	Audio.stop_voice()
	UI.hide_subtitle()
	await wait(0.15)


func wait(seconds: float, skippable := false) -> void:
	_skip_requested = false
	var t := seconds * (0.01 if GameState.fast_mode else 1.0)
	while t > 0.0:
		await get_tree().process_frame
		if not get_tree().paused:
			t -= get_process_delta_time()
		if skippable and _skip_requested:
			_skip_requested = false
			break
