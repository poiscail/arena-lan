extends RefCounted
## Chargement des modèles 3D (Quaternius Toon Shooter Game Kit, CC0) mis à l'échelle et orientés pour le jeu.

const Data := preload("res://scripts/data.gd")
const CHAR_PATH := "res://assets/soldiers/%s.gltf"
const WEAPON_PATH := "res://assets/guns/%s.gltf"
const HAND_BONE := "Index1_R"
const LOOPING := ["Idle", "Idle_Shoot", "Walk", "Walk_Shoot", "Run", "Run_Gun", "Run_Shoot", "Jump_Idle"]


## Personnage animé, pieds à l'origine, regard vers -Z, hauteur donnée.
static func character(model: String, height: float) -> Node3D:
	var root := Node3D.new()
	var pivot := Node3D.new()
	pivot.rotation.y = PI
	root.add_child(pivot)
	var inst: Node3D = load(CHAR_PATH % model).instantiate()
	pivot.add_child(inst)
	var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
	if ap != null:
		for n in LOOPING:
			if ap.has_animation(n):
				ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	attach_weapon(root, "")  # le kit range toutes ses armes dans la main : on les cache avant de mesurer
	var box := _local_aabb(inst)
	var s := height / maxf(box.size.y, 0.01)
	inst.scale = Vector3.ONE * s
	inst.position.y = -box.position.y * s
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		m.extra_cull_margin = 2.0  # le maillage animé peut sortir de sa boîte d'origine
	return root


## Affiche dans la main droite l'arme du kit portant ce nom ("" = mains vides) et cache les autres.
static func attach_weapon(character_root: Node3D, model: String) -> Node3D:
	var hand := character_root.find_child(HAND_BONE, true, false)
	var shown: Node3D = null
	if hand == null:
		return null
	for gun in hand.get_children():
		if gun is Node3D:
			gun.visible = gun.name == model
			if gun.visible:
				shown = gun
				(gun as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return shown if shown != null else hand


## Chemin du modèle d'une arme : « q/... » = Ultimate Gun Pack (FBX), sinon Toon Shooter (glTF).
static func gun_path(model: String) -> String:
	if model.begins_with("q/"):
		return "res://assets/guns_q/%s.fbx" % model.substr(2)
	return WEAPON_PATH % model


## Sens du canon dans le modèle d'origine : +1 vers +X (Ultimate Gun Pack), -1 vers -X (Toon Shooter).
static func barrel_sign(model: String) -> float:
	return 1.0 if model.begins_with("q/") else -1.0


## Arme pour la vue à la première personne : centrée, canon vers -Z, longueur donnée.
static func weapon(model: String, length: float) -> Node3D:
	var root := Node3D.new()
	var pivot := Node3D.new()
	pivot.rotation.y = PI / 2.0 * barrel_sign(model)  # canon vers -Z
	root.add_child(pivot)
	var inst: Node3D = load(gun_path(model)).instantiate()
	inst.set_meta("model", model)
	pivot.add_child(inst)
	var box := _local_aabb(inst)
	var s := length / maxf(box.size.x, 0.01)
	inst.scale = Vector3.ONE * s
	inst.position = -box.get_center() * s
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## Points utiles d'une arme dans son repère d'origine (bout du canon, dessus, poignée...),
## calculés à partir des sommets du modèle.
static func gun_points(gun: Node3D, model: String) -> Dictionary:
	var box := _local_aabb(gun)
	var L := maxf(box.size.x, 0.001)
	var dir := barrel_sign(model)
	var verts := PackedVector3Array()
	for m in gun.find_children("*", "MeshInstance3D", true, false):
		if not m.visible or m.has_meta("attachment") or m.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = m
		while n != gun and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		for si in m.mesh.get_surface_count():
			var arr: Array = m.mesh.surface_get_arrays(si)
			for v in arr[Mesh.ARRAY_VERTEX]:
				verts.append(xf * v)
	var muzzle_x := box.end.x if dir > 0.0 else box.position.x
	var rear_x := box.position.x if dir > 0.0 else box.end.x
	var cx := box.get_center().x
	var slice := func(x: float, w: float) -> Array:
		var lo := INF
		var hi := -INF
		var sum := 0.0
		var count := 0
		for v in verts:
			if absf(v.x - x) < w:
				lo = minf(lo, v.y)
				hi = maxf(hi, v.y)
				sum += v.y
				count += 1
		if count == 0:
			return [box.position.y, box.end.y, box.get_center().y]
		return [lo, hi, sum / count]
	var muzzle: Array = slice.call(muzzle_x, L * 0.012)
	var top: Array = slice.call(cx, L * 0.08)
	var pistol := box.size.y > L * 0.5  # pistolets et revolvers : plus hauts que longs
	var grip_x := rear_x + dir * L * (0.22 if pistol else 0.36)
	var grip: Array = slice.call(grip_x, L * 0.04)
	var front: Array = slice.call(cx + dir * L * 0.2, L * 0.05)
	return {
		"L": L, "dir": dir, "box": box, "pistol": pistol, "verts": verts,
		"muzzle": Vector3(muzzle_x, (muzzle[0] + muzzle[1]) / 2.0, box.get_center().z),
		"top": Vector3(cx, top[1], box.get_center().z),
		"grip": Vector3(grip_x, lerpf(grip[0], grip[1], 0.55 if pistol else 0.45), box.get_center().z),
		"front_bottom": Vector3(cx + dir * L * 0.2, front[0], box.get_center().z),
	}


static func _local_aabb(top: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for m in top.find_children("*", "MeshInstance3D", true, false):
		if not m.visible:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = m
		while n != top and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var a: AABB = xf * (m as MeshInstance3D).get_aabb()
		if first:
			result = a
			first = false
		else:
			result = result.merge(a)
	return result


const SKIN_SHADER := preload("res://assets/shaders/gun_skin.gdshader")
static var _skin_mats := {}

## Applique un skin (Data.CAMOS) à toutes les pièces d'une arme (pas aux accessoires) :
## chaque pièce reçoit le matériau du skin, qui garde un peu de sa couleur d'origine.
static func apply_camo(node: Node, camo: Dictionary) -> void:
	for m in node.find_children("*", "MeshInstance3D", true, false):
		if m.has_meta("attachment") or m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var src: Material = m.mesh.surface_get_material(s)
			var base := Color(0.2, 0.2, 0.2)
			if src is BaseMaterial3D:
				base = (src as BaseMaterial3D).albedo_color
			m.set_surface_override_material(s, skin_material(camo, base))


## Matériau d'un skin pour une pièce de couleur donnée (partagé entre toutes les armes).
static func skin_material(camo: Dictionary, base: Color) -> ShaderMaterial:
	var key := "%s|%s" % [camo["name"], base.to_html(false)]
	if _skin_mats.has(key):
		return _skin_mats[key]
	# Le rendu standard n'a pas de vrais reflets : on y réduit l'aspect métallique (sinon tout noir)
	var adv := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	var mat := ShaderMaterial.new()
	mat.shader = SKIN_SHADER
	mat.set_shader_parameter("base_color", base)
	mat.set_shader_parameter("pattern", int(camo.get("p", 0)))
	mat.set_shader_parameter("c1", camo.get("c1", Color.WHITE))
	mat.set_shader_parameter("c2", camo.get("c2", Color.BLACK))
	mat.set_shader_parameter("c3", camo.get("c3", Color.GRAY))
	mat.set_shader_parameter("scale", float(camo.get("s", 8.0)))
	mat.set_shader_parameter("detail", float(camo.get("d", 0.35)))
	mat.set_shader_parameter("metal", minf(float(camo.get("m", 0.15)), 0.7) * (1.0 if adv else 0.45))
	mat.set_shader_parameter("rough", float(camo.get("ro", 0.5)))
	mat.set_shader_parameter("emit", float(camo.get("e", 0.0)))
	mat.set_shader_parameter("speed", float(camo.get("sp", 0.0)))
	_skin_mats[key] = mat
	return mat


## Ajoute les accessoires visibles sur un modèle d'arme (dans son repère d'origine).
## Silencieux, lunette et poignée : modèles de l'Ultimate Gun Pack ; chargeur étendu : boîte sombre.
static func add_attachments(gun: Node3D, atts: Array) -> void:
	if atts.is_empty():
		return
	var model: String = gun.get_meta("model", "")
	var p := gun_points(gun, model)
	var L: float = p["L"]
	var dir: float = p["dir"]
	var handgun := model.begins_with("q/Pistol") or model.begins_with("q/Revolver")
	for a in atts:
		match a:
			"silencer":
				var len := L * (0.36 if handgun else 0.24)
				_part(gun, "Silencer_1", len, p["muzzle"] + Vector3(dir * len * 0.47, 0, 0), dir)
			"optic":
				var dot := _red_dot(L * (0.22 if handgun else 0.13), dir)
				dot.position = p["top"] + Vector3(-dir * L * (0.02 if handgun else 0.06), -L * 0.004, 0)
				gun.add_child(dot)
			"grip":
				var part := _part(gun, "Grip", L * 0.14, Vector3.ZERO, dir, true)
				var h: float = part.get_meta("height")
				part.position = p["front_bottom"] - Vector3(0, h * 0.45, 0)
			"scope":
				var len := L * 0.42
				var part := _part(gun, "Scope_1", len, Vector3.ZERO, dir)
				var h: float = part.get_meta("height")
				part.position = p["top"] + Vector3(-dir * L * 0.05, h * 0.5 + L * 0.01, 0)
			"bayonet":
				var len := L * 0.24
				var m: Vector3 = p["muzzle"]
				_part(gun, "Bayonet", len, Vector3(m.x - dir * len * 0.15, m.y - L * 0.045, m.z), dir)
			"flashlight":
				var len := L * 0.13
				var fb: Vector3 = p["front_bottom"]
				var m: Vector3 = p["muzzle"]
				var part := _part(gun, "Flashlight", len, Vector3(fb.x + dir * L * 0.08, lerpf(fb.y, m.y, 0.6), m.z + L * 0.035), dir)
				var spot := SpotLight3D.new()
				spot.rotation.y = -dir * PI / 2.0  # éclaire dans l'axe du canon
				spot.spot_range = 22.0
				spot.spot_angle = 18.0
				spot.light_energy = 1.6
				spot.light_color = Color(1.0, 0.97, 0.9)
				spot.shadow_enabled = false
				spot.position = Vector3(dir * len * 0.5, 0, 0)
				part.add_child(spot)
			"bipod":
				var part := _part(gun, "Bipod", L * 0.16, Vector3.ZERO, dir, true)
				var fb: Vector3 = p["front_bottom"]
				part.position = Vector3(fb.x + dir * L * 0.12, fb.y - L * 0.08, fb.z)
			"stock":
				var len := L * 0.45
				var box: AABB = p["box"]
				var g: Vector3 = p["grip"]
				var rear := box.position.x if dir > 0.0 else box.end.x
				_part(gun, "Stock", len, Vector3(rear - dir * len * 0.42, g.y + L * 0.06, g.z), dir)
			"mag":
				_extended_mag(gun, model, p)


## Chargeur étendu : prolonge le vrai chargeur du modèle (repéré grâce à Data.MAG_HINTS)
## dans son axe, avec une semelle au bout.
static func _extended_mag(gun: Node3D, model: String, p: Dictionary) -> void:
	if not Data.MAG_HINTS.has(model):
		return
	if not _mag_cache.has(model):
		_mag_cache[model] = _measure_mag(gun, Data.MAG_HINTS[model], p["box"])
	var g: Dictionary = _mag_cache[model]
	if g.is_empty():
		return
	var angle: float = g["angle"]
	var width: float = g["width"] * 0.94
	var thick: float = g["thick"] * 0.85
	var h: float = g["h"]
	var bottom: Vector3 = g["bottom"]
	var ext := clampf(h * 0.38, p["L"] * 0.04, p["L"] * 0.12)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.11, 0.11, 0.12)
	mat.roughness = 0.65
	var holder := Node3D.new()
	holder.position = bottom
	holder.rotation.z = angle
	gun.add_child(holder)
	# Le prolongement part un peu au-dessus du bas d'origine pour bien se raccorder
	_box(holder, Vector3(width, ext + h * 0.04, thick), Vector3(0, -ext / 2.0 + h * 0.02, 0), mat)
	var plate := mat.duplicate() as StandardMaterial3D
	plate.albedo_color = Color(0.07, 0.07, 0.075)
	_box(holder, Vector3(width * 1.12, ext * 0.12, thick * 1.12), Vector3(0, -ext, 0), plate)


static var _mag_cache := {}

## Mesure le chargeur d'un modèle : on échantillonne ses faces (les modèles low poly ont trop peu
## de sommets), puis on garde la zone indiquée par l'indice. Renvoie le bas du chargeur, son
## inclinaison (angle autour de Z), sa largeur, son épaisseur et sa hauteur.
static func _measure_mag(gun: Node3D, hint: Array, box: AABB) -> Dictionary:
	var pts := PackedVector3Array()
	for m in gun.find_children("*", "MeshInstance3D", true, false):
		if not m.visible or m.has_meta("attachment") or m.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = m
		while n != gun and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var faces: PackedVector3Array = m.mesh.get_faces()
		for t in range(0, faces.size(), 3):
			var a: Vector3 = xf * faces[t]
			var b: Vector3 = xf * faces[t + 1]
			var c: Vector3 = xf * faces[t + 2]
			for i in 7:
				for j in 7 - i:
					var u := i / 6.0
					var v := j / 6.0
					pts.append(a + (b - a) * u + (c - a) * v)
	var sel := PackedVector3Array()
	for v in pts:
		var fx := (v.x - box.position.x) / box.size.x
		var fy := (v.y - box.position.y) / box.size.y
		if absf(fx - float(hint[0])) < float(hint[2]) and fy < float(hint[1]):
			sel.append(v)
	if sel.size() < 10:
		return {}
	var lo := INF
	var hi := -INF
	for v in sel:
		lo = minf(lo, v.y)
		hi = maxf(hi, v.y)
	var h := hi - lo
	# Deux bandes horizontales : près du bas et près du haut. Leur centre donne l'axe du chargeur.
	var band := func(y0: float, y1: float) -> Array:
		var x0 := INF
		var x1 := -INF
		var zz0 := INF
		var zz1 := -INF
		for v in sel:
			if v.y >= y0 and v.y <= y1:
				x0 = minf(x0, v.x)
				x1 = maxf(x1, v.x)
				zz0 = minf(zz0, v.z)
				zz1 = maxf(zz1, v.z)
		return [(x0 + x1) / 2.0, (y0 + y1) / 2.0, x1 - x0, zz1 - zz0, (zz0 + zz1) / 2.0]
	var low: Array = band.call(lo + h * 0.1, lo + h * 0.3)
	var top: Array = band.call(hi - h * 0.35, hi - h * 0.1)
	if not is_finite(low[0]) or not is_finite(top[0]):
		return {}
	var axis := Vector2(low[0] - top[0], low[1] - top[1]).normalized()
	var angle := atan2(axis.x, -axis.y)
	var width: float = low[2] * cos(angle)
	# Point du bas sur l'axe : on prolonge depuis la bande basse jusqu'au fond du chargeur
	var down: float = (low[1] - lo) - width * 0.5 * absf(sin(angle))
	var bottom := Vector3(low[0] + axis.x / maxf(-axis.y, 0.2) * down, low[1] - down, low[4])
	return {"angle": angle, "width": width, "thick": low[3], "h": h, "bottom": bottom}


## Viseur point rouge fabriqué ici (le pack n'en a pas) : socle, tube octogonal ouvert,
## verre teinté et point rouge lumineux. Le nœud « SightPoint » marque l'axe de visée.
static func _red_dot(size: float, dir: float) -> Node3D:
	var wrap := Node3D.new()
	if dir < 0.0:
		wrap.rotation.y = PI
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.09, 0.09, 0.1)
	dark.roughness = 0.5
	var r := size * 0.3  # rayon du tube
	var mount_h := size * 0.2
	_box(wrap, Vector3(size * 0.75, mount_h, r * 1.3), Vector3(0, mount_h / 2.0, 0), dark)
	_box(wrap, Vector3(size * 0.9, mount_h * 0.35, r * 1.6), Vector3(0, mount_h * 0.17, 0), dark)
	var cy := mount_h + r
	var plank := 2.0 * r * tan(PI / 8.0) * 1.1
	for k in 8:
		var a := TAU * k / 8.0 + PI / 8.0
		var m := _box(wrap, Vector3(size, plank, r * 0.12), Vector3(0, cy + cos(a) * r, sin(a) * r), dark)
		m.rotation.x = a - PI / 2.0
	# Molette de réglage sur le côté
	var knob := _box(wrap, Vector3(size * 0.22, size * 0.22, r * 0.35), Vector3(-size * 0.1, cy, r * 1.15), dark)
	knob.rotation.z = PI / 4.0
	# Verre teinté à l'avant
	var glass := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = r * 0.92
	disc.bottom_radius = r * 0.92
	disc.height = size * 0.01
	disc.radial_segments = 8
	glass.mesh = disc
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(0.45, 0.75, 1.0, 0.14)
	gm.metallic = 0.6
	gm.roughness = 0.05
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.material_override = gm
	glass.rotation.z = PI / 2.0
	glass.position = Vector3(size * 0.3, cy, 0)
	glass.set_meta("attachment", true)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wrap.add_child(glass)
	# Point rouge projeté sur le verre
	var dot := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = r * 0.055
	sph.height = r * 0.11
	sph.radial_segments = 8
	sph.rings = 4
	dot.mesh = sph
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(1.0, 0.08, 0.05)
	dot.material_override = dm
	dot.position = Vector3(size * 0.29, cy, 0)
	dot.set_meta("attachment", true)
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wrap.add_child(dot)
	var sight := Node3D.new()
	sight.name = "SightPoint"
	sight.position = Vector3(size * 0.29, cy, 0)
	wrap.add_child(sight)
	return wrap


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.material_override = mat
	m.position = pos
	m.set_meta("attachment", true)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


## Charge un accessoire, le met à la taille voulue (longueur sur X, ou hauteur si « by_width »
## donne la largeur) et l'oriente comme l'arme. Renvoie le nœud (méta « height » = hauteur finale).
static func _part(gun: Node3D, name: String, size: float, pos: Vector3, dir: float, by_width := false) -> Node3D:
	var wrap := Node3D.new()
	var inst: Node3D = load("res://assets/guns_q/%s.fbx" % name).instantiate()
	var box := _local_aabb(inst)
	var ref := box.size.x if not by_width else box.size.y  # by_width : taille donnée = hauteur
	var s := size / maxf(ref, 0.001)
	inst.scale = Vector3.ONE * s
	inst.position = -box.get_center() * s
	if dir < 0.0:
		wrap.rotation.y = PI
	wrap.add_child(inst)
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		m.set_meta("attachment", true)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wrap.set_meta("height", box.size.y * s)
	wrap.position = pos
	gun.add_child(wrap)
	return wrap


const CharmSwing := preload("res://scripts/charm_swing.gd")
static var _trinket_mats := {}
static var _sticker_texs := {}

## Breloque et autocollants choisis dans l'armurerie (« charm » / « sticker » de la personnalisation).
static func add_trinkets(gun: Node3D, c: Dictionary) -> void:
	var ci := int(c.get("charm", 0))
	var si := int(c.get("sticker", 0))
	if ci <= 0 and si <= 0:
		return
	var model: String = gun.get_meta("model", "")
	var p := gun_points(gun, model)
	var L: float = p["L"]
	var dir: float = p["dir"]
	var box: AABB = p["box"]
	var pistol: bool = p["pistol"]
	var faces := _gun_faces(gun)
	var rear_x := box.position.x if dir > 0.0 else box.end.x
	if si > 0 and si < Data.STICKERS.size():
		# Sur la carcasse, au-dessus de la poignée : on cherche une hauteur où l'arme est pleine
		var size := L * (0.15 if pistol else 0.075)
		var sx: float = box.get_center().x - dir * L * (0.0 if pistol else 0.06)
		var top: float = p["top"].y
		for k in 6:
			var sy: float = top - size * (0.7 + 0.2 * k)
			var zs := []
			for o in [Vector2.ZERO, Vector2(-0.4, -0.4), Vector2(0.4, -0.4), Vector2(-0.4, 0.4), Vector2(0.4, 0.4)]:
				var r := _side_z(faces, sx + o.x * size, sy + o.y * size)
				if r.is_empty():
					break
				zs.append(r)
			if zs.size() < 5:
				continue
			var tex := sticker_texture(si)
			for side in [1.0, -1.0]:
				var z := -INF
				for r in zs:
					z = maxf(z, r[1] if side > 0.0 else -r[0])
				var q := MeshInstance3D.new()
				var qm := QuadMesh.new()
				qm.size = Vector2(size, size)
				q.mesh = qm
				var mat := StandardMaterial3D.new()
				mat.albedo_texture = tex
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				mat.alpha_scissor_threshold = 0.5
				mat.roughness = 0.45
				mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				q.material_override = mat
				q.position = Vector3(sx, sy, side * (z + L * 0.002))
				if side < 0.0:
					q.rotation.y = PI
				q.set_meta("attachment", true)
				q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				gun.add_child(q)
			break
	if ci > 0 and ci < Data.CHARMS.size():
		var size := L * (0.1 if pistol else 0.055)
		var hang := CharmSwing.new()
		hang.name = "Charm"
		if pistol:
			# Dragonne au bas de la poignée
			var gx: float = rear_x + dir * L * 0.16
			var gy: float = box.position.y
			for k in 12:
				gy = box.position.y + L * 0.02 * k
				if not _side_z(faces, gx, gy).is_empty():
					break
			hang.position = Vector3(gx, gy, box.get_center().z)
		else:
			# Accrochée sur le flanc visible, à l'arrière de la carcasse
			var cx: float = rear_x + dir * L * 0.32
			var cy: float = p["top"].y - L * 0.03
			var r := []
			for k in 10:
				r = _side_z(faces, cx, cy)
				if not r.is_empty():
					break
				cy -= L * 0.02
			var z: float = box.get_center().z
			if not r.is_empty():
				# Le joueur voit le côté -Z quand le canon va vers +X (et l'inverse)
				z = (r[0] - L * 0.01) if dir > 0.0 else (r[1] + L * 0.01)
			hang.position = Vector3(cx, cy, z)
		var chain := size * 0.8
		hang.length = chain + size * 0.45
		var metal := _trinket_mat(Color(0.75, 0.76, 0.78), 0.9, 0.3)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = size * 0.06
		tm.outer_radius = size * 0.11
		ring.mesh = tm
		ring.rotation.z = PI / 2.0
		ring.material_override = metal
		hang.add_child(ring)
		var link := MeshInstance3D.new()
		link.mesh = _cyl(size * 0.025, size * 0.025, chain, 6)
		link.position.y = -chain * 0.5
		link.material_override = metal
		hang.add_child(link)
		var body := charm(Data.CHARMS[ci], size)
		body.position.y = -chain - size * 0.45
		hang.add_child(body)
		for m in hang.find_children("*", "MeshInstance3D", true, false):
			m.set_meta("attachment", true)
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gun.add_child(hang)


## Triangles du modèle d'arme (sans les accessoires), dans le repère de « gun ».
static func _gun_faces(gun: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for m in gun.find_children("*", "MeshInstance3D", true, false):
		if not m.visible or m.has_meta("attachment") or m.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = m
		while n != gun and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		for v in m.mesh.get_faces():
			out.append(xf * v)
	return out


## Épaisseur de l'arme au point (x, y), le long de Z : [z min, z max], ou [] si rien n'y passe.
static func _side_z(faces: PackedVector3Array, x: float, y: float) -> Array:
	var lo := INF
	var hi := -INF
	for i in range(0, faces.size() - 2, 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var den := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
		if absf(den) < 1e-9:
			continue
		var u := ((b.y - c.y) * (x - c.x) + (c.x - b.x) * (y - c.y)) / den
		var v := ((c.y - a.y) * (x - c.x) + (a.x - c.x) * (y - c.y)) / den
		if u < 0.0 or v < 0.0 or u + v > 1.0:
			continue
		var z := u * a.z + v * b.z + (1.0 - u - v) * c.z
		lo = minf(lo, z)
		hi = maxf(hi, z)
	return [] if lo == INF else [lo, hi]


static func _trinket_mat(col: Color, metal := 0.1, rough := 0.5, emit := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f" % [col.to_html(false), metal, rough, emit]
	if _trinket_mats.has(key):
		return _trinket_mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = metal * (1.0 if RenderingServer.get_current_rendering_method() != "gl_compatibility" else 0.45)
	mat.roughness = rough
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emit > 0.0:
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = emit
	_trinket_mats[key] = mat
	return mat


static func _add_mesh(root: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.material_override = mat
	root.add_child(mi)
	return mi


static func _sphere(r: float) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	return sm


static func _boxm(size: Vector3) -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = size
	return bm


static func _cyl(top: float, bottom: float, h: float, seg := 14) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	return c


## Objet d'une breloque, centré, de taille « s » environ (le dessus est vers +Y).
static func charm(cm: Dictionary, s: float) -> Node3D:
	var root := Node3D.new()
	var c1: Color = cm.get("c1", Color.WHITE)
	var c2: Color = cm.get("c2", Color.BLACK)
	var e := float(cm.get("e", 0.0))
	var m1 := _trinket_mat(c1, 0.2, 0.45, e)
	var m2 := _trinket_mat(c2, 0.2, 0.45, e * 0.6)
	match String(cm.get("shape", "")):
		"die":
			var d := s * 0.7
			_add_mesh(root, _boxm(Vector3.ONE * d), Vector3.ZERO, m1)
			var dot := _sphere(d * 0.09)
			# Faces avant / arrière : 5 et 2 ; côtés : 3 et 1
			for o in [Vector2(0, 0), Vector2(-0.25, -0.25), Vector2(0.25, 0.25), Vector2(-0.25, 0.25), Vector2(0.25, -0.25)]:
				_add_mesh(root, dot, Vector3(o.x * d, o.y * d, d * 0.5), m2)
			for o in [Vector2(-0.25, -0.25), Vector2(0.25, 0.25)]:
				_add_mesh(root, dot, Vector3(o.x * d, o.y * d, -d * 0.5), m2)
			for o in [-0.25, 0.0, 0.25]:
				_add_mesh(root, dot, Vector3(d * 0.5, o * d, o * d), m2)
			_add_mesh(root, dot, Vector3(-d * 0.5, 0, 0), m2)
		"bullet":
			_add_mesh(root, _cyl(s * 0.17, s * 0.17, s * 0.6), Vector3(0, s * 0.15, 0), m1)
			_add_mesh(root, _cyl(s * 0.17, 0.0, s * 0.42), Vector3(0, -s * 0.36, 0), m2)
			_add_mesh(root, _cyl(s * 0.19, s * 0.19, s * 0.06), Vector3(0, s * 0.45, 0), m1)
		"tag":
			_add_mesh(root, _boxm(Vector3(s * 0.55, s * 0.85, s * 0.05)), Vector3.ZERO, m1)
			_add_mesh(root, _boxm(Vector3(s * 0.4, s * 0.06, s * 0.06)), Vector3(0, s * 0.1, 0), m2)
			_add_mesh(root, _boxm(Vector3(s * 0.3, s * 0.06, s * 0.06)), Vector3(0, -s * 0.05, 0), m2)
			_add_mesh(root, _boxm(Vector3(s * 0.36, s * 0.06, s * 0.06)), Vector3(0, -s * 0.2, 0), m2)
		"grenade":
			_add_mesh(root, _sphere(s * 0.36), Vector3(0, -s * 0.05, 0), m1, Vector3.ZERO, Vector3(1, 1.15, 1))
			_add_mesh(root, _cyl(s * 0.12, s * 0.14, s * 0.18), Vector3(0, s * 0.38, 0), m2)
			_add_mesh(root, _boxm(Vector3(s * 0.08, s * 0.4, s * 0.1)), Vector3(s * 0.2, s * 0.22, 0), m2, Vector3(0, 0, -0.35))
		"duck":
			_add_mesh(root, _sphere(s * 0.34), Vector3(0, -s * 0.12, 0), m1, Vector3.ZERO, Vector3(1.25, 0.85, 1.0))
			_add_mesh(root, _sphere(s * 0.2), Vector3(s * 0.22, s * 0.2, 0), m1)
			_add_mesh(root, _boxm(Vector3(s * 0.2, s * 0.06, s * 0.14)), Vector3(s * 0.46, s * 0.16, 0), m2)
			var eye := _trinket_mat(Color(0.05, 0.05, 0.05), 0.0, 0.3)
			for z in [-1.0, 1.0]:
				_add_mesh(root, _sphere(s * 0.035), Vector3(s * 0.3, s * 0.26, z * s * 0.16), eye)
		"heart":
			for x in [-1.0, 1.0]:
				_add_mesh(root, _sphere(s * 0.22), Vector3(x * s * 0.16, s * 0.12, 0), m1, Vector3.ZERO, Vector3(1, 1, 0.55))
			_add_mesh(root, _boxm(Vector3(s * 0.4, s * 0.4, s * 0.22)), Vector3(0, -s * 0.08, 0), m1, Vector3(0, 0, PI / 4.0))
		"star":
			_add_mesh(root, _star_mesh(s * 0.5, s * 0.21, s * 0.14), Vector3.ZERO, m1)
			_add_mesh(root, _star_mesh(s * 0.25, s * 0.1, s * 0.18), Vector3.ZERO, m2)
		"skull":
			_add_mesh(root, _sphere(s * 0.34), Vector3(0, s * 0.08, 0), m1)
			_add_mesh(root, _boxm(Vector3(s * 0.36, s * 0.22, s * 0.4)), Vector3(0, -s * 0.24, 0), m1)
			var hole := _sphere(s * 0.085)
			for z in [-1.0, 1.0]:
				for x in [-1.0, 1.0]:
					_add_mesh(root, hole, Vector3(x * s * 0.13, s * 0.03, z * s * 0.29), m2)
				_add_mesh(root, _boxm(Vector3(s * 0.06, s * 0.08, s * 0.03)), Vector3(0, -s * 0.12, z * s * 0.2), m2)
		"coin":
			_add_mesh(root, _cyl(s * 0.42, s * 0.42, s * 0.08, 24), Vector3.ZERO, _trinket_mat(c1, 0.9, 0.3), Vector3(PI / 2.0, 0, 0))
			_add_mesh(root, _cyl(s * 0.34, s * 0.34, s * 0.1, 24), Vector3.ZERO, _trinket_mat(c2, 0.9, 0.35), Vector3(PI / 2.0, 0, 0))
			_add_mesh(root, _star_mesh(s * 0.24, s * 0.1, s * 0.12), Vector3.ZERO, _trinket_mat(c1, 0.9, 0.3))
		"gem":
			var gm := _trinket_mat(c1, 0.4, 0.1, maxf(e, 0.6))
			_add_mesh(root, _cyl(s * 0.3, 0.0, s * 0.5, 6), Vector3(0, -s * 0.2, 0), gm)
			_add_mesh(root, _cyl(s * 0.16, s * 0.3, s * 0.2, 6), Vector3(0, s * 0.15, 0), gm)
	return root


## Étoile à 5 branches en relief (faces vers ±Z).
static func _star_mesh(r_out: float, r_in: float, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := []
	for i in 10:
		var a := PI / 2.0 + TAU * i / 10.0
		pts.append(Vector2(cos(a), sin(a)) * (r_out if i % 2 == 0 else r_in))
	var h := depth * 0.5
	for i in 10:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % 10]
		# Faces avant et arrière (légèrement bombées), puis tranche
		for tri in [[Vector3(0, 0, h), Vector3(b.x, b.y, h * 0.4), Vector3(a.x, a.y, h * 0.4)],
				[Vector3(0, 0, -h), Vector3(a.x, a.y, -h * 0.4), Vector3(b.x, b.y, -h * 0.4)],
				[Vector3(a.x, a.y, h * 0.4), Vector3(a.x, a.y, -h * 0.4), Vector3(b.x, b.y, h * 0.4)],
				[Vector3(b.x, b.y, h * 0.4), Vector3(a.x, a.y, -h * 0.4), Vector3(b.x, b.y, -h * 0.4)]]:
			for v in tri:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## Image d'un autocollant (dessin entouré d'un liseré blanc découpé), mise en cache.
static func sticker_texture(si: int) -> ImageTexture:
	if _sticker_texs.has(si):
		return _sticker_texs[si]
	var stk: Dictionary = Data.STICKERS[si]
	var N := 96
	var img := Image.create_empty(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			var p := Vector2((x + 0.5) / N * 2.0 - 1.0, 1.0 - (y + 0.5) / N * 2.0)
			var c := _sticker_pixel(stk, p * 1.12)
			if c.a <= 0.0:
				c = Color(0.96, 0.96, 0.94) if _sticker_pixel(stk, p * 1.02).a > 0.0 else Color(0, 0, 0, 0)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_sticker_texs[si] = tex
	return tex


static func _in_poly(p: Vector2, pts: Array) -> bool:
	var inside := false
	var j := pts.size() - 1
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[j]
		if (a.y > p.y) != (b.y > p.y) and p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
			inside = not inside
		j = i
	return inside


## Couleur du dessin d'un autocollant au point p (de -1 à 1, y vers le haut) ; alpha 0 = en dehors.
static func _sticker_pixel(stk: Dictionary, p: Vector2) -> Color:
	var c1: Color = stk.get("c1", Color.WHITE)
	var c2: Color = stk.get("c2", Color.BLACK)
	var none := Color(0, 0, 0, 0)
	var d := p.length()
	var pic := String(stk.get("pic", ""))
	match pic:
		"target":
			if d > 0.92:
				return none
			return c1 if int(d * 4.6) % 2 == 0 else c2
		"flag":
			if absf(p.x) > 0.9 or absf(p.y) > 0.62:
				return none
			return c1 if p.x < -0.3 else (c2 if p.x < 0.3 else stk.get("c3", c1))
		"bolt":
			var bolt := [Vector2(0.2, 0.95), Vector2(-0.55, -0.05), Vector2(-0.05, -0.05), Vector2(-0.3, -0.95), Vector2(0.6, 0.15), Vector2(0.1, 0.15), Vector2(0.45, 0.95)]
			return c1 if _in_poly(p, bolt) else none
		"heart":
			var q := p * 1.25 + Vector2(0, 0.15)
			var v := pow(q.x * q.x + q.y * q.y - 1.0, 3.0) - q.x * q.x * q.y * q.y * q.y
			if v > 0.0:
				return none
			return c2 if (q - Vector2(-0.45, 0.45)).length() < 0.16 else c1
		"star":
			var pts := []
			for i in 10:
				var a := PI / 2.0 + TAU * i / 10.0
				pts.append(Vector2(cos(a), sin(a)) * (0.95 if i % 2 == 0 else 0.4))
			if not _in_poly(p, pts):
				return none
			return c1 if d > 0.18 else c2
		"crown":
			var crown := [Vector2(-0.8, -0.55), Vector2(-0.9, 0.5), Vector2(-0.45, 0.05), Vector2(0, 0.7), Vector2(0.45, 0.05), Vector2(0.9, 0.5), Vector2(0.8, -0.55)]
			if absf(p.x) < 0.8 and p.y < -0.6 and p.y > -0.8:
				return c1
			if not _in_poly(p, crown):
				return none
			return c2 if (p - Vector2(0, -0.2)).length() < 0.16 else c1
		"hazard":
			if not _in_poly(p, [Vector2(0, 0.9), Vector2(-0.95, -0.75), Vector2(0.95, -0.75)]):
				return none
			if not _in_poly(p, [Vector2(0, 0.66), Vector2(-0.72, -0.62), Vector2(0.72, -0.62)]):
				return c2
			if (absf(p.x) < 0.08 and p.y > -0.2 and p.y < 0.4) or (p - Vector2(0, -0.38)).length() < 0.1:
				return c2
			return c1
		"skull":
			var head := (p - Vector2(0, 0.15)).length() < 0.68
			var jaw := absf(p.x) < 0.38 and p.y < -0.25 and p.y > -0.85
			if not head and not jaw:
				return none
			if (p - Vector2(-0.27, 0.12)).length() < 0.18 or (p - Vector2(0.27, 0.12)).length() < 0.18:
				return c2
			if _in_poly(p, [Vector2(0, -0.05), Vector2(-0.09, -0.24), Vector2(0.09, -0.24)]):
				return c2
			if jaw and p.y < -0.5 and int((p.x + 0.38) * 9.0) % 2 == 1:
				return c2
			return c1
		"flame":
			var w := 0.62 * sqrt(clampf((0.95 - p.y) / 1.9, 0.0, 1.0)) * clampf((p.y + 0.95) * 1.6, 0.0, 1.0)
			var x := p.x - sin(p.y * 3.0) * 0.1
			if absf(x) > w:
				return none
			return c2 if absf(x) < w * 0.45 and p.y < 0.35 else c1
		"cross":
			if d > 0.95:
				return none
			if (d > 0.62 and d < 0.74) or (absf(p.x) < 0.06 and d > 0.2) or (absf(p.y) < 0.06 and d > 0.2) or d < 0.07:
				return c1
			return c2
		"nuke":
			if d > 0.95:
				return none
			var ang := fposmod(atan2(p.y, p.x) - PI / 2.0, TAU / 3.0)
			if d < 0.17 or (d > 0.25 and d < 0.82 and absf(ang - TAU / 6.0) < PI / 6.0):
				return c2
			return c1
		"eye":
			if absf(p.y) > 0.62 * (1.0 - p.x * p.x):
				return none
			if d < 0.18:
				return c2
			if d < 0.46:
				return c1
			return Color(0.97, 0.97, 0.95)
	return none
