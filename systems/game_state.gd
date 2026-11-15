extends Node
## GameState (autoload): chapter registry, progression, checkpoints,
## save/load, settings, input map and scene loading.

signal settings_changed

const SAVE_PATH := "user://savegame.json"
const SETTINGS_PATH := "user://settings.json"

const CHAPTERS := [
	{"id": "ch1", "image": "newborn", "num": "Chapter One", "title": "The Beginning", "scene": "res://levels/ch1_beginning/ch1_beginning.tscn",
		"blurb": "A warm family home. A promise made over birthday candles.", "tip": "Explore the house — every room holds a memory."},
	{"id": "ch2", "image": "robotics_champion", "num": "Chapter Two", "title": "The Curious Mind", "scene": "",
		"blurb": "School, university and the first robot.", "tip": ""},
	{"id": "ch3", "image": "blue_caravan", "num": "Chapter Three", "title": "The Engineer", "scene": "",
		"blurb": "A laboratory, a city — and a blue caravan selling buns.", "tip": ""},
	{"id": "ch4", "image": "outbreak", "num": "Chapter Four", "title": "The Outbreak", "scene": "",
		"blurb": "The city falls silent.", "tip": ""},
	{"id": "ch5", "image": "outbreak", "num": "Chapter Five", "title": "Finding Her", "scene": "",
		"blurb": "Nothing else matters.", "tip": ""},
	{"id": "ch6", "image": "forest_rescue", "num": "Chapter Six", "title": "Through the Woods", "scene": "",
		"blurb": "Carry her. Keep moving.", "tip": ""},
	{"id": "ch7", "image": "forest_rescue", "num": "Chapter Seven", "title": "The Human Threat", "scene": "",
		"blurb": "Survival belongs to the strongest — or the smartest.", "tip": ""},
	{"id": "ch8", "image": "island_arrival", "num": "Chapter Eight", "title": "The Last Journey", "scene": "",
		"blurb": "An island on the horizon.", "tip": ""},
	{"id": "ch9", "image": "island_arrival", "num": "Final Chapter", "title": "A World Worth Living In", "scene": "",
		"blurb": "Keep the promise.", "tip": ""},
]

const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra"]

var settings := {
	"quality": 2,
	"fullscreen": false,
	"render_scale": 1.0,
	"master_volume": 0.85,
	"music_volume": 0.7,
	"sfx_volume": 0.9,
	"mouse_sensitivity": 0.22,
	"invert_y": false,
	"subtitles": true,
}

# Progression
var current_chapter := ""
var checkpoint := ""
var flags := {}
var collectibles := {}       # chapter_id -> Array[String]
var unlocked: Array = ["ch1"]
var completed: Array = []
var player_health := 100.0

# Runtime
var in_gameplay := false
var in_cutscene := false
var fast_mode := false        # used by automated tests: compresses all waits
var touch_mode := false       # phone / tablet: on-screen controls, no mouse capture
var detail_scale := 1.0       # vegetation density etc. (lower on phones)
var _loading := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	touch_mode = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") \
		or OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.get_environment("TLP_TOUCH") == "1"
	if OS.has_feature("web"):
		settings.quality = 0 if touch_mode else 1
		detail_scale = 0.3 if touch_mode else 0.6
	load_settings()
	_peek_progress()
	call_deferred("apply_settings")


# ---------------------------------------------------------------- chapters
func get_chapter(id: String) -> Dictionary:
	for c in CHAPTERS:
		if c.id == id:
			return c
	return {}


func chapter_index(id: String) -> int:
	for i in CHAPTERS.size():
		if CHAPTERS[i].id == id:
			return i
	return -1


func is_built(id: String) -> bool:
	return get_chapter(id).get("scene", "") != ""


func new_game() -> void:
	flags = {}
	collectibles = {}
	checkpoint = ""
	player_health = 100.0
	load_chapter("ch1")


func continue_game() -> void:
	if load_game():
		load_chapter(current_chapter, checkpoint)


func load_chapter(id: String, from_checkpoint: String = "") -> void:
	if _loading:
		return
	var ch := get_chapter(id)
	if ch.is_empty() or ch.scene == "":
		UI.toast("%s is still in development." % ch.get("title", id))
		return
	_loading = true
	if current_chapter != id:
		flags = {}
	current_chapter = id
	checkpoint = from_checkpoint
	get_tree().paused = false
	await UI.fade_out(0.8)
	UI.show_loading(ch)
	var started := Time.get_ticks_msec()
	ResourceLoader.load_threaded_request(ch.scene)
	var progress := []
	while true:
		var st := ResourceLoader.load_threaded_get_status(ch.scene, progress)
		if progress.size() > 0:
			UI.set_loading_progress(progress[0])
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("Failed to load " + ch.scene)
			_loading = false
			UI.hide_loading()
			return
		await get_tree().process_frame
	var packed: PackedScene = ResourceLoader.load_threaded_get(ch.scene)
	var min_ms := 50 if fast_mode else 1800
	while Time.get_ticks_msec() - started < min_ms:
		UI.set_loading_progress(1.0)
		await get_tree().process_frame
	get_tree().change_scene_to_packed(packed)
	await get_tree().process_frame
	await get_tree().process_frame
	UI.hide_loading()
	_loading = false


func return_to_menu() -> void:
	in_gameplay = false
	in_cutscene = false
	get_tree().paused = false
	await UI.fade_out(0.6)
	UI.reset_overlays()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await get_tree().process_frame
	UI.fade_in(0.8)


# ---------------------------------------------------------------- flags / collectibles
func set_flag(key: String, value = true) -> void:
	flags[key] = value


func get_flag(key: String, default = false):
	return flags.get(key, default)


func add_collectible(chapter_id: String, id: String) -> bool:
	if not collectibles.has(chapter_id):
		collectibles[chapter_id] = []
	if id in collectibles[chapter_id]:
		return false
	collectibles[chapter_id].append(id)
	return true


func collectible_count(chapter_id: String) -> int:
	return collectibles.get(chapter_id, []).size()


func has_collectible(chapter_id: String, id: String) -> bool:
	return id in collectibles.get(chapter_id, [])


func reach_checkpoint(id: String, announce := true) -> void:
	checkpoint = id
	save_game()
	if announce:
		UI.toast("Checkpoint saved")


func complete_chapter(id: String) -> void:
	if not id in completed:
		completed.append(id)
	var i := chapter_index(id)
	if i >= 0 and i + 1 < CHAPTERS.size():
		var next_id: String = CHAPTERS[i + 1].id
		if not next_id in unlocked:
			unlocked.append(next_id)
		current_chapter = next_id
		checkpoint = ""
		flags = {}
	save_game()


# ---------------------------------------------------------------- save / load
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> void:
	var data := {
		"version": 1,
		"chapter": current_chapter,
		"checkpoint": checkpoint,
		"flags": flags,
		"collectibles": collectibles,
		"unlocked": unlocked,
		"completed": completed,
		"health": player_health,
		"saved_at": Time.get_datetime_string_from_system(),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return false
	current_chapter = data.get("chapter", "ch1")
	checkpoint = data.get("checkpoint", "")
	flags = data.get("flags", {})
	collectibles = data.get("collectibles", {})
	unlocked = data.get("unlocked", ["ch1"])
	completed = data.get("completed", [])
	player_health = float(data.get("health", 100.0))
	if not is_built(current_chapter):
		# Next chapter isn't built yet: resume the last playable one.
		current_chapter = "ch1"
		checkpoint = ""
		flags = {}
	return true


func _peek_progress() -> void:
	# Keep unlocked chapters across a New Game.
	if not has_save():
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) == TYPE_DICTIONARY:
		unlocked = data.get("unlocked", ["ch1"])
		completed = data.get("completed", [])
		collectibles = data.get("collectibles", {})


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


# ---------------------------------------------------------------- settings
func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) == TYPE_DICTIONARY:
		for k in data.keys():
			if settings.has(k):
				settings[k] = data[k]


func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings, "\t"))


func set_setting(key: String, value) -> void:
	settings[key] = value
	save_settings()
	apply_settings()


func apply_settings() -> void:
	var win := get_window()
	if win and not fast_mode:
		var want_full: bool = settings.fullscreen
		var is_full := win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
		if want_full != is_full:
			win.mode = Window.MODE_FULLSCREEN if want_full else Window.MODE_WINDOWED
	var q: int = int(settings.quality)
	var vp := get_viewport()
	vp.scaling_3d_scale = clampf(float(settings.render_scale), 0.5, 1.0)
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][q]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q <= 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.positional_shadow_atlas_size = [1024, 2048, 4096, 8192][q]
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096, 8192][q], true)
	for n in get_tree().get_nodes_in_group("world_env"):
		if n is WorldEnvironment and n.environment:
			apply_env_quality(n.environment)
	for l in get_tree().get_nodes_in_group("sun"):
		if l is DirectionalLight3D:
			l.directional_shadow_max_distance = [30.0, 50.0, 90.0, 140.0][q]
			l.directional_shadow_mode = [DirectionalLight3D.SHADOW_ORTHOGONAL, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
				DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS][q]
	for l in get_tree().get_nodes_in_group("shadow_light"):
		if l is Light3D:
			l.shadow_enabled = q >= 2
	Audio.apply_volumes()
	settings_changed.emit()


func apply_env_quality(env: Environment) -> void:
	var q: int = int(settings.quality)
	env.ssao_enabled = q >= 1
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssil_enabled = q >= 3
	env.ssr_enabled = q >= 3
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.08
	env.volumetric_fog_enabled = q >= 2 and env.get_meta("wants_volumetric", false)
	env.fog_enabled = env.get_meta("wants_fog", true)


# ---------------------------------------------------------------- input
func _setup_input() -> void:
	_bind("move_forward", [KEY_W, KEY_UP], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_bind("move_back", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_bind("move_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_bind("move_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_bind("look_left", [], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_bind("look_right", [], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_bind("look_up", [], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_bind("look_down", [], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_bind("sprint", [KEY_SHIFT], [JOY_BUTTON_LEFT_STICK])
	_bind("walk", [KEY_ALT], [])
	_bind("jump", [KEY_SPACE], [JOY_BUTTON_A])
	_bind("crouch", [KEY_C, KEY_CTRL], [JOY_BUTTON_B])
	_bind("interact", [KEY_E], [JOY_BUTTON_X])
	_bind("skip", [KEY_ENTER, KEY_SPACE], [JOY_BUTTON_A])
	_bind("pause", [KEY_ESCAPE], [JOY_BUTTON_START])
	_bind("journal", [KEY_TAB, KEY_J], [JOY_BUTTON_BACK])
	# Reserved for combat chapters (Milestone 5)
	_bind("fire", [], [], [], [MOUSE_BUTTON_LEFT])
	_bind("aim", [], [], [], [MOUSE_BUTTON_RIGHT])
	_bind("reload", [KEY_R], [JOY_BUTTON_Y])
	_bind("melee", [KEY_F], [JOY_BUTTON_RIGHT_SHOULDER])


func _bind(action: String, keys: Array, buttons: Array, axes: Array = [], mouse: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(action, jb)
	for a in axes:
		var jm := InputEventJoypadMotion.new()
		jm.axis = a[0]
		jm.axis_value = a[1]
		InputMap.action_add_event(action, jm)
	for m in mouse:
		var mb := InputEventMouseButton.new()
		mb.button_index = m
		InputMap.action_add_event(action, mb)


func capture_mouse(on: bool) -> void:
	if touch_mode or fast_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func wait(seconds: float) -> void:
	## Pause-aware wait that respects fast_mode (tests).
	var t := seconds * (0.01 if fast_mode else 1.0)
	await get_tree().create_timer(max(t, 0.0)).timeout
