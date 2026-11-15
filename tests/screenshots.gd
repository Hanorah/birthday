extends Node
## Renders reference screenshots: godot --path . res://tests/screenshots.tscn -- <outdir>

var outdir := "user://shots"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		outdir = args[0]
	DirAccess.make_dir_recursive_absolute(outdir)
	GameState.fast_mode = false
	if args.size() > 1:
		GameState.settings.quality = int(args[1])
	call_deferred("_run")

func snap(name: String) -> void:
	for i in 8:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(outdir + "/" + name + ".png")
	print("saved ", name, " draw_calls=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), " objects=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME), " fps=", Engine.get_frames_per_second())

func _run() -> void:
	var tree := get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	tree.current_scene = null
	tree.change_scene_to_file("res://ui/main_menu.tscn")
	await get_tree().create_timer(2.5).timeout
	await snap("01_main_menu")
	GameState.checkpoint = "morning"
	GameState.flags = {}
	tree.change_scene_to_file("res://levels/ch1_beginning/ch1_beginning.tscn")
	await get_tree().create_timer(2.0).timeout
	var lv = tree.current_scene
	UI.set_black(false)
	UI.reset_overlays()
	var cam := Camera3D.new()
	lv.add_child(cam)
	cam.make_current()
	var shots := [
		["02_bedroom_player", Vector3(3.8, 1.3, 0.8), Vector3(5.8, 0.6, 2.4), 9.5],
		["03_living_room", Vector3(-1.0, 1.7, 4.8), Vector3(-4.5, 0.8, -2.0), 9.5],
		["04_kitchen_mum", Vector3(2.0, 1.6, -1.0), Vector3(4.4, 1.0, -4.8), 9.5],
		["05_house_exterior", Vector3(6.0, 3.0, 22.0), Vector3(-1.0, 2.0, 4.0), 13.0],
		["06_party_golden_hour", Vector3(3.0, 1.8, 9.0), Vector3(3.0, 0.9, 13.0), 17.6],
		["07_treehouse", Vector3(-6.0, 2.5, 20.0), Vector3(-12.0, 3.0, 14.0), 17.0],
		["08_night_nursery", Vector3(6.2, 2.0, 5.4), Vector3(4.0, 0.7, 3.0), 21.5],
	]
	lv._start_party_approach()
	await get_tree().create_timer(8.5).timeout
	for s in shots:
		lv.set_time(s[3])
		if s[0] == "08_night_nursery":
			lv._build_nursery()
			for k in lv.npcs: lv.npcs[k].visible = false
			lv.place("MUM", Vector3(3.25, 0, 2.95), Vector3(4, 0, 3.0))
			lv.place("DAD", Vector3(4.75, 0, 3.45), Vector3(4, 0, 3.1))
		if s[0] == "04_kitchen_mum":
			lv.place("MUM", Vector3(4.4, 0, -4.75), Vector3(2.0, 0, -1.0))
		if s[0] == "02_bedroom_player":
			lv.player.teleport(Vector3(5.6, 0.05, 2.4), deg_to_rad(-120))
		cam.global_position = s[1]
		cam.look_at(s[2], Vector3.UP)
		cam.fov = 55
		await snap(s[0])
	# character line-up: hero at each age
	lv.set_time(13.0)
	for k in lv.npcs: lv.npcs[k].visible = false
	var x := -2.0
	for st in [1, 2, 3, 4]:
		var h := Humanoid.new()
		h.character_id = "protagonist"
		h.stage = st
		for k in lv.hero_look(st): h.set(k, lv.hero_look(st)[k])
		lv.add_child(h)
		h.global_position = Vector3(x, 0, 9.0)
		x += 1.3
	cam.global_position = Vector3(0.0, 1.2, 12.6)
	cam.look_at(Vector3(0.0, 0.95, 9.0), Vector3.UP)
	cam.fov = 45
	await snap("09_hero_ages")
	cam.global_position = Vector3(1.9, 1.7, 10.1)
	cam.look_at(Vector3(1.9, 1.62, 9.0), Vector3.UP)
	cam.fov = 30
	await snap("10_hero_adult_face")
	print("done")
	get_tree().quit()
