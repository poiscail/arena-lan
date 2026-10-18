extends RefCounted
## Chargement des modèles 3D (Kenney, CC0) mis à l'échelle et orientés pour le jeu.

const CHAR_PATH := "res://assets/characters/%s.glb"
const WEAPON_PATH := "res://assets/weapons/%s.glb"
const LOOPING := ["idle", "walk", "sprint", "holding-both", "holding-right"]


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
		if ap.has_animation("idle"):
			ap.play("idle")
			ap.seek(0.0, true)
	var box := _local_aabb(inst)
	var s := height / maxf(box.size.y, 0.01)
	inst.scale = Vector3.ONE * s
	inst.position = Vector3(-box.get_center().x * s, -box.position.y * s, -box.get_center().z * s)
	return root


## Arme centrée sur l'origine, canon vers -Z, longueur donnée.
static func weapon(model: String, length: float) -> Node3D:
	var root := Node3D.new()
	var pivot := Node3D.new()  # les blasters Kenney ont déjà le canon vers -Z
	root.add_child(pivot)
	var inst: Node3D = load(WEAPON_PATH % model).instantiate()
	pivot.add_child(inst)
	var box := _local_aabb(inst)
	var s := length / maxf(box.size.z, 0.01)
	inst.scale = Vector3.ONE * s
	inst.position = -box.get_center() * s
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


static func _local_aabb(top: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for m in top.find_children("*", "MeshInstance3D", true, false):
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
