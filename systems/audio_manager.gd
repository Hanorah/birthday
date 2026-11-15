extends Node
## Audio (autoload): music with crossfade, pooled SFX, voice lines.
## Files are looked up by name in res://audio/<kind>/<name>.(ogg|wav|mp3),
## so a placeholder can be replaced just by dropping in a better file.

const EXTS := ["ogg", "wav", "mp3"]

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _active_music: AudioStreamPlayer
var _current_music := ""
var _sfx_pool: Array[AudioStreamPlayer] = []
var _voice: AudioStreamPlayer
var _cache := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_ensure_bus("Voice")
	_music_a = _make_player("Music")
	_music_b = _make_player("Music")
	_active_music = _music_a
	for p in [_music_a, _music_b]:
		p.finished.connect(_on_music_finished.bind(p))
	for i in 10:
		_sfx_pool.append(_make_player("SFX"))
	_voice = _make_player("Voice")


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")


func _make_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func apply_volumes() -> void:
	var s: Dictionary = GameState.settings
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(s.master_volume), 0.0001)))
	var m := AudioServer.get_bus_index("Music")
	if m >= 0:
		AudioServer.set_bus_volume_db(m, linear_to_db(maxf(float(s.music_volume), 0.0001)))
	var x := AudioServer.get_bus_index("SFX")
	if x >= 0:
		AudioServer.set_bus_volume_db(x, linear_to_db(maxf(float(s.sfx_volume), 0.0001)))


func find_stream(kind: String, sound_name: String) -> AudioStream:
	var key := kind + "/" + sound_name
	if _cache.has(key):
		return _cache[key]
	var stream: AudioStream = null
	for e in EXTS:
		var path := "res://audio/%s/%s.%s" % [kind, sound_name, e]
		if ResourceLoader.exists(path):
			stream = load(path)
			break
	_cache[key] = stream
	return stream


func play_music(track: String, fade := 2.0, volume_db := 0.0) -> void:
	if track == _current_music:
		return
	_current_music = track
	var stream := find_stream("music", track)
	var old := _active_music
	var nxt := _music_b if _active_music == _music_a else _music_a
	_active_music = nxt
	if stream:
		nxt.stream = stream
		nxt.volume_db = -40.0
		nxt.play()
		var t := create_tween()
		t.tween_property(nxt, "volume_db", volume_db, fade)
	if old.playing:
		var t2 := create_tween()
		t2.tween_property(old, "volume_db", -40.0, fade)
		t2.tween_callback(old.stop)


func stop_music(fade := 2.0) -> void:
	_current_music = ""
	var p := _active_music
	if p.playing:
		var t := create_tween()
		t.tween_property(p, "volume_db", -40.0, fade)
		t.tween_callback(p.stop)


func _on_music_finished(p: AudioStreamPlayer) -> void:
	if p == _active_music and _current_music != "":
		p.play()  # loop


func play_sfx(sound_name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var stream := find_stream("sfx", sound_name)
	if stream == null:
		return
	for p in _sfx_pool:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return


func play_voice(line_id: String) -> float:
	## Plays res://audio/voice/<line_id>.* if it exists; returns its length (0 if none).
	var stream := find_stream("voice", line_id)
	if stream == null:
		return 0.0
	_voice.stream = stream
	_voice.play()
	return stream.get_length()


func stop_voice() -> void:
	_voice.stop()
