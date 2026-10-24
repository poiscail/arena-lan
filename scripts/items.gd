extends Node3D
## Objets de la partie : trousses de soin et bonus, barils explosifs, grenades et fumigènes.
## Le serveur décide de tout (ramassage, explosions, dégâts) ; les clients affichent.

const Data := preload("res://scripts/data.gd")
const GUN_PATH := "res://assets/guns/%s.gltf"

const PICKUP_RADIUS := 1.3
const BARREL_HP := 25
const BARREL_RESPAWN := 30.0
const GRENADE_FUSE := 2.2
const SMOKE_TIME := 12.0
const SMOKE_RADIUS := 4.5

var game
var _pickups := []   # {"kind", "pos", "node", "active", "timer"}
var _barrels := []   # {"pos", "node", "hp", "active", "timer"}
var _grenades := {}  # id -> {"body", "kind", "owner", "fuse"}
var _smokes := []    # {"pos", "node", "t"}
var _grenade_serial := 0
var _t := 0.0


func setup(map) -> void:
	print("[objets] %d trousses, %d bonus, %d barils" % [map.health_points.size(), map.bonus_points.size(), map.barrel_points.size()])
	for p in map.health_points:
		_add_pickup("health", p)
	for b in map.bonus_points:
		_add_pickup(b[0], b[1])
	for p in map.barrel_points:
		_add_barrel(p)
	for b in map.breakable_points:
		_add_breakable(b[0], b[1], b[2], map.BREAKABLE_SIZES[b[0]])


# --- Construction -------------------------------------------------------------------

func _add_pickup(kind: String, pos: Vector3) -> void:
	var info: Array = Data.PICKUPS[kind]
	var node := Node3D.new()
	node.position = pos
	add_child(node)
	if kind == "health":
		var m: Node3D = load("res://assets/env/Health.gltf").instantiate()
		m.scale = Vector3.ONE * 0.8
		node.add_child(m)
	else:
		# Caisse lumineuse de la couleur du bonus
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.55, 0.55, 0.55)
		box.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = info[1]
		mat.emission_enabled = true
		mat.emission = info[1]
		mat.emission_energy_multiplier = 0.6
		box.material_override = mat
		box.position.y = 0.3
		node.add_child(box)
	var label := Label3D.new()
	label.text = info[0]
	label.font_size = 36
	label.outline_size = 8
	label.modulate = info[1]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 1.2
	node.add_child(label)
	var glow := OmniLight3D.new()
	glow.light_color = info[1]
	glow.light_energy = 0.8
	glow.omni_range = 2.5
	glow.position.y = 0.5
	node.add_child(glow)
	_pickups.append({"kind": kind, "pos": pos, "node": node, "active": true, "timer": 0.0})


func _add_barrel(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.set_meta("barrel", _barrels.size())
	var m: Node3D = load("res://assets/env/ExplodingBarrel.gltf").instantiate()
	body.add_child(m)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.42
	cyl.height = 1.2
	shape.shape = cyl
	shape.position.y = 0.6
	body.add_child(shape)
	add_child(body)
	_barrels.append({"pos": pos, "node": body, "hp": BARREL_HP, "active": true, "timer": 0.0})


# --- Objets destructibles -------------------------------------------------------------

const BREAK_RESPAWN := 45.0
const PIECE_HP := {"planks": 30.0, "crate": 70.0, "glass": 1.0}
var _breakables := []  # {"kind", "pos", "node", "hp": [par morceau], "timer"}
var _wood_mat: StandardMaterial3D
var _wood_dark: StandardMaterial3D
var _glass_mat: StandardMaterial3D


func _mats() -> void:
	if _wood_mat != null:
		return
	_wood_mat = StandardMaterial3D.new()
	_wood_mat.albedo_color = Color(0.58, 0.4, 0.24)
	_wood_mat.roughness = 0.85
	_wood_dark = StandardMaterial3D.new()
	_wood_dark.albedo_color = Color(0.36, 0.24, 0.14)
	_wood_dark.roughness = 0.9
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.albedo_color = Color(0.7, 0.88, 1.0, 0.28)
	_glass_mat.roughness = 0.05
	_glass_mat.metallic = 0.3
	_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


## Un objet destructible : chaque morceau (planche, caisse, vitre) a sa propre forme de collision,
## donc on peut percer une barricade planche par planche.
func _add_breakable(kind: String, pos: Vector3, yaw: float, size: Vector3) -> void:
	_mats()
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees.y = yaw
	body.set_meta("breakable", _breakables.size())
	var hp := []
	match kind:
		"planks":
			# Deux poteaux et quatre planches horizontales
			for sx in [-1.0, 1.0]:
				_vis_box(body, Vector3(0.14, size.y + 0.15, 0.14), Vector3(sx * (size.x / 2.0 - 0.1), (size.y + 0.15) / 2.0, 0), _wood_dark)
			for k in 4:
				var y := 0.22 + k * 0.33
				var piece := _piece(body, Vector3(size.x, 0.27, 0.07), Vector3(0, y, 0.05), _wood_mat, k)
				piece.rotation.z = (k % 2 - 0.5) * 0.04
				hp.append(PIECE_HP["planks"])
		"crate":
			var piece := _piece(body, size, Vector3(0, size.y / 2.0, 0), _wood_mat, 0)
			# Renforts sur les arêtes
			for e in [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]:
				var m := _vis_box(piece, Vector3(0.1, size.y + 0.02, 0.1), Vector3(e.x * size.x / 2.0, 0, e.z * size.z / 2.0), _wood_dark)
				m.set_meta("trim", true)
			hp.append(PIECE_HP["crate"])
		"glass":
			for sx in [-1.0, 1.0]:
				_vis_box(body, Vector3(0.12, size.y, 0.16), Vector3(sx * (size.x / 2.0 - 0.06), size.y / 2.0, 0), _wood_dark)
			_vis_box(body, Vector3(size.x, 0.12, 0.16), Vector3(0, size.y - 0.06, 0), _wood_dark)
			_vis_box(body, Vector3(size.x, 0.25, 0.16), Vector3(0, 0.125, 0), _wood_dark)
			_piece(body, Vector3(size.x - 0.24, size.y - 0.37, 0.03), Vector3(0, 0.25 + (size.y - 0.37) / 2.0, 0), _glass_mat, 0)
			hp.append(PIECE_HP["glass"])
	add_child(body)
	_breakables.append({"kind": kind, "pos": pos, "node": body, "hp": hp, "timer": 0.0})


func _vis_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
	return m


## Morceau cassable : un visuel et une forme de collision (méta « piece » = son numéro).
func _piece(body: StaticBody3D, size: Vector3, pos: Vector3, mat: Material, index: int) -> MeshInstance3D:
	var m := _vis_box(body, size, pos, mat)
	m.name = "Piece%d" % index
	if mat == _glass_mat:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shape := CollisionShape3D.new()
	shape.name = "Shape%d" % index
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	shape.set_meta("piece", index)
	body.add_child(shape)
	return m


## (Serveur) Un tir touche peut-être un objet destructible (hit = résultat du rayon).
func server_hit_breakable(hit: Dictionary, dmg: float) -> void:
	var body = hit.get("collider")
	if body == null or not (body is StaticBody3D) or not body.has_meta("breakable"):
		return
	var owner_id: int = body.shape_find_owner(int(hit.get("shape", 0)))
	var shape_node = body.shape_owner_get_owner(owner_id)
	if shape_node == null or not shape_node.has_meta("piece"):
		return
	_damage_piece(int(body.get_meta("breakable")), int(shape_node.get_meta("piece")), dmg, hit.position)


func _damage_piece(i: int, piece: int, dmg: float, at: Vector3) -> void:
	var b: Dictionary = _breakables[i]
	if piece >= b["hp"].size() or b["hp"][piece] <= 0.0:
		return
	b["hp"][piece] -= dmg
	if b["hp"][piece] <= 0.0:
		_broadcast("break_piece", [i, piece, at, true])
		var all_broken := true
		for h in b["hp"]:
			if h > 0.0:
				all_broken = false
		if all_broken:
			b["timer"] = BREAK_RESPAWN


## (Serveur) Les explosions brisent tout ce qui est proche.
func server_explosion_breakables(at: Vector3, radius: float) -> void:
	for i in _breakables.size():
		var b: Dictionary = _breakables[i]
		if (b["pos"] as Vector3).distance_to(at) < radius + 1.0:
			for piece in b["hp"].size():
				_damage_piece(i, piece, 999.0, at)


func _update_breakables(delta: float) -> void:
	for i in _breakables.size():
		var b: Dictionary = _breakables[i]
		if b["timer"] <= 0.0:
			continue
		b["timer"] -= delta
		if b["timer"] <= 0.0:
			# Réapparition seulement si personne n'est dessus
			for id in game.chars:
				if game.chars[id].alive and game.chars[id].position.distance_to(b["pos"]) < 2.0:
					b["timer"] = 3.0
					break
			if b["timer"] <= 0.0:
				_broadcast("breakable_reset", [i])


@rpc("authority", "call_remote", "reliable")
func break_piece(i: int, piece: int, at: Vector3, fx: bool) -> void:
	if i < 0 or i >= _breakables.size():
		return
	var b: Dictionary = _breakables[i]
	var body: StaticBody3D = b["node"]
	if piece < b["hp"].size():
		b["hp"][piece] = 0.0
	var vis := body.get_node_or_null("Piece%d" % piece) as MeshInstance3D
	var shape := body.get_node_or_null("Shape%d" % piece) as CollisionShape3D
	if shape != null:
		shape.set_deferred("disabled", true)
	if vis == null or not vis.visible:
		return
	vis.visible = false
	if not fx:
		return
	_debris(b["kind"], vis, at)
	if b["kind"] == "glass":
		game.sfx.play("impactMetal_light_001", vis.global_position, 2.0, 0.1, 50.0, 2.2)
		game.sfx.play("impactGeneric_light_002", vis.global_position, 0.0, 0.1, 50.0, 2.6)
	else:
		game.sfx.play("impactPunch_medium_000", vis.global_position, 2.0, 0.1, 50.0, 0.6)
		game.sfx.play("impactGeneric_light_000", vis.global_position, 0.0, 0.1, 50.0, 0.7)


## Débris qui tombent et rebondissent, puis disparaissent.
func _debris(kind: String, vis: MeshInstance3D, at: Vector3) -> void:
	var size: Vector3 = (vis.mesh as BoxMesh).size
	var center := vis.global_position
	var basis := vis.global_transform.basis
	var count := 3 if kind == "planks" else (6 if kind == "crate" else 14)
	for k in count:
		var piece_size: Vector3
		var offset: Vector3
		match kind:
			"planks":
				piece_size = Vector3(size.x / count, size.y, size.z)
				offset = Vector3((k - (count - 1) / 2.0) * size.x / count, 0, 0)
			"crate":
				piece_size = Vector3(size.x * randf_range(0.4, 0.9), 0.06, size.z * randf_range(0.2, 0.4))
				offset = Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), randf_range(-0.4, 0.4)) * size
			_:
				piece_size = Vector3(randf_range(0.15, 0.4), randf_range(0.15, 0.4), 0.02)
				offset = Vector3(randf_range(-0.5, 0.5) * size.x, randf_range(-0.5, 0.5) * size.y, 0)
		var rb := RigidBody3D.new()
		rb.collision_layer = 0
		rb.collision_mask = 1
		rb.mass = 0.5
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = piece_size
		m.mesh = bm
		m.material_override = _glass_mat if kind == "glass" else (_wood_mat if randf() < 0.7 else _wood_dark)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rb.add_child(m)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = piece_size.max(Vector3.ONE * 0.04)
		cs.shape = box
		rb.add_child(cs)
		add_child(rb)
		rb.global_position = center + basis * offset
		rb.global_basis = basis
		var away: Vector3 = (rb.global_position - at)
		away.y = 0
		away = away.normalized() if away.length() > 0.01 else Vector3.UP
		rb.linear_velocity = away * randf_range(1.5, 4.0) + Vector3(0, randf_range(1.0, 3.0), 0)
		rb.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
		get_tree().create_timer(randf_range(4.0, 6.0)).timeout.connect(rb.queue_free)


@rpc("authority", "call_remote", "reliable")
func breakable_reset(i: int) -> void:
	if i < 0 or i >= _breakables.size():
		return
	var b: Dictionary = _breakables[i]
	var body: StaticBody3D = b["node"]
	for k in b["hp"].size():
		b["hp"][k] = PIECE_HP[b["kind"]]
		var vis := body.get_node_or_null("Piece%d" % k) as MeshInstance3D
		var shape := body.get_node_or_null("Shape%d" % k) as CollisionShape3D
		if vis != null:
			vis.visible = true
		if shape != null:
			shape.set_deferred("disabled", false)


# --- Boucle -------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	for p in _pickups:
		var n: Node3D = p["node"]
		n.rotation.y = _t * 1.5
		n.position.y = p["pos"].y + 0.35 + sin(_t * 2.5) * 0.12
	for i in range(_smokes.size() - 1, -1, -1):
		var s: Dictionary = _smokes[i]
		s["t"] -= delta
		var a := clampf(s["t"] / 2.0, 0.0, 1.0)  # se dissipe sur les 2 dernières secondes
		for puff in s["node"].get_children():
			puff.material_override.albedo_color.a = 0.85 * a
			puff.position.y += delta * 0.05
		if s["t"] <= 0.0:
			s["node"].queue_free()
			_smokes.remove_at(i)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or game.match_over:
		return
	_update_pickups(delta)
	_update_breakables(delta)
	for i in _barrels.size():
		var b: Dictionary = _barrels[i]
		if not b["active"]:
			b["timer"] -= delta
			if b["timer"] <= 0.0:
				_broadcast("barrel_state", [i, true])
	for id in _grenades.keys():
		var g: Dictionary = _grenades[id]
		g["fuse"] -= delta
		if g["fuse"] <= 0.0:
			_server_grenade_boom(id)


## (Serveur) Ramassage des trousses et bonus.
func _update_pickups(delta: float) -> void:
	for i in _pickups.size():
		var p: Dictionary = _pickups[i]
		if not p["active"]:
			p["timer"] -= delta
			if p["timer"] <= 0.0:
				_broadcast("pickup_state", [i, true])
			continue
		for id in game.chars:
			var c = game.chars[id]
			if not c.alive or not _wants(c, p["kind"]):
				continue
			var d: Vector3 = c.position - p["pos"]
			if Vector2(d.x, d.z).length() < PICKUP_RADIUS and absf(d.y) < 1.5:
				_server_apply_pickup(c, p["kind"])
				p["timer"] = Data.PICKUPS[p["kind"]][2]
				_broadcast("pickup_state", [i, false])
				break


func _wants(c, kind: String) -> bool:
	match kind:
		"health":
			return c.hp < 100
		"armor":
			return c.armor < 100
	return true


func _server_apply_pickup(c, kind: String) -> void:
	match kind:
		"health":
			c.hp = mini(100, c.hp + 50)
		"armor":
			c.armor = mini(100, c.armor + 50)
	print("[bonus] %s -> %s" % [c.display_name, kind])
	_broadcast("on_pickup", [c.char_id, kind, c.hp, c.armor])


# --- Barils -------------------------------------------------------------------------

## (Serveur) Un tir ou une explosion touche peut-être un baril.
func server_hit_barrel(collider, dmg: float, shooter) -> void:
	if collider == null or not collider.has_meta("barrel"):
		return
	var i: int = collider.get_meta("barrel")
	var b: Dictionary = _barrels[i]
	if not b["active"]:
		return
	b["hp"] -= dmg
	if b["hp"] <= 0:
		_explode_barrel(i, shooter)


func _explode_barrel(i: int, shooter) -> void:
	var b: Dictionary = _barrels[i]
	b["active"] = false
	b["timer"] = BARREL_RESPAWN
	_broadcast("barrel_state", [i, false])
	var at: Vector3 = b["pos"] + Vector3(0, 0.7, 0)
	_broadcast("explosion_fx", [at, float(Data.BARREL.splash)])
	game.server_explosion(shooter, at, Data.BARREL, Data.KILL_BARREL)
	# Réaction en chaîne sur les barils proches
	for j in _barrels.size():
		if j != i and _barrels[j]["active"] and _barrels[j]["pos"].distance_to(b["pos"]) < float(Data.BARREL.splash):
			get_tree().create_timer(0.15).timeout.connect(func() -> void:
				if _barrels[j]["active"]:
					_explode_barrel(j, shooter))


## (Serveur) Les explosions font aussi sauter les barils autour.
func server_explosion_barrels(at: Vector3, radius: float, shooter) -> void:
	server_explosion_breakables(at, radius)
	for j in _barrels.size():
		if _barrels[j]["active"] and _barrels[j]["pos"].distance_to(at) < radius:
			_explode_barrel.call_deferred(j, shooter)


# --- Grenades -----------------------------------------------------------------------

## Le joueur local lance une grenade (0 explosive, 1 fumigène).
func throw_grenade(c, kind: int) -> void:
	var origin: Vector3 = c.camera.global_position - c.camera.global_transform.basis.z * 0.6
	var vel: Vector3 = -c.camera.global_transform.basis.z * 17.0 + Vector3(0, 3.0, 0) + c.velocity * 0.5
	if multiplayer.is_server():
		_server_throw(c, kind, origin, vel)
	else:
		req_grenade.rpc_id(1, kind, origin, vel)


@rpc("any_peer", "call_remote", "reliable")
func req_grenade(kind: int, origin: Vector3, vel: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var c = game.chars.get("P%d" % multiplayer.get_remote_sender_id())
	if c != null:
		_server_throw(c, kind, origin, vel)


func _server_throw(c, kind: int, origin: Vector3, vel: Vector3) -> void:
	kind = clampi(kind, 0, 1)
	if not c.alive or game.match_over or c.grenades[kind] <= 0:
		return
	c.grenades[kind] -= 1
	if origin.distance_to(c.eye_position()) > 3.0:
		origin = c.eye_position()
	vel = vel.limit_length(25.0)
	_grenade_serial += 1
	var id := "G%d" % _grenade_serial
	print("[grenade] %s lance %s" % [c.display_name, "une grenade" if kind == 0 else "un fumigène"])
	_broadcast("spawn_grenade", [id, kind, c.char_id, origin, vel])


@rpc("authority", "call_remote", "reliable")
func spawn_grenade(id: String, kind: int, owner_id: String, origin: Vector3, vel: Vector3) -> void:
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1
	body.mass = 0.4
	body.continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.8
	body.physics_material_override = pm
	var shape := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.12
	shape.shape = sph
	body.add_child(shape)
	var m: Node3D = load(GUN_PATH % ("Grenade" if kind == 0 else "FireGrenade")).instantiate()
	var box: AABB = preload("res://scripts/models.gd")._local_aabb(m)
	m.scale = Vector3.ONE * (0.3 / maxf(box.size.y, 0.01))
	m.position = -box.get_center() * m.scale.x
	if kind == 1:
		_tint(m, Color(0.75, 0.78, 0.8))
	body.add_child(m)
	add_child(body)
	body.global_position = origin
	body.linear_velocity = vel
	body.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	body.contact_monitor = true
	body.max_contacts_reported = 1
	body.body_entered.connect(func(_b: Node) -> void:
		if body.linear_velocity.length() > 2.0:
			game.sfx.play("impactMetal_light_00%d" % (randi() % 2), body.global_position, -6.0, 0.15, 30.0))
	game.sfx.play("cloth1", origin, -6.0)
	_grenades[id] = {"body": body, "kind": kind, "owner": owner_id, "fuse": GRENADE_FUSE}
	var c = game.chars.get(owner_id)
	if c != null and not c.is_local:
		c.play_shoot()


func _server_grenade_boom(id: String) -> void:
	var g: Dictionary = _grenades[id]
	var pos: Vector3 = g["body"].global_position
	_broadcast("grenade_boom", [id, pos, g["kind"]])
	if g["kind"] == 0:
		var s = game.chars.get(g["owner"])
		game.server_explosion(s, pos + Vector3(0, 0.2, 0), Data.GRENADE, Data.KILL_GRENADE)


@rpc("authority", "call_remote", "reliable")
func grenade_boom(id: String, pos: Vector3, kind: int) -> void:
	var g = _grenades.get(id)
	if g != null:
		g["body"].queue_free()
		_grenades.erase(id)
	if kind == 0:
		game.spawn_explosion(pos + Vector3(0, 0.2, 0), float(Data.GRENADE.splash))
	else:
		_spawn_smoke(pos)


func _spawn_smoke(pos: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	for i in 14:
		var puff := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var r := randf_range(1.3, 2.2)
		sm.radius = r
		sm.height = r * 1.6
		puff.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.82, 0.84, 0.86, 0.85)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		puff.material_override = mat
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := randf() * TAU
		var d := randf() * (SMOKE_RADIUS - 1.5)
		puff.position = Vector3(cos(a) * d, r * 0.6 + randf() * 1.2, sin(a) * d)
		root.add_child(puff)
	_smokes.append({"pos": pos, "node": root, "t": SMOKE_TIME})


## Vrai si un segment traverse un nuage de fumée (les bots ne voient pas à travers).
func smoke_blocks(a: Vector3, b: Vector3) -> bool:
	for s in _smokes:
		if s["t"] < 1.0:
			continue
		var c: Vector3 = s["pos"] + Vector3(0, 1.5, 0)
		var ab := b - a
		var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		if (a + ab * t).distance_to(c) < SMOKE_RADIUS - 0.5:
			return true
	return false


func _tint(node: Node, color: Color) -> void:
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		m.material_override = mat


# --- Réseau -------------------------------------------------------------------------

func _broadcast(method: String, args: Array) -> void:
	for p in game.ready_peers:
		callv("rpc_id", [p, method] + args)
	callv(method, args)


## (Serveur) Envoie l'état des objets à un joueur qui arrive en cours de partie.
func sync_to(peer: int) -> void:
	for i in _pickups.size():
		pickup_state.rpc_id(peer, i, _pickups[i]["active"])
	for i in _barrels.size():
		barrel_state.rpc_id(peer, i, _barrels[i]["active"])
	for i in _breakables.size():
		for k in _breakables[i]["hp"].size():
			if _breakables[i]["hp"][k] <= 0.0:
				break_piece.rpc_id(peer, i, k, Vector3.ZERO, false)


@rpc("authority", "call_remote", "reliable")
func pickup_state(i: int, active: bool) -> void:
	if i >= 0 and i < _pickups.size():
		_pickups[i]["active"] = active
		_pickups[i]["node"].visible = active


@rpc("authority", "call_remote", "reliable")
func barrel_state(i: int, active: bool) -> void:
	if i < 0 or i >= _barrels.size():
		return
	var b: Dictionary = _barrels[i]
	b["active"] = active
	b["hp"] = BARREL_HP
	b["node"].visible = active
	b["node"].process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	b["node"].get_child(1).set_deferred("disabled", not active)


@rpc("authority", "call_remote", "reliable")
func explosion_fx(pos: Vector3, radius: float) -> void:
	game.spawn_explosion(pos, radius)


@rpc("authority", "call_remote", "reliable")
func on_pickup(id: String, kind: String, hp: int, armor: int) -> void:
	var c = game.chars.get(id)
	if c == null:
		return
	c.hp = hp
	c.armor = armor
	c.apply_pickup(kind)
	if c.is_local:
		game.hud.pickup_flash(Data.PICKUPS[kind][0], Data.PICKUPS[kind][1])
		game.sfx.play("confirmation_002", null, -4.0, 0.0)


## Position du bonus disponible le plus proche parmi « kinds » (ou null), pour les bots.
func nearest_pickup(pos: Vector3, kinds: Array, max_dist: float):
	var best = null
	var best_d := max_dist
	for p in _pickups:
		if p["active"] and kinds.has(p["kind"]):
			var d: float = pos.distance_to(p["pos"])
			if d < best_d:
				best_d = d
				best = p["pos"]
	return best


## (Serveur) Un bot lance une grenade en cloche vers « target ».
func server_throw_at(c, kind: int, target: Vector3) -> void:
	var origin: Vector3 = c.eye_position()
	var d := target - origin
	var horiz := Vector2(d.x, d.z)
	var dist := maxf(horiz.length(), 1.0)
	var speed := clampf(dist * 0.9, 7.0, 17.0)
	var t := dist / speed
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var vy := (d.y + 0.5 * g * t * t) / t
	var dir := horiz.normalized()
	origin += Vector3(dir.x, 0, dir.y) * 0.5
	_server_throw(c, kind, origin, Vector3(dir.x * speed, vy, dir.y * speed))
