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


## Arme pour la vue à la première personne : centrée, canon vers -Z, longueur donnée.
static func weapon(model: String, length: float) -> Node3D:
	var root := Node3D.new()
	var pivot := Node3D.new()
	pivot.rotation.y = -PI / 2.0  # les armes du kit pointent vers -X
	root.add_child(pivot)
	var inst: Node3D = load(WEAPON_PATH % model).instantiate()
	pivot.add_child(inst)
	var box := _local_aabb(inst)
	var s := length / maxf(box.size.x, 0.01)
	inst.scale = Vector3.ONE * s
	inst.position = -box.get_center() * s
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


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
