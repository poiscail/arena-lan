extends RefCounted
## Chargement des modèles 3D (Quaternius Toon Shooter Game Kit, CC0) mis à l'échelle et orientés pour le jeu.

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
	var muzzle: Array = slice.call(muzzle_x, L * 0.03)
	var top: Array = slice.call(cx, L * 0.08)
	var pistol := box.size.y > L * 0.5  # pistolets et revolvers : plus hauts que longs
	var grip_x := rear_x + dir * L * (0.22 if pistol else 0.36)
	var grip: Array = slice.call(grip_x, L * 0.04)
	var front: Array = slice.call(cx + dir * L * 0.2, L * 0.05)
	return {
		"L": L, "dir": dir, "box": box, "pistol": pistol,
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
	for a in atts:
		match a:
			"silencer":
				var len := L * (0.32 if p["pistol"] else 0.22)
				_part(gun, "Silencer_Short", len, p["muzzle"] + Vector3(dir * len * 0.5, 0, 0), dir)
			"optic":
				var len := L * (0.4 if p["pistol"] else 0.3)
				var part := _part(gun, "Scope_3", len, Vector3.ZERO, dir)
				var h: float = part.get_meta("height")
				part.position = p["top"] + Vector3(-dir * L * 0.04, h * 0.5 + L * 0.005, 0)
			"grip":
				var part := _part(gun, "Grip", L * 0.07, Vector3.ZERO, dir, true)
				var h: float = part.get_meta("height")
				part.position = p["front_bottom"] - Vector3(0, h * 0.45, 0)
			"mag":
				var m := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(L * 0.07, L * 0.22, L * 0.05)
				m.mesh = bm
				var mat := StandardMaterial3D.new()
				mat.albedo_color = Color(0.13, 0.13, 0.14)
				m.material_override = mat
				m.rotation.z = 0.2 * dir
				var box: AABB = p["box"]
				m.position = Vector3(box.get_center().x + dir * L * 0.07, box.position.y - L * 0.02, box.get_center().z)
				m.set_meta("attachment", true)
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				gun.add_child(m)


## Charge un accessoire, le met à la taille voulue (longueur sur X, ou hauteur si « by_width »
## donne la largeur) et l'oriente comme l'arme. Renvoie le nœud (méta « height » = hauteur finale).
static func _part(gun: Node3D, name: String, size: float, pos: Vector3, dir: float, by_width := false) -> Node3D:
	var wrap := Node3D.new()
	var inst: Node3D = load("res://assets/guns_q/%s.fbx" % name).instantiate()
	var box := _local_aabb(inst)
	var ref := box.size.x if not by_width else box.size.x
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
