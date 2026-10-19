extends RefCounted
## Personnages Quaternius (Universal Base Characters + tenues) animés avec la Universal Animation Library.
## Tous partagent le même squelette de 65 os, donc les animations s'appliquent directement.

const PEOPLE_PATH := "res://assets/people/%s.gltf"
const UAL_PATH := "res://assets/ual/UAL1_Standard.glb"
const GUN_PATH := "res://assets/guns/%s.gltf"
const SKELETON := "Armature/Skeleton3D"
const Models := preload("res://scripts/models.gd")
const LOOPING := ["Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Idle", "Crouch_Fwd",
		"Pistol_Idle", "Pistol_Aim_Neutral", "Pistol_Aim_Up", "Pistol_Aim_Down", "Dance", "Idle_Talking"]

# Réglage de l'arme dans la main droite (os "hand_r")
const GUN_POS := Vector3(0.0, 0.0, 0.06)
const GUN_ROT := Vector3(0.0, 180.0, -90.0)
const GUN_LENGTH := 0.75

static var _lib: AnimationLibrary


static func anim_library() -> AnimationLibrary:
	if _lib == null:
		var ual: Node = load(UAL_PATH).instantiate()
		var ap: AnimationPlayer = ual.find_child("AnimationPlayer", true, false)
		_lib = ap.get_animation_library("")
		for n in LOOPING:
			if _lib.has_animation(n):
				_lib.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		ual.free()
	return _lib


## Construit un personnage : les "parts" sont des glTF du même squelette superposés (corps + tenue).
## Renvoie un Node3D (pieds à l'origine, regard vers -Z) avec les métadonnées "tree", "skeleton", "hand".
static func build(parts: Array, height: float) -> Node3D:
	var root := Node3D.new()
	var pivot := Node3D.new()
	pivot.rotation.y = PI
	root.add_child(pivot)
	var base: Node3D = load(PEOPLE_PATH % parts[0]).instantiate()
	pivot.add_child(base)
	var skel: Skeleton3D = base.get_node(SKELETON)
	for i in range(1, parts.size()):
		var extra: Node3D = load(PEOPLE_PATH % parts[i]).instantiate()
		var extra_skel: Skeleton3D = extra.get_node(SKELETON)
		for m in extra_skel.get_children():
			if m is MeshInstance3D:
				extra_skel.remove_child(m)
				m.owner = null
				skel.add_child(m)
				m.skeleton = NodePath("..")
		extra.free()
	for m in skel.get_children():
		if m is MeshInstance3D:
			m.extra_cull_margin = 2.0

	var tree := _make_tree(skel)
	base.add_child(tree)

	# Taille : mesurée sur le maillage au repos
	var box := _mesh_aabb(skel)
	var s := height / maxf(box.size.y, 0.01)
	base.scale = Vector3.ONE * s
	base.position.y = -box.position.y * s

	var hand := BoneAttachment3D.new()
	hand.bone_name = "hand_r"
	skel.add_child(hand)

	root.set_meta("tree", tree)
	root.set_meta("skeleton", skel)
	root.set_meta("hand", hand)
	root.set_meta("scale", s)
	return root


## Met une arme du kit Toon Shooter dans la main droite.
static func hold_gun(character: Node3D, model: String, length := GUN_LENGTH) -> Node3D:
	var hand: BoneAttachment3D = character.get_meta("hand")
	for c in hand.get_children():
		c.queue_free()
	if model == "":
		return null
	var holder := Node3D.new()
	holder.position = GUN_POS
	holder.rotation_degrees = GUN_ROT
	hand.add_child(holder)
	var gun: Node3D = load(GUN_PATH % model).instantiate()
	var native_len: float = maxf(Models._local_aabb(gun).size.x, 0.01)
	gun.scale = Vector3.ONE * (length / native_len / float(character.get_meta("scale")))
	holder.add_child(gun)
	return gun


static func _make_tree(skel: Skeleton3D) -> AnimationTree:
	var tree := AnimationTree.new()
	tree.add_animation_library("", anim_library())
	tree.root_node = NodePath("..")

	var bt := AnimationNodeBlendTree.new()

	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = 10.0
	loco.add_blend_point(_anim("Idle"), 0.0, -1, "idle")
	loco.add_blend_point(_anim("Walk"), 2.5, -1, "walk")
	loco.add_blend_point(_anim("Jog_Fwd"), 6.0, -1, "jog")
	loco.add_blend_point(_anim("Sprint"), 9.5, -1, "sprint")
	bt.add_node("loco", loco, Vector2(0, 0))

	# Glissade : posture accroupie mélangée aux jambes
	var slide := AnimationNodeBlend2.new()
	bt.add_node("slide", slide, Vector2(150, 0))
	bt.add_node("crouch", _anim("Crouch_Idle"), Vector2(0, -150))
	bt.connect_node("slide", 0, "loco")
	bt.connect_node("slide", 1, "crouch")

	var aim := AnimationNodeBlendSpace1D.new()
	aim.min_space = -1.0
	aim.max_space = 1.0
	aim.add_blend_point(_anim("Pistol_Aim_Down"), -1.0, -1, "down")
	aim.add_blend_point(_anim("Pistol_Aim_Neutral"), 0.0, -1, "neutral")
	aim.add_blend_point(_anim("Pistol_Aim_Up"), 1.0, -1, "up")
	bt.add_node("aim", aim, Vector2(0, 200))

	var upper := AnimationNodeBlend2.new()
	upper.filter_enabled = true
	_filter_upper(upper, skel)
	bt.add_node("upper", upper, Vector2(300, 100))
	bt.connect_node("upper", 0, "slide")
	bt.connect_node("upper", 1, "aim")

	var shoot := AnimationNodeOneShot.new()
	shoot.filter_enabled = true
	shoot.fadein_time = 0.03
	shoot.fadeout_time = 0.1
	_filter_upper(shoot, skel)
	bt.add_node("shoot", shoot, Vector2(500, 100))
	bt.add_node("shoot_anim", _anim("Pistol_Shoot"), Vector2(300, 300))
	bt.connect_node("shoot", 0, "upper")
	bt.connect_node("shoot", 1, "shoot_anim")

	var state := AnimationNodeTransition.new()
	state.add_input("alive")
	state.add_input("dead")
	state.xfade_time = 0.15
	bt.add_node("state", state, Vector2(700, 100))
	bt.add_node("death", _anim("Death01"), Vector2(500, 300))
	bt.connect_node("state", 0, "shoot")
	bt.connect_node("state", 1, "death")
	bt.connect_node("output", 0, "state")

	tree.tree_root = bt
	tree.active = true
	tree.set("parameters/upper/blend_amount", 1.0)
	tree.set("parameters/state/transition_request", "alive")
	return tree


static func _anim(n: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = n
	return a


## Le haut du corps = spine_02 et tout ce qui en descend (buste, bras, tête).
static func _filter_upper(node: AnimationNode, skel: Skeleton3D) -> void:
	var start := skel.find_bone("spine_02")
	for i in skel.get_bone_count():
		var b := i
		while b != -1 and b != start:
			b = skel.get_bone_parent(b)
		if b == start:
			node.set_filter_path(NodePath(SKELETON + ":" + skel.get_bone_name(i)), true)


static func _mesh_aabb(skel: Skeleton3D) -> AABB:
	var result := AABB()
	var first := true
	for m in skel.get_children():
		if m is MeshInstance3D:
			var a: AABB = m.get_aabb()
			if first:
				result = a
				first = false
			else:
				result = result.merge(a)
	return result


## Oriente l'arme tenue dans la direction visée « fwd » (au lieu de suivre la rotation de la main).
static func aim_gun(gun: Node3D, character: Node3D, fwd: Vector3) -> void:
	if gun == null or not is_instance_valid(gun):
		return
	var holder: Node3D = gun.get_parent()
	var s: float = character.get_meta("scale")
	# Les armes du kit pointent vers -X dans leur repère : quart de tour pour viser vers -Z
	var b := Basis.looking_at(fwd, Vector3.UP) * Basis(Vector3.UP, -PI / 2.0)
	holder.global_transform = Transform3D(b.scaled_local(Vector3.ONE * s), holder.global_position)
