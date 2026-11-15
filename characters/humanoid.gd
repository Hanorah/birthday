class_name Humanoid
extends Node3D
## Procedural, age-aware human figure with procedural animation.
##
## Every character in the game is a Humanoid. Proportions follow real
## age-based head-to-body ratios, so the same person reads as the same person
## from newborn to adult. To swap in a real rigged model (e.g. a likeness
## scanned from photos), drop a GLB at the path returned by
## `model_path_for()` — see docs/ASSETS_NEEDED.md. If found, it is used
## instead and driven via its AnimationPlayer (idle/walk/run/jump/crouch...).

signal footstep

enum Stage { NEWBORN, CHILD, TEEN, YOUNG_ADULT, ADULT, SURVIVOR }

const STAGE_KEYS := ["newborn", "child", "teen", "young_adult", "adult", "survivor"]
# height (m), heads-tall, limb thickness factor
const PROPORTIONS := {
	Stage.NEWBORN: [0.52, 4.0, 1.35],
	Stage.CHILD: [1.10, 5.3, 1.18],
	Stage.TEEN: [1.64, 6.7, 0.95],
	Stage.YOUNG_ADULT: [1.80, 7.3, 1.0],
	Stage.ADULT: [1.83, 7.5, 1.06],
	Stage.SURVIVOR: [1.83, 7.5, 1.04],
}

@export var character_id := ""          # e.g. "protagonist", "mum"
@export var stage: Stage = Stage.ADULT
@export var female := false
@export var height_scale := 1.0
@export var build := 1.0                # body width multiplier
@export var skin_color := Color(0.30, 0.18, 0.12)
@export var hair_color := Color(0.04, 0.035, 0.03)
@export var hair_style := "locs"        # locs, twists, lowcut, puffs, bun, long, wrap, grey_short, bald
@export var beard := 0.0                # 0 none .. 1 full
@export var top_color := Color(0.25, 0.4, 0.3)
@export var bottom_color := Color(0.2, 0.22, 0.3)
@export var shoe_color := Color(0.12, 0.1, 0.09)
@export var dress := false
@export var dress_color := Color(0.7, 0.25, 0.15)
@export var long_sleeves := false
@export var eye_color := Color(0.12, 0.07, 0.04)

# Animation inputs (set by controllers / cinematics)
var move_speed := 0.0
var grounded := true
var crouch_target := 0.0
var climbing := false
var sitting := false
var talking := false
var waving := false
var reach := 0.0
var arms_up := 0.0
var look_target = null      # Vector3 or null
var lie_down := false

var H := 1.8
var hu := 0.24
var _crouch := 0.0
var _phase := 0.0
var _t := 0.0
var _blink_t := 2.0
var _last_step_sign := 1.0
var _hip_y := 0.9
var _leg_len := 0.85

var hips: Node3D
var spine: Node3D
var neck: Node3D
var head: Node3D
var jaw: Node3D
var shoulder_l: Node3D
var shoulder_r: Node3D
var elbow_l: Node3D
var elbow_r: Node3D
var hip_l: Node3D
var hip_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var eyes: Array[Node3D] = []

var _imported: Node3D
var _anim: AnimationPlayer
var _mats := {}


static func model_path_for(id: String, st: int) -> String:
	return "res://assets/characters/%s/%s_%s.glb" % [id, id, STAGE_KEYS[st]]


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	eyes.clear()
	_imported = null
	_anim = null
	if character_id != "":
		var p := model_path_for(character_id, stage)
		if ResourceLoader.exists(p):
			var ps: PackedScene = load(p)
			_imported = ps.instantiate()
			add_child(_imported)
			_anim = _imported.find_child("AnimationPlayer", true, false)
			return
	_build_procedural()


# ------------------------------------------------------------------ materials
func _mat(key: String, color: Color, rough := 0.8, sss := 0.0) -> StandardMaterial3D:
	var k := key + color.to_html()
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if sss > 0.0:
		m.subsurf_scatter_enabled = true
		m.subsurf_scatter_strength = sss
		m.rim_enabled = true
		m.rim = 0.25
		m.rim_tint = 0.6
	_mats[k] = m
	return m


func _skin() -> StandardMaterial3D:
	return _mat("skin", skin_color, 0.52, 0.35)


func _capsule(parent: Node3D, radius: float, length: float, mat: Material, offset := Vector3.ZERO, down := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = maxf(length, radius * 2.0 + 0.001)
	cm.radial_segments = 16
	cm.rings = 6
	mi.mesh = cm
	mi.material_override = mat
	mi.position = offset + (Vector3(0, -length * 0.5, 0) if down else Vector3(0, length * 0.5, 0))
	parent.add_child(mi)
	return mi


func _sphere(parent: Node3D, radius: float, mat: Material, pos := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 20
	sm.rings = 12
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, size: Vector3, mat: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3, n: String) -> Node3D:
	var p := Node3D.new()
	p.name = n
	p.position = pos
	parent.add_child(p)
	return p


# ------------------------------------------------------------------ build
func _build_procedural() -> void:
	var pr: Array = PROPORTIONS[stage]
	H = pr[0] * height_scale * (0.94 if female and stage >= Stage.TEEN else 1.0)
	var heads: float = pr[1]
	var thick: float = pr[2] * build
	hu = H / heads
	var t := clampf((heads - 4.0) / 3.5, 0.0, 1.0)  # 0 baby .. 1 adult
	_leg_len = H * lerpf(0.34, 0.47, t)
	var foot_h := H * 0.03
	_hip_y = _leg_len + foot_h
	var shoulder_y := H - hu - hu * 0.22
	var torso_len := shoulder_y - _hip_y
	var shoulder_w := hu * lerpf(1.45, 1.95, t) * (0.9 if female else 1.0) * build
	var hip_w := hu * lerpf(0.55, 0.62, t) * (1.12 if female else 1.0)
	var limb := H * 0.026 * thick
	var upper_arm := H * lerpf(0.15, 0.185, t)
	var fore_arm := H * lerpf(0.13, 0.16, t)

	var skin := _skin()
	var top := _mat("top", top_color, 0.9)
	var bottom := _mat("bottom", bottom_color, 0.92)
	var shoes := _mat("shoe", shoe_color, 0.6)

	hips = _pivot(self, Vector3(0, _hip_y, 0), "Hips")
	_sphere(hips, hip_w * 1.15, bottom, Vector3(0, 0.0, 0), Vector3(1.0, 0.7, 0.75))

	spine = _pivot(hips, Vector3.ZERO, "Spine")
	# torso: abdomen + chest (ellipsoids sized from real proportions)
	var chest_r := shoulder_w * 0.5
	var belly := _capsule(spine, hip_w * 1.02, torso_len * 0.72, top, Vector3(0, 0, 0), false)
	belly.scale = Vector3(1.0, 1.0, 0.66)
	var chest := _sphere(spine, 0.5, top, Vector3(0, torso_len * 0.6, 0),
		Vector3(shoulder_w * 0.88, torso_len * 0.82, shoulder_w * 0.48 * (1.15 if stage <= Stage.CHILD else 1.0)))
	chest.name = "Chest"
	# shoulder line
	var traps := _capsule(spine, limb * 1.35, shoulder_w * 0.95, top)
	traps.rotation.z = PI * 0.5
	traps.position = Vector3(0, torso_len * 0.9, -limb * 0.3)
	if female and stage >= Stage.TEEN:
		for sx in [-1.0, 1.0]:
			_sphere(spine, chest_r * 0.24, top, Vector3(sx * chest_r * 0.36, torso_len * 0.64, chest_r * 0.42), Vector3(1, 0.9, 0.8))
	if dress:
		var dm := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		var dlen := _leg_len * 0.72
		cyl.top_radius = hip_w * 1.1
		cyl.bottom_radius = hip_w * 2.0
		cyl.height = dlen
		dm.mesh = cyl
		dm.material_override = _mat("dress", dress_color, 0.85)
		dm.position = Vector3(0, -dlen * 0.5 + hip_w * 0.4, 0)
		dm.scale = Vector3(1, 1, 0.8)
		hips.add_child(dm)
		chest.material_override = _mat("dress", dress_color, 0.85)

	# neck + head
	neck = _pivot(spine, Vector3(0, torso_len, 0), "Neck")
	_capsule(neck, limb * 1.25, hu * 0.35, skin, Vector3.ZERO, false)
	head = _pivot(neck, Vector3(0, hu * 0.22, 0), "Head")
	_build_head()

	# arms
	for side in [-1.0, 1.0]:
		var sh := _pivot(spine, Vector3(side * shoulder_w * 0.5, torso_len * 0.93, 0), "Shoulder")
		_sphere(sh, limb * 1.35, top, Vector3.ZERO)
		_capsule(sh, limb * 1.12, upper_arm, top if (long_sleeves or upper_arm > 0) else skin)
		if not long_sleeves:
			# short sleeve: lower half of upper arm shows skin
			_capsule(sh, limb * 1.0, upper_arm * 0.5, skin, Vector3(0, -upper_arm * 0.5, 0))
		var el := _pivot(sh, Vector3(0, -upper_arm, 0), "Elbow")
		_capsule(el, limb * 0.95, fore_arm, top if long_sleeves else skin)
		var hand := _sphere(el, limb * 1.25, skin, Vector3(0, -fore_arm - limb * 0.6, 0), Vector3(0.8, 1.25, 0.55))
		hand.name = "Hand"
		if side < 0:
			shoulder_r = sh
			elbow_r = el
		else:
			shoulder_l = sh
			elbow_l = el

	# legs
	var thigh := _leg_len * 0.5
	var shin := _leg_len * 0.5
	for side in [-1.0, 1.0]:
		var hp := _pivot(hips, Vector3(side * hip_w * 0.55, 0, 0), "Hip")
		var leg_mat := bottom
		_capsule(hp, limb * 1.55, thigh, leg_mat)
		var kn := _pivot(hp, Vector3(0, -thigh, 0), "Knee")
		var shorts := stage == Stage.CHILD and not dress
		_capsule(kn, limb * 1.15, shin, skin if (shorts or dress) else bottom)
		var ft := _box(kn, Vector3(limb * 2.2, foot_h * 1.4, H * 0.14), shoes, Vector3(0, -shin - foot_h * 0.3, H * 0.035))
		ft.name = "Foot"
		if side < 0:
			hip_r = hp
			knee_r = kn
		else:
			hip_l = hp
			knee_l = kn
	if stage == Stage.NEWBORN:
		_swaddle()
	StaticBatcher.batch_rig(self)


func _swaddle() -> void:
	# Newborns are swaddled: hide limbs inside a soft blanket.
	var blanket := _mat("blanket", Color(0.95, 0.88, 0.72), 1.0)
	for n in [shoulder_l, shoulder_r, hip_l, hip_r]:
		n.visible = false
	_capsule(hips, H * 0.2, H * 0.78, blanket, Vector3(0, -H * 0.12, 0), false)
	_sphere(head, hu * 0.55, blanket, Vector3(0, hu * 0.45, -hu * 0.12), Vector3(1.05, 1.0, 1.0))


func _build_head() -> void:
	var skin := _skin()
	var r := hu * 0.48
	var face_z := r * 0.92
	var skull := _sphere(head, r, skin, Vector3(0, hu * 0.5, 0), Vector3(0.88 if not female else 0.84, 1.08, 1.0))
	skull.name = "Skull"
	# jaw / chin
	jaw = _pivot(head, Vector3(0, hu * 0.3, r * 0.15), "Jaw")
	_sphere(jaw, r * 0.62, skin, Vector3(0, -hu * 0.02, r * 0.18), Vector3(1.05 if not female else 0.95, 0.75, 0.9))
	# eyes
	var white := _mat("eyewhite", Color(0.93, 0.9, 0.86), 0.25)
	var iris := _mat("iris", eye_color, 0.15)
	var pupil := _mat("pupil", Color(0.01, 0.01, 0.01), 0.05)
	var eye_y := hu * 0.53
	var eye_x := r * 0.36
	var eye_r := hu * (0.07 if stage > Stage.CHILD else 0.085)
	for sx in [-1.0, 1.0]:
		var e := Node3D.new()
		e.position = Vector3(sx * eye_x, eye_y, face_z * 1.0)
		head.add_child(e)
		_sphere(e, eye_r, white, Vector3.ZERO, Vector3(1.2, 0.9, 0.55))
		_sphere(e, eye_r * 0.58, iris, Vector3(0, 0, eye_r * 0.42), Vector3(1, 1, 0.5))
		_sphere(e, eye_r * 0.28, pupil, Vector3(0, 0, eye_r * 0.62), Vector3(1, 1, 0.4))
		eyes.append(e)
		# brow
		var brow := _box(head, Vector3(eye_r * 2.6, eye_r * (0.35 if not female else 0.22), eye_r * 0.6), _mat("brow", hair_color.lightened(0.05), 1.0),
			Vector3(sx * eye_x, eye_y + eye_r * 1.45, face_z * 0.9))
		brow.rotation.z = sx * -0.12
		# lid crease (skin, darker)
		_sphere(head, eye_r * 1.15, _mat("lid", skin_color.darkened(0.1), 0.6), Vector3(sx * eye_x, eye_y + eye_r * 1.0, face_z * 0.93), Vector3(1.15, 0.28, 0.7))
	# nose — broad
	var nose_m := _mat("nose", skin_color.darkened(0.04), 0.5)
	_sphere(head, hu * 0.06, nose_m, Vector3(0, hu * 0.40, face_z * 1.02), Vector3(1.0, 1.3, 1.0))
	_sphere(head, hu * 0.07, nose_m, Vector3(0, hu * 0.36, face_z * 1.0), Vector3(1.55, 0.85, 0.95))
	# lips
	var lip := _mat("lip", skin_color.darkened(0.22).lerp(Color(0.35, 0.12, 0.12), 0.25), 0.45)
	_sphere(head, hu * 0.06, lip, Vector3(0, hu * 0.285, face_z * 0.97), Vector3(1.9, 0.55, 0.8))
	_sphere(jaw, hu * 0.06, lip, Vector3(0, -hu * 0.03, face_z * 0.83), Vector3(1.8, 0.6, 0.8))
	# ears
	for sx in [-1.0, 1.0]:
		_sphere(head, hu * 0.085, skin, Vector3(sx * r * 0.88, hu * 0.46, 0), Vector3(0.45, 1.0, 0.75))
	_build_hair(r)
	if beard > 0.0:
		_build_beard(r, face_z)


func _build_hair(r: float) -> void:
	var hm := _mat("hair", hair_color, 0.85)
	var cy := hu * 0.5
	match hair_style:
		"bald":
			pass
		"lowcut", "grey_short":
			_hair_cap(hm, r, cy, 1.0)
		"locs", "twists":
			_hair_cap(hm, r, cy, 1.02)
			var rng := RandomNumberGenerator.new()
			rng.seed = 1987
			var count := 46 if hair_style == "locs" else 34
			var length := hu * (0.38 if hair_style == "locs" else 0.2)
			for i in count:
				var theta := rng.randf_range(0.0, TAU)
				var phi := rng.randf_range(0.0, 1.15)   # from top
				var dir := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
				if dir.z > 0.55 and phi > 0.75:
					continue  # keep forehead clear
				var piv := Node3D.new()
				piv.position = Vector3(0, cy + r * 0.3, -r * 0.12) + Vector3(dir.x * 0.86, dir.y * 0.72, dir.z * 0.92) * r
				head.add_child(piv)
				var up := dir.lerp(Vector3.UP, 0.35).normalized()
				if hair_style == "locs":
					up = (dir + Vector3(0, -0.9, 0) * (phi / 1.15)).normalized()
				piv.basis = Basis(Quaternion(Vector3.UP, up))
				var l := length * rng.randf_range(0.75, 1.15)
				var c := _capsule(piv, hu * 0.042, l, hm, Vector3.ZERO, false)
				c.rotation.z = rng.randf_range(-0.25, 0.25)
				var xf := piv.transform * c.transform
				piv.remove_child(c)
				head.add_child(c)
				c.transform = xf
				head.remove_child(piv)
				piv.free()
		"puffs":
			_hair_cap(hm, r, cy, 1.03)
			for sx in [-1.0, 1.0]:
				_sphere(head, r * 0.5, hm, Vector3(sx * r * 0.75, cy + r * 0.85, -r * 0.1))
		"bun":
			_hair_cap(hm, r, cy, 1.03)
			_sphere(head, r * 0.48, hm, Vector3(0, cy + r * 0.9, -r * 0.45))
		"long":
			_sphere(head, r * 1.06, hm, Vector3(0, cy + r * 0.08, -r * 0.08), Vector3(0.95, 1.0, 1.0))
			_capsule(head, r * 0.85, hu * 1.1, hm, Vector3(0, cy, -r * 0.45)).scale = Vector3(1.1, 1, 0.5)
		"wrap":
			var wm := _mat("wrap", dress_color.lightened(0.15), 0.9)
			_sphere(head, r * 1.12, wm, Vector3(0, cy + r * 0.25, -r * 0.05), Vector3(0.95, 0.85, 1.0))
			_sphere(head, r * 0.6, wm, Vector3(0, cy + r * 1.05, -r * 0.15), Vector3(1.4, 0.8, 1.0))


func _hair_cap(hm: Material, r: float, cy: float, grow: float) -> void:
	# Covers crown and back of the skull, leaving a natural hairline above the brows.
	_sphere(head, r * grow, hm, Vector3(0, cy + r * 0.3, -r * 0.14), Vector3(0.92, 0.82, 0.98))
	_sphere(head, r * 0.9 * grow, hm, Vector3(0, cy + r * 0.05, -r * 0.3), Vector3(0.95, 0.95, 0.85))


func _build_beard(r: float, face_z: float) -> void:
	var bm := _mat("beard", hair_color.lightened(0.02), 1.0)
	var b := _sphere(jaw, r * 0.72, bm, Vector3(0, -hu * 0.03, r * 0.16), Vector3(1.12, 0.62 + 0.25 * beard, 0.95))
	b.name = "Beard"
	# sideburns + cheeks
	for sx in [-1.0, 1.0]:
		_sphere(head, r * 0.3, bm, Vector3(sx * r * 0.72, hu * 0.36, r * 0.3), Vector3(0.6, 1.4, 0.9))
	# moustache
	_sphere(head, hu * 0.055, bm, Vector3(0, hu * 0.31, face_z * 0.98), Vector3(2.4, 0.5, 0.7))
	# re-add lower lip in front of beard
	var lip := _mat("lip", skin_color.darkened(0.22).lerp(Color(0.35, 0.12, 0.12), 0.25), 0.45)
	_sphere(jaw, hu * 0.055, lip, Vector3(0, -hu * 0.025, face_z * 0.92), Vector3(1.7, 0.55, 0.7))


# ------------------------------------------------------------------ animate
func _process(delta: float) -> void:
	_t += delta
	if _imported:
		_drive_imported()
		return
	if hips == null:
		return
	_crouch = move_toward(_crouch, crouch_target, delta * 4.0)
	var spd := move_speed
	var stride := maxf(_leg_len * 1.7, 0.4)
	if spd > 0.05:
		_phase = fmod(_phase + delta * spd / stride * TAU, TAU * 1000.0)
	var amt := clampf(spd / 1.8, 0.0, 1.0)
	var run := clampf((spd / maxf(H, 0.5) - 1.6) / 1.6, 0.0, 1.0)
	var s := sin(_phase)
	var c := cos(_phase)

	# footstep events
	var sg := signf(s)
	if amt > 0.2 and sg != _last_step_sign and grounded and not climbing:
		footstep.emit()
	_last_step_sign = sg

	var thigh_amp := 0.45 * amt + 0.3 * run
	var knee_amp := 0.6 * amt + 0.7 * run
	var arm_amp := 0.35 * amt + 0.45 * run
	var breath := sin(_t * 1.6) * 0.012

	var hl := -s * thigh_amp
	var hr := s * thigh_amp
	var kl := maxf(0.0, c) * knee_amp + 0.05 * amt
	var kr := maxf(0.0, -c) * knee_amp + 0.05 * amt
	var al := s * arm_amp
	var ar := -s * arm_amp
	var el := -0.15 - 0.9 * run - 0.1 * amt
	var er := el
	var lean := 0.06 * amt + 0.16 * run
	var hip_y := _hip_y + (absf(c) - 0.6) * 0.05 * H * amt
	var arm_out := 0.07

	# crouch
	if _crouch > 0.0:
		hl = lerpf(hl, -1.2 + hl * 0.4, _crouch)
		hr = lerpf(hr, -1.2 + hr * 0.4, _crouch)
		kl = lerpf(kl, 1.9 + kl * 0.3, _crouch)
		kr = lerpf(kr, 1.9 + kr * 0.3, _crouch)
		lean = lerpf(lean, 0.45, _crouch)
		hip_y -= _leg_len * 0.38 * _crouch
		el = lerpf(el, -0.9, _crouch)
		er = el

	if not grounded and not climbing:
		hl = -0.55
		hr = 0.15
		kl = 0.9
		kr = 0.5
		al = -0.5
		ar = 0.4
		arm_out = 0.35

	if climbing:
		var cs := sin(_t * 5.0)
		al = -2.7 + cs * 0.35
		ar = -2.7 - cs * 0.35
		el = -0.5
		er = -0.5
		hl = -0.7 + cs * 0.4
		hr = -0.7 - cs * 0.4
		kl = 1.1
		kr = 1.1
		lean = -0.05
		arm_out = 0.15

	if sitting:
		hl = -1.5
		hr = -1.5
		kl = 1.5
		kr = 1.5
		hip_y = _hip_y - _leg_len * 0.5
		al = -0.45
		ar = -0.45
		el = -0.7
		er = -0.7
		lean = -0.05

	if arms_up > 0.0:
		al = lerpf(al, -2.9, arms_up)
		ar = lerpf(ar, -2.9, arms_up)
		el = lerpf(el, -0.2, arms_up)
		er = el

	if reach > 0.0:
		ar = lerpf(ar, -1.35, reach)
		er = lerpf(er, -0.15, reach)

	hips.position.y = hip_y
	spine.rotation.x = lean + breath
	hip_l.rotation.x = hl
	hip_r.rotation.x = hr
	knee_l.rotation.x = kl
	knee_r.rotation.x = kr
	shoulder_l.rotation = Vector3(al, 0, arm_out)
	shoulder_r.rotation = Vector3(ar, 0, -arm_out)
	elbow_l.rotation.x = el
	elbow_r.rotation.x = er

	if waving:
		shoulder_r.rotation = Vector3(-0.3, 0, -2.5)
		elbow_r.rotation = Vector3(0, 0, -0.5 + sin(_t * 9.0) * 0.45)

	# head look
	var target_yaw := 0.0
	var target_pitch := 0.0
	if look_target != null and head:
		var local: Vector3 = (global_transform.affine_inverse() * (look_target as Vector3))
		var from := head.position + neck.position + spine.position + hips.position
		var d := local - from
		target_yaw = clampf(atan2(d.x, d.z), -1.1, 1.1)
		target_pitch = clampf(-atan2(d.y, Vector2(d.x, d.z).length()), -0.6, 0.5)
	if head:
		head.rotation.y = lerp_angle(head.rotation.y, target_yaw, delta * 5.0)
		head.rotation.x = lerp_angle(head.rotation.x, target_pitch, delta * 5.0)

	# talking
	if jaw:
		var open := 0.0
		if talking:
			open = (sin(_t * 15.0) * 0.5 + 0.5) * (sin(_t * 4.3) * 0.5 + 0.5)
		jaw.rotation.x = open * 0.22

	# blinking
	_blink_t -= delta
	var blink := 1.0
	if _blink_t < 0.0:
		blink = 0.1
		if _blink_t < -0.12:
			_blink_t = randf_range(2.2, 5.0)
	for e in eyes:
		e.scale.y = blink


func _drive_imported() -> void:
	if _anim == null:
		return
	var want := "idle"
	if climbing:
		want = "climb"
	elif not grounded:
		want = "jump"
	elif crouch_target > 0.5:
		want = "crouch_walk" if move_speed > 0.2 else "crouch_idle"
	elif sitting:
		want = "sit"
	elif move_speed > H * 2.0:
		want = "run"
	elif move_speed > 0.2:
		want = "walk"
	if _anim.has_animation(want) and _anim.current_animation != want:
		_anim.play(want, 0.2)
