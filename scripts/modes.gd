extends Node3D
## Modes de jeu : capture du drapeau, roi de la colline, course aux armes, élimination par manches.
## (Le match à mort classique est géré directement par game.gd.)
## Le serveur décide ; les clients reçoivent l'état par RPC.

const Data := preload("res://scripts/data.gd")

const FLAG_HOME := [Vector3(0, 0, 24), Vector3(0, 0, -24)]
const FLAG_RADIUS := 1.6
const FLAG_RETURN_TIME := 20.0
const HILL_POS := Vector3.ZERO
const HILL_RADIUS := 7.0
const ROUND_DELAY := 4.0

var game
var rules := "dm"
var team_pts := [0, 0]

# Capture du drapeau : état de chaque drapeau
var _flags := []  # {"team", "state" ("home" / "carried" / "dropped"), "pos", "carrier", "timer", "node"}
# Roi de la colline
var _hill: MeshInstance3D
var _hill_mat: StandardMaterial3D
var _hill_t := 0.0
var hill_owner := -2  # -2 personne, -1 contestée, sinon équipe (ou -10 - n° en chacun pour soi)
# Élimination
var round_over := false
var round_num := 1

# Recherche et destruction : deux sites (A et B), une bombe portée par un attaquant
const SITE_RADIUS := 3.2
const PLANT_TIME := 3.0
const DEFUSE_TIME := 6.0
const BOMB_TIMER := 35.0
const ROUND_TIME := 105.0
const BOMB_BLAST := {"damage": 400, "splash": 11.0}
const SIDE_SWITCH := 2  # les équipes échangent attaque / défense toutes les 2 manches
var sites: Array[Vector3] = []
var bomb := {"state": "none", "pos": Vector3.ZERO, "carrier": "", "site": -1, "timer": 0.0, "planter": ""}
var round_time := ROUND_TIME
var local_progress := 0.0  # pose / désamorçage du joueur local (0 à 1)
var local_action := ""
var _progress := {}  # (serveur) char_id -> secondes de pose / désamorçage
var _bomb_node: Node3D
var _bomb_light: OmniLight3D
var _interact_sent := false
var _beep_t := 0.0
var _sync_t := 0.0


func setup(p_rules: String) -> void:
	rules = p_rules
	if rules == "ctf":
		for t in 2:
			_flags.append({"team": t, "state": "home", "pos": FLAG_HOME[t], "carrier": "", "timer": 0.0,
				"node": _make_flag(t)})
	elif rules == "koth":
		_make_hill()
	elif rules == "snd":
		_make_sites()


func limit() -> int:
	var l: int = Data.RULES[rules]["limit"]
	return l if l > 0 else int(game.settings.score_limit)


# --- Construction -------------------------------------------------------------------

func _make_flag(team: int) -> Node3D:
	var root := Node3D.new()
	var color: Color = Data.TEAM_COLORS[team]
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.04
	cm.bottom_radius = 0.04
	cm.height = 2.4
	pole.mesh = cm
	pole.position.y = 1.2
	root.add_child(pole)
	var cloth := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.55, 0.04)
	cloth.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.5
	cloth.material_override = mat
	cloth.position = Vector3(0.47, 2.1, 0)
	root.add_child(cloth)
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 4.0
	light.light_energy = 1.2
	light.position.y = 1.5
	root.add_child(light)
	var label := Label3D.new()
	label.text = "DRAPEAU " + Data.TEAM_NAMES[team]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 40
	label.outline_size = 10
	label.modulate = color.lightened(0.3)
	label.position.y = 2.9
	root.add_child(label)
	add_child(root)
	root.position = FLAG_HOME[team]
	# Socle de la base
	var base := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = FLAG_RADIUS
	bc.bottom_radius = FLAG_RADIUS
	bc.height = 0.06
	base.mesh = bc
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.albedo_color = Color(color, 0.35)
	base.material_override = bmat
	base.position = FLAG_HOME[team] + Vector3(0, 0.04, 0)
	add_child(base)
	return root


func _make_hill() -> void:
	_hill = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = HILL_RADIUS
	cm.bottom_radius = HILL_RADIUS
	cm.height = 0.05
	_hill.mesh = cm
	_hill_mat = StandardMaterial3D.new()
	_hill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hill_mat.albedo_color = Color(1, 1, 1, 0.25)
	_hill.material_override = _hill_mat
	_hill.position = HILL_POS + Vector3(0, 0.05, 0)
	add_child(_hill)
	var label := Label3D.new()
	label.text = "ZONE"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 56
	label.outline_size = 12
	label.position = HILL_POS + Vector3(0, 4.5, 0)
	add_child(label)


## Sites A et B : de part et d'autre du centre, entre les deux camps, sur un endroit dégagé.
## Calculés pareil sur toutes les machines (même carte).
func _make_sites() -> void:
	var map = game.map
	var c0 := Vector3.ZERO
	var c1 := Vector3.ZERO
	for p in map.team_spawns[0]:
		c0 += p
	for p in map.team_spawns[1]:
		c1 += p
	c0 /= maxf(map.team_spawns[0].size(), 1)
	c1 /= maxf(map.team_spawns[1].size(), 1)
	var mid := (c0 + c1) / 2.0
	var axis := (c1 - c0)
	axis.y = 0
	axis = axis.normalized() if axis.length() > 0.1 else Vector3.FORWARD
	var side := axis.cross(Vector3.UP).normalized()
	for s in [-1.0, 1.0]:
		var want: Vector3 = mid + side * s * 15.0
		want.y = 0
		var best := want
		var found := false
		for ring in 12:
			for k in 8:
				var a := TAU * k / 8.0
				var p: Vector3 = want + Vector3(cos(a), 0, sin(a)) * ring * 1.5
				if map.is_clear(p) and map.is_clear(p + Vector3(1.5, 0, 0)) and map.is_clear(p - Vector3(1.5, 0, 0)):
					best = p
					found = true
					break
			if found:
				break
		sites.append(best)
	var names := ["A", "B"]
	for i in 2:
		var ring := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = SITE_RADIUS
		cm.bottom_radius = SITE_RADIUS
		cm.height = 0.04
		ring.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.55, 0.1, 0.28)
		ring.material_override = mat
		ring.position = sites[i] + Vector3(0, 0.04, 0)
		add_child(ring)
		var label := Label3D.new()
		label.text = names[i]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 96
		label.outline_size = 16
		label.modulate = Color(1.0, 0.65, 0.2)
		label.position = sites[i] + Vector3(0, 3.5, 0)
		add_child(label)
	# La bombe (visible posée ou lâchée)
	_bomb_node = Node3D.new()
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.42, 0.18, 0.3)
	body.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.2, 0.22, 0.18)
	body.material_override = bmat
	body.position.y = 0.09
	_bomb_node.add_child(body)
	var screen := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.16, 0.02, 0.1)
	screen.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.1, 0.9, 0.3)
	smat.emission_enabled = true
	smat.emission = Color(0.1, 0.9, 0.3)
	screen.material_override = smat
	screen.position = Vector3(0.06, 0.19, 0)
	_bomb_node.add_child(screen)
	_bomb_light = OmniLight3D.new()
	_bomb_light.light_color = Color(1, 0.15, 0.1)
	_bomb_light.omni_range = 3.0
	_bomb_light.light_energy = 0.0
	_bomb_light.position.y = 0.4
	_bomb_node.add_child(_bomb_light)
	var bl := Label3D.new()
	bl.name = "Label"
	bl.text = "BOMBE"
	bl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bl.no_depth_test = true
	bl.font_size = 36
	bl.outline_size = 10
	bl.modulate = Color(1, 0.4, 0.3)
	bl.position.y = 1.0
	_bomb_node.add_child(bl)
	_bomb_node.visible = false
	add_child(_bomb_node)


## Équipe qui attaque (pose la bombe) pendant la manche en cours.
func attackers() -> int:
	return int((round_num - 1) / SIDE_SWITCH) % 2


## (Serveur) Début de manche : la bombe est donnée à un attaquant au hasard.
func _start_bomb_round() -> void:
	_progress.clear()
	round_time = ROUND_TIME
	var team := attackers()
	var cands := []
	for id in game.chars:
		var c = game.chars[id]
		if c.alive and c.team == team:
			cands.append(c)
	var carrier: String = cands.pick_random().char_id if not cands.is_empty() else ""
	_set_bomb("carried" if carrier != "" else "none", Vector3.ZERO, carrier, -1, 0.0, "")
	_event("Manche %d : les %s attaquent !" % [round_num, Data.TEAM_NAMES[team]], team)


func _set_bomb(state: String, pos: Vector3, carrier: String, site: int, timer: float, planter: String) -> void:
	bomb = {"state": state, "pos": pos, "carrier": carrier, "site": site, "timer": timer, "planter": planter}
	_broadcast("bomb_state", [state, pos, carrier, site, timer])


func _update_snd(delta: float) -> void:
	if round_over:
		return
	var att := attackers()
	if bomb["state"] == "none":
		# Personne n'avait la bombe (début de partie) : on la donne dès qu'un attaquant est là
		for id in game.chars:
			var c = game.chars[id]
			if c.alive and c.team == att:
				_start_bomb_round()
				break
		return
	round_time -= delta
	# Bombe lâchée : un attaquant qui passe dessus la ramasse
	if bomb["state"] == "dropped":
		for id in game.chars:
			var c = game.chars[id]
			if c.alive and c.team == att and _dist2d(c.position, bomb["pos"]) < 1.3:
				_set_bomb("carried", Vector3.ZERO, c.char_id, -1, 0.0, "")
				_event("%s a ramassé la bombe" % c.display_name, att)
				break
	# Pose (porteur sur un site) et désamorçage (défenseur près de la bombe posée)
	for id in game.chars:
		var c = game.chars[id]
		var acting := false
		if c.alive and (c.interacting or (c.is_bot and bot_interact(c))):
			if bomb["state"] == "carried" and bomb["carrier"] == id:
				for i in sites.size():
					if _dist2d(c.position, sites[i]) < SITE_RADIUS:
						acting = true
						_progress[id] = float(_progress.get(id, 0.0)) + delta
						if _progress[id] >= PLANT_TIME:
							_progress.clear()
							_set_bomb("planted", Vector3(c.position.x, 0, c.position.z), "", i, BOMB_TIMER, id)
							_event("BOMBE POSÉE SUR LE SITE %s !" % ["A", "B"][i], att)
						break
			elif bomb["state"] == "planted" and c.team == 1 - att and _dist2d(c.position, bomb["pos"]) < 1.6:
				acting = true
				_progress[id] = float(_progress.get(id, 0.0)) + delta
				if _progress[id] >= DEFUSE_TIME:
					_progress.clear()
					_set_bomb("defused", bomb["pos"], "", bomb["site"], 0.0, "")
					_event("%s a désamorcé la bombe !" % c.display_name, 1 - att)
					_add_pts(c, 1)
					_end_round(1 - att, "Bombe désamorcée")
					return
		if not acting and _progress.has(id):
			_progress.erase(id)
	# Compte à rebours de la bombe
	if bomb["state"] == "planted":
		bomb["timer"] -= delta
		if bomb["timer"] <= 0.0:
			var pos: Vector3 = bomb["pos"]
			var planter = game.chars.get(bomb["planter"])
			if planter == null:
				for id in game.chars:
					if game.chars[id].team == att:
						planter = game.chars[id]
						break
			_set_bomb("exploded", pos, "", bomb["site"], 0.0, "")
			game.items._broadcast("explosion_fx", [pos + Vector3(0, 0.5, 0), float(BOMB_BLAST.splash)])
			if planter != null:
				game.server_explosion(planter, pos + Vector3(0, 0.5, 0), BOMB_BLAST, Data.KILL_BOMB)
				_add_pts(planter, 1)
			_end_round(att, "La bombe a explosé")
			return
	elif round_time <= 0.0:
		_end_round(1 - att, "Temps écoulé")
		return
	# Progression envoyée aux joueurs (barre de pose / désamorçage)
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 0.1
		var prog := {}
		for id in _progress:
			var planting: bool = bomb["state"] == "carried"
			prog[id] = [float(_progress[id]) / (PLANT_TIME if planting else DEFUSE_TIME), "pose" if planting else "désamorçage"]
		_broadcast("snd_tick", [prog, round_time, float(bomb["timer"])])


## (Serveur) Fin d'une manche de recherche et destruction.
func _end_round(winner: int, why: String) -> void:
	if round_over:
		return
	round_over = true
	team_pts[winner] += 1
	_event("%s : manche pour les %s ! (%d - %d)" % [why, Data.TEAM_NAMES[winner], team_pts[0], team_pts[1]], winner)
	_sync_pts()
	game.check_win()
	if game.match_over:
		return
	await get_tree().create_timer(ROUND_DELAY).timeout
	if game.match_over:
		return
	var switched := attackers()
	round_num += 1
	round_over = false
	for id in game.chars:
		var c = game.chars[id]
		game._broadcast("on_respawn", [id, game._pick_spawn(c.team), c.next_class if c.next_class >= 0 else c.class_id, c.next_armory])
		c.next_class = -1
		c.next_armory = {}
	_sync_pts()
	if attackers() != switched:
		_event("Changement de camp !", -1)
	_start_bomb_round()


# --- Boucle -------------------------------------------------------------------------

func _process(delta: float) -> void:
	if rules == "snd":
		_process_snd(delta)
	# Les drapeaux portés suivent leur porteur (sur toutes les machines)
	for f in _flags:
		var n: Node3D = f["node"]
		if f["state"] == "carried":
			var c = game.chars.get(f["carrier"])
			if c != null:
				n.global_position = c.global_position + Vector3(0, 0.4, 0) + c.global_transform.basis.z * 0.3
				n.visible = not c.is_local
		else:
			n.position = f["pos"]
			n.visible = true
	if _hill != null:
		var col := Color(1, 1, 1, 0.25)
		if hill_owner >= 0:
			col = Color(Data.TEAM_COLORS[hill_owner], 0.4)
		elif hill_owner == -1:
			col = Color(1, 0.8, 0.2, 0.35)
		elif hill_owner <= -10:
			col = Color(1, 0.6, 0.2, 0.4)
		_hill_mat.albedo_color = col


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or game.match_over:
		return
	if rules == "ctf":
		_update_ctf(delta)
	elif rules == "koth":
		_update_koth(delta)
	elif rules == "snd":
		_update_snd(delta)


## (Toutes les machines) Bombe visible, bips qui accélèrent, touche d'action envoyée à l'hôte.
func _process_snd(delta: float) -> void:
	var st: String = bomb["state"]
	_bomb_node.visible = st in ["dropped", "planted", "defused"]
	_bomb_node.position = bomb["pos"]
	(_bomb_node.get_node("Label") as Label3D).text = {"dropped": "BOMBE", "planted": "BOMBE %d s" % ceili(float(bomb["timer"])), "defused": "DÉSAMORCÉE"}.get(st, "")
	if st == "planted":
		if not multiplayer.is_server():  # l'hôte le décompte déjà dans _update_snd
			bomb["timer"] = maxf(0.0, float(bomb["timer"]) - delta)
		var t: float = bomb["timer"]
		var period := clampf(t / BOMB_TIMER, 0.08, 1.0) * 1.0
		_beep_t -= delta
		if _beep_t <= 0.0:
			_beep_t = period
			_bomb_light.light_energy = 3.0
			game.sfx.play("select_001", bomb["pos"] + Vector3(0, 0.3, 0), -4.0, 0.0, 40.0, 1.6)
		_bomb_light.light_energy = move_toward(_bomb_light.light_energy, 0.0, delta * 20.0)
	else:
		_bomb_light.light_energy = 0.0
	# Touche d'action (F) du joueur local : envoyée à l'hôte quand elle change
	var c = game.local_char
	if c == null:
		return
	var held: bool = Input.is_action_pressed("interact") and c.alive and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if held != _interact_sent:
		_interact_sent = held
		game.send_interact(held)


func _update_ctf(delta: float) -> void:
	for f in _flags:
		var t: int = f["team"]
		if f["state"] == "dropped":
			f["timer"] -= delta
			if f["timer"] <= 0.0:
				_set_flag(t, "home", FLAG_HOME[t], "")
				_event("Le drapeau %s est revenu à sa base" % Data.TEAM_NAMES[t], t)
				continue
		if f["state"] == "carried":
			continue
		for id in game.chars:
			var c = game.chars[id]
			if not c.alive or _dist2d(c.position, f["pos"]) > FLAG_RADIUS:
				continue
			if c.team != t:
				_set_flag(t, "carried", f["pos"], c.char_id)
				_event("%s a pris le drapeau %s !" % [c.display_name, Data.TEAM_NAMES[t]], c.team)
				break
			elif f["state"] == "dropped":
				_set_flag(t, "home", FLAG_HOME[t], "")
				_event("%s a ramené son drapeau" % c.display_name, t)
				break
	# Capture : porteur du drapeau ennemi dans sa base, avec son propre drapeau à la maison
	for f in _flags:
		if f["state"] != "carried":
			continue
		var c = game.chars.get(f["carrier"])
		if c == null or not c.alive:
			continue
		var own: Dictionary = _flags[c.team]
		if own["state"] == "home" and _dist2d(c.position, FLAG_HOME[c.team]) < FLAG_RADIUS + 0.4:
			team_pts[c.team] += 1
			_add_pts(c, 1)
			_set_flag(f["team"], "home", FLAG_HOME[f["team"]], "")
			_event("%s a capturé le drapeau ! (%d - %d)" % [c.display_name, team_pts[0], team_pts[1]], c.team)
			_sync_pts()
			game.check_win()


func _update_koth(delta: float) -> void:
	_hill_t += delta
	if _hill_t < 1.0:
		return
	_hill_t = 0.0
	var inside := []
	for id in game.chars:
		var c = game.chars[id]
		if c.alive and _dist2d(c.position, HILL_POS) < HILL_RADIUS:
			inside.append(c)
	var holder := -2
	if game.settings.mode == "team":
		var teams := {}
		for c in inside:
			teams[c.team] = true
		if teams.size() == 1:
			holder = teams.keys()[0]
			team_pts[holder] += 1
			if int(team_pts[holder]) % 10 == 0:
				print("[mode] zone : %s %d - %d" % [Data.TEAM_NAMES[holder], team_pts[0], team_pts[1]])
			for c in inside:
				_add_pts(c, 1)
		elif teams.size() > 1:
			holder = -1
	else:
		if inside.size() == 1:
			holder = -10
			_add_pts(inside[0], 1)
		elif inside.size() > 1:
			holder = -1
	if holder != hill_owner:
		hill_owner = holder
		_broadcast("hill_state", [holder])
	_sync_pts()
	game.check_win()


func _dist2d(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _add_pts(c, n: int) -> void:
	if game.scores.has(c.char_id):
		game.scores[c.char_id]["pts"] = int(game.scores[c.char_id].get("pts", 0)) + n


# --- Événements appelés par game.gd (serveur) ------------------------------------------

## Une élimination vient d'avoir lieu.
func on_kill(s, t, weapon: int) -> void:
	if rules == "ctf":
		for f in _flags:
			if f["state"] == "carried" and f["carrier"] == t.char_id:
				_set_flag(f["team"], "dropped", Vector3(t.position.x, 0, t.position.z), "")
				f["timer"] = FLAG_RETURN_TIME
				_event("%s a lâché le drapeau %s" % [t.display_name, Data.TEAM_NAMES[f["team"]]], f["team"])
	elif rules == "gungame":
		var lvl := int(game.scores.get(s.char_id, {}).get("pts", 0))
		if weapon == Data.KILL_KNIFE:
			# Humiliation : la victime recule d'un niveau
			var vl := int(game.scores.get(t.char_id, {}).get("pts", 0))
			if vl > 0:
				game.scores[t.char_id]["pts"] = vl - 1
				gungame_weapon(t)
		elif lvl < Data.GUNGAME_LADDER.size() and weapon == Data.GUNGAME_LADDER[lvl]:
			game.scores[s.char_id]["pts"] = lvl + 1
			if lvl + 1 < Data.GUNGAME_LADDER.size():
				gungame_weapon(s)
				_event("%s passe au niveau %d : %s" % [s.display_name, lvl + 2,
					Data.WEAPONS[Data.GUNGAME_LADDER[lvl + 1]].name], -1, s.char_id)
	elif rules == "elim":
		_check_round()
	elif rules == "snd":
		if bomb["state"] == "carried" and bomb["carrier"] == t.char_id:
			_set_bomb("dropped", Vector3(t.position.x, 0, t.position.z), "", -1, 0.0, "")
			_event("%s a lâché la bombe" % t.display_name, attackers())
		_progress.erase(t.char_id)
		_check_snd_teams()


## (Serveur) Une équipe entièrement éliminée : les défenseurs perdent ; les attaquants aussi,
## sauf si la bombe est déjà posée (les défenseurs doivent encore la désamorcer).
func _check_snd_teams() -> void:
	if round_over:
		return
	var alive := [0, 0]
	for id in game.chars:
		var c = game.chars[id]
		if c.alive and c.team >= 0:
			alive[c.team] += 1
	var att := attackers()
	if alive[1 - att] == 0:
		_end_round(att, "Défense éliminée")
	elif alive[att] == 0 and bomb["state"] != "planted":
		_end_round(1 - att, "Attaque éliminée")


## Peut-on réapparaître automatiquement ? (non en manches : on attend la manche suivante)
func allows_respawn() -> bool:
	return rules != "elim" and rules != "snd"


## (Serveur) Donne à un personnage l'arme de son niveau en course aux armes.
func gungame_weapon(c) -> void:
	if rules != "gungame":
		return
	var lvl := clampi(int(game.scores.get(c.char_id, {}).get("pts", 0)), 0, Data.GUNGAME_LADDER.size() - 1)
	game._broadcast("set_loadout", [c.char_id, [Data.GUNGAME_LADDER[lvl]]])


func _check_round() -> void:
	if round_over:
		return
	var alive := [0, 0]
	for id in game.chars:
		var c = game.chars[id]
		if c.alive and c.team >= 0:
			alive[c.team] += 1
	if alive[0] > 0 and alive[1] > 0:
		return
	round_over = true
	var winner := 0 if alive[0] > 0 else 1
	team_pts[winner] += 1
	_event("Manche %d pour les %s ! (%d - %d)" % [round_num, Data.TEAM_NAMES[winner], team_pts[0], team_pts[1]], winner)
	_sync_pts()
	game.check_win()
	if game.match_over:
		return
	await get_tree().create_timer(ROUND_DELAY).timeout
	if game.match_over:
		return
	round_num += 1
	round_over = false
	for id in game.chars:
		var c = game.chars[id]
		game._broadcast("on_respawn", [id, game._pick_spawn(c.team), c.next_class if c.next_class >= 0 else c.class_id, c.next_armory])
		c.next_class = -1
		c.next_armory = {}
	_event("Manche %d : c'est parti !" % round_num, -1)


# --- Robots ---------------------------------------------------------------------------

## Objectif d'un bot selon le mode (ou null pour son comportement habituel).
func bot_goal(c):
	if rules == "ctf" and c.team >= 0:
		for f in _flags:
			if f["state"] == "carried" and f["carrier"] == c.char_id:
				return FLAG_HOME[c.team]  # rentrer à la base
		var enemy: Dictionary = _flags[1 - c.team]
		var own: Dictionary = _flags[c.team]
		if own["state"] == "dropped" and randf() < 0.6:
			return own["pos"]
		if enemy["state"] != "carried" and randf() < 0.75:
			return enemy["pos"]
	elif rules == "koth" and randf() < 0.6:
		var a := randf() * TAU
		return HILL_POS + Vector3(cos(a), 0, sin(a)) * randf_range(3.5, HILL_RADIUS - 1.0)
	elif rules == "snd" and c.team >= 0 and not sites.is_empty():
		var att := attackers()
		var st: String = bomb["state"]
		if c.team == att:
			if st == "carried" and bomb["carrier"] == c.char_id:
				return sites[_bot_site(c)]
			if st == "dropped":
				return bomb["pos"]
			if st == "planted" and randf() < 0.7:
				return bomb["pos"] + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))  # garder la bombe
			if st == "carried" and randf() < 0.6:
				var carrier = game.chars.get(bomb["carrier"])
				if carrier != null:
					return carrier.position  # escorter le porteur
		else:
			if st == "planted":
				return bomb["pos"]
			if randf() < 0.7:
				return sites[hash(c.char_id) % 2] + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
	return null


## Site choisi par un bot porteur de la bombe (le même toute la manche).
func _bot_site(c) -> int:
	return (hash(c.char_id) + round_num) % 2


## (Serveur) Les bots posent / désamorcent tout seuls quand ils sont au bon endroit.
func bot_interact(c) -> bool:
	if rules != "snd" or sites.is_empty():
		return false
	if bomb["state"] == "carried" and bomb["carrier"] == c.char_id:
		return _dist2d(c.position, sites[_bot_site(c)]) < SITE_RADIUS - 0.8
	if bomb["state"] == "planted" and c.team == 1 - attackers():
		return _dist2d(c.position, bomb["pos"]) < 1.3
	return false


# --- Réseau ---------------------------------------------------------------------------

func _broadcast(method: String, args: Array) -> void:
	for p in game.ready_peers:
		callv("rpc_id", [p, method] + args)
	callv(method, args)


func _set_flag(team: int, state: String, pos: Vector3, carrier: String) -> void:
	_broadcast("flag_state", [team, state, pos, carrier])


func _sync_pts() -> void:
	_broadcast("sync_pts", [team_pts, round_num])


## Message de mode affiché à tous (dans le fil des éliminations et au centre de l'écran).
func _event(text: String, team: int, only_id := "") -> void:
	print("[mode] " + text)
	_broadcast("mode_event", [text, team, only_id])


func sync_to(peer: int) -> void:
	sync_pts.rpc_id(peer, team_pts, round_num)
	for f in _flags:
		flag_state.rpc_id(peer, f["team"], f["state"], f["pos"], f["carrier"])
	if _hill != null:
		hill_state.rpc_id(peer, hill_owner)
	if rules == "snd":
		bomb_state.rpc_id(peer, bomb["state"], bomb["pos"], bomb["carrier"], bomb["site"], float(bomb["timer"]))
	if rules == "gungame":
		for id in game.chars:
			var lvl := clampi(int(game.scores.get(id, {}).get("pts", 0)), 0, Data.GUNGAME_LADDER.size() - 1)
			game.set_loadout.rpc_id(peer, id, [Data.GUNGAME_LADDER[lvl]])


@rpc("authority", "call_remote", "reliable")
func flag_state(team: int, state: String, pos: Vector3, carrier: String) -> void:
	if team < 0 or team >= _flags.size():
		return
	var f: Dictionary = _flags[team]
	f["state"] = state
	f["pos"] = pos
	f["carrier"] = carrier


@rpc("authority", "call_remote", "reliable")
func sync_pts(pts: Array, rn: int) -> void:
	team_pts = pts
	round_num = rn
	game.hud.refresh_scores()


@rpc("authority", "call_remote", "reliable")
func hill_state(h: int) -> void:
	hill_owner = h


@rpc("authority", "call_remote", "reliable")
func bomb_state(state: String, pos: Vector3, carrier: String, site: int, timer: float) -> void:
	bomb["state"] = state
	bomb["pos"] = pos
	bomb["carrier"] = carrier
	bomb["site"] = site
	bomb["timer"] = timer
	if state == "planted" and game.sfx != null:
		game.sfx.play("metalLatch", pos, 0.0, 0.0, 60.0)
	if state != "carried" and state != "planted":
		local_progress = 0.0


@rpc("authority", "call_remote", "unreliable_ordered")
func snd_tick(prog: Dictionary, rt: float, bt: float) -> void:
	round_time = rt
	if bomb["state"] == "planted":
		bomb["timer"] = bt
	var c = game.local_char
	if c != null and prog.has(c.char_id):
		local_progress = float(prog[c.char_id][0])
		local_action = String(prog[c.char_id][1])
	else:
		local_progress = 0.0


@rpc("authority", "call_remote", "reliable")
func mode_event(text: String, team: int, only_id: String) -> void:
	if only_id != "" and (game.local_char == null or game.local_char.char_id != only_id):
		return
	var hex: String = "#ffcc55" if team < 0 else Data.TEAM_HEX[team]
	game.hud.add_kill("[color=%s]%s[/color]" % [hex, Data.esc(text)])
	game.hud.announce(text)


## Texte d'aide sur l'objectif, affiché sous le score.
func objective_text() -> String:
	var c = game.local_char
	match rules:
		"ctf":
			if c != null:
				for f in _flags:
					if f["state"] == "carried" and f["carrier"] == c.char_id:
						return "TU AS LE DRAPEAU : RAMÈNE-LE À TA BASE !"
			return "CAPTURE DU DRAPEAU · PREMIER À %d" % limit()
		"koth":
			return "ROI DE LA COLLINE · TIENS LA ZONE · PREMIER À %d" % limit()
		"gungame":
			if c != null and game.scores.has(c.char_id):
				var lvl := int(game.scores[c.char_id].get("pts", 0))
				return "COURSE AUX ARMES · NIVEAU %d / %d" % [mini(lvl + 1, limit()), limit()]
			return "COURSE AUX ARMES"
		"elim":
			return "ÉLIMINATION · MANCHE %d · PREMIER À %d" % [round_num, limit()]
		"snd":
			return _snd_text()
	return ""


func _snd_text() -> String:
	var c = game.local_char
	var key: String = Net.binding_text("interact")
	if local_progress > 0.0:
		var n := int(local_progress * 20.0)
		return "%s  %s%s" % [local_action.to_upper(), "█".repeat(n), "░".repeat(20 - n)]
	var att := attackers()
	var st: String = bomb["state"]
	if st == "planted":
		var where: String = ["A", "B"][clampi(int(bomb["site"]), 0, 1)]
		if c != null and c.team != att:
			return "BOMBE EN %s : %d s · DÉSAMORCE-LA (maintiens %s)" % [where, ceili(float(bomb["timer"])), key]
		return "BOMBE EN %s : %d s · PROTÈGE-LA" % [where, ceili(float(bomb["timer"]))]
	var t := "MANCHE %d · %d:%02d" % [round_num, int(round_time) / 60, int(round_time) % 60]
	if c == null or c.team < 0:
		return t
	if c.team == att:
		if st == "carried" and bomb["carrier"] == c.char_id:
			return "%s · TU AS LA BOMBE : pose-la sur A ou B (maintiens %s)" % [t, key]
		if st == "dropped":
			return "%s · ATTAQUE · la bombe est au sol, ramasse-la !" % t
		return "%s · ATTAQUE · escorte le porteur de la bombe" % t
	return "%s · DÉFENSE · protège les sites A et B" % t


## Vrai si le bot porte le drapeau ennemi : il rentre à sa base au lieu de se battre.
func bot_busy(c) -> bool:
	if rules == "snd":
		return bot_interact(c)  # en train de poser / désamorcer : ne pas se retourner pour tirer
	if rules != "ctf":
		return false
	for f in _flags:
		if f["state"] == "carried" and f["carrier"] == c.char_id:
			return true
	return false
