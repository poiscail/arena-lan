extends RefCounted
## Bras et mains à la première personne (gants et manches low poly), posés sur l'arme :
## main droite sur la poignée, main gauche sous le garde-main (ou en soutien sur les pistolets).
## Ils sont enfants de l'arme de la vue FPS, donc suivent le recul, le rechargement, la visée...

const Models := preload("res://scripts/models.gd")
const Data := preload("res://scripts/data.gd")

const GLOVE := Color(0.07, 0.07, 0.08)
const GLOVE_PAD := Color(0.16, 0.16, 0.17)
const SLEEVE := Color(0.24, 0.27, 0.2)

# Coudes, dans le repère de l'arme de la vue FPS (hors de l'écran, en bas)
const ELBOW_R := Vector3(0.2, -0.4, 0.32)
const ELBOW_L := Vector3(-0.42, -0.36, 0.2)
const ELBOW_L_PISTOL := Vector3(-0.3, -0.42, 0.3)

static var _mats := {}


static func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var key := c.to_html() + str(rough)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		_mats[key] = m
	return _mats[key]


## Ajoute les bras à une arme construite par Models.weapon() (racine -> pivot -> modèle).
static func add_to(g: Node3D, model: String) -> void:
	var pivot: Node3D = g.get_child(0)
	var inst: Node3D = pivot.get_child(0)
	var p := Models.gun_points(inst, model)
	var xf: Transform3D = pivot.transform * inst.transform
	var s: float = inst.scale.x
	var box: AABB = p["box"]
	var half_w := clampf(box.size.z * s * 0.3, 0.011, 0.024)  # demi-épaisseur de la poignée
	var handgun := model.begins_with("q/Pistol") or model.begins_with("q/Revolver")
	var arms := Node3D.new()
	arms.name = "Arms"
	g.add_child(arms)

	# Main droite sur la poignée, doigts autour, poignet vers l'arrière
	var grip: Vector3 = xf * (p["grip"] as Vector3)
	var rh := _right_hand(half_w)
	rh.position = grip
	rh.rotation.x = -0.28
	arms.add_child(rh)
	var wrist_r := rh.transform * Vector3(half_w * 0.6 + 0.012, -0.035, 0.05)
	_forearm(arms, wrist_r, ELBOW_R)

	# Le bras gauche est un groupe à part : il bouge pendant le rechargement
	var left := Node3D.new()
	left.name = "LeftArm"
	arms.add_child(left)
	var lh: Node3D
	if handgun:
		# Main gauche en soutien sous la main droite (prise à deux mains)
		lh = _support_hand(half_w)
		lh.position = grip + Vector3(-0.004, -0.012, -0.004)
		lh.rotation.x = -0.28
		left.add_child(lh)
		_forearm(left, lh.transform * Vector3(-half_w - 0.015, -0.04, 0.045), ELBOW_L_PISTOL)
	else:
		# Main gauche sous le garde-main
		var front: Vector3 = xf * (p["front_bottom"] as Vector3)
		var fw := clampf(box.size.z * s * 0.42, 0.014, 0.03)
		lh = _front_hand(fw)
		lh.position = front
		left.add_child(lh)
		_forearm(left, lh.transform * Vector3(-0.01, -0.035, 0.045), ELBOW_L)

	for m in arms.find_children("*", "MeshInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.set_meta("attachment", true)
	g.set_meta("lh_rest", lh.position)
	_prepare_reload(g, inst, model, p, xf, handgun)


## Prépare le rechargement à la première personne : un nœud « Mag » (le chargeur, que la main
## gauche retire puis remet) et les points où va la main, rangés en métadonnées de l'arme.
static func _prepare_reload(g: Node3D, inst: Node3D, model: String, p: Dictionary, xf: Transform3D, handgun: bool) -> void:
	var mag := Node3D.new()
	mag.name = "Mag"
	g.add_child(mag)
	var geo := Models.mag_geometry(inst, model, p["box"])
	if geo.is_empty():
		# Pas de chargeur amovible (pompe, revolver, lance-roquettes…) : la main gauche va chercher
		# des munitions et les glisse sous la carcasse
		var under: Vector3 = (p["grip"] as Vector3).lerp(p["front_bottom"], 0.5)
		g.set_meta("mag_grab", xf * under)
		g.set_meta("mag_out", Vector3.DOWN)
		g.set_meta("mag_len", 0.035)
		return
	var bottom: Vector3 = geo["bottom"]
	var h: float = geo["h"]
	var up := Basis(Vector3.BACK, float(geo["angle"])) * Vector3.UP
	if handgun:
		# Le chargeur d'un pistolet est dans la poignée : on en fabrique un, caché dedans,
		# qui sort par le bas
		var holder := Node3D.new()
		holder.transform = xf * Transform3D(Basis(Vector3.BACK, float(geo["angle"])), bottom)
		var size := Vector3(float(geo["width"]) * 0.8, h * 0.9, float(geo["thick"]) * 0.7)
		var box := _box(holder, size, Vector3(0, h * 0.45, 0), Color(0.09, 0.09, 0.1))
		box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mag.add_child(holder)
	else:
		_split_mag(inst, xf, geo, mag)
	var ext := inst.get_node_or_null("ExtMag") as Node3D
	if ext != null:
		var t := xf * ext.transform
		ext.get_parent().remove_child(ext)
		ext.transform = t
		mag.add_child(ext)
	var len := h * (1.45 if ext != null else 1.1)
	g.set_meta("mag_grab", xf * (bottom + up * h * 0.12))
	g.set_meta("mag_out", (xf.basis * -up).normalized())
	g.set_meta("mag_len", len * xf.basis.get_scale().x)


## Sépare le chargeur du reste du modèle : les triangles qui sont dans le volume du chargeur
## passent dans de nouveaux maillages, enfants de « mag » (dans le repère de la vue FPS).
static func _split_mag(inst: Node3D, xf: Transform3D, geo: Dictionary, mag: Node3D) -> void:
	var bottom: Vector3 = geo["bottom"]
	var h: float = geo["h"]
	var width: float = geo["width"]
	var thick: float = geo["thick"]
	var to_mag := Basis(Vector3.BACK, -float(geo["angle"]))  # Y le long du chargeur
	var inside := func(v: Vector3, wf: float, top: float) -> bool:
		var l := to_mag * (v - bottom)
		return absf(l.x) <= width * wf and absf(l.z) <= thick * wf and l.y >= -h * 0.15 and l.y <= h * top
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		if not m.visible or m.has_meta("attachment") or m.mesh == null:
			continue
		var xf_m := Transform3D.IDENTITY
		var n: Node = m
		while n != inst and n is Node3D:
			xf_m = (n as Node3D).transform * xf_m
			n = n.get_parent()
		var keep := ArrayMesh.new()
		var out := ArrayMesh.new()
		for s in m.mesh.get_surface_count():
			var arrays: Array = m.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				idx = arrays[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				idx.resize(verts.size())
				for i in verts.size():
					idx[i] = i
			var ki := PackedInt32Array()
			var mi := PackedInt32Array()
			for t in range(0, idx.size() - 2, 3):
				var a := xf_m * verts[idx[t]]
				var b := xf_m * verts[idx[t + 1]]
				var c := xf_m * verts[idx[t + 2]]
				if inside.call((a + b + c) / 3.0, 0.75, 1.0) and inside.call(a, 1.0, 2.0) and inside.call(b, 1.0, 2.0) and inside.call(c, 1.0, 2.0):
					mi.append_array([idx[t], idx[t + 1], idx[t + 2]])
				else:
					ki.append_array([idx[t], idx[t + 1], idx[t + 2]])
			var mat: Material = m.get_surface_override_material(s)
			if mat == null:
				mat = m.mesh.surface_get_material(s)
			for part in [[keep, ki], [out, mi]]:
				if (part[1] as PackedInt32Array).is_empty():
					continue
				var arr := arrays.duplicate()
				arr[Mesh.ARRAY_INDEX] = part[1]
				var am: ArrayMesh = part[0]
				am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				am.surface_set_material(am.get_surface_count() - 1, mat)
		if out.get_surface_count() == 0:
			continue
		m.mesh = keep
		for s in m.get_surface_override_material_count():
			m.set_surface_override_material(s, null)
		if keep.get_surface_count() == 0:
			m.visible = false
		var piece := MeshInstance3D.new()
		piece.mesh = out
		piece.transform = xf * xf_m
		piece.material_override = m.material_override
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mag.add_child(piece)


## Main droite : dos de la main à droite de la poignée, 4 doigts devant, pouce à gauche.
static func _right_hand(hw: float) -> Node3D:
	var h := Node3D.new()
	_box(h, Vector3(0.026, 0.088, 0.082), Vector3(hw + 0.013, -0.005, 0.008), GLOVE)
	_box(h, Vector3(0.008, 0.07, 0.05), Vector3(hw + 0.027, -0.005, 0.005), GLOVE_PAD)  # renfort
	for i in 4:
		var y := 0.024 - i * 0.021
		# Phalanges : devant la poignée puis sur le côté gauche
		_box(h, Vector3(hw * 2.0 + 0.026, 0.018, 0.022), Vector3(0.002, y, -0.033), GLOVE)
		_box(h, Vector3(0.016, 0.018, 0.03), Vector3(-hw - 0.007, y, -0.02), GLOVE)
	# Index posé le long du pontet, pouce de l'autre côté
	var thumb := _box(h, Vector3(0.019, 0.02, 0.06), Vector3(-hw - 0.011, 0.045, -0.012), GLOVE)
	thumb.rotation.x = 0.35
	return h


## Main gauche de soutien (pistolets) : couvre la main droite par la gauche et par-devant.
static func _support_hand(hw: float) -> Node3D:
	var h := Node3D.new()
	_box(h, Vector3(0.026, 0.08, 0.08), Vector3(-hw - 0.028, -0.012, 0.004), GLOVE)
	for i in 4:
		var y := 0.006 - i * 0.02
		_box(h, Vector3(hw * 2.0 + 0.05, 0.018, 0.02), Vector3(0.004, y, -0.056), GLOVE)
	var thumb := _box(h, Vector3(0.018, 0.019, 0.055), Vector3(-hw - 0.03, 0.035, -0.022), GLOVE)
	thumb.rotation.x = 0.2
	return h


## Main gauche sous le garde-main : paume dessous, doigts qui remontent à gauche, pouce à droite.
static func _front_hand(fw: float) -> Node3D:
	var h := Node3D.new()
	_box(h, Vector3(fw * 2.0 + 0.02, 0.026, 0.09), Vector3(0, -0.016, 0.0), GLOVE)
	_box(h, Vector3(fw * 2.0, 0.008, 0.06), Vector3(0, -0.031, 0.0), GLOVE_PAD)
	for i in 4:
		var z := -0.033 + i * 0.022
		var f := _box(h, Vector3(0.017, 0.05, 0.019), Vector3(-fw - 0.012, 0.008, z), GLOVE)
		f.rotation.z = -0.25
	var thumb := _box(h, Vector3(0.018, 0.04, 0.05), Vector3(fw + 0.012, 0.002, -0.01), GLOVE)
	thumb.rotation.z = 0.3
	return h


## Avant-bras du poignet jusqu'au coude (et un peu au-delà) : poignet de gant puis manche.
static func _forearm(parent: Node3D, wrist: Vector3, elbow: Vector3) -> void:
	var dir := (elbow - wrist).normalized()
	var length := wrist.distance_to(elbow) + 0.18
	# Poignet du gant
	_cyl(parent, wrist + dir * 0.025, dir, 0.06, 0.027, 0.029, GLOVE)
	# Manche (plus large vers le coude)
	var sleeve_start := wrist + dir * 0.05
	_cyl(parent, sleeve_start + dir * (length - 0.05) * 0.5, dir, length - 0.05, 0.033, 0.042, SLEEVE)
	# Revers de la manche
	_cyl(parent, sleeve_start + dir * 0.012, dir, 0.026, 0.037, 0.037, SLEEVE.darkened(0.25))


static func _box(parent: Node3D, size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.material_override = _mat(c)
	m.position = pos
	parent.add_child(m)
	return m


## Cylindre centré en « center », axe le long de « dir » ; r_top côté poignet.
static func _cyl(parent: Node3D, center: Vector3, dir: Vector3, height: float, r_wrist: float, r_elbow: float, c: Color) -> void:
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.height = height
	cm.bottom_radius = r_wrist  # l'axe Y local pointe vers le coude : le bas est côté poignet
	cm.top_radius = r_elbow
	cm.radial_segments = 8
	cm.rings = 1
	m.mesh = cm
	m.material_override = _mat(c, 1.0)
	m.basis = Basis(Quaternion(Vector3.UP, dir))
	m.position = center
	parent.add_child(m)
