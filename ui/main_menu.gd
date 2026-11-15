extends Node3D
## Main menu: a slow sunset over the island he will one day build,
## with New Game / Continue / Chapters / Settings / Exit.

const E = preload("res://environments/env_builder.gd")

var cam: Camera3D
var _t := 0.0
var _menu: VBoxContainer
var _chapters: Control
var _ui: CanvasLayer


func _ready() -> void:
	GameState.in_gameplay = false
	GameState.in_cutscene = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_scene()
	_build_ui()
	GameState.apply_settings()
	Audio.play_music("menu", 2.0, -3.0)
	UI.fade_in(1.5)


func _build_scene() -> void:
	var we := E.environment(Color(0.22, 0.28, 0.55), Color(1.0, 0.55, 0.3), Color(0.05, 0.1, 0.18), 0.5, Color(1.0, 0.6, 0.4), 0.003)
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-6, 160, 0)
	sun.light_color = Color(1.0, 0.6, 0.35)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.add_to_group("sun")
	add_child(sun)
	# ocean
	var ocean := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(800, 800)
	ocean.mesh = pm
	var om := StandardMaterial3D.new()
	om.albedo_color = Color(0.06, 0.2, 0.3)
	om.metallic = 0.6
	om.roughness = 0.08
	om.normal_enabled = true
	om.normal_texture = E.noise_texture("waves", 0.08, 3)
	om.normal_scale = 0.25
	om.uv1_scale = Vector3(60, 60, 60)
	ocean.material_override = om
	add_child(ocean)
	# island
	var sand := E.textured("sand", Color(0.86, 0.76, 0.56), 0.15, 0.95, Vector3(2, 2, 2), 0.1)
	E.sphere(self, 18.0, Vector3(0, -14.5, -60), sand, Vector3(1.6, 1.0, 1.0))
	E.sphere(self, 12.0, Vector3(4, -7.5, -62), E.textured("jungle", Color(0.15, 0.32, 0.14), 0.4, 0.95, Vector3(3, 3, 3), 0.15), Vector3(1.4, 0.9, 1.0))
	# house silhouette on the island
	E.box(self, Vector3(7, 2.4, 4), Vector3(-6, 4.3, -58), E.mat(Color(0.95, 0.93, 0.88), 0.6), false)
	E.box(self, Vector3(8, 0.3, 5), Vector3(-6, 5.6, -58), E.mat(Color(0.25, 0.22, 0.2), 0.6), false)
	E.box(self, Vector3(5, 1.5, 0.05), Vector3(-6, 4.2, -55.95), E.emissive(Color(1.0, 0.8, 0.5), 1.4), false)
	# palms
	for i in 6:
		var p := Vector3(-18 + i * 6.5, 1.5 + randf() * 1.5, -52 + randf_range(-3, 3))
		_palm(p, randf_range(5, 8))
	StaticBatcher.batch(self)
	cam = Camera3D.new()
	cam.position = Vector3(0, 3.0, 8.0)
	cam.fov = 50
	add_child(cam)
	cam.look_at(Vector3(0, 4.0, -60), Vector3.UP)


func _palm(base: Vector3, h: float) -> void:
	var trunk := E.mat(Color(0.35, 0.26, 0.18), 0.9)
	var leaf := E.mat(Color(0.12, 0.28, 0.12), 0.8)
	for i in 6:
		var t := i / 6.0
		E.cylinder(self, 0.18, 0.22, h / 6.0 + 0.05, base + Vector3(t * t * 1.2, t * h + h / 12.0, 0), trunk)
	var top := base + Vector3(1.2, h, 0)
	for i in 7:
		var a := i * TAU / 7.0
		var b := E.box(self, Vector3(0.5, 0.06, 3.0), top + Vector3(cos(a) * 1.3, -0.3, sin(a) * 1.3), leaf, false)
		b.rotation = Vector3(0.35, -a + PI * 0.5, 0)


func _process(delta: float) -> void:
	_t += delta
	cam.position = Vector3(sin(_t * 0.05) * 3.0, 3.0 + sin(_t * 0.11) * 0.3, 8.0)
	cam.look_at(Vector3(sin(_t * 0.03) * 2.0, 4.0, -60), Vector3.UP)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	var shade := TextureRect.new()
	var grad := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.75))
	g.set_color(1, Color(0, 0, 0, 0.0))
	grad.gradient = g
	grad.fill_to = Vector2(1, 0)
	shade.texture = grad
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	root.position = Vector2(110, -300)
	root.add_theme_constant_override("separation", 6)
	_ui.add_child(root)
	root.add_child(UI._label("A STORY ABOUT ONE LIFE", 16, UI.sans, UI.GOLD))
	root.add_child(UI._label("THE LAST PROMISE", 84, UI.serif))
	var tag := UI._label("A man who spent his life building things\nhas to build a future worth surviving for.", 21, UI.serif, Color(0.88, 0.84, 0.76))
	root.add_child(tag)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 36)
	root.add_child(sp)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 4)
	root.add_child(_menu)
	var cont := UI.menu_button("Continue", func(): GameState.continue_game())
	cont.disabled = not GameState.has_save()
	_menu.add_child(cont)
	_menu.add_child(UI.menu_button("New Game", _confirm_new_game))
	_menu.add_child(UI.menu_button("Chapters", _show_chapters))
	_menu.add_child(UI.menu_button("Settings", func(): UI.open_settings()))
	if not OS.has_feature("web"):
		_menu.add_child(UI.menu_button("Exit", func(): get_tree().quit()))
	else:
		_menu.add_child(UI.menu_button("Full Screen", func():
			var w := get_window()
			w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN))
	(_menu.get_child(0 if not cont.disabled else 1) as Button).grab_focus()

	var foot := UI._label("For %s  ·  born %s" % [Story.HERO_NAME, Story.BIRTH_DATE_TEXT], 15, UI.sans, Color(1, 1, 1, 0.45))
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(110, -60)
	_ui.add_child(foot)


func _confirm_new_game() -> void:
	GameState.new_game()


func _show_chapters() -> void:
	if _chapters:
		_chapters.queue_free()
	_chapters = PanelContainer.new()
	_chapters.add_theme_stylebox_override("panel", UI._panel_style(0.82, 8))
	_chapters.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_chapters.position = Vector2(-760, -380)
	_chapters.custom_minimum_size = Vector2(660, 760)
	_ui.add_child(_chapters)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_chapters.add_child(v)
	v.add_child(UI._label("CHAPTERS", 36, UI.serif))
	for ch in GameState.CHAPTERS:
		var built := GameState.is_built(ch.id)
		var unlocked: bool = ch.id in GameState.unlocked
		var status := ""
		if not built:
			status = "  —  in development"
		elif not unlocked:
			status = "  —  locked"
		elif ch.id in GameState.completed:
			status = "  —  complete"
		var b := UI.menu_button("%s: %s%s" % [ch.num, ch.title, status], func(): GameState.load_chapter(ch.id))
		b.add_theme_font_size_override("font_size", 21)
		b.disabled = not (built and unlocked)
		b.tooltip_text = ch.blurb
		v.add_child(b)
	var n := GameState.collectible_count("ch1")
	v.add_child(UI._label("Memories & photos collected (Ch. 1): %d" % n, 16, UI.sans, UI.GOLD))
	v.add_child(UI.menu_button("Close", func(): _chapters.queue_free()))
