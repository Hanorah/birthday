class_name NPC
extends Node3D
## A story character: a Humanoid with an optional Interactable, idle
## behaviour (looks at the player when close) and scripted movement.

@export var display_name := ""
@export var talk_prompt := "Talk"
@export var look_at_player := true
@export var look_radius := 4.5

var model: Humanoid
var interact_point: Interactable
var collision: StaticBody3D
var _walking := false


static func create(nm: String, cfg: Dictionary) -> NPC:
	var n := NPC.new()
	n.name = nm
	n.display_name = cfg.get("display_name", nm)
	var h := Humanoid.new()
	h.name = "Model"
	for k in cfg.keys():
		if k in h:
			h.set(k, cfg[k])
	n.model = h
	n.add_child(h)
	return n


func _ready() -> void:
	if model == null:
		model = Humanoid.new()
		add_child(model)
	collision = StaticBody3D.new()
	collision.collision_layer = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	var h: float = Humanoid.PROPORTIONS[model.stage][0]
	cap.radius = clampf(h * 0.15, 0.1, 0.28)
	cap.height = maxf(h, cap.radius * 2.0 + 0.01)
	cs.shape = cap
	cs.position.y = cap.height * 0.5
	collision.add_child(cs)
	add_child(collision)
	interact_point = Interactable.new()
	interact_point.prompt = talk_prompt + " to " + display_name if talk_prompt == "Talk" else talk_prompt
	interact_point.radius = 2.0
	interact_point.position.y = h * 0.6
	interact_point.marker_height = h * 0.55
	add_child(interact_point)


func _process(_delta: float) -> void:
	if not look_at_player or model == null:
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p and p.global_position.distance_to(global_position) < look_radius:
		var ph: float = 1.0
		if p is Player:
			ph = Humanoid.PROPORTIONS[(p as Player).stage][0] * 0.9
		model.look_target = p.global_position + Vector3(0, ph, 0)
	elif not _walking:
		model.look_target = null


func face(point: Vector3) -> void:
	var d := point - global_position
	model.rotation.y = atan2(d.x, d.z)


func walk_to(target: Vector3, speed := 1.3) -> void:
	_walking = true
	face(target)
	var dist := global_position.distance_to(target)
	model.move_speed = speed
	var tw := create_tween()
	tw.tween_property(self, "global_position", target, maxf(dist / speed, 0.05) * (0.01 if GameState.fast_mode else 1.0))
	await tw.finished
	model.move_speed = 0.0
	_walking = false


func set_talking(on: bool) -> void:
	if model:
		model.talking = on
