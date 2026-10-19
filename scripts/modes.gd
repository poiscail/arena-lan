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


func setup(p_rules: String) -> void:
	rules = p_rules
	if rules == "ctf":
		for t in 2:
			_flags.append({"team": t, "state": "home", "pos": FLAG_HOME[t], "carrier": "", "timer": 0.0,
				"node": _make_flag(t)})
	elif rules == "koth":
		_make_hill()


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


# --- Boucle -------------------------------------------------------------------------

func _process(_delta: float) -> void:
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


## Peut-on réapparaître automatiquement ? (non en élimination : on attend la manche suivante)
func allows_respawn() -> bool:
	return rules != "elim"


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
	return null


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
	return ""


## Vrai si le bot porte le drapeau ennemi : il rentre à sa base au lieu de se battre.
func bot_busy(c) -> bool:
	if rules != "ctf":
		return false
	for f in _flags:
		if f["state"] == "carried" and f["carrier"] == c.char_id:
			return true
	return false
