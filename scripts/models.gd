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


## Applique un camouflage (Data.CAMOS) à toutes les pièces d'une arme, par-dessus ses textures.
static func apply_camo(node: Node, camo: Dictionary) -> void:
	var overlay: StandardMaterial3D = null
	if camo["name"] != "Standard":
		overlay = StandardMaterial3D.new()
		overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		overlay.albedo_color = camo["color"]
		overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if camo["add"] else BaseMaterial3D.BLEND_MODE_MUL
		if camo.has("pattern"):
			overlay.albedo_texture = pattern_texture(camo["pattern"])
			overlay.uv1_triplanar = true
			overlay.uv1_scale = Vector3.ONE * 3.0
			overlay.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if camo["pattern"] in ["digital", "arctic"] else BaseMaterial3D.TEXTURE_FILTER_LINEAR
	for m in node.find_children("*", "MeshInstance3D", true, false):
		if not m.has_meta("attachment"):
			m.material_overlay = overlay


static var _patterns := {}

## Textures de motifs générées une seule fois (mêmes sur toutes les machines grâce à la graine fixe).
static func pattern_texture(kind: String) -> ImageTexture:
	if _patterns.has(kind):
		return _patterns[kind]
	var n := 128
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.035
	var noise2 := FastNoiseLite.new()
	noise2.seed = 21
	noise2.frequency = 0.08
	var pal: Array = {
		"digital": [Color(0.35, 0.42, 0.3), Color(0.55, 0.6, 0.45), Color(0.22, 0.25, 0.2), Color(0.7, 0.68, 0.55)],
		"arctic": [Color(0.95, 0.97, 1.0), Color(0.75, 0.82, 0.9), Color(0.55, 0.62, 0.7), Color(1, 1, 1)],
		"woodland": [Color(0.3, 0.38, 0.2), Color(0.45, 0.35, 0.2), Color(0.15, 0.15, 0.12), Color(0.55, 0.55, 0.35)],
	}.get(kind, [])
	for y in n:
		for x in n:
			var c := Color.WHITE
			match kind:
				"digital", "arctic":
					# Pixels de 8×8 choisis selon un bruit : motif « numérique »
					var v := noise.get_noise_2d(float(x / 8) * 8.0, float(y / 8) * 8.0) + noise2.get_noise_2d(float(x / 8) * 8.0, float(y / 8) * 8.0) * 0.5
					c = pal[clampi(int((v + 1.0) * 2.0), 0, 3)]
				"woodland":
					var v := noise.get_noise_2d(x, y)
					c = pal[clampi(int((v + 0.6) * 3.0), 0, 3)]
				"tiger":
					var s := sin((x + noise.get_noise_2d(x, y) * 40.0) * 0.25)
					c = Color(0.08, 0.06, 0.05) if s > 0.55 else Color(1.0, 0.55, 0.15)
				"carbon":
					var cell := ((x / 4) + (y / 4)) % 2
					var g := 0.12 + 0.1 * float((x if cell == 0 else y) % 4) / 4.0
					c = Color(g, g, g * 1.1)
				"lava":
					var v := noise.get_noise_2d(x, y) + noise2.get_noise_2d(x, y) * 0.4
					c = Color(0.12, 0.08, 0.07).lerp(Color(1.0, 0.4, 0.05), clampf((v - 0.15) * 3.0, 0.0, 1.0))
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_patterns[kind] = tex
	return tex


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
