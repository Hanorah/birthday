extends Node
## Automated playthrough test. Run headless:
##   godot --headless --path . res://tests/test_runner.tscn
## Plays Chapter One end-to-end in fast mode and checks every system.

var failures := 0
var passes := 0


func _ready() -> void:
	GameState.fast_mode = true
	GameState.delete_save()
	call_deferred("_detach")


func _detach() -> void:
	var tree := get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	tree.current_scene = null
	await _run()
	print("\n==== TESTS: %d passed, %d failed ====" % [passes, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
		print("  PASS  ", what)
	else:
		failures += 1
		print("  FAIL  ", what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func wait_until(cond: Callable, max_frames := 3000) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await get_tree().process_frame
	return false


func _run() -> void:
	print("== Humanoid: all life stages")
	for st in 6:
		var h := Humanoid.new()
		h.stage = st
		h.beard = 1.0 if st >= 4 else 0.0
		h.hair_style = ["lowcut", "lowcut", "twists", "locs", "locs", "locs"][st]
		add_child(h)
		h.move_speed = 3.0
		await frames(3)
		check(h.head != null and h.hip_l != null, "stage %s builds with skeleton" % Humanoid.STAGE_KEYS[st])
		h.queue_free()

	print("== Main menu")
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await frames(5)
	check(get_tree().current_scene != null and get_tree().current_scene.name == "MainMenu", "main menu loads")

	print("== New game -> Chapter One intro")
	GameState.new_game()
	var ok := await wait_until(func(): return get_tree().current_scene != null and get_tree().current_scene.name == "Ch1Beginning", 600)
	check(ok, "chapter one scene loads via loading screen")
	ok = await wait_until(func(): return GameState.checkpoint == "morning" and not GameState.in_cutscene, 6000)
	check(ok, "intro cinematic plays through to 1992 morning")
	var level = get_tree().current_scene
	var player: Player = level.player
	check(player != null and player.stage == Humanoid.Stage.CHILD, "player is the five-year-old")
	check(UI.get_objective().contains("Mum"), "objective: find Mum")

	print("== Movement")
	player.teleport(Vector3(-4.0, 0.05, 3.0), 0.0)
	player.cam_yaw.rotation.y = 0.0
	await frames(5)
	var start := player.global_position
	Input.action_press("move_forward")
	for i in 60:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	check(player.global_position.distance_to(start) > 0.8, "player walks (moved %.2f m)" % player.global_position.distance_to(start))
	check(player.is_on_floor(), "player stands on the floor")
	Input.action_press("jump")
	var peak := 0.0
	for i in 30:
		await get_tree().physics_frame
		peak = maxf(peak, player.global_position.y)
	Input.action_release("jump")
	check(peak > 0.3, "player jumps (peak %.2f m)" % peak)
	await frames(60)
	Input.action_press("crouch")
	await frames(2)
	Input.action_release("crouch")
	await frames(10)
	check(player.model.crouch_target == 1.0, "player crouches")
	Input.action_press("crouch")
	await frames(2)
	Input.action_release("crouch")

	print("== Climbing the treehouse ladder")
	player.teleport(Vector3(-12.0, 0.05, 16.25), PI)
	player.cam_yaw.rotation.y = 0.0
	await frames(5)
	Input.action_press("move_forward")
	var max_y := 0.0
	for i in 400:
		await get_tree().physics_frame
		max_y = maxf(max_y, player.global_position.y)
	Input.action_press("move_forward")
	for i in 40:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	for i in 30:
		await get_tree().physics_frame
	print("    final pos ", player.global_position)
	check(max_y > 3.2, "player climbs the ladder (reached %.2f m)" % max_y)
	check(player.global_position.y > 3.0 and player.global_position.z < 15.6, "player stands in the treehouse")

	print("== Story: Mum")
	player.teleport(Vector3(4.4, 0.05, -3.6), PI)
	await level._on_mum()
	check(GameState.get_flag("talked_mum"), "talked to Mum")
	check(GameState.checkpoint == "talked_mum", "checkpoint saved after Mum")

	print("== Story: Dad & radio parts")
	await level._on_dad()
	check(GameState.get_flag("talked_dad"), "talked to Dad")
	check(level.part_points["battery"].enabled, "radio parts become available")
	for k in ["battery", "knob", "screwdriver"]:
		level.part_points[k].interact(player)
	check(level._parts_found().size() == 3, "all three parts collected")
	check(level.radio_point.enabled, "radio can now be fixed")
	await level._on_radio()
	check(GameState.get_flag("radio_fixed"), "radio fixed (tap challenge)")

	print("== Memories")
	for id in level.MEMORIES:
		level.memory_points[id].interact(player)
	await frames(5)
	check(GameState.collectible_count("ch1") >= 6, "all six memories collected")
	check(GameState.has_collectible("ch1", "unlock_bolt_design"), "unlockable granted")

	print("== Save / load")
	GameState.save_game()
	var saved_flags := GameState.flags.duplicate(true)
	GameState.flags = {}
	check(GameState.load_game() and GameState.get_flag("radio_fixed"), "save file round-trips progress")

	print("== Story: hide and seek")
	level.hide_spot = "pantry"
	level._on_hide_spot("wardrobe")
	await frames(3)
	await level._on_hide_spot("pantry")
	check(GameState.get_flag("sister_found"), "found the sister")
	check(level.party_point.enabled, "party is ready")

	print("== Story: birthday, promise and growing up")
	await level._on_party()
	ok = await wait_until(func(): return get_tree().current_scene != null and get_tree().current_scene.name == "MainMenu", 3000)
	check(ok, "chapter ends and returns to the main menu")
	check("ch1" in GameState.completed, "chapter one marked complete")
	check("ch2" in GameState.unlocked, "chapter two unlocked")
	check(GameState.has_collectible("ch1", "photo_fifth_birthday"), "birthday photo collected")

	print("== Continue from checkpoint")
	GameState.current_chapter = "ch1"
	GameState.checkpoint = "radio_fixed"
	GameState.flags = {"talked_mum": true, "talked_dad": true, "parts": ["battery", "knob", "screwdriver"], "radio_fixed": true}
	GameState.save_game()
	GameState.continue_game()
	ok = await wait_until(func(): return get_tree().current_scene != null and get_tree().current_scene.name == "Ch1Beginning", 600)
	await frames(20)
	check(ok and UI.get_objective().contains("Hide and seek"), "continue resumes at the hide-and-seek checkpoint")

	print("== Settings & pause")
	for q in 4:
		GameState.set_setting("quality", q)
	check(true, "all graphics presets apply")
	UI.toggle_pause()
	check(get_tree().paused, "pause menu pauses the game")
	UI.toggle_pause()
	check(not get_tree().paused, "resume unpauses")
	GameState.set_setting("quality", 2)
	GameState.delete_save()
