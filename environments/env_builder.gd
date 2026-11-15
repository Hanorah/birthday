class_name EnvBuilder
extends RefCounted
## Helpers for building environments from code: materials (with procedural
## noise textures), solid boxes with collision, walls with door/window gaps,
## furniture, trees, lights and vegetation scatter.
## Any piece can later be replaced by an authored mesh with the same footprint.

static var _mats := {}
static var _noise_tex := {}


static func noise_texture(key: String, freq := 0.02, octaves := 4, stretch := Vector2.ONE, c1 := Color.WHITE, c2 := Color.BLACK) -> NoiseTexture2D:
	if _noise_tex.has(key):
		return _noise_tex[key]
	var n := FastNoiseLite.new()
	n.seed = hash(key) % 10000
	n.frequency = freq
	n.fractal_octaves = octaves
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.noise = n
	var g := Gradient.new()
	g.set_color(0, c2)
	g.set_color(1, c1)
	t.color_ramp = g
	_noise_tex[key] = t
	return t


static func mat(color: Color, rough := 0.8, metal := 0.0, key := "") -> StandardMaterial3D:
	var k := key + color.to_html() + str(rough) + str(metal)
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	_mats[k] = m
	return m


static func textured(key: String, color: Color, variation := 0.25, rough := 0.85, uv_scale := Vector3(1, 1, 1), freq := 0.03, stretch := false) -> StandardMaterial3D:
	if _mats.has("tex_" + key):
		return _mats["tex_" + key]
	var m := StandardMaterial3D.new()
	var light := Color(1, 1, 1)
	var dark := Color(1.0 - variation, 1.0 - variation, 1.0 - variation)
	m.albedo_texture = noise_texture(key, freq, 5, Vector2.ONE, light, dark)
	m.albedo_color = color
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_scale = uv_scale
	m.uv1_world_triplanar = true
	_mats["tex_" + key] = m
	return m


static func emissive(color: Color, energy := 2.0) -> StandardMaterial3D:
	var k := "em" + color.to_html() + str(energy)
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_mats[k] = m
	return m


static func glass() -> StandardMaterial3D:
	if _mats.has("glass"):
		return _mats["glass"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.85, 0.95, 0.18)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic = 0.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["glass"] = m
	return m


# ---------------------------------------------------------------- primitives
static func box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, collide := true, rot_y := 0.0, shadows := true) -> Node3D:
	var root: Node3D
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		root = body
	else:
		root = Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = material
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	root.position = pos
	root.rotation.y = rot_y
	parent.add_child(root)
	return root


static func cylinder(parent: Node3D, r_top: float, r_bottom: float, height: float, pos: Vector3, material: Material, collide := false, segments := 20) -> Node3D:
	var root: Node3D = StaticBody3D.new() if collide else Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bottom
	cm.height = height
	cm.radial_segments = segments
	mi.mesh = cm
	mi.material_override = material
	root.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = maxf(r_top, r_bottom)
		sh.height = height
		cs.shape = sh
		root.add_child(cs)
	root.position = pos
	parent.add_child(root)
	return root


static func sphere(parent: Node3D, radius: float, pos: Vector3, material: Material, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2
	sm.radial_segments = 16
	sm.rings = 10
	mi.mesh = sm
	mi.material_override = material
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func omni(parent: Node3D, pos: Vector3, color: Color, energy := 1.0, rng := 6.0, shadows := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.2
	l.shadow_enabled = shadows
	if shadows:
		l.add_to_group("shadow_light")
	parent.add_child(l)
	return l


# ---------------------------------------------------------------- architecture
static func wall(parent: Node3D, a: Vector2, b: Vector2, height: float, thick: float, material: Material, gaps: Array = []) -> void:
	## Axis-aligned wall from a to b (x,z). gaps: [{from, to, bottom, top}] measured along the wall.
	var length := a.distance_to(b)
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	var dir := (b - a).normalized()
	var sorted := gaps.duplicate()
	sorted.sort_custom(func(g1, g2): return g1.from < g2.from)
	var cursor := 0.0
	var pieces := []  # [start, end, bottom, top]
	for g in sorted:
		if g.from > cursor:
			pieces.append([cursor, g.from, 0.0, height])
		if g.get("bottom", 0.0) > 0.0:
			pieces.append([g.from, g.to, 0.0, g.bottom])
		if g.get("top", height) < height:
			pieces.append([g.from, g.to, g.top, height])
		cursor = g.to
	if cursor < length:
		pieces.append([cursor, length, 0.0, height])
	for p in pieces:
		var l: float = p[1] - p[0]
		var h: float = p[3] - p[2]
		if l <= 0.001 or h <= 0.001:
			continue
		var mid: Vector2 = a + dir * ((p[0] + p[1]) * 0.5)
		var size := Vector3(l, h, thick) if along_x else Vector3(thick, h, l)
		box(parent, size, Vector3(mid.x, p[2] + h * 0.5, mid.y), material)
	# window glass + sills
	for g in sorted:
		if g.get("glass", false):
			var gl: float = g.to - g.from
			var gh: float = g.top - g.bottom
			var gm: Vector2 = a + dir * ((g.from + g.to) * 0.5)
			var gs := Vector3(gl, gh, 0.03) if along_x else Vector3(0.03, gh, gl)
			box(parent, gs, Vector3(gm.x, g.bottom + gh * 0.5, gm.y), glass(), true, 0.0, false)
			var ss := Vector3(gl + 0.1, 0.06, thick + 0.12) if along_x else Vector3(thick + 0.12, 0.06, gl + 0.1)
			box(parent, ss, Vector3(gm.x, g.bottom - 0.03, gm.y), mat(Color(0.92, 0.9, 0.85), 0.6), false)


# ---------------------------------------------------------------- nature
static func tree(parent: Node3D, pos: Vector3, height := 6.0, seed_val := 0, foliage := Color(0.22, 0.42, 0.16)) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var bark := textured("bark", Color(0.33, 0.24, 0.17), 0.45, 0.95, Vector3(2, 6, 2), 0.08)
	cylinder(root, height * 0.035, height * 0.06, height * 0.6, Vector3(0, height * 0.3, 0), bark, false, 10)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = height * 0.06
	sh.height = height * 0.6
	cs.shape = sh
	cs.position.y = height * 0.3
	body.add_child(cs)
	root.add_child(body)
	var leaf := textured("leaf" + foliage.to_html(), foliage, 0.4, 0.9, Vector3(3, 3, 3), 0.12)
	for i in 7:
		var r := height * rng.randf_range(0.17, 0.26)
		var p := Vector3(rng.randf_range(-1, 1) * height * 0.18, height * rng.randf_range(0.6, 0.9), rng.randf_range(-1, 1) * height * 0.18)
		sphere(root, r, p, leaf, Vector3(1.0, rng.randf_range(0.75, 0.95), 1.0))
	return root


static func scatter_grass(parent: Node3D, area: Rect2, count: int, avoid: Array, color := Color(0.3, 0.5, 0.18), seed_val := 7) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var blade := PrismMesh.new()
	blade.size = Vector3(0.05, 0.28, 0.01)
	mm.mesh = blade
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var xforms := []
	var tries := 0
	while xforms.size() < count and tries < count * 3:
		tries += 1
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		var blocked := false
		for r in avoid:
			if (r as Rect2).has_point(p):
				blocked = true
				break
		if blocked:
			continue
		var s := rng.randf_range(0.6, 1.4)
		var b := Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.2, 0.2)).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s))
		xforms.append([Transform3D(b, Vector3(p.x, 0.12 * s, p.y)), rng.randf_range(0.8, 1.15)])
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i][0])
		var v: float = xforms[i][1]
		mm.set_instance_color(i, Color(color.r * v, color.g * v, color.b * v))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


static func scatter_flowers(parent: Node3D, area: Rect2, count: int, colors: Array, seed_val := 11) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var head := SphereMesh.new()
	head.radius = 0.05
	head.height = 0.08
	head.radial_segments = 8
	head.rings = 4
	mm.mesh = head
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	for i in count:
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(p.x, rng.randf_range(0.18, 0.32), p.y)))
		mm.set_instance_color(i, colors[rng.randi() % colors.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.7
	mmi.material_override = m
	parent.add_child(mmi)
	return mmi


static func environment(sky_top: Color, sky_horizon: Color, ground: Color, ambient: float, fog_color: Color, fog_density: float) -> WorldEnvironment:
	var we := WorldEnvironment.new()
	we.add_to_group("world_env")
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = sky_top
	sm.sky_horizon_color = sky_horizon
	sm.ground_horizon_color = sky_horizon
	sm.ground_bottom_color = ground
	sm.sun_angle_max = 30.0
	sm.sun_curve = 0.12
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = ambient
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = fog_color
	env.fog_density = fog_density
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.06
	env.set_meta("wants_fog", true)
	we.environment = env
	return we
