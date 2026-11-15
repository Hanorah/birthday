extends CanvasLayer
## UI (autoload): fades, letterbox, subtitles, objectives, prompts, toasts,
## title cards, HUD, loading screen, pause menu and settings panel.

const GOLD := Color(0.95, 0.78, 0.45)
const CREAM := Color(0.96, 0.92, 0.84)

var serif: SystemFont
var sans: SystemFont

var _fade: ColorRect
var _bar_top: ColorRect
var _bar_bottom: ColorRect
var _sub_panel: PanelContainer
var _sub_speaker: Label
var _sub_text: Label
var _objective_box: VBoxContainer
var _objective_label: Label
var _prompt: PanelContainer
var _prompt_label: Label
var _toasts: VBoxContainer
var _title_root: Control
var _title_top: Label
var _title_main: Label
var _title_sub: Label
var _caption: Label
var _hud: Control
var _health_bar: ProgressBar
var _ammo_label: Label
var _meter_root: VBoxContainer
var _meter_label: Label
var _meter: ProgressBar
var _loading: Control
var _loading_title: Label
var _loading_num: Label
var _loading_blurb: Label
var _loading_bar: ProgressBar
var _pause: Control
var _settings_layer: Control
var _journal: PanelContainer
var _journal_text: RichTextLabel
var _sub_serial := 0
var _still_root: Control
var _still: TextureRect
var _still_caption: Label
var _loading_bg: TextureRect
var touch: TouchControls


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	serif = SystemFont.new()
	serif.font_names = PackedStringArray(["Georgia", "Cambria", "Times New Roman", "DejaVu Serif", "serif"])
	sans = SystemFont.new()
	sans.font_names = PackedStringArray(["Segoe UI", "Helvetica Neue", "Arial", "DejaVu Sans", "sans-serif"])
	_build()


func _full(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _label(text: String, size: int, font: Font, color := CREAM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel_style(alpha := 0.55, radius := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.035, 0.03, alpha)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _build() -> void:
	# HUD (bottom-most)
	_hud = _full(Control.new())
	add_child(_hud)
	var hb := VBoxContainer.new()
	hb.position = Vector2(36, 36)
	_hud.add_child(hb)
	_health_bar = ProgressBar.new()
	_health_bar.custom_minimum_size = Vector2(240, 10)
	_health_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.25, 0.2)
	fill.set_corner_radius_all(3)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(3)
	_health_bar.add_theme_stylebox_override("fill", fill)
	_health_bar.add_theme_stylebox_override("background", bg)
	_health_bar.value = 100
	hb.add_child(_health_bar)
	_ammo_label = _label("", 26, sans)
	_ammo_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo_label.position = Vector2(-220, -90)
	_hud.add_child(_ammo_label)
	_health_bar.visible = false
	_ammo_label.visible = false

	# Objective (top-left)
	_objective_box = VBoxContainer.new()
	_objective_box.position = Vector2(36, 70)
	_objective_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_objective_box)
	var ot := _label("OBJECTIVE", 13, sans, GOLD)
	_objective_box.add_child(ot)
	_objective_label = _label("", 21, serif)
	_objective_label.custom_minimum_size = Vector2(520, 0)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_box.add_child(_objective_label)
	_objective_box.modulate.a = 0.0

	# Hold meter (centre)
	_meter_root = VBoxContainer.new()
	_meter_root.set_anchors_preset(Control.PRESET_CENTER)
	_meter_root.position = Vector2(-160, 120)
	_meter_root.custom_minimum_size = Vector2(320, 0)
	_meter_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_meter_root)
	_meter_label = _label("", 20, serif)
	_meter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meter_root.add_child(_meter_label)
	_meter = ProgressBar.new()
	_meter.custom_minimum_size = Vector2(320, 12)
	_meter.show_percentage = false
	var mf := StyleBoxFlat.new()
	mf.bg_color = GOLD
	mf.set_corner_radius_all(6)
	_meter.add_theme_stylebox_override("fill", mf)
	_meter.add_theme_stylebox_override("background", bg)
	_meter_root.add_child(_meter)
	_meter_root.visible = false

	# Interaction prompt
	_prompt = PanelContainer.new()
	_prompt.add_theme_stylebox_override("panel", _panel_style(0.6, 20))
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-150, -240)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt)
	_prompt_label = _label("", 20, sans)
	_prompt.add_child(_prompt_label)
	_prompt.visible = false

	# Toasts (top-right)
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toasts.position = Vector2(-460, 36)
	_toasts.custom_minimum_size = Vector2(420, 0)
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)

	# Caption (bottom-left, e.g. dates/places)
	_caption = _label("", 24, serif, CREAM)
	_caption.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_caption.position = Vector2(60, -150)
	_caption.modulate.a = 0.0
	add_child(_caption)

	# Letterbox
	_bar_top = ColorRect.new()
	_bar_top.color = Color.BLACK
	_bar_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar_top.custom_minimum_size = Vector2(0, 0)
	_bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_top)
	_bar_bottom = ColorRect.new()
	_bar_bottom.color = Color.BLACK
	_bar_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_bottom)
	_bar_top.size.y = 0
	_bar_bottom.size.y = 0

	# Subtitles
	_sub_panel = PanelContainer.new()
	_sub_panel.add_theme_stylebox_override("panel", _panel_style(0.45, 4))
	_sub_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sub_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sub_panel)
	var sv := VBoxContainer.new()
	sv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_panel.add_child(sv)
	_sub_speaker = _label("", 16, sans, GOLD)
	_sub_speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(_sub_speaker)
	_sub_text = _label("", 25, serif)
	_sub_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_text.custom_minimum_size = Vector2(900, 0)
	sv.add_child(_sub_text)
	_sub_panel.visible = false

	# Title card
	_title_root = _full(Control.new())
	add_child(_title_root)
	var tv := VBoxContainer.new()
	tv.set_anchors_preset(Control.PRESET_FULL_RECT)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_root.add_child(tv)
	_title_top = _label("", 22, sans, GOLD)
	_title_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(_title_top)
	_title_main = _label("", 76, serif)
	_title_main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(_title_main)
	_title_sub = _label("", 22, serif, Color(0.85, 0.82, 0.76))
	_title_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(_title_sub)
	_title_root.modulate.a = 0.0

	# Journal
	_journal = PanelContainer.new()
	_journal.add_theme_stylebox_override("panel", _panel_style(0.85, 8))
	_journal.set_anchors_preset(Control.PRESET_CENTER)
	_journal.position = Vector2(-380, -260)
	_journal.custom_minimum_size = Vector2(760, 520)
	add_child(_journal)
	_journal_text = RichTextLabel.new()
	_journal_text.bbcode_enabled = true
	_journal_text.add_theme_font_override("normal_font", serif)
	_journal_text.add_theme_font_size_override("normal_font_size", 20)
	_journal_text.add_theme_font_size_override("bold_font_size", 24)
	_journal.add_child(_journal_text)
	_journal.visible = false

	# Cinematic stills (full-screen artwork between 3D scenes)
	_still_root = _full(ColorRect.new())
	(_still_root as ColorRect).color = Color.BLACK
	add_child(_still_root)
	_still = TextureRect.new()
	_still.set_anchors_preset(Control.PRESET_FULL_RECT)
	_still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_still.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_still_root.add_child(_still)
	_still_caption = _label("", 26, serif)
	_still_caption.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_still_caption.position = Vector2(70, -110)
	_still_root.add_child(_still_caption)
	_still_root.modulate.a = 0.0
	_still_root.visible = false

	# On-screen touch controls (phones / tablets)
	if GameState.touch_mode:
		touch = TouchControls.new()
		add_child(touch)

	# Fade (above gameplay UI)
	_fade = _full(ColorRect.new())
	_fade.color = Color(0, 0, 0, 0)
	add_child(_fade)

	_build_loading()
	_build_pause()
	_settings_layer = _full(Control.new())
	add_child(_settings_layer)


# ================================================================ fades / bars
func fade_out(t := 1.0, color := Color.BLACK) -> void:
	_fade.color = Color(color.r, color.g, color.b, _fade.color.a)
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_fade, "color:a", 1.0, _t(t))
	await tw.finished


func fade_in(t := 1.0) -> void:
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_fade, "color:a", 0.0, _t(t))
	await tw.finished


func flash(color := Color.WHITE, t := 0.6) -> void:
	_fade.color = Color(color.r, color.g, color.b, 0.95)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, _t(t))
	await tw.finished


func set_black(on: bool) -> void:
	_fade.color = Color(0, 0, 0, 1.0 if on else 0.0)


func letterbox(on: bool, t := 0.8) -> void:
	var h := 0.0
	if on:
		h = get_viewport().get_visible_rect().size.y * 0.11
	var tw := create_tween().set_parallel()
	tw.tween_property(_bar_top, "size:y", h, _t(t))
	tw.tween_property(_bar_bottom, "size:y", h, _t(t))
	tw.tween_property(_bar_bottom, "position:y", get_viewport().get_visible_rect().size.y - h, _t(t))
	_objective_box.visible = not on
	if on:
		hide_prompt()


func _t(t: float) -> float:
	return t * (0.01 if GameState.fast_mode else 1.0)


# ================================================================ stills
static func load_photo(photo_name: String) -> Texture2D:
	## Loads res://photos/<name>.png|jpg. Works whether or not the editor has imported it.
	for ext in ["png", "jpg", "jpeg", "webp"]:
		var path := "res://photos/%s.%s" % [photo_name, ext]
		var abs_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(abs_path) or FileAccess.file_exists(path):
			var img := Image.load_from_file(abs_path)
			if img:
				return ImageTexture.create_from_image(img)
		if ResourceLoader.exists(path):
			return load(path)
	return null


func show_still(photo_name: String, hold := 4.5, caption_text := "") -> void:
	## Full-screen artwork with a slow push-in. Skips silently if the image is missing.
	var tex := load_photo(photo_name)
	if tex == null:
		return
	_still.texture = tex
	_still_caption.text = caption_text
	_still_root.visible = true
	_still_root.modulate.a = 0.0
	await get_tree().process_frame
	_still.pivot_offset = _still.size * 0.5
	_still.scale = Vector2.ONE
	var zoom := create_tween()
	zoom.tween_property(_still, "scale", Vector2(1.07, 1.07), _t(hold + 2.4)).set_trans(Tween.TRANS_SINE)
	var tw := create_tween()
	tw.tween_property(_still_root, "modulate:a", 1.0, _t(1.2))
	tw.tween_interval(_t(hold))
	tw.tween_property(_still_root, "modulate:a", 0.0, _t(1.2))
	await tw.finished
	_still_root.visible = false


# ================================================================ subtitles
func show_subtitle(speaker: String, text: String, color := GOLD) -> void:
	_sub_serial += 1
	if not GameState.settings.subtitles:
		_sub_panel.visible = false
		return
	_sub_speaker.text = speaker.to_upper()
	_sub_speaker.visible = speaker != ""
	_sub_speaker.add_theme_color_override("font_color", color)
	_sub_text.text = text
	_sub_panel.visible = true
	_sub_panel.reset_size()
	await get_tree().process_frame
	var vs := get_viewport().get_visible_rect().size
	_sub_panel.position = Vector2((vs.x - _sub_panel.size.x) * 0.5, vs.y - _sub_panel.size.y - vs.y * 0.13)


func hide_subtitle() -> void:
	_sub_panel.visible = false


# ================================================================ objective / prompt / toast
func set_objective(text: String) -> void:
	if text == "":
		var tw := create_tween()
		tw.tween_property(_objective_box, "modulate:a", 0.0, 0.4)
		return
	_objective_label.text = text
	Audio.play_sfx("objective", -6.0)
	var t2 := create_tween()
	_objective_box.modulate.a = 0.0
	t2.tween_property(_objective_box, "modulate:a", 1.0, 0.8)


func get_objective() -> String:
	return _objective_label.text if _objective_box.modulate.a > 0.0 else ""


func touch_look() -> Vector2:
	return touch.consume_look() if touch else Vector2.ZERO


func show_prompt(text: String) -> void:
	if GameState.touch_mode:
		text = text.replace("[E]  ", "").replace("[E]", "USE")
	_prompt_label.text = text
	_prompt.visible = true
	_prompt.reset_size()
	var vs := get_viewport().get_visible_rect().size
	_prompt.position = Vector2((vs.x - _prompt.size.x) * 0.5, vs.y * 0.66)


func hide_prompt() -> void:
	_prompt.visible = false


func toast(text: String, seconds := 3.5) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_style(0.6, 6))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(text, 19, sans)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	p.add_child(l)
	_toasts.add_child(p)
	p.modulate.a = 0.0
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(p, "modulate:a", 1.0, 0.3)
	tw.tween_interval(_t(seconds))
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


func caption(text: String, seconds := 4.0) -> void:
	_caption.text = text
	var tw := create_tween()
	tw.tween_property(_caption, "modulate:a", 1.0, _t(1.2))
	tw.tween_interval(_t(seconds))
	tw.tween_property(_caption, "modulate:a", 0.0, _t(1.2))


func title_card(top: String, main: String, sub: String, hold := 3.5) -> void:
	_title_top.text = top
	_title_main.text = main
	_title_sub.text = sub
	var tw := create_tween()
	tw.tween_property(_title_root, "modulate:a", 1.0, _t(1.6))
	tw.tween_interval(_t(hold))
	tw.tween_property(_title_root, "modulate:a", 0.0, _t(1.6))
	await tw.finished


# ================================================================ HUD
func show_combat_hud(on: bool) -> void:
	_health_bar.visible = on
	_ammo_label.visible = on


func set_health(v: float) -> void:
	_health_bar.value = v


func set_ammo(clip: int, reserve: int) -> void:
	_ammo_label.text = "%d  /  %d" % [clip, reserve]


func show_meter(text: String, value: float) -> void:
	_meter_root.visible = true
	_meter_label.text = text.replace("[E]", "USE") if GameState.touch_mode else text
	_meter.value = value * 100.0


func hide_meter() -> void:
	_meter_root.visible = false


func reset_overlays() -> void:
	hide_subtitle()
	hide_prompt()
	hide_meter()
	set_objective("")
	_journal.visible = false
	_title_root.modulate.a = 0.0
	_caption.modulate.a = 0.0
	_still_root.visible = false
	_bar_top.size.y = 0
	_bar_bottom.size.y = 0
	_objective_box.visible = true
	show_combat_hud(false)
	_pause.visible = false
	for c in _settings_layer.get_children():
		c.queue_free()


# ================================================================ journal
func toggle_journal(content_bbcode: String) -> void:
	_journal.visible = not _journal.visible
	_journal_text.text = content_bbcode


func journal_open() -> bool:
	return _journal.visible


# ================================================================ loading screen
func _build_loading() -> void:
	_loading = _full(ColorRect.new())
	(_loading as ColorRect).color = Color(0.03, 0.025, 0.02)
	add_child(_loading)
	_loading_bg = TextureRect.new()
	_loading_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_loading_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_loading_bg.modulate = Color(0.55, 0.55, 0.55)
	_loading_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading.add_child(_loading_bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	v.position = Vector2(90, -300)
	v.custom_minimum_size = Vector2(900, 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading.add_child(v)
	_loading_num = _label("", 20, sans, GOLD)
	v.add_child(_loading_num)
	_loading_title = _label("", 60, serif)
	v.add_child(_loading_title)
	_loading_blurb = _label("", 22, serif, Color(0.8, 0.77, 0.7))
	_loading_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_loading_blurb)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 24)
	v.add_child(sp)
	_loading_bar = ProgressBar.new()
	_loading_bar.custom_minimum_size = Vector2(420, 3)
	_loading_bar.show_percentage = false
	var f := StyleBoxFlat.new()
	f.bg_color = GOLD
	var b := StyleBoxFlat.new()
	b.bg_color = Color(1, 1, 1, 0.12)
	_loading_bar.add_theme_stylebox_override("fill", f)
	_loading_bar.add_theme_stylebox_override("background", b)
	v.add_child(_loading_bar)
	_loading.visible = false


func show_loading(ch: Dictionary) -> void:
	_loading_num.text = ch.get("num", "").to_upper()
	_loading_title.text = ch.get("title", "")
	var tip: String = ch.get("tip", "")
	_loading_blurb.text = ch.get("blurb", "") + ("\n\n" + tip if tip != "" else "")
	_loading_bar.value = 0
	_loading_bg.texture = load_photo(ch.get("image", "")) if ch.get("image", "") != "" else null
	_loading.visible = true
	_fade.color.a = 0.0


func set_loading_progress(p: float) -> void:
	_loading_bar.value = p * 100.0


func hide_loading() -> void:
	set_black(true)
	_loading.visible = false


# ================================================================ pause
func _build_pause() -> void:
	_pause = _full(ColorRect.new())
	(_pause as ColorRect).color = Color(0, 0, 0, 0.6)
	_pause.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_pause)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	v.position = Vector2(120, -200)
	v.add_theme_constant_override("separation", 10)
	_pause.add_child(v)
	v.add_child(_label("PAUSED", 48, serif))
	v.add_child(menu_button("Resume", toggle_pause))
	v.add_child(menu_button("Save Game", func():
		GameState.save_game()
		toast("Game saved")))
	v.add_child(menu_button("Settings", func(): open_settings()))
	v.add_child(menu_button("Quit to Main Menu", func():
		_pause.visible = false
		GameState.return_to_menu()))
	_pause.visible = false


func menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", serif)
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_focus_color", GOLD)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.25))
	b.custom_minimum_size = Vector2(320, 44)
	b.pressed.connect(func():
		Audio.play_sfx("ui_click", -4.0)
		cb.call())
	b.mouse_entered.connect(func(): Audio.play_sfx("ui_hover", -14.0))
	return b


func toggle_pause() -> void:
	if not GameState.in_gameplay:
		return
	_pause.visible = not _pause.visible
	get_tree().paused = _pause.visible
	if _pause.visible:
		GameState.capture_mouse(false)
		(_pause.get_child(0).get_child(1) as Button).grab_focus()
	else:
		for c in _settings_layer.get_children():
			c.queue_free()
		if not GameState.in_cutscene:
			GameState.capture_mouse(true)


func is_paused() -> bool:
	return _pause.visible


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _settings_layer.get_child_count() > 0:
			for c in _settings_layer.get_children():
				c.queue_free()
		elif _journal.visible:
			_journal.visible = false
		elif GameState.in_gameplay:
			toggle_pause()
		get_viewport().set_input_as_handled()


# ================================================================ settings
func open_settings() -> void:
	for c in _settings_layer.get_children():
		c.queue_free()
	var bgc := _full(ColorRect.new())
	(bgc as ColorRect).color = Color(0.02, 0.02, 0.02, 0.92)
	bgc.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_layer.add_child(bgc)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.position = Vector2(-330, -330)
	v.custom_minimum_size = Vector2(660, 0)
	v.add_theme_constant_override("separation", 12)
	bgc.add_child(v)
	v.add_child(_label("SETTINGS", 44, serif))
	var s: Dictionary = GameState.settings

	var q := OptionButton.new()
	for n in GameState.QUALITY_NAMES:
		q.add_item(n)
	q.selected = int(s.quality)
	q.item_selected.connect(func(i): GameState.set_setting("quality", i))
	v.add_child(_row("Graphics quality", q))

	var rs := _slider(0.5, 1.0, 0.05, float(s.render_scale), func(x): GameState.set_setting("render_scale", x))
	v.add_child(_row("Render scale", rs))

	var fs := CheckBox.new()
	fs.button_pressed = bool(s.fullscreen)
	fs.toggled.connect(func(b): GameState.set_setting("fullscreen", b))
	v.add_child(_row("Fullscreen", fs))

	v.add_child(_row("Master volume", _slider(0, 1, 0.05, float(s.master_volume), func(x): GameState.set_setting("master_volume", x))))
	v.add_child(_row("Music volume", _slider(0, 1, 0.05, float(s.music_volume), func(x): GameState.set_setting("music_volume", x))))
	v.add_child(_row("Effects volume", _slider(0, 1, 0.05, float(s.sfx_volume), func(x): GameState.set_setting("sfx_volume", x))))
	v.add_child(_row("Mouse sensitivity", _slider(0.05, 0.6, 0.01, float(s.mouse_sensitivity), func(x): GameState.set_setting("mouse_sensitivity", x))))

	var inv := CheckBox.new()
	inv.button_pressed = bool(s.invert_y)
	inv.toggled.connect(func(b): GameState.set_setting("invert_y", b))
	v.add_child(_row("Invert camera Y", inv))

	var sub := CheckBox.new()
	sub.button_pressed = bool(s.subtitles)
	sub.toggled.connect(func(b): GameState.set_setting("subtitles", b))
	v.add_child(_row("Subtitles", sub))

	var back := menu_button("Back", func(): bgc.queue_free())
	v.add_child(back)
	q.grab_focus()


func _row(text: String, ctrl: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := _label(text, 21, sans)
	l.custom_minimum_size = Vector2(300, 0)
	h.add_child(l)
	ctrl.custom_minimum_size = Vector2(300, 30)
	h.add_child(ctrl)
	return h


func _slider(mn: float, mx: float, step: float, val: float, cb: Callable) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = mn
	sl.max_value = mx
	sl.step = step
	sl.value = val
	sl.value_changed.connect(cb)
	return sl
