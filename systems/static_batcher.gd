class_name StaticBatcher
extends RefCounted
## Merges many small static MeshInstance3Ds that share a material into one
## mesh per material. Cuts draw calls by ~90% so scenes run on phones.
## Collision bodies are untouched (they are separate nodes).


static func batch(root: Node3D, exclude_types := ["Humanoid", "NPC", "Player", "Interactable"], exclude_nodes: Array = []) -> int:
	var groups := {}   # material -> Array of [Mesh, Transform3D, shadow]
	var to_free: Array[Node] = []
	var inv := root.global_transform.affine_inverse()
	_collect(root, root, inv, groups, to_free, exclude_types, exclude_nodes)
	var made := 0
	for mat in groups.keys():
		var items: Array = groups[mat]
		if items.size() < 2:
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for it in items:
			var m: Mesh = it[0]
			for s in m.get_surface_count():
				st.append_from(m, s, it[1])
		var mesh := st.commit()
		var mi := MeshInstance3D.new()
		mi.name = "Batched_%d" % made
		mi.mesh = mesh
		mi.material_override = mat
		root.add_child(mi)
		made += 1
		for it in items:
			(it[2] as Node).queue_free()
	return made


static func _is_excluded(n: Node, exclude_types: Array, exclude_nodes: Array) -> bool:
	if n in exclude_nodes:
		return true
	return n is Humanoid or n is NPC or n is Player or n is Interactable


static func _collect(n: Node, root: Node3D, inv: Transform3D, groups: Dictionary, to_free: Array, et: Array, en: Array) -> void:
	if n != root and _is_excluded(n, et, en):
		return
	for c in n.get_children():
		if c is MeshInstance3D and c.get_child_count() == 0 and c.visible:
			var mi := c as MeshInstance3D
			if mi.mesh and mi.material_override and not (mi.mesh is ArrayMesh and mi.name.begins_with("Batched")):
				var mat := mi.material_override
				if mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					continue
				if not groups.has(mat):
					groups[mat] = []
				groups[mat].append([mi.mesh, inv * mi.global_transform, mi])
				continue
		if c is Node3D or c is Node:
			_collect(c, root, inv, groups, to_free, et, en)


static func batch_rig(root: Node3D) -> void:
	## For animated characters: merge only the direct mesh children of each
	## bone pivot (parts that never move relative to each other).
	_batch_children(root)
	for c in root.get_children():
		if c is Node3D and not (c is MeshInstance3D):
			batch_rig(c)


static func _batch_children(parent: Node3D) -> void:
	var groups := {}
	for c in parent.get_children():
		if c is MeshInstance3D and c.get_child_count() == 0 and c.material_override and (c as MeshInstance3D).mesh:
			var key = c.material_override
			if not groups.has(key):
				groups[key] = []
			groups[key].append(c)
	for mat in groups.keys():
		var items: Array = groups[mat]
		if items.size() < 2:
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for mi in items:
			var m: Mesh = mi.mesh
			var xf: Transform3D = mi.transform
			for s in m.get_surface_count():
				st.append_from(m, s, xf)
		var out := MeshInstance3D.new()
		out.mesh = st.commit()
		out.material_override = mat
		parent.add_child(out)
		for mi in items:
			parent.remove_child(mi)
			mi.queue_free()
