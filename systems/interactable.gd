class_name Interactable
extends Node3D
## Anything the player can use. Emits `interacted(by)`; the level decides
## what happens. Shows a soft floating marker when `show_marker` is on.

signal interacted(by)

@export var prompt := "Interact"
@export var radius := 1.8
@export var enabled := true:
	set(v):
		enabled = v
		if _marker:
			_marker.visible = v and show_marker
@export var one_shot := false
@export var show_marker := false:
	set(v):
		show_marker = v
		if _marker:
			_marker.visible = v and enabled
@export var marker_height := 0.6

var _marker: MeshInstance3D
var _t := randf() * 10.0


func _ready() -> void:
	add_to_group("interactable")
	_marker = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.045
	sm.height = 0.09
	_marker.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.85, 0.5)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.8, 0.45)
	m.emission_energy_multiplier = 3.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker.material_override = m
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.position.y = marker_height
	add_child(_marker)
	_marker.visible = show_marker and enabled


func _process(delta: float) -> void:
	if _marker and _marker.visible:
		_t += delta
		_marker.position.y = marker_height + sin(_t * 2.2) * 0.05
		var s := 1.0 + sin(_t * 3.0) * 0.2
		_marker.scale = Vector3(s, s, s)


func interact(by: Node) -> void:
	if not enabled:
		return
	if one_shot:
		enabled = false
	interacted.emit(by)
