class_name Player
extends CharacterBody3D
## Third-person player controller: walk / jog / sprint, jump, crouch, climb,
## smooth follow camera with collision, contextual interaction.

signal interacted(target)

@export var stage: Humanoid.Stage = Humanoid.Stage.ADULT
@export var appearance := {}   # overrides passed to the Humanoid

var model: Humanoid
var cam_rig: Node3D
var cam_yaw: Node3D
var cam_pitch: Node3D
var spring: SpringArm3D
var camera: Camera3D
var collider: CollisionShape3D

var controls_enabled := true
var camera_enabled := true
var health := 100.0

var walk_speed := 1.6
var jog_speed := 3.8
var sprint_speed := 6.0
var crouch_speed := 1.4
var jump_velocity := 4.6
var climb_speed := 1.6

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _crouched := false
var _climbing := false
var _focus: Interactable = null
var _cam_dist := 3.2
var _cam_height := 1.5
var _was_on_floor := true
var _was_climbing := false
var _climb_dir := Vector3.ZERO


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50)
	_build()
	set_stage(stage)
	GameState.capture_mouse(true)


func _build() -> void:
	collider = CollisionShape3D.new()
	collider.shape = CapsuleShape3D.new()
	add_child(collider)

	cam_rig = Node3D.new()
	cam_rig.name = "CameraRig"
	cam_rig.top_level = true
	add_child(cam_rig)
	cam_yaw = Node3D.new()
	cam_rig.add_child(cam_yaw)
	cam_pitch = Node3D.new()
	cam_pitch.rotation.x = -0.22
	cam_yaw.add_child(cam_pitch)
	spring = SpringArm3D.new()
	spring.collision_mask = 1
	spring.margin = 0.15
	spring.shape = SphereShape3D.new()
	(spring.shape as SphereShape3D).radius = 0.18
	cam_pitch.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.near = 0.05
	spring.add_child(camera)
	spring.add_excluded_object(get_rid())


func set_stage(st: Humanoid.Stage) -> void:
	stage = st
	if model:
		model.queue_free()
	model = Humanoid.new()
	model.character_id = "protagonist"
	model.stage = st
	for k in appearance.keys():
		model.set(k, appearance[k])
	add_child(model)
	model.footstep.connect(_on_footstep)
	var h: float = Humanoid.PROPORTIONS[st][0]
	var sc := h / 1.83
	walk_speed = 1.6 * lerpf(sc, 1.0, 0.4)
	jog_speed = 3.8 * lerpf(sc, 1.0, 0.35)
	sprint_speed = 6.0 * lerpf(sc, 1.0, 0.3)
	crouch_speed = 1.4 * lerpf(sc, 1.0, 0.4)
	jump_velocity = 4.6 * lerpf(sc, 1.0, 0.55)
	_cam_height = h * 0.88
	_cam_dist = lerpf(2.2, 3.2, clampf((h - 1.0) / 0.83, 0, 1))
	_apply_capsule(false)
	spring.spring_length = _cam_dist
	spring.position = Vector3(0.0, 0, 0)
	camera.position = Vector3(h * 0.2, 0, 0)  # over-the-shoulder offset
	cam_rig.global_position = global_position + Vector3(0, _cam_height, 0)


func _apply_capsule(crouch: bool) -> void:
	var h: float = Humanoid.PROPORTIONS[stage][0]
	var cap := collider.shape as CapsuleShape3D
	var height := h * (0.62 if crouch else 1.0)
	cap.radius = clampf(h * 0.16, 0.12, 0.3)
	cap.height = maxf(height, cap.radius * 2.0 + 0.01)
	collider.position.y = cap.height * 0.5


func face_direction(dir: Vector3) -> void:
	if dir.length() > 0.01:
		model.rotation.y = atan2(dir.x, dir.z)


func snap_camera_behind() -> void:
	cam_yaw.rotation.y = model.rotation.y + PI
	cam_rig.global_position = global_position + Vector3(0, _cam_height, 0)


func teleport(pos: Vector3, yaw := 0.0) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	model.rotation.y = yaw
	snap_camera_behind()


func _unhandled_input(event: InputEvent) -> void:
	if not camera_enabled or get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = float(GameState.settings.mouse_sensitivity) * 0.01
		var inv := -1.0 if GameState.settings.invert_y else 1.0
		cam_yaw.rotation.y -= event.relative.x * sens
		cam_pitch.rotation.x = clampf(cam_pitch.rotation.x - event.relative.y * sens * inv, -1.25, 0.65)
	elif event is InputEventMouseButton and event.pressed and GameState.in_gameplay and not GameState.in_cutscene:
		GameState.capture_mouse(true)


func _physics_process(delta: float) -> void:
	# --- camera (gamepad look + smooth follow)
	if camera_enabled:
		var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		cam_yaw.rotation.y -= look.x * delta * 2.6
		var inv := -1.0 if GameState.settings.invert_y else 1.0
		cam_pitch.rotation.x = clampf(cam_pitch.rotation.x - look.y * delta * 1.8 * inv, -1.25, 0.65)
		var tl := UI.touch_look()
		if tl != Vector2.ZERO:
			var ts: float = float(GameState.settings.mouse_sensitivity) * 0.022
			cam_yaw.rotation.y -= tl.x * ts
			cam_pitch.rotation.x = clampf(cam_pitch.rotation.x - tl.y * ts * inv, -1.25, 0.65)
	var crouch_h := 0.7 if _crouched else 1.0
	var target := global_position + Vector3(0, _cam_height * crouch_h, 0)
	cam_rig.global_position = cam_rig.global_position.lerp(target, clampf(delta * 10.0, 0, 1))

	# --- movement
	var input := Vector2.ZERO
	if controls_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis_y := Basis(Vector3.UP, cam_yaw.rotation.y)
	var dir := (basis_y * Vector3(input.x, 0, input.y))
	dir.y = 0
	if dir.length() > 1.0:
		dir = dir.normalized()

	if controls_enabled and Input.is_action_just_pressed("crouch"):
		_crouched = not _crouched
		_apply_capsule(_crouched)

	var speed := jog_speed
	if _crouched:
		speed = crouch_speed
	elif Input.is_action_pressed("walk") or input.length() < 0.55:
		speed = walk_speed if input.length() > 0.0 else 0.0
	elif Input.is_action_pressed("sprint"):
		speed = sprint_speed
	if input.length() > 0.0 and input.length() < 0.55:
		speed = walk_speed

	# --- climbing
	_climbing = false
	if controls_enabled and input.y < -0.3 and is_on_wall():
		for i in get_slide_collision_count():
			var col := get_slide_collision(i)
			var obj := col.get_collider()
			if obj is Node and (obj as Node).is_in_group("climbable"):
				_climbing = true
				break
	if _climbing:
		_climb_dir = -get_wall_normal()
		velocity = _climb_dir * 0.6
		velocity.y = climb_speed
		_crouched = false
	elif _was_climbing and input.y < -0.3:
		# mantle over the top
		velocity = _climb_dir * 2.2
		velocity.y = 3.0
	else:
		if not is_on_floor():
			velocity.y -= _gravity * delta
		elif controls_enabled and Input.is_action_just_pressed("jump") and not _crouched:
			velocity.y = jump_velocity
			Audio.play_sfx("jump", -10.0, randf_range(0.95, 1.05))
		var horiz := dir * speed
		var accel := 12.0 if is_on_floor() else 3.0
		velocity.x = move_toward(velocity.x, horiz.x, accel * delta * maxf(speed, 3.0))
		velocity.z = move_toward(velocity.z, horiz.z, accel * delta * maxf(speed, 3.0))

	_was_climbing = _climbing
	move_and_slide()

	if is_on_floor() and not _was_on_floor:
		Audio.play_sfx("footstep", -6.0, 0.8)
	_was_on_floor = is_on_floor()

	# --- model
	var flat := Vector3(velocity.x, 0, velocity.z)
	if flat.length() > 0.2:
		var yaw := atan2(flat.x, flat.z)
		model.rotation.y = lerp_angle(model.rotation.y, yaw, clampf(delta * 12.0, 0, 1))
	model.move_speed = flat.length()
	model.grounded = is_on_floor()
	model.climbing = _climbing
	model.crouch_target = 1.0 if _crouched else 0.0

	_update_focus()


func _on_footstep() -> void:
	var vol := -14.0 if _crouched else -9.0
	Audio.play_sfx("footstep", vol, randf_range(0.9, 1.1) * (1.25 if stage == Humanoid.Stage.CHILD else 1.0))


# ------------------------------------------------------------------ interaction
func _update_focus() -> void:
	var best: Interactable = null
	if controls_enabled and not GameState.in_cutscene:
		var best_score := INF
		var fwd := Vector3(sin(model.rotation.y), 0, cos(model.rotation.y))
		var cam_fwd := -camera.global_transform.basis.z
		cam_fwd.y = 0
		for n in get_tree().get_nodes_in_group("interactable"):
			var it := n as Interactable
			if it == null or not it.enabled or not it.is_visible_in_tree():
				continue
			var to := it.global_position - global_position
			var dist := Vector2(to.x, to.z).length()
			if dist > it.radius or absf(to.y) > 2.6:
				continue
			var dirn := Vector3(to.x, 0, to.z).normalized()
			var facing := maxf(fwd.dot(dirn), cam_fwd.normalized().dot(dirn))
			var score := dist - facing * 0.8
			if score < best_score:
				best_score = score
				best = it
	if best != _focus:
		_focus = best
		if _focus:
			UI.show_prompt("[E]  " + _focus.prompt)
		else:
			UI.hide_prompt()
	if _focus and controls_enabled and Input.is_action_just_pressed("interact"):
		var f := _focus
		_focus = null
		UI.hide_prompt()
		interacted.emit(f)
		f.interact(self)


func set_controls(on: bool) -> void:
	controls_enabled = on
	camera_enabled = on
	if not on:
		_focus = null
		UI.hide_prompt()
		model.move_speed = 0.0
		velocity.x = 0
		velocity.z = 0


func take_damage(amount: float) -> void:
	health = maxf(health - amount, 0.0)
	UI.set_health(health)


func heal(amount: float) -> void:
	health = minf(health + amount, 100.0)
	UI.set_health(health)
