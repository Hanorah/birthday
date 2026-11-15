class_name TouchControls
extends Control
## On-screen controls for phones/tablets:
##  - left thumb: floating joystick (move)
##  - right thumb: drag anywhere to look
##  - buttons: USE (interact), JUMP, CROUCH, RUN (hold), journal, pause
##  - during cutscenes: tap anywhere to skip the current line
## Sends real InputEventActions, so gameplay code is identical for keyboard,
## gamepad and touch.

const BTN_COLOR := Color(1, 1, 1, 0.16)
const BTN_EDGE := Color(1, 1, 1, 0.45)
const ACCENT := Color(0.95, 0.78, 0.45)

var _font: Font
var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_touch := -1
var _look_last := Vector2.ZERO
var _look_accum := Vector2.ZERO
var _button_touches := {}   # touch index -> button id
var _buttons := []          # [{id, action, label, anchor(Vector2 0..1), offset, radius}]
var _move_vec := Vector2.ZERO
var interact_highlight := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_buttons = [
		{"id": "use", "action": "interact", "label": "USE", "anchor": Vector2(1, 1), "offset": Vector2(-120, -150), "radius": 62.0},
		{"id": "jump", "action": "jump", "label": "JUMP", "anchor": Vector2(1, 1), "offset": Vector2(-250, -90), "radius": 50.0},
		{"id": "crouch", "action": "crouch", "label": "CROUCH", "anchor": Vector2(1, 1), "offset": Vector2(-250, -230), "radius": 44.0},
		{"id": "run", "action": "sprint", "label": "RUN", "anchor": Vector2(1, 1), "offset": Vector2(-110, -300), "radius": 44.0},
		{"id": "pause", "action": "", "label": "II", "anchor": Vector2(1, 0), "offset": Vector2(-60, 60), "radius": 34.0},
		{"id": "journal", "action": "journal", "label": "☰", "anchor": Vector2(1, 0), "offset": Vector2(-150, 60), "radius": 34.0},
	]


func _gameplay_active() -> bool:
	return GameState.in_gameplay and not get_tree().paused and not UI.journal_open()


func _btn_center(b: Dictionary) -> Vector2:
	var vs := get_viewport_rect().size
	return Vector2(vs.x * b.anchor.x, vs.y * b.anchor.y) + b.offset


func _hit_button(p: Vector2):
	for b in _buttons:
		if p.distance_to(_btn_center(b)) <= b.radius * 1.15:
			return b
	return null


func _send(action: String, pressed: bool, strength := 1.0) -> void:
	if action == "":
		return
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = strength if pressed else 0.0
	Input.parse_input_event(ev)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)


func _on_touch(e: InputEventScreenTouch) -> void:
	var vs := get_viewport_rect().size
	if e.pressed:
		# tap/hold challenges inside cutscenes (radio repair, candles): screen = USE button
		if GameState.in_cutscene and UI._meter_root.visible:
			_button_touches[e.index] = "meter"
			_send("interact", true)
			return
		# cutscene: tap anywhere to skip the current line
		if GameState.in_cutscene and not get_tree().paused:
			_send("skip", true)
			_send("skip", false)
			return
		if not _gameplay_active():
			return
		var b = _hit_button(e.position)
		if b != null:
			_button_touches[e.index] = b.id
			if b.id == "pause":
				UI.toggle_pause()
			else:
				_send(b.action, true)
			queue_redraw()
			return
		if e.position.x < vs.x * 0.42 and _stick_touch == -1:
			_stick_touch = e.index
			_stick_origin = e.position
			_stick_pos = e.position
		elif _look_touch == -1:
			_look_touch = e.index
			_look_last = e.position
	else:
		if _button_touches.has(e.index):
			var id: String = _button_touches[e.index]
			_button_touches.erase(e.index)
			if id == "meter":
				_send("interact", false)
			for b in _buttons:
				if b.id == id:
					_send(b.action, false)
		if e.index == _stick_touch:
			_stick_touch = -1
			_set_move(Vector2.ZERO)
		if e.index == _look_touch:
			_look_touch = -1
	queue_redraw()


func _on_drag(e: InputEventScreenDrag) -> void:
	if e.index == _stick_touch:
		_stick_pos = e.position
		var max_r := 80.0
		var d := (_stick_pos - _stick_origin)
		if d.length() > max_r:
			_stick_origin = _stick_pos - d.normalized() * max_r  # floating stick follows the thumb
			d = _stick_pos - _stick_origin
		_set_move(d / max_r)
		queue_redraw()
	elif e.index == _look_touch:
		_look_accum += e.position - _look_last
		_look_last = e.position


func _set_move(v: Vector2) -> void:
	if v.length() < 0.12:
		v = Vector2.ZERO
	var pairs := [["move_right", maxf(v.x, 0.0)], ["move_left", maxf(-v.x, 0.0)], ["move_back", maxf(v.y, 0.0)], ["move_forward", maxf(-v.y, 0.0)]]
	for p in pairs:
		_send(p[0], p[1] > 0.0, clampf(p[1], 0.0, 1.0))
	_move_vec = v


func consume_look() -> Vector2:
	var l := _look_accum
	_look_accum = Vector2.ZERO
	return l


func release_all() -> void:
	_set_move(Vector2.ZERO)
	for b in _buttons:
		_send(b.action, false)
	_button_touches.clear()
	_stick_touch = -1
	_look_touch = -1


func _process(_d: float) -> void:
	queue_redraw()
	var active := _gameplay_active()
	var want := active or GameState.in_cutscene
	if not active and (_stick_touch != -1 or _button_touches.size() > 0):
		release_all()
	var hl := UI._prompt.visible
	if hl != interact_highlight or want != (modulate.a > 0.5):
		interact_highlight = hl
		modulate.a = 1.0 if want else 0.0
		queue_redraw()


func _draw() -> void:
	var vs := get_viewport_rect().size
	if vs.y > vs.x:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.92))
		_text("Turn your phone sideways to play", vs * 0.5, 34, Color.WHITE)
		return
	if GameState.in_cutscene and UI._meter_root.visible:
		_text("Tap / hold the screen", Vector2(vs.x * 0.5, vs.y * 0.5 + 200), 22, Color(1, 1, 1, 0.7))
		return
	if GameState.in_cutscene:
		_text("Tap to skip line", Vector2(vs.x - 150, vs.y - 40), 18, Color(1, 1, 1, 0.5))
		return
	if not _gameplay_active():
		return
	# joystick
	if _stick_touch != -1:
		draw_circle(_stick_origin, 80, Color(1, 1, 1, 0.1))
		draw_arc(_stick_origin, 80, 0, TAU, 48, BTN_EDGE, 3.0)
		draw_circle(_stick_pos, 36, Color(1, 1, 1, 0.35))
	else:
		var hint := Vector2(170, vs.y - 160)
		draw_arc(hint, 70, 0, TAU, 48, Color(1, 1, 1, 0.22), 3.0)
		draw_circle(hint, 30, Color(1, 1, 1, 0.12))
		_text("MOVE", hint + Vector2(0, 105), 16, Color(1, 1, 1, 0.4))
	# buttons
	for b in _buttons:
		var c := _btn_center(b)
		var pressed: bool = b.id in _button_touches.values()
		var fill := BTN_COLOR
		var edge := BTN_EDGE
		if b.id == "use" and interact_highlight:
			fill = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.45)
			edge = ACCENT
		if pressed:
			fill = Color(1, 1, 1, 0.4)
		draw_circle(c, b.radius, fill)
		draw_arc(c, b.radius, 0, TAU, 48, edge, 3.0)
		_text(b.label, c, 20 if b.radius > 40 else 22, Color.WHITE)


func _text(t: String, center: Vector2, size: int, col: Color) -> void:
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(_font, center + Vector2(-w * 0.5, size * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
