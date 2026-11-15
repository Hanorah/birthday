extends Node3D
## CHAPTER ONE — THE BEGINNING
## 16 November 1987: he is born. 16 November 1992: his fifth birthday.
## Gameplay: explore the family home, help Mum, fix Grandma's radio with Dad
## (find 3 parts), play hide-and-seek with his sister, blow out the candles
## and make the promise. Ends with the growing-up transition.

const E = preload("res://environments/env_builder.gd")
const CHAPTER := "ch1"
const SKIN := Color(0.29, 0.17, 0.11)

const MEMORIES := {
	"mem_newborn_photo": "The First Photo",
	"mem_wedding": "Mum & Dad",
	"mem_drawing": "A Robot With a Heart",
	"mem_height": "Height Marks",
	"mem_toy_robot": "Bolt",
	"mem_treehouse": "Keep Out",
}
const PARTS := {"battery": "Battery", "knob": "Tuning Knob", "screwdriver": "Screwdriver"}

var player: Player
var cin: Cinematic
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var sky_mat: ProceduralSkyMaterial
var npcs := {}
var interior_lights: Array[OmniLight3D] = []
var party_lights: Array[OmniLight3D] = []
var bulbs_mat: StandardMaterial3D
var room_set: Node3D
var radio_node: Node3D
var radio_player: AudioStreamPlayer3D
var cake: Node3D
var candles := []          # [flame MeshInstance3D, OmniLight3D]
var part_points := {}      # id -> Interactable
var hide_points := {}      # id -> Interactable
var memory_points := {}    # id -> Interactable
var radio_point: Interactable
var party_point: Interactable
var hide_spot := ""
var _hour := 9.5
var _busy := false


# =================================================================== lifecycle
func _ready() -> void:
	GameState.in_gameplay = true
	UI.reset_overlays()
	UI.set_black(true)
	_build_world()
	_build_house()
	_build_garden()
	_build_family()
	_build_interactables()
	StaticBatcher.batch(get_node("House"))
	StaticBatcher.batch(get_node("Garden"), [], [cake])
	player = Player.new()
	player.name = "Player"
	player.appearance = hero_look(Humanoid.Stage.CHILD)
	player.stage = Humanoid.Stage.CHILD
	add_child(player)
	player.teleport(Vector3(5.6, 0.05, 2.4), PI)
	cin = Cinematic.new("res://narrative/dialogue_ch1.json")
	add_child(cin)
	for k in npcs.keys():
		cin.bind_speaker(k, npcs[k])
	cin.bind_speaker("HERO", player.model)
	GameState.apply_settings()
	call_deferred("_start")


func _start() -> void:
	Audio.play_music("childhood", 3.0, -4.0)
	if GameState.checkpoint == "":
		await play_intro()
	else:
		_restore()


func _process(delta: float) -> void:
	# cousin runs laps around the garden tree
	if npcs.has("COUSIN") and npcs.COUSIN.get_meta("running", false):
		var c: NPC = npcs.COUSIN
		var a: float = c.get_meta("angle", 0.0) + delta * 0.55
		c.set_meta("angle", a)
		var centre := Vector3(-6.5, 0, 17.5)
		var p := centre + Vector3(cos(a) * 3.2, 0, sin(a) * 3.2)
		c.face(p + Vector3(-sin(a), 0, cos(a)))
		c.global_position = p
		c.model.move_speed = 2.0
	# flicker candle flames
	for cdl in candles:
		if cdl[1] is OmniLight3D and cdl[1].visible:
			cdl[1].light_energy = 0.75 + randf() * 0.3


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("journal") and GameState.in_gameplay and not GameState.in_cutscene:
		UI.toggle_journal(_journal_text())


func hero_look(stage: Humanoid.Stage) -> Dictionary:
	## The protagonist's look at each age. Reference: supplied photo — deep
	## brown skin, short twists growing into locs, full beard as an adult.
	var base := {"skin_color": SKIN, "hair_color": Color(0.035, 0.03, 0.028), "eye_color": Color(0.1, 0.06, 0.035)}
	match stage:
		Humanoid.Stage.NEWBORN:
			base.merge({"hair_style": "lowcut"})
		Humanoid.Stage.CHILD:
			base.merge({"hair_style": "lowcut", "top_color": Color(0.96, 0.74, 0.18), "bottom_color": Color(0.22, 0.32, 0.55), "shoe_color": Color(0.85, 0.85, 0.85)})
		Humanoid.Stage.TEEN:
			base.merge({"hair_style": "twists", "top_color": Color(0.92, 0.92, 0.9), "bottom_color": Color(0.12, 0.14, 0.25), "long_sleeves": false})
		Humanoid.Stage.YOUNG_ADULT:
			base.merge({"hair_style": "locs", "beard": 0.45, "top_color": Color(0.34, 0.34, 0.37), "bottom_color": Color(0.18, 0.24, 0.38), "long_sleeves": true})
		_:
			base.merge({"hair_style": "locs", "beard": 1.0, "top_color": Color(0.72, 0.66, 0.78), "bottom_color": Color(0.15, 0.16, 0.2)})
	return base


# =================================================================== world / lighting
func _build_world() -> void:
	world_env = E.environment(Color(0.3, 0.5, 0.8), Color(0.85, 0.75, 0.6), Color(0.25, 0.22, 0.18), 0.6, Color(0.9, 0.78, 0.6), 0.004)
	world_env.environment.set_meta("wants_volumetric", true)
	world_env.environment.volumetric_fog_density = 0.008
	world_env.environment.volumetric_fog_albedo = Color(1.0, 0.9, 0.75)
	add_child(world_env)
	sky_mat = world_env.environment.sky.sky_material
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.add_to_group("sun")
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_blur = 1.5
	sun.light_angular_distance = 1.0
	add_child(sun)


func set_time(hour: float) -> void:
	_hour = hour
	var night := hour < 6.0 or hour > 19.5
	var day_t := clampf((hour - 6.0) / 12.0, 0.0, 1.0)
	var elev := sin(day_t * PI) * 58.0
	var low := 1.0 - clampf(elev / 30.0, 0.0, 1.0)  # 1 near horizon
	if night:
		sun.rotation_degrees = Vector3(-38, -30, 0)
		sun.light_color = Color(0.55, 0.65, 0.95)
		sun.light_energy = 0.12
		sky_mat.sky_top_color = Color(0.02, 0.03, 0.08)
		sky_mat.sky_horizon_color = Color(0.08, 0.09, 0.16)
		sky_mat.ground_horizon_color = Color(0.06, 0.06, 0.1)
		world_env.environment.ambient_light_energy = 0.4
		world_env.environment.fog_light_color = Color(0.1, 0.12, 0.2)
	else:
		sun.rotation_degrees = Vector3(-maxf(elev, 3.0), lerpf(-80.0, 80.0, day_t), 0)
		sun.light_color = Color(1.0, 0.95, 0.86).lerp(Color(1.0, 0.55, 0.28), low)
		sun.light_energy = lerpf(1.35, 0.9, low)
		sky_mat.sky_top_color = Color(0.28, 0.5, 0.82).lerp(Color(0.32, 0.36, 0.6), low)
		sky_mat.sky_horizon_color = Color(0.82, 0.86, 0.9).lerp(Color(1.0, 0.62, 0.35), low)
		sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
		world_env.environment.ambient_light_energy = lerpf(0.75, 0.55, low)
		world_env.environment.fog_light_color = Color(0.85, 0.82, 0.75).lerp(Color(1.0, 0.65, 0.4), low)
	var lamp := 0.9 if night else (1.4 if low > 0.6 else 0.8)
	for l in interior_lights:
		l.light_energy = lamp
	var pl := 1.2 if (night or low > 0.5) else 0.0
	for l in party_lights:
		l.light_energy = pl
	if bulbs_mat:
		bulbs_mat.emission_energy_multiplier = 3.0 if pl > 0.0 else 0.2


func tween_time(to_hour: float, dur: float) -> void:
	var tw := create_tween()
	tw.tween_method(set_time, _hour, to_hour, dur * (0.01 if GameState.fast_mode else 1.0))
	await tw.finished


# =================================================================== house
func _build_house() -> void:
	var house := Node3D.new()
	house.name = "House"
	add_child(house)
	var wall_m := E.textured("plaster", Color(0.93, 0.86, 0.74), 0.12, 0.92, Vector3(0.6, 0.6, 0.6), 0.05)
	var wood := E.textured("woodfloor", Color(0.55, 0.36, 0.22), 0.3, 0.6, Vector3(0.4, 0.4, 3.0), 0.04)
	var tiles := E.textured("tiles", Color(0.86, 0.84, 0.78), 0.1, 0.35, Vector3(1.5, 1.5, 1.5), 0.2)
	var carpet := E.textured("carpet", Color(0.55, 0.62, 0.72), 0.2, 1.0, Vector3(2, 2, 2), 0.3)
	var trim := E.mat(Color(0.98, 0.96, 0.92), 0.5)

	# floors (top at y = 0.01)
	E.box(house, Vector3(8, 0.2, 12), Vector3(-4, -0.09, 0), wood)
	E.box(house, Vector3(8, 0.2, 6), Vector3(4, -0.09, -3), tiles)
	E.box(house, Vector3(8, 0.2, 6), Vector3(4, -0.09, 3), carpet)
	# ceiling
	E.box(house, Vector3(16.4, 0.2, 12.4), Vector3(0, 3.1, 0), E.mat(Color(0.96, 0.94, 0.9), 0.9))
	# skirting
	for z in [-5.88, 5.88]:
		E.box(house, Vector3(16, 0.12, 0.04), Vector3(0, 0.07, z), trim, false)

	var H := 3.0
	var T := 0.22
	E.wall(house, Vector2(-8, 6), Vector2(8, 6), H, T, wall_m, [
		{"from": 3.0, "to": 4.2, "bottom": 0.0, "top": 2.3},
		{"from": 5.5, "to": 7.2, "bottom": 0.9, "top": 2.2, "glass": true},
		{"from": 9.5, "to": 11.0, "bottom": 0.9, "top": 2.2, "glass": true}])
	E.wall(house, Vector2(-8, -6), Vector2(8, -6), H, T, wall_m, [
		{"from": 3.0, "to": 6.0, "bottom": 0.9, "top": 2.3, "glass": true},
		{"from": 11.0, "to": 13.0, "bottom": 1.1, "top": 2.2, "glass": true}])
	E.wall(house, Vector2(-8, -6), Vector2(-8, 6), H, T, wall_m, [
		{"from": 4.0, "to": 6.5, "bottom": 0.9, "top": 2.3, "glass": true}])
	E.wall(house, Vector2(8, -6), Vector2(8, 6), H, T, wall_m, [
		{"from": 3.0, "to": 4.2, "bottom": 0.0, "top": 2.3},
		{"from": 8.0, "to": 10.0, "bottom": 0.9, "top": 2.2, "glass": true}])
	E.wall(house, Vector2(0, -6), Vector2(0, 6), H, T * 0.7, wall_m, [
		{"from": 2.5, "to": 3.7, "bottom": 0.0, "top": 2.3},
		{"from": 8.3, "to": 9.5, "bottom": 0.0, "top": 2.3}])
	E.wall(house, Vector2(0, 0), Vector2(8, 0), H, T * 0.7, wall_m)

	# front door (swung open) and back door
	var door_m := E.textured("doorwood", Color(0.42, 0.24, 0.13), 0.3, 0.55, Vector3(1, 4, 1), 0.06)
	var fd := E.box(house, Vector3(1.15, 2.25, 0.06), Vector3(-5.0 + 0.05, 1.13, 6.55), door_m, true, deg_to_rad(-80))
	fd.position = Vector3(-4.98, 1.13, 6.6)
	E.box(house, Vector3(0.06, 2.25, 1.15), Vector3(8.6, 1.13, -3.55), door_m, true)

	# roof
	var roof_m := E.textured("rooftile", Color(0.55, 0.22, 0.14), 0.35, 0.8, Vector3(2, 2, 2), 0.25)
	for sgn in [-1.0, 1.0]:
		var slab := E.box(house, Vector3(17.2, 0.25, 7.2), Vector3(0, 4.72, sgn * 3.15), roof_m)
		slab.rotation.x = sgn * 0.45
	for sx in [-1.0, 1.0]:
		var gable := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(12.4, 2.9, 0.22)
		gable.mesh = pm
		gable.material_override = wall_m
		gable.position = Vector3(sx * 8.0, 3.2 + 1.45, 0)
		gable.rotation.y = PI * 0.5
		house.add_child(gable)
	# front step + porch light
	E.box(house, Vector3(2.0, 0.12, 1.0), Vector3(-4.4, 0.06, 6.7), E.mat(Color(0.6, 0.58, 0.55), 0.9))
	E.omni(house, Vector3(-4.4, 2.6, 6.6), Color(1.0, 0.8, 0.55), 0.8, 5.0)

	# interior lights
	interior_lights.append(E.omni(house, Vector3(-4, 2.65, 0), Color(1.0, 0.8, 0.55), 1.0, 9.0, true))
	interior_lights.append(E.omni(house, Vector3(4, 2.65, -3), Color(1.0, 0.85, 0.65), 1.0, 7.0, true))
	interior_lights.append(E.omni(house, Vector3(4, 2.65, 3), Color(1.0, 0.78, 0.55), 1.0, 7.0, true))
	for p in [Vector3(-4, 2.98, 0), Vector3(4, 2.98, -3), Vector3(4, 2.98, 3)]:
		E.cylinder(house, 0.25, 0.3, 0.08, p, E.emissive(Color(1.0, 0.9, 0.7), 1.5))

	_build_living_room(house)
	_build_kitchen(house)


func _build_living_room(house: Node3D) -> void:
	var fabric := E.textured("sofa", Color(0.62, 0.42, 0.25), 0.2, 0.95, Vector3(2, 2, 2), 0.3)
	var wood := E.mat(Color(0.36, 0.22, 0.12), 0.55)
	# rug
	E.box(house, Vector3(4.2, 0.02, 3.2), Vector3(-4, 0.02, -1.6), E.textured("rug", Color(0.72, 0.22, 0.16), 0.35, 1.0, Vector3(3, 3, 3), 0.35), false)
	# sofa facing the TV (north)
	E.box(house, Vector3(2.6, 0.42, 0.95), Vector3(-4, 0.21, 0.2), fabric)
	E.box(house, Vector3(2.6, 0.55, 0.22), Vector3(-4, 0.7, 0.62), fabric)
	for sx in [-1.0, 1.0]:
		E.box(house, Vector3(0.22, 0.6, 0.95), Vector3(-4 + sx * 1.3, 0.3, 0.2), fabric)
	for i in 3:
		E.box(house, Vector3(0.8, 0.12, 0.8), Vector3(-4.85 + i * 0.85, 0.48, 0.15), E.mat(Color(0.7, 0.5, 0.32), 0.95), false)
	# coffee table + TV cabinet + CRT
	E.box(house, Vector3(1.4, 0.06, 0.7), Vector3(-4, 0.42, -1.6), wood)
	for p in [Vector3(-4.6, 0.2, -1.9), Vector3(-3.4, 0.2, -1.9), Vector3(-4.6, 0.2, -1.3), Vector3(-3.4, 0.2, -1.3)]:
		E.box(house, Vector3(0.06, 0.4, 0.06), p, wood, false)
	E.box(house, Vector3(1.8, 0.6, 0.5), Vector3(-4, 0.3, -5.6), wood)
	E.box(house, Vector3(0.8, 0.62, 0.6), Vector3(-4, 0.92, -5.55), E.mat(Color(0.12, 0.12, 0.13), 0.4))
	E.box(house, Vector3(0.6, 0.45, 0.02), Vector3(-4, 0.94, -5.24), E.mat(Color(0.05, 0.08, 0.07), 0.1, 0.3), false)
	# bookshelf
	E.box(house, Vector3(0.4, 2.2, 1.6), Vector3(-7.7, 1.1, -3.6), wood)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for shelf in 4:
		var z := -4.3
		while z < -2.95:
			var w := rng.randf_range(0.04, 0.09)
			var h := rng.randf_range(0.25, 0.38)
			var col := Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.6), rng.randf_range(0.35, 0.7))
			E.box(house, Vector3(0.28, h, w), Vector3(-7.45, 0.12 + shelf * 0.52 + h * 0.5, z), E.mat(col, 0.8), false)
			z += w + 0.01
	# armchair
	E.box(house, Vector3(0.9, 0.42, 0.9), Vector3(-6.6, 0.21, 1.8), fabric)
	E.box(house, Vector3(0.9, 0.5, 0.2), Vector3(-6.6, 0.65, 2.2), fabric)
	# floor lamp
	E.cylinder(house, 0.02, 0.02, 1.6, Vector3(-7.3, 0.8, 1.0), E.mat(Color(0.2, 0.18, 0.15), 0.4, 0.6))
	E.cylinder(house, 0.16, 0.25, 0.3, Vector3(-7.3, 1.7, 1.0), E.emissive(Color(1.0, 0.85, 0.6), 0.8))
	interior_lights.append(E.omni(house, Vector3(-7.3, 1.6, 1.0), Color(1.0, 0.75, 0.45), 0.8, 4.5))
	# radio table (north-east corner of living room)
	E.box(house, Vector3(0.9, 0.75, 0.5), Vector3(-1.2, 0.375, -5.55), wood)
	radio_node = Node3D.new()
	radio_node.position = Vector3(-1.2, 0.75, -5.55)
	house.add_child(radio_node)
	E.box(radio_node, Vector3(0.55, 0.32, 0.24), Vector3(0, 0.16, 0), E.mat(Color(0.45, 0.28, 0.15), 0.4), false)
	E.box(radio_node, Vector3(0.3, 0.2, 0.01), Vector3(-0.08, 0.17, 0.125), E.mat(Color(0.75, 0.68, 0.5), 0.9), false)
	E.cylinder(radio_node, 0.004, 0.004, 0.5, Vector3(0.2, 0.55, 0), E.mat(Color(0.75, 0.75, 0.75), 0.2, 1.0))
	radio_player = AudioStreamPlayer3D.new()
	radio_player.unit_size = 4.0
	radio_player.bus = "Music"
	radio_player.position = Vector3(0, 0.2, 0)
	radio_node.add_child(radio_player)
	radio_player.finished.connect(func(): radio_player.play())
	# plants
	for p in [Vector3(-7.4, 0, 5.3), Vector3(-0.6, 0, 5.3)]:
		E.cylinder(house, 0.2, 0.15, 0.4, p + Vector3(0, 0.2, 0), E.mat(Color(0.7, 0.4, 0.25), 0.8))
		for i in 4:
			E.sphere(house, 0.22, p + Vector3(randf_range(-0.1, 0.1), 0.6 + i * 0.12, randf_range(-0.1, 0.1)), E.mat(Color(0.18, 0.42, 0.18), 0.85))
	# wall photo frames (west wall)
	_frame(house, Vector3(-7.86, 1.65, 3.2), Vector2(0.55, 0.42), Color(0.85, 0.7, 0.55), true)
	_frame(house, Vector3(-7.86, 1.75, 4.4), Vector2(0.4, 0.55), Color(0.75, 0.75, 0.72), true)
	_frame(house, Vector3(-7.86, 1.2, 4.0), Vector2(0.3, 0.3), Color(0.6, 0.75, 0.85), true)


func _frame(parent: Node3D, pos: Vector3, size: Vector2, photo: Color, on_x_wall: bool) -> void:
	var fr := E.mat(Color(0.25, 0.16, 0.08), 0.4)
	var depth := 0.04
	if on_x_wall:
		E.box(parent, Vector3(depth, size.y + 0.08, size.x + 0.08), pos, fr, false)
		E.box(parent, Vector3(0.01, size.y, size.x), pos + Vector3(depth * 0.5 + 0.005, 0, 0), E.mat(photo, 0.3), false)
	else:
		E.box(parent, Vector3(size.x + 0.08, size.y + 0.08, depth), pos, fr, false)
		E.box(parent, Vector3(size.x, size.y, 0.01), pos + Vector3(0, 0, depth * 0.5 + 0.005), E.mat(photo, 0.3), false)


func _build_kitchen(house: Node3D) -> void:
	var cab := E.mat(Color(0.82, 0.74, 0.58), 0.6)
	var top := E.textured("counter", Color(0.3, 0.28, 0.26), 0.25, 0.3, Vector3(2, 2, 2), 0.15)
	E.box(house, Vector3(5.0, 0.86, 0.62), Vector3(4.2, 0.43, -5.6), cab)
	E.box(house, Vector3(5.1, 0.05, 0.68), Vector3(4.2, 0.885, -5.58), top, false)
	for i in 6:
		E.box(house, Vector3(0.78, 0.7, 0.01), Vector3(2.1 + i * 0.84, 0.45, -5.285), E.mat(Color(0.88, 0.8, 0.64), 0.55), false)
	# upper cabinets
	E.box(house, Vector3(3.6, 0.7, 0.36), Vector3(5.2, 2.15, -5.75), cab)
	# stove
	E.box(house, Vector3(0.7, 0.9, 0.62), Vector3(1.35, 0.45, -5.6), E.mat(Color(0.9, 0.9, 0.88), 0.3, 0.2))
	for p in [Vector3(1.2, 0.91, -5.7), Vector3(1.5, 0.91, -5.5)]:
		E.cylinder(house, 0.09, 0.09, 0.02, p, E.mat(Color(0.1, 0.1, 0.1), 0.5))
	# fridge
	E.box(house, Vector3(0.8, 1.9, 0.7), Vector3(7.4, 0.95, -5.5), E.mat(Color(0.94, 0.94, 0.92), 0.25, 0.1))
	# kitchen table + chairs
	var wood := E.mat(Color(0.5, 0.32, 0.18), 0.6)
	E.box(house, Vector3(1.6, 0.06, 1.0), Vector3(4.0, 0.76, -2.4), wood)
	for p in [Vector3(3.3, 0.37, -2.0), Vector3(4.7, 0.37, -2.0), Vector3(3.3, 0.37, -2.8), Vector3(4.7, 0.37, -2.8)]:
		E.box(house, Vector3(0.06, 0.74, 0.06), p, wood, false)
	for p in [Vector3(3.5, 0, -1.55), Vector3(4.5, 0, -1.55), Vector3(3.5, 0, -3.25), Vector3(4.5, 0, -3.25)]:
		E.box(house, Vector3(0.42, 0.05, 0.42), p + Vector3(0, 0.45, 0), wood)
		E.box(house, Vector3(0.42, 0.5, 0.05), p + Vector3(0, 0.72, 0.2 * signf(p.z + 2.4)), wood, false)
	# fruit bowl
	E.cylinder(house, 0.18, 0.12, 0.08, Vector3(4.0, 0.83, -2.4), E.mat(Color(0.85, 0.82, 0.75), 0.4))
	for i in 5:
		E.sphere(house, 0.05, Vector3(3.92 + (i % 3) * 0.07, 0.89, -2.45 + (i / 3) * 0.08), E.mat([Color(0.9, 0.3, 0.1), Color(0.95, 0.75, 0.1), Color(0.4, 0.7, 0.2)][i % 3], 0.5))
	# pantry (tall cupboard, hide spot)
	E.box(house, Vector3(0.9, 2.2, 0.62), Vector3(0.6, 1.1, -5.6), cab)
	# cake-in-progress on counter
	E.cylinder(house, 0.16, 0.16, 0.12, Vector3(4.5, 0.97, -5.55), E.mat(Color(0.98, 0.95, 0.88), 0.6))
	E.cylinder(house, 0.2, 0.14, 0.12, Vector3(5.2, 0.97, -5.55), E.mat(Color(0.75, 0.75, 0.78), 0.3, 0.6))


func _build_nursery() -> void:
	if room_set:
		room_set.queue_free()
	room_set = Node3D.new()
	room_set.name = "Nursery1987"
	add_child(room_set)
	var white := E.mat(Color(0.95, 0.93, 0.88), 0.6)
	# crib
	var c := Vector3(4.0, 0, 3.0)
	E.box(room_set, Vector3(0.75, 0.1, 1.25), c + Vector3(0, 0.45, 0), white)
	E.box(room_set, Vector3(0.68, 0.1, 1.18), c + Vector3(0, 0.55, 0), E.mat(Color(0.95, 0.9, 0.8), 1.0), false)
	for sx in [-1.0, 1.0]:
		for i in 9:
			E.box(room_set, Vector3(0.025, 0.5, 0.025), c + Vector3(sx * 0.37, 0.75, -0.6 + i * 0.15), white, false)
		E.box(room_set, Vector3(0.05, 0.04, 1.25), c + Vector3(sx * 0.37, 1.0, 0), white, false)
	for sz in [-1.0, 1.0]:
		E.box(room_set, Vector3(0.75, 0.7, 0.05), c + Vector3(0, 0.7, sz * 0.62), white, false)
	for p in [Vector3(-0.35, 0, -0.6), Vector3(0.35, 0, -0.6), Vector3(-0.35, 0, 0.6), Vector3(0.35, 0, 0.6)]:
		E.box(room_set, Vector3(0.05, 0.45, 0.05), c + p + Vector3(0, 0.22, 0), white, false)
	# mobile above crib
	for i in 5:
		var a := i * TAU / 5.0
		E.sphere(room_set, 0.05, c + Vector3(cos(a) * 0.25, 1.6, sin(a) * 0.25), E.mat(Color.from_hsv(i / 5.0, 0.45, 0.95), 0.6))
	# rocking chair + night lamp
	E.box(room_set, Vector3(0.6, 0.08, 0.6), Vector3(6.8, 0.45, 4.6), E.mat(Color(0.45, 0.3, 0.18), 0.6))
	E.box(room_set, Vector3(0.6, 0.8, 0.08), Vector3(6.8, 0.85, 4.9), E.mat(Color(0.45, 0.3, 0.18), 0.6))
	E.box(room_set, Vector3(0.5, 0.6, 0.4), Vector3(1.2, 0.3, 5.5), white)
	E.sphere(room_set, 0.14, Vector3(1.2, 0.75, 5.5), E.emissive(Color(1.0, 0.8, 0.5), 1.6))
	var nl := E.omni(room_set, Vector3(1.2, 0.95, 5.3), Color(1.0, 0.7, 0.4), 1.2, 6.0, true)
	nl.name = "NightLamp"
	StaticBatcher.batch(room_set)


func _build_kids_room() -> void:
	if room_set:
		room_set.queue_free()
	room_set = Node3D.new()
	room_set.name = "KidsRoom1992"
	add_child(room_set)
	var wood := E.mat(Color(0.6, 0.42, 0.26), 0.6)
	# bed
	E.box(room_set, Vector3(1.1, 0.4, 2.0), Vector3(6.9, 0.2, 1.3), wood)
	E.box(room_set, Vector3(1.05, 0.15, 1.95), Vector3(6.9, 0.47, 1.3), E.textured("blanket", Color(0.25, 0.45, 0.8), 0.25, 1.0, Vector3(3, 3, 3), 0.4), false)
	E.box(room_set, Vector3(0.6, 0.12, 0.35), Vector3(6.9, 0.6, 0.55), E.mat(Color(0.97, 0.97, 0.95), 1.0), false)
	E.box(room_set, Vector3(1.1, 0.8, 0.08), Vector3(6.9, 0.4, 0.28), wood)
	# wardrobe (hide spot)
	E.box(room_set, Vector3(1.4, 2.1, 0.6), Vector3(6.5, 1.05, 5.55), wood)
	E.box(room_set, Vector3(0.02, 1.9, 0.02), Vector3(6.5, 1.05, 5.24), E.mat(Color(0.3, 0.2, 0.1), 0.6), false)
	# toy chest
	E.box(room_set, Vector3(1.0, 0.55, 0.6), Vector3(4.3, 0.275, 5.5), E.mat(Color(0.85, 0.3, 0.2), 0.7))
	E.box(room_set, Vector3(1.04, 0.08, 0.64), Vector3(4.3, 0.58, 5.5), E.mat(Color(0.95, 0.75, 0.2), 0.7), false)
	# desk with building blocks + drawings on wall
	E.box(room_set, Vector3(1.0, 0.05, 0.55), Vector3(1.3, 0.55, 0.45), wood)
	for p in [Vector3(0.85, 0.27, 0.25), Vector3(1.75, 0.27, 0.25), Vector3(0.85, 0.27, 0.65), Vector3(1.75, 0.27, 0.65)]:
		E.box(room_set, Vector3(0.05, 0.54, 0.05), p, wood, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 9:
		E.box(room_set, Vector3(0.07, 0.07, 0.07), Vector3(1.1 + (i % 3) * 0.08, 0.61 + (i / 3) * 0.075, 0.45), E.mat(Color.from_hsv(rng.randf(), 0.7, 0.9), 0.5), false)
	for i in 3:
		_frame(room_set, Vector3(1.0 + i * 0.75, 1.6, 0.16), Vector2(0.4, 0.3), Color.from_hsv(i * 0.3, 0.3, 0.98), false)
	# Bolt the toy robot (memory) on the rug
	E.box(room_set, Vector3(1.8, 0.02, 1.4), Vector3(3.6, 0.02, 2.6), E.textured("kidsrug", Color(0.35, 0.65, 0.45), 0.3, 1.0, Vector3(4, 4, 4), 0.3), false)
	var bolt := Node3D.new()
	bolt.position = Vector3(3.4, 0.03, 2.4)
	room_set.add_child(bolt)
	var metal := E.mat(Color(0.65, 0.68, 0.72), 0.35, 0.8)
	E.box(bolt, Vector3(0.12, 0.13, 0.09), Vector3(0, 0.15, 0), metal, false)
	E.box(bolt, Vector3(0.09, 0.08, 0.08), Vector3(0, 0.26, 0), metal, false)
	for sx in [-1.0, 1.0]:
		E.sphere(bolt, 0.012, Vector3(sx * 0.02, 0.27, 0.042), E.emissive(Color(0.3, 0.8, 1.0), 2.0))
		E.box(bolt, Vector3(0.03, 0.08, 0.03), Vector3(sx * 0.035, 0.045, 0), metal, false)
		E.box(bolt, Vector3(0.025, 0.09, 0.025), Vector3(sx * 0.08, 0.15, 0), metal, false)
	E.cylinder(bolt, 0.012, 0.012, 0.03, Vector3(0, 0.15, -0.055), E.mat(Color(0.9, 0.7, 0.2), 0.3, 0.8))
	# posters / bunting
	for i in 8:
		var pm := MeshInstance3D.new()
		var pr := PrismMesh.new()
		pr.size = Vector3(0.25, 0.25, 0.01)
		pm.mesh = pr
		pm.material_override = E.mat(Color.from_hsv(i / 8.0, 0.6, 0.95), 0.8)
		pm.position = Vector3(1.0 + i * 0.85, 2.7, 5.86)
		pm.rotation.z = PI
		room_set.add_child(pm)
	StaticBatcher.batch(room_set)


# =================================================================== garden
func _build_garden() -> void:
	var g := Node3D.new()
	g.name = "Garden"
	add_child(g)
	var grass := E.textured("grass", Color(0.36, 0.55, 0.22), 0.35, 0.95, Vector3(0.25, 0.25, 0.25), 0.06)
	E.box(g, Vector3(120, 0.2, 120), Vector3(0, -0.1, 8), grass)
	# path
	var stone := E.textured("stone", Color(0.72, 0.68, 0.6), 0.3, 0.9, Vector3(2, 2, 2), 0.2)
	for i in 14:
		E.box(g, Vector3(1.1, 0.04, 0.8), Vector3(-4.4 + sin(i * 0.7) * 0.15, 0.02, 7.6 + i * 1.45), stone, false)
	# fence
	var fence_m := E.textured("fence", Color(0.82, 0.78, 0.7), 0.25, 0.9, Vector3(1, 4, 1), 0.1)
	_fence_line(g, Vector2(-20, -10), Vector2(-20, 28), fence_m)
	_fence_line(g, Vector2(20, -10), Vector2(20, 28), fence_m)
	_fence_line(g, Vector2(-20, -10), Vector2(20, -10), fence_m)
	_fence_line(g, Vector2(-20, 28), Vector2(-5.2, 28), fence_m)
	_fence_line(g, Vector2(-3.6, 28), Vector2(20, 28), fence_m)
	# trees
	var leaf_cols := [Color(0.22, 0.42, 0.16), Color(0.28, 0.46, 0.18), Color(0.18, 0.36, 0.14)]
	var spots := [Vector3(14, 0, 22), Vector3(16, 0, 3), Vector3(-16, 0, 3), Vector3(-15, 0, -7), Vector3(13, 0, -8), Vector3(9, 0, 25)]
	for i in spots.size():
		E.tree(g, spots[i], randf_range(5.5, 7.5), i, leaf_cols[i % 3])
	for i in 26:
		var a := i * TAU / 26.0
		var p := Vector3(cos(a) * randf_range(32, 45), 0, 8 + sin(a) * randf_range(32, 45))
		E.tree(g, p, randf_range(7, 11), 100 + i, leaf_cols[i % 3])
	# distant hills
	for i in 6:
		var a := i * TAU / 6.0 + 0.3
		E.sphere(g, 40.0, Vector3(cos(a) * 95, -22, 8 + sin(a) * 95), E.mat(Color(0.3, 0.42, 0.25), 1.0), Vector3(1.6, 0.6, 1.0))
	# neighbour houses
	for p in [Vector3(-36, 0, 10), Vector3(34, 0, -4)]:
		E.box(g, Vector3(9, 3.2, 7), p + Vector3(0, 1.6, 0), E.mat(Color(0.85, 0.8, 0.7), 0.9))
		var r := E.box(g, Vector3(10, 0.3, 8), p + Vector3(0, 3.6, 0), E.mat(Color(0.45, 0.25, 0.18), 0.8))
		r.rotation.z = 0.05
	# hedges + flower beds
	var hedge := E.textured("hedge", Color(0.2, 0.38, 0.16), 0.4, 0.95, Vector3(3, 3, 3), 0.2)
	for i in 10:
		E.sphere(g, 0.6, Vector3(-19 + i * 1.1, 0.45, -9.2), hedge, Vector3(1, 0.8, 1))
	E.scatter_flowers(g, Rect2(-7.8, 6.3, 2.6, 1.0), 70, [Color(0.95, 0.3, 0.35), Color(1, 0.85, 0.2), Color(0.95, 0.95, 0.95)], 3)
	E.scatter_flowers(g, Rect2(-2.6, 6.3, 10.0, 1.0), 120, [Color(0.95, 0.4, 0.6), Color(1, 0.6, 0.15), Color(0.7, 0.4, 0.9)], 4)
	E.scatter_grass(g, Rect2(-19.5, -9.5, 39, 37), int(9000 * GameState.detail_scale), [Rect2(-8.2, -6.2, 16.4, 12.4), Rect2(-5.2, 7.0, 1.6, 21), Rect2(0.5, 11.5, 5.2, 3.0)], Color(0.32, 0.52, 0.18))
	# clothesline
	for x in [8.5, 14.5]:
		E.cylinder(g, 0.04, 0.04, 2.0, Vector3(x, 1.0, 18.5), E.mat(Color(0.5, 0.5, 0.5), 0.4, 0.7))
	E.box(g, Vector3(6, 0.01, 0.01), Vector3(11.5, 1.95, 18.5), E.mat(Color(0.9, 0.9, 0.9), 0.5), false)
	var cloth := [Color(0.95, 0.95, 0.95), Color(0.8, 0.25, 0.2), Color(0.25, 0.45, 0.75), Color(0.95, 0.75, 0.2)]
	for i in 4:
		E.box(g, Vector3(0.8, 0.9, 0.02), Vector3(9.5 + i * 1.3, 1.5, 18.5), E.mat(cloth[i], 1.0), false)

	_build_party_area(g)
	_build_shed(g)
	_build_treehouse(g)


func _fence_line(g: Node3D, a: Vector2, b: Vector2, m: Material) -> void:
	var len := a.distance_to(b)
	var dir := (b - a).normalized()
	var n := int(len / 2.0)
	for i in n + 1:
		var p := a + dir * (len * i / maxf(n, 1))
		E.box(g, Vector3(0.12, 1.3, 0.12), Vector3(p.x, 0.65, p.y), m, false)
	var mid := (a + b) * 0.5
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	for h in [0.45, 1.05]:
		var s := Vector3(len, 0.1, 0.05) if along_x else Vector3(0.05, 0.1, len)
		E.box(g, s, Vector3(mid.x, h, mid.y), m, true)


func _build_party_area(g: Node3D) -> void:
	var c := Vector3(3, 0, 13)
	var wood := E.mat(Color(0.45, 0.3, 0.18), 0.6)
	E.box(g, Vector3(3.2, 0.06, 1.2), c + Vector3(0, 0.76, 0), E.mat(Color(0.98, 0.95, 0.88), 0.9))
	E.box(g, Vector3(3.3, 0.35, 1.3), c + Vector3(0, 0.6, 0), E.mat(Color(0.98, 0.95, 0.88), 0.95), false)
	for p in [Vector3(-1.5, 0, -0.5), Vector3(1.5, 0, -0.5), Vector3(-1.5, 0, 0.5), Vector3(1.5, 0, 0.5)]:
		E.box(g, Vector3(0.08, 0.76, 0.08), c + p + Vector3(0, 0.38, 0), wood, false)
	# plates, cups, food
	for i in 6:
		var x := -1.25 + i * 0.5
		for sz in [-1.0, 1.0]:
			E.cylinder(g, 0.11, 0.1, 0.02, c + Vector3(x, 0.8, sz * 0.38), E.mat(Color(0.95, 0.95, 0.97), 0.3))
	for i in 4:
		E.cylinder(g, 0.18, 0.15, 0.08, c + Vector3(-1.1 + i * 0.75, 0.83, 0.05), E.mat([Color(0.9, 0.45, 0.15), Color(0.85, 0.75, 0.3), Color(0.55, 0.3, 0.15), Color(0.95, 0.85, 0.7)][i], 0.6))
	# birthday cake with 5 candles
	cake = Node3D.new()
	cake.position = c + Vector3(0, 0.79, -0.22)
	g.add_child(cake)
	E.cylinder(cake, 0.24, 0.24, 0.18, Vector3(0, 0.09, 0), E.mat(Color(0.98, 0.92, 0.85), 0.6))
	E.cylinder(cake, 0.245, 0.245, 0.03, Vector3(0, 0.16, 0), E.mat(Color(0.9, 0.35, 0.45), 0.5))
	E.cylinder(cake, 0.18, 0.18, 0.1, Vector3(0, 0.23, 0), E.mat(Color(0.98, 0.92, 0.85), 0.6))
	for i in 5:
		var a := i * TAU / 5.0
		var p := Vector3(cos(a) * 0.1, 0.33, sin(a) * 0.1)
		E.cylinder(cake, 0.008, 0.008, 0.1, p, E.mat(Color.from_hsv(i / 5.0, 0.5, 0.95), 0.5))
		var flame := E.sphere(cake, 0.012, p + Vector3(0, 0.065, 0), E.emissive(Color(1.0, 0.7, 0.25), 6.0), Vector3(1, 1.8, 1))
		# one real light for the whole cake (cheap on phones); others are markers
		var l: Node3D = E.omni(cake, Vector3(0, 0.45, 0), Color(1.0, 0.65, 0.3), 0.9, 2.5) if i == 4 else Node3D.new()
		if i != 4:
			cake.add_child(l)
		candles.append([flame, l])
	# chairs
	for i in 3:
		for sz in [-1.0, 1.0]:
			var p := c + Vector3(-1.0 + i * 1.0, 0, sz * 0.95)
			E.box(g, Vector3(0.42, 0.05, 0.42), p + Vector3(0, 0.45, 0), wood)
			E.box(g, Vector3(0.42, 0.5, 0.05), p + Vector3(0, 0.72, sz * 0.2), wood, false)
	# string lights on four poles + bunting
	bulbs_mat = E.emissive(Color(1.0, 0.8, 0.45), 0.2)
	var poles := [c + Vector3(-2.6, 0, -2.2), c + Vector3(2.6, 0, -2.2), c + Vector3(2.6, 0, 2.2), c + Vector3(-2.6, 0, 2.2)]
	for p in poles:
		E.cylinder(g, 0.04, 0.05, 2.7, p + Vector3(0, 1.35, 0), wood, true)
	for i in 4:
		var a: Vector3 = poles[i] + Vector3(0, 2.6, 0)
		var b: Vector3 = poles[(i + 1) % 4] + Vector3(0, 2.6, 0)
		for k in 12:
			var t := (k + 0.5) / 12.0
			var p := a.lerp(b, t) - Vector3(0, sin(t * PI) * 0.35, 0)
			E.sphere(g, 0.035, p, bulbs_mat)
			if k % 2 == 0:
				var pm := MeshInstance3D.new()
				var pr := PrismMesh.new()
				pr.size = Vector3(0.18, 0.22, 0.01)
				pm.mesh = pr
				pm.material_override = E.mat(Color.from_hsv(k / 12.0 + i * 0.2, 0.6, 0.95), 0.8)
				pm.position = p - Vector3(0, 0.15, 0)
				pm.rotation = Vector3(0, atan2(b.x - a.x, b.z - a.z) + PI * 0.5, PI)
				g.add_child(pm)
	for p in [c + Vector3(-2.6, 2.2, 0), c + Vector3(2.6, 2.2, 0)]:
		party_lights.append(E.omni(g, p, Color(1.0, 0.75, 0.45), 0.0, 7.0))
	party_lights.append(E.omni(g, c + Vector3(0, 2.3, 0), Color(1.0, 0.75, 0.45), 0.0, 6.0, true))
	# gift boxes
	for i in 3:
		E.box(g, Vector3(0.3, 0.25, 0.3), c + Vector3(2.0 + i * 0.35, 0.125, -1.0 + i * 0.2), E.mat(Color.from_hsv(i * 0.33, 0.6, 0.9), 0.6))


func _build_shed(g: Node3D) -> void:
	var s := Vector3(12, 0, 12)
	var plank := E.textured("shedwood", Color(0.5, 0.36, 0.24), 0.35, 0.9, Vector3(1, 4, 1), 0.08)
	E.box(g, Vector3(3.2, 0.1, 3.2), s + Vector3(0, 0.05, 0), plank)
	E.wall(g, Vector2(s.x - 1.5, s.z - 1.5), Vector2(s.x + 1.5, s.z - 1.5), 2.4, 0.12, plank)
	E.wall(g, Vector2(s.x - 1.5, s.z + 1.5), Vector2(s.x + 1.5, s.z + 1.5), 2.4, 0.12, plank, [{"from": 1.2, "to": 2.0, "bottom": 1.1, "top": 1.7, "glass": true}])
	E.wall(g, Vector2(s.x + 1.5, s.z - 1.5), Vector2(s.x + 1.5, s.z + 1.5), 2.4, 0.12, plank)
	E.wall(g, Vector2(s.x - 1.5, s.z - 1.5), Vector2(s.x - 1.5, s.z + 1.5), 2.4, 0.12, plank, [{"from": 1.0, "to": 2.1, "bottom": 0.0, "top": 2.0}])
	var roof := E.box(g, Vector3(3.6, 0.15, 3.6), s + Vector3(0, 2.55, 0), E.mat(Color(0.3, 0.3, 0.32), 0.6, 0.4))
	roof.rotation.z = 0.12
	# workbench + tools + trunk
	E.box(g, Vector3(0.6, 0.85, 2.2), s + Vector3(1.1, 0.425, 0), E.mat(Color(0.4, 0.28, 0.17), 0.7))
	E.box(g, Vector3(0.05, 0.9, 1.6), s + Vector3(1.42, 1.6, 0), E.mat(Color(0.55, 0.45, 0.3), 0.9), false)
	for i in 5:
		E.box(g, Vector3(0.03, 0.25, 0.04), s + Vector3(1.38, 1.6, -0.6 + i * 0.3), E.mat(Color(0.5, 0.5, 0.52), 0.3, 0.9), false)
	E.box(g, Vector3(0.9, 0.55, 0.55), s + Vector3(-0.2, 0.275, 1.1), E.mat(Color(0.35, 0.22, 0.12), 0.7))
	E.box(g, Vector3(0.6, 0.6, 0.6), s + Vector3(-0.6, 0.3, -0.9), plank)
	E.omni(g, s + Vector3(0, 2.1, 0), Color(1.0, 0.85, 0.6), 0.5, 4.0)


func _build_treehouse(g: Node3D) -> void:
	var t := Vector3(-12, 0, 14)
	E.tree(g, t, 10.0, 77, Color(0.25, 0.44, 0.17))
	var plank := E.textured("thwood", Color(0.55, 0.38, 0.22), 0.35, 0.9, Vector3(2, 2, 2), 0.1)
	E.box(g, Vector3(3.0, 0.2, 3.0), t + Vector3(0, 3.2, 0), plank)
	# railings with a gap for the ladder (south side)
	E.box(g, Vector3(3.0, 0.7, 0.08), t + Vector3(0, 3.65, -1.46), plank)
	E.box(g, Vector3(0.08, 0.7, 3.0), t + Vector3(-1.46, 3.65, 0), plank)
	E.box(g, Vector3(0.08, 0.7, 3.0), t + Vector3(1.46, 3.65, 0), plank)
	E.box(g, Vector3(1.0, 0.7, 0.08), t + Vector3(-1.0, 3.65, 1.46), plank)
	E.box(g, Vector3(1.0, 0.7, 0.08), t + Vector3(1.0, 3.65, 1.46), plank)
	var roof := E.box(g, Vector3(3.4, 0.12, 3.4), t + Vector3(0, 5.0, 0), E.mat(Color(0.7, 0.25, 0.18), 0.8))
	roof.rotation.x = 0.1
	for p in [Vector3(-1.4, 4.1, -1.4), Vector3(1.4, 4.1, -1.4), Vector3(-1.4, 4.1, 1.4), Vector3(1.4, 4.1, 1.4)]:
		E.box(g, Vector3(0.1, 1.8, 0.1), t + p, plank, false)
	# support stilts
	for p in [Vector3(-1.3, 1.55, -1.3), Vector3(1.3, 1.55, -1.3), Vector3(-1.3, 1.55, 1.3), Vector3(1.3, 1.55, 1.3)]:
		E.box(g, Vector3(0.14, 3.1, 0.14), t + p, plank)
	# ladder (climbable)
	var ladder := E.box(g, Vector3(0.75, 3.4, 0.12), t + Vector3(0, 1.7, 1.62), E.mat(Color(0, 0, 0, 0), 1.0))
	ladder.add_to_group("climbable")
	(ladder.get_child(1) as MeshInstance3D).visible = false
	for sx in [-0.34, 0.34]:
		E.box(g, Vector3(0.07, 3.7, 0.07), t + Vector3(sx, 1.85, 1.62), plank, false)
	for i in 11:
		E.box(g, Vector3(0.68, 0.05, 0.06), t + Vector3(0, 0.3 + i * 0.32, 1.62), plank, false)
	# sign
	E.box(g, Vector3(0.7, 0.35, 0.03), t + Vector3(-0.6, 3.75, 1.52), E.mat(Color(0.85, 0.75, 0.5), 0.9), false)


# =================================================================== characters
func _build_family() -> void:
	var defs := {
		"MUM": {"display_name": "Mum", "stage": Humanoid.Stage.ADULT, "female": true, "skin_color": Color(0.36, 0.22, 0.15),
			"hair_style": "wrap", "dress": true, "dress_color": Color(0.82, 0.38, 0.12), "top_color": Color(0.82, 0.38, 0.12), "bottom_color": Color(0.82, 0.38, 0.12)},
		"DAD": {"display_name": "Dad", "stage": Humanoid.Stage.ADULT, "skin_color": Color(0.27, 0.16, 0.1), "hair_style": "lowcut", "beard": 0.25,
			"top_color": Color(0.32, 0.47, 0.62), "bottom_color": Color(0.22, 0.2, 0.18), "long_sleeves": true, "build": 1.08},
		"SISTER": {"display_name": Story.SISTER_NAME, "stage": Humanoid.Stage.CHILD, "female": true, "height_scale": 1.16, "skin_color": Color(0.33, 0.2, 0.13),
			"hair_style": "puffs", "dress": true, "dress_color": Color(0.86, 0.45, 0.62), "top_color": Color(0.86, 0.45, 0.62)},
		"GRANDMA": {"display_name": "Grandma", "stage": Humanoid.Stage.ADULT, "female": true, "height_scale": 0.93, "build": 1.12, "skin_color": Color(0.32, 0.2, 0.14),
			"hair_style": "wrap", "dress": true, "dress_color": Color(0.42, 0.24, 0.52), "top_color": Color(0.42, 0.24, 0.52)},
		"UNCLE": {"display_name": "Uncle Femi", "stage": Humanoid.Stage.ADULT, "skin_color": Color(0.26, 0.15, 0.1), "hair_style": "bald", "beard": 0.6,
			"top_color": Color(0.24, 0.5, 0.34), "bottom_color": Color(0.85, 0.82, 0.75), "build": 1.12},
		"COUSIN": {"display_name": "Cousin Tayo", "stage": Humanoid.Stage.CHILD, "height_scale": 1.05, "skin_color": Color(0.3, 0.18, 0.12), "hair_style": "lowcut",
			"top_color": Color(0.85, 0.2, 0.2), "bottom_color": Color(0.2, 0.2, 0.25)},
	}
	for key in defs.keys():
		var n := NPC.create(key.capitalize(), defs[key])
		add_child(n)
		npcs[key] = n
		n.visible = false
		n.interact_point.enabled = false


func place(key: String, pos: Vector3, look_at_point = null, visible_on := true) -> NPC:
	var n: NPC = npcs[key]
	n.global_position = pos
	n.visible = visible_on
	n.model.sitting = false
	n.model.waving = false
	n.set_meta("running", false)
	if look_at_point != null:
		n.face(look_at_point)
	return n


# =================================================================== interactables
func _point(pos: Vector3, prompt: String, cb: Callable, marker := false, radius := 1.6) -> Interactable:
	var it := Interactable.new()
	it.prompt = prompt
	it.radius = radius
	it.show_marker = marker
	it.marker_height = 0.35
	it.position = pos
	add_child(it)
	it.interacted.connect(func(_by): cb.call())
	return it


func _build_interactables() -> void:
	# memories
	var mem_pos := {
		"mem_newborn_photo": Vector3(-7.6, 1.4, 3.2),
		"mem_wedding": Vector3(-7.6, 1.4, 4.4),
		"mem_drawing": Vector3(7.4, 1.1, -5.0),
		"mem_height": Vector3(0.2, 0.9, 2.15),
		"mem_toy_robot": Vector3(3.4, 0.2, 2.4),
		"mem_treehouse": Vector3(-12.6, 3.6, 15.2),
	}
	for id in MEMORIES.keys():
		var p := _point(mem_pos[id], "Look: " + MEMORIES[id], _on_memory.bind(id), true, 1.7)
		p.enabled = false
		memory_points[id] = p
	# radio parts
	part_points["battery"] = _point(Vector3(2.4, 0.75, -5.1), "Open the drawer", _on_part.bind("battery"), true)
	part_points["knob"] = _point(Vector3(4.3, 0.6, 5.0), "Search the toy chest", _on_part.bind("knob"), true)
	part_points["screwdriver"] = _point(Vector3(12.9, 1.0, 12.0), "Search the workbench", _on_part.bind("screwdriver"), true)
	for k in part_points:
		part_points[k].enabled = false
	radio_point = _point(Vector3(-1.2, 0.95, -5.15), "Fix the radio", _on_radio, true, 1.8)
	radio_point.enabled = false
	# hide & seek spots
	hide_points["wardrobe"] = _point(Vector3(6.5, 1.0, 5.0), "Open the wardrobe", _on_hide_spot.bind("wardrobe"))
	hide_points["pantry"] = _point(Vector3(0.6, 1.0, -5.0), "Open the pantry", _on_hide_spot.bind("pantry"))
	hide_points["shed"] = _point(Vector3(11.8, 0.6, 13.0), "Open the old trunk", _on_hide_spot.bind("shed"))
	hide_points["treehouse"] = _point(Vector3(-11.6, 3.6, 13.4), "Look behind the crates", _on_hide_spot.bind("treehouse"))
	E.box(self, Vector3(0.5, 0.5, 0.5), Vector3(-11.6, 3.55, 13.0), E.mat(Color(0.5, 0.36, 0.22), 0.8))
	for k in hide_points:
		hide_points[k].enabled = false
	party_point = _point(Vector3(3, 0.5, 12.2), "Join the party", _on_party, true, 1.8)
	party_point.enabled = false
	# family conversation points
	npcs.MUM.interact_point.interacted.connect(func(_b): _on_mum())
	npcs.DAD.interact_point.interacted.connect(func(_b): _on_dad())
	npcs.GRANDMA.interact_point.interacted.connect(func(_b): _ambient_chat("GRANDMA"))
	npcs.UNCLE.interact_point.interacted.connect(func(_b): _ambient_chat("UNCLE"))
	npcs.COUSIN.interact_point.interacted.connect(func(_b): _ambient_chat("COUSIN"))


func _enable_memories() -> void:
	for id in memory_points:
		memory_points[id].enabled = not GameState.has_collectible(CHAPTER, id)


# =================================================================== INTRO (1987)
func play_intro() -> void:
	set_time(21.5)
	_build_nursery()
	player.visible = false
	cin.begin(player)
	UI.set_black(true)
	var baby := Humanoid.new()
	baby.character_id = "protagonist"
	baby.stage = Humanoid.Stage.NEWBORN
	for k in hero_look(Humanoid.Stage.NEWBORN):
		baby.set(k, hero_look(Humanoid.Stage.NEWBORN)[k])
	room_set.add_child(baby)
	baby.position = Vector3(4.0, 0.62, 3.3)
	baby.rotation.x = -PI * 0.5
	place("MUM", Vector3(3.25, 0, 2.95), Vector3(4, 0, 3.0))
	place("DAD", Vector3(4.75, 0, 3.45), Vector3(4, 0, 3.1))
	npcs.MUM.model.reach = 0.6
	npcs.MUM.model.look_target = Vector3(4.0, 0.7, 2.95)
	npcs.DAD.model.look_target = Vector3(4.0, 0.7, 2.95)
	npcs.MUM.look_at_player = false
	npcs.DAD.look_at_player = false

	cin.cut(Vector3(6.6, 2.1, 5.6), Vector3(4.0, 0.7, 3.0), 40)
	await UI.show_still("newborn", 5.5, Story.BIRTH_DATE_TEXT)
	await UI.fade_in(3.0)
	cin.move(Vector3(5.0, 1.45, 4.3), Vector3(4.0, 0.65, 3.0), 12.0, 34)
	await cin.line("ch1_vo_001", 0.5)
	cin.cut(Vector3(4.15, 1.4, 2.55), Vector3(3.25, 1.5, 2.98), 32)
	cin.move(Vector3(4.05, 1.4, 2.65), Vector3(3.25, 1.52, 2.98), 6.0)
	await cin.line("ch1_001")
	cin.cut(Vector3(3.8, 1.55, 3.8), Vector3(4.75, 1.6, 3.45), 32)
	await cin.line("ch1_002")
	cin.cut(Vector3(4.0, 1.25, 2.1), Vector3(4.0, 0.62, 3.0), 30)
	cin.move(Vector3(4.0, 1.05, 2.5), Vector3(4.0, 0.62, 3.0), 6.0, 26)
	await cin.line("ch1_003")
	cin.cut(Vector3(3.6, 1.5, 4.2), Vector3(4.75, 1.62, 3.45), 28)
	cin.move(Vector3(3.9, 1.55, 4.0), Vector3(4.75, 1.64, 3.45), 7.0, 24)
	await cin.line("ch1_004", 1.0)
	await UI.fade_out(1.5)

	# Living room: the family arrives
	baby.reparent(npcs.MUM.model.spine, false)
	var tl: float = npcs.MUM.model.neck.position.y
	baby.position = Vector3(0.18, tl * 0.65, 0.2)
	baby.rotation = Vector3(-PI * 0.5, 0, PI * 0.42)
	npcs.MUM.model.reach = 0.8
	place("MUM", Vector3(-4.0, 0, 1.6), Vector3(-4, 0, 3))
	place("DAD", Vector3(-3.3, 0, 1.9), Vector3(-4, 0, 3))
	place("GRANDMA", Vector3(-4.7, 0, 2.1), Vector3(-4.0, 0, 1.6))
	place("UNCLE", Vector3(-2.9, 0, 2.6), Vector3(-4.0, 0, 1.6))
	place("SISTER", Vector3(-4.4, 0, 2.6), Vector3(-4.0, 0, 1.6))
	npcs.SISTER.model.height_scale = 0.78
	npcs.SISTER.model.rebuild()
	npcs.MUM.model.look_target = Vector3(-3.9, 1.2, 2.0)
	npcs.GRANDMA.model.look_target = Vector3(-3.95, 1.2, 1.8)
	npcs.UNCLE.model.look_target = Vector3(-3.95, 1.2, 1.8)
	cin.cut(Vector3(-2.2, 1.7, 4.6), Vector3(-3.9, 1.2, 2.0), 40)
	await UI.fade_in(1.2)
	cin.move(Vector3(-2.6, 1.55, 4.3), Vector3(-3.9, 1.15, 2.0), 9.0)
	await cin.line("ch1_005")
	await cin.line("ch1_006")
	npcs.DAD.model.arms_up = 0.0
	await cin.line("ch1_007")
	# family photo
	for k in ["MUM", "DAD", "GRANDMA", "UNCLE", "SISTER"]:
		npcs[k].face(Vector3(-3.9, 0, 5.4))
		npcs[k].model.look_target = Vector3(-3.9, 1.5, 5.4)
	cin.cut(Vector3(-3.9, 1.5, 5.3), Vector3(-3.9, 1.2, 2.0), 42)
	await cin.wait(1.2)
	Audio.play_sfx("shutter")
	await UI.flash(Color.WHITE, 1.2)
	await cin.wait(1.5)
	await UI.fade_out(2.0)
	baby.queue_free()
	npcs.SISTER.model.height_scale = 1.16
	npcs.SISTER.model.rebuild()
	npcs.MUM.model.reach = 0.0

	await UI.title_card("", "THE LAST PROMISE", "", 2.5)
	await UI.title_card("CHAPTER ONE", "The Beginning", "", 2.0)
	await _start_morning(true)


# =================================================================== MORNING (1992)
func _setup_morning() -> void:
	set_time(9.5)
	_build_kids_room()
	player.visible = true
	place("MUM", Vector3(4.4, 0, -4.75), Vector3(4.4, 0, -6))
	place("DAD", Vector3(-1.2, 0, -4.45), Vector3(-1.2, 0, -6))
	place("GRANDMA", Vector3(-4.6, 0.05, 0.25), Vector3(-4.6, 0, -3))
	npcs.GRANDMA.model.sitting = true
	place("UNCLE", Vector3(1.0, 0, 10.8), Vector3(3, 0, 13))
	place("COUSIN", Vector3(-6.5, 0, 14.3))
	npcs.COUSIN.set_meta("running", true)
	for k in ["MUM", "DAD", "GRANDMA", "UNCLE", "COUSIN"]:
		npcs[k].interact_point.enabled = true
		npcs[k].look_at_player = true
	npcs.SISTER.visible = false
	npcs.SISTER.interact_point.enabled = false
	_enable_memories()


func _start_morning(from_intro: bool) -> void:
	_setup_morning()
	player.teleport(Vector3(5.8, 0.05, 2.4), PI * 0.75)
	if from_intro:
		cin.begin(player)
		cin.cut(Vector3(2.4, 1.3, 1.2), Vector3(6.2, 0.7, 2.2), 45)
		UI.caption("16 November 1992 — five years later", 4.5)
		await UI.fade_in(2.0)
		cin.move(Vector3(3.2, 1.0, 1.6), Vector3(6.0, 0.6, 2.3), 6.0)
		await cin.line("ch1_vo_002", 0.5)
		cin.end()
	else:
		await UI.fade_in(1.5)
	GameState.reach_checkpoint("morning", false)
	UI.set_objective("It's your fifth birthday! Find Mum in the kitchen.")
	if GameState.touch_mode:
		UI.toast("Left thumb: move · Right thumb: look · USE: interact · ☰: journal", 7.0)
	else:
		UI.toast("Move: WASD · Look: Mouse · Interact: E · Jump: Space · Crouch: C · Journal: Tab", 7.0)


# =================================================================== story beats
func _on_mum() -> void:
	if _busy:
		return
	if not GameState.get_flag("talked_mum"):
		_busy = true
		cin.begin(player)
		player.face_direction(npcs.MUM.global_position - player.global_position)
		var mid: Vector3 = (player.global_position + npcs.MUM.global_position) * 0.5
		cin.cut(mid + Vector3(1.6, 1.2, 1.4), mid + Vector3(0, 0.9, 0), 42)
		npcs.MUM.face(player.global_position)
		await cin.line("ch1_010")
		await cin.line("ch1_011")
		await cin.line("ch1_012")
		await cin.line("ch1_013")
		cin.end()
		GameState.set_flag("talked_mum")
		GameState.reach_checkpoint("talked_mum")
		npcs.MUM.face(Vector3(4.4, 0, -6))
		_busy = false
		_objective_radio()
	else:
		_ambient_chat("MUM")


func _objective_radio() -> void:
	if not GameState.get_flag("talked_dad"):
		UI.set_objective("Find Dad in the living room. He's fighting with Grandma's old radio.")
	else:
		_update_parts_objective()


func _on_dad() -> void:
	if _busy:
		return
	if not GameState.get_flag("talked_mum"):
		_ambient_chat("DAD")
		return
	if not GameState.get_flag("talked_dad"):
		_busy = true
		cin.begin(player)
		var mid: Vector3 = (player.global_position + npcs.DAD.global_position) * 0.5
		npcs.DAD.face(player.global_position)
		cin.cut(mid + Vector3(1.8, 1.3, 1.2), mid + Vector3(0, 1.0, 0), 42)
		await cin.line("ch1_020")
		await cin.line("ch1_021")
		await cin.line("ch1_022")
		cin.end()
		GameState.set_flag("talked_dad")
		_busy = false
		_update_parts_objective()
	elif not GameState.get_flag("radio_fixed"):
		if _parts_found().size() < 3:
			cin.line("ch1_023")
		else:
			cin.line("ch1_024")
	else:
		_ambient_chat("DAD")


func _parts_found() -> Array:
	return GameState.get_flag("parts", [])


func _update_parts_objective() -> void:
	var found := _parts_found()
	for k in part_points:
		part_points[k].enabled = not (k in found)
	if found.size() < 3:
		var missing := []
		for k in PARTS:
			if not k in found:
				missing.append(PARTS[k])
		UI.set_objective("Find the missing radio parts (%d/3): %s" % [found.size(), ", ".join(missing)])
		radio_point.enabled = false
	else:
		UI.set_objective("Bring the parts to Dad and fix the radio.")
		radio_point.enabled = true


func _on_part(id: String) -> void:
	var found := _parts_found().duplicate()
	if id in found:
		return
	found.append(id)
	GameState.set_flag("parts", found)
	Audio.play_sfx("pickup")
	UI.toast("Found: " + PARTS[id])
	_update_parts_objective()


func _on_radio() -> void:
	if _busy or _parts_found().size() < 3:
		return
	_busy = true
	radio_point.enabled = false
	cin.begin(player)
	player.teleport(Vector3(-1.2, 0.05, -4.6), PI)
	npcs.DAD.global_position = Vector3(-0.5, 0, -4.4)
	npcs.DAD.face(Vector3(-1.2, 0.8, -5.5))
	player.model.reach = 1.0
	cin.cut(Vector3(-2.3, 1.4, -3.7), Vector3(-1.2, 0.85, -5.4), 40)
	cin.set_process_unhandled_input(false)
	var steps := [["Open the back panel", 4], ["Fit the battery", 2], ["Attach the tuning knob", 3], ["Tighten the screws", 4]]
	for s in steps:
		await tap_challenge(s[0], s[1])
	cin.set_process_unhandled_input(true)
	UI.hide_meter()
	player.model.reach = 0.0
	Audio.play_sfx("static", -4.0)
	await cin.wait(1.2)
	Audio.stop_music(1.5)
	var radio_stream := Audio.find_stream("music", "radio")
	if radio_stream:
		radio_player.stream = radio_stream
		radio_player.play()
	cin.cut(Vector3(-0.2, 1.5, -3.2), Vector3(-1.0, 0.9, -4.9), 44)
	npcs.DAD.model.arms_up = 1.0
	await cin.line("ch1_025")
	npcs.DAD.model.arms_up = 0.0
	await cin.line("ch1_026")
	player.model.arms_up = 1.0
	await cin.line("ch1_027")
	player.model.arms_up = 0.0
	await cin.line("ch1_028")
	await UI.show_still("radio", 4.0)
	cin.end()
	GameState.set_flag("radio_fixed")
	_busy = false
	GameState.reach_checkpoint("radio_fixed")
	_start_hide_and_seek()


func tap_challenge(text: String, taps: int) -> void:
	var done := 0
	UI.show_meter(text + "  —  tap [E]", 0.0)
	while done < taps:
		await get_tree().process_frame
		if GameState.fast_mode or Input.is_action_just_pressed("interact"):
			done += 1
			Audio.play_sfx("tick", -6.0, 0.9 + done * 0.08)
			UI.show_meter(text + "  —  tap [E]", float(done) / taps)
	await cin.wait(0.25)


# --------------------------------------------------------------- hide & seek
func _start_hide_and_seek() -> void:
	if radio_player.stream == null:
		var rs := Audio.find_stream("music", "radio")
		if rs:
			radio_player.stream = rs
			radio_player.play()
	if hide_spot == "":
		var keys := hide_points.keys()
		hide_spot = keys[randi() % keys.size()]
	for k in hide_points:
		hide_points[k].enabled = true
	UI.set_objective("Hide and seek! Find %s. (Try the wardrobe, the pantry, the shed... or somewhere high.)" % Story.SISTER_NAME)


func _on_hide_spot(id: String) -> void:
	if _busy:
		return
	hide_points[id].enabled = false
	Audio.play_sfx("door", -6.0)
	if id != hide_spot:
		var lines := {"wardrobe": "ch1_030", "pantry": "ch1_031", "shed": "ch1_032", "treehouse": "ch1_031"}
		cin.line(lines[id])
		return
	_busy = true
	cin.begin(player)
	var p: Vector3 = hide_points[id].global_position
	var sis: NPC = place("SISTER", Vector3(p.x, p.y - 1.0 if p.y > 2 else 0.0, p.z) + Vector3(0.3, 0, 0.6), player.global_position)
	if id == "treehouse":
		sis.global_position = Vector3(-11.4, 3.3, 13.9)
	sis.model.arms_up = 1.0
	Audio.play_sfx("giggle")
	var mid := (player.global_position + sis.global_position) * 0.5
	cin.cut(mid + Vector3(1.5, 1.0, 1.5), mid + Vector3(0, 0.7, 0), 44)
	await cin.line("ch1_033")
	sis.model.arms_up = 0.0
	await cin.line("ch1_034")
	await cin.line("ch1_035")
	cin.end()
	for k in hide_points:
		hide_points[k].enabled = false
	GameState.set_flag("sister_found")
	GameState.reach_checkpoint("sister_found")
	_busy = false
	place("SISTER", Vector3(1.3, 0, 13.7), Vector3(3, 0, 12.8), false)
	_start_party_approach()


func _start_party_approach() -> void:
	UI.set_objective("Join your family in the garden for the party.")
	tween_time(17.4, 8.0)
	place("MUM", Vector3(1.8, 0, 12.25), Vector3(3, 0, 13))
	place("DAD", Vector3(4.2, 0, 12.25), Vector3(3, 0, 13))
	place("GRANDMA", Vector3(2.3, 0, 13.95), Vector3(3, 0, 12.8))
	place("UNCLE", Vector3(3.8, 0, 13.95), Vector3(3, 0, 12.8))
	place("COUSIN", Vector3(4.8, 0, 13.6), Vector3(3, 0, 12.8))
	place("SISTER", Vector3(1.3, 0, 13.7), Vector3(3, 0, 12.8))
	for c in candles:
		c[0].visible = true
		c[1].visible = true
	party_point.enabled = true
	Audio.play_music("childhood", 4.0, -4.0)


# --------------------------------------------------------------- birthday
func _on_party() -> void:
	if _busy:
		return
	_busy = true
	party_point.enabled = false
	radio_player.stop()
	set_time(17.6)
	cin.begin(player)
	player.teleport(Vector3(3.0, 0.05, 12.05), 0.0)
	for k in ["MUM", "DAD", "GRANDMA", "UNCLE", "COUSIN", "SISTER"]:
		npcs[k].model.look_target = cake.global_position + Vector3(0, 0.3, 0)
	cin.cut(Vector3(3.0, 2.4, 9.8), Vector3(3.0, 0.9, 13.0), 44)
	cin.move(Vector3(3.0, 1.6, 10.9), Vector3(3.0, 0.95, 12.8), 8.0, 38)
	await cin.line("ch1_040", 1.0)
	cin.cut(Vector3(3.0, 1.15, 14.3), Vector3(3.0, 0.95, 12.2), 36)
	await cin.line("ch1_041")
	# player blows out the candles
	cin.cut(Vector3(3.6, 1.2, 11.3), Vector3(3.0, 1.0, 12.8), 36)
	cin.set_process_unhandled_input(false)
	await hold_challenge("Make a wish... then hold [E] to blow out the candles", 2.4)
	cin.set_process_unhandled_input(true)
	Audio.play_sfx("cheer")
	npcs.UNCLE.model.arms_up = 1.0
	npcs.COUSIN.model.arms_up = 1.0
	await cin.wait(1.5)
	npcs.UNCLE.model.arms_up = 0.0
	npcs.COUSIN.model.arms_up = 0.0
	for k in npcs:
		npcs[k].model.look_target = player.global_position + Vector3(0, 0.9, 0)
	cin.cut(Vector3(2.0, 1.5, 14.6), Vector3(2.4, 1.3, 13.6), 40)
	await cin.line("ch1_042")
	cin.cut(Vector3(3.0, 1.0, 13.3), Vector3(3.0, 0.95, 12.05), 32)
	cin.move(Vector3(3.0, 0.95, 12.9), Vector3(3.0, 0.95, 12.05), 6.0, 26)
	await cin.line("ch1_043")
	cin.cut(Vector3(3.2, 1.6, 12.6), Vector3(3.8, 1.65, 13.95), 36)
	npcs.UNCLE.model.arms_up = 0.5
	await cin.line("ch1_044")
	npcs.UNCLE.model.arms_up = 0.0
	cin.cut(Vector3(3.0, 0.95, 13.1), Vector3(3.0, 0.92, 12.05), 22)
	Audio.play_sfx("promise_chime", -4.0)
	await cin.line("ch1_045", 1.2)
	cin.cut(Vector3(4.6, 1.8, 11.2), Vector3(3.0, 1.0, 12.6), 40)
	await cin.line("ch1_046")
	# birthday photo
	for k in npcs:
		npcs[k].face(Vector3(3, 0, 9.0))
		npcs[k].model.look_target = Vector3(3, 1.4, 9.0)
	player.face_direction(Vector3(0, 0, -1))
	cin.cut(Vector3(3.0, 1.45, 9.3), Vector3(3.0, 1.0, 12.8), 46)
	await cin.wait(1.0)
	Audio.play_sfx("shutter")
	await UI.flash(Color.WHITE, 1.4)
	await UI.show_still("birthday", 5.0, "16 November 1992")
	GameState.add_collectible(CHAPTER, "photo_fifth_birthday")
	UI.toast("Photo added to the album: Fifth Birthday")
	await cin.wait(1.5)
	GameState.set_flag("candles_done")
	await play_growing_up()


func hold_challenge(text: String, seconds: float) -> void:
	var v := 0.0
	var lit := candles.size()
	UI.show_meter(text, 0.0)
	while v < 1.0:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		if GameState.fast_mode or Input.is_action_pressed("interact"):
			v += dt / seconds * (50.0 if GameState.fast_mode else 1.0)
			if randf() < 0.15:
				Audio.play_sfx("blow", -10.0, randf_range(0.9, 1.1))
		else:
			v = maxf(v - dt * 0.25, 0.0)
		UI.show_meter(text, v)
		var should_be_lit := candles.size() - int(floor(v * candles.size()))
		while lit > should_be_lit:
			lit -= 1
			candles[lit][0].visible = false
			candles[lit][1].visible = false
			Audio.play_sfx("candle_out", -4.0, randf_range(0.9, 1.2))
	for c in candles:
		c[0].visible = false
		c[1].visible = false
	UI.hide_meter()


# =================================================================== GROWING UP
func play_growing_up() -> void:
	await UI.fade_out(1.2)
	for k in npcs:
		npcs[k].visible = false
	set_time(18.1)
	player.teleport(Vector3(-2.0, 0.05, 18.0), PI * 0.5)
	player.model.look_target = null
	UI.caption("", 0.1)
	var centre := player.global_position
	cin.orbit(centre, 3.2, 1.3, -0.6, 0.2, 7.0)
	await UI.fade_in(1.5)
	await cin.line("ch1_vo_010")
	var stages := [[Humanoid.Stage.TEEN, "2002", "teen_inventor"], [Humanoid.Stage.YOUNG_ADULT, "2007", "robotics_champion"], [Humanoid.Stage.ADULT, "Today", "engineer_lab"]]
	var angle := 0.2
	for s in stages:
		Audio.play_sfx("whoosh", -6.0)
		await UI.flash(Color(1.0, 0.9, 0.75), 0.9)
		player.appearance = hero_look(s[0])
		player.set_stage(s[0])
		player.model.rotation.y = PI * 0.5
		set_time(18.1 + angle * 0.3)
		UI.caption(s[1], 2.0)
		var h: float = Humanoid.PROPORTIONS[s[0]][0]
		cin.orbit(centre, 3.0 + h * 0.6, h * 0.9, angle, angle + 0.8, 6.0)
		angle += 0.8
		if s[0] == Humanoid.Stage.TEEN:
			await cin.line("ch1_vo_011")
		elif s[0] == Humanoid.Stage.YOUNG_ADULT:
			await cin.line("ch1_vo_012", 1.0)
		else:
			await cin.wait(2.0)
		await UI.show_still(s[2], 3.5, s[1])
	await UI.fade_out(2.5)
	Audio.stop_music(3.0)
	cin.end()
	UI.set_objective("")
	GameState.complete_chapter(CHAPTER)
	await UI.title_card("CHAPTER ONE COMPLETE", "The Curious Mind", "Chapter Two is next in development.", 3.0)
	GameState.return_to_menu()


# =================================================================== misc
func _on_memory(id: String) -> void:
	if GameState.add_collectible(CHAPTER, id):
		Audio.play_sfx("memory")
		var n := 0
		for k in MEMORIES:
			if GameState.has_collectible(CHAPTER, k):
				n += 1
		UI.toast("Memory found (%d/%d): %s" % [n, MEMORIES.size(), MEMORIES[id]])
		if n == MEMORIES.size():
			UI.toast("All memories found! Unlocked: \"Bolt\" companion design (Chapter Two)", 5.0)
			GameState.add_collectible(CHAPTER, "unlock_bolt_design")
		GameState.save_game()
	memory_points[id].enabled = false
	cin.line(id)


func _ambient_chat(key: String) -> void:
	var chats := {
		"MUM": ["Mum: Don't touch the cake. I can see you.", "Mum: Five years. Where did the time go?"],
		"DAD": ["Dad: You're getting tall, chief. Too tall.", "Dad: Your mother says no cake before dinner. I say... also no cake before dinner."],
		"GRANDMA": ["Grandma: Come, let me look at you. Eh! You've grown since breakfast.", "Grandma: That radio was my wedding present, you know."],
		"UNCLE": ["Uncle Femi: These lights will not hang themselves. Actually — can you make them?", "Uncle Femi: Happy birthday, small man!"],
		"COUSIN": ["Tayo: Bet you can't catch me!", "Tayo: Is there going to be jollof?"],
	}
	var opts: Array = chats.get(key, ["..."])
	var line: String = Story.fill(opts[randi() % opts.size()])
	var parts := line.split(": ", true, 1)
	var n: NPC = npcs.get(key)
	if n:
		n.face(player.global_position)
		n.set_talking(true)
	await cin.say(parts[0], parts[1] if parts.size() > 1 else line)
	if n:
		n.set_talking(false)


func _journal_text() -> String:
	var t := "[b]CHAPTER ONE — THE BEGINNING[/b]\n[i]16 November 1992[/i]\n\n"
	t += "[b]Current objective[/b]\n" + UI.get_objective() + "\n\n"
	t += "[b]Memories[/b]\n"
	for id in MEMORIES:
		t += ("  ✓ " if GameState.has_collectible(CHAPTER, id) else "  ○ ") + (MEMORIES[id] if GameState.has_collectible(CHAPTER, id) else "???") + "\n"
	t += "\n[b]Radio parts[/b]\n"
	for k in PARTS:
		t += ("  ✓ " if k in _parts_found() else "  ○ ") + PARTS[k] + "\n"
	t += "\n[i]Press Tab to close[/i]"
	return t


func _restore() -> void:
	## Resume from a checkpoint.
	_setup_morning()
	if GameState.get_flag("sister_found"):
		player.teleport(Vector3(-4.4, 0.05, 8.5), 0.0)
		radio_player.stream = Audio.find_stream("music", "radio")
		_start_party_approach()
		set_time(17.4)
	elif GameState.get_flag("radio_fixed"):
		player.teleport(Vector3(-2.0, 0.05, -3.5), 0.0)
		npcs.DAD.global_position = Vector3(-0.5, 0, -4.4)
		_start_hide_and_seek()
	elif GameState.get_flag("talked_mum"):
		player.teleport(Vector3(3.5, 0.05, -3.8), PI)
		_objective_radio()
	else:
		player.teleport(Vector3(5.8, 0.05, 2.4), PI * 0.75)
		UI.set_objective("It's your fifth birthday! Find Mum in the kitchen.")
	await UI.fade_in(1.5)
