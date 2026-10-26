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

# Zombies (coopération) : vagues de zombies de plus en plus nombreux et résistants
const ZOMBIE_MAX := 14          # zombies en même temps sur la carte
const ZOMBIE_REACH := 1.6
const WAVE_PAUSE := 9.0
const START_WEAPON := 4         # pistolet de départ
var wave := 0
var zombies_left := 0           # (affiché) zombies encore à éliminer dans la vague
var _to_spawn := 0
var _spawn_t := 0.0
var _wave_wait := 6.0
var _zatk := {}                 # (serveur) zombie -> recharge de son attaque
var _was_inter := {}            # (serveur) joueur -> touche d'action déjà maintenue
var shops := []                 # [{pos, item}] : achats aux murs (Data.ZOMBIE_SHOP)

# Domination : points A, B et C entre les deux camps
const DOM_RADIUS := 3.5
const DOM_CAP_TIME := 5.0             # secondes pour prendre seul un point neutre (le double pour un point ennemi)
const DOM_NAMES := ["A", "B", "C"]
var dom_points: Array[Vector3] = []
var dom_val := [0.0, 0.0, 0.0]        # jauge de -1 (pris par les ROUGES) à +1 (pris par les BLEUS)
var dom_owner := [-1, -1, -1]         # -1 neutre, sinon équipe
var _dom_marks := []                  # [anneau, matériau, étiquette] de chaque point
var _dom_t := 0.0
var _dom_sync_t := 0.0
var _dom_dirty := false

# Battle Royale : zone qui rétrécit par phases, armes à ramasser, pas de réapparition
# Phases : [attente avant de rétrécir (s), durée du rétrécissement (s), rayon visé, dégâts / s hors zone]
const BR_PHASES := [[25.0, 25.0, 28.0, 2.0], [20.0, 20.0, 16.0, 4.0], [15.0, 20.0, 8.0, 7.0], [10.0, 15.0, 3.0, 12.0], [9999.0, 1.0, 3.0, 20.0]]
const BR_START_RADIUS := 44.0
const BR_LOOT := 26
var zone := {"c0": Vector3.ZERO, "c1": Vector3.ZERO, "r0": BR_START_RADIUS, "r1": BR_START_RADIUS, "t0": 0.0, "dur": 1.0, "phase": 0, "wait": 25.0}
var zone_clock := 0.0           # temps écoulé (identique sur toutes les machines, recalé par l'hôte)
var loot := {}                  # id -> {"wi", "pos", "node"}
var br_alive := 0
var _zone_wall: MeshInstance3D
var _zone_mat: StandardMaterial3D
var _zone_dmg_t := 0.0
var _loot_serial := 0
var _br_started := false


func setup(p_rules: String) -> void:
	rules = p_rules
	if rules == "ctf":
		for t in 2:
			_flags.append({"team": t, "state": "home", "pos": FLAG_HOME[t], "carrier": "", "timer": 0.0,
				"node": _make_flag(t)})
	elif rules == "koth":
		_make_hill()
	elif rules == "dom":
		_make_dom()
	elif rules == "snd":
		_make_sites()
	elif rules == "zombies":
		_make_shops()
	elif rules == "br":
		_make_zone()


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
	var camps := _camp_centers()
	var mid: Vector3 = (camps[0] + camps[1]) / 2.0
	var axis: Vector3 = camps[1] - camps[0]
	axis.y = 0
	axis = axis.normalized() if axis.length() > 0.1 else Vector3.FORWARD
	var side := axis.cross(Vector3.UP).normalized()
	for s in [-1.0, 1.0]:
		sites.append(_clear_spot(mid + side * s * 15.0))
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


## Centre des points d'apparition de chaque équipe.
func _camp_centers() -> Array:
	var map = game.map
	var c := []
	for t in 2:
		var sum := Vector3.ZERO
		for p in map.team_spawns[t]:
			sum += p
		sum /= maxf(map.team_spawns[t].size(), 1)
		sum.y = 0
		c.append(sum)
	return c


## Endroit dégagé le plus proche de « want » (en spirale autour).
func _clear_spot(want: Vector3) -> Vector3:
	var map = game.map
	want.y = 0
	for ring in 12:
		for k in 8:
			var a := TAU * k / 8.0
			var p: Vector3 = want + Vector3(cos(a), 0, sin(a)) * ring * 1.5
			if map.is_clear(p) and map.is_clear(p + Vector3(1.5, 0, 0)) and map.is_clear(p - Vector3(1.5, 0, 0)):
				return p
	return want


## Points A, B et C de la Domination : sur l'axe entre les deux camps (A côté BLEUS, C côté ROUGES).
## Calculés pareil sur toutes les machines (même carte).
func _make_dom() -> void:
	var camps := _camp_centers()
	for i in 3:
		dom_points.append(_clear_spot((camps[0] as Vector3).lerp(camps[1], [0.22, 0.5, 0.78][i])))
		var ring := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = DOM_RADIUS
		cm.bottom_radius = DOM_RADIUS
		cm.height = 0.04
		ring.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 1, 1, 0.22)
		ring.material_override = mat
		ring.position = dom_points[i] + Vector3(0, 0.04, 0)
		add_child(ring)
		var label := Label3D.new()
		label.text = DOM_NAMES[i]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 88
		label.outline_size = 16
		label.position = dom_points[i] + Vector3(0, 3.5, 0)
		add_child(label)
		_dom_marks.append([ring, mat, label])


## Couleur d'un point de Domination selon son propriétaire.
func dom_color(i: int) -> Color:
	return Data.TEAM_COLORS[dom_owner[i]] if int(dom_owner[i]) >= 0 else Color(0.92, 0.92, 0.92)


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


# --- Zombies ----------------------------------------------------------------------------

const Models := preload("res://scripts/models.gd")

## Postes d'achat posés sur la carte (mêmes positions sur toutes les machines).
func _make_shops() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var pts: Array = game.map.nav_points.duplicate()
	var chosen: Array[Vector3] = []
	for tries in 400:
		if chosen.size() >= Data.ZOMBIE_SHOP.size() or pts.is_empty():
			break
		var p: Vector3 = pts[rng.randi() % pts.size()]
		var ok: bool = game.map.is_clear(p)
		for q in chosen:
			if q.distance_to(p) < 11.0:
				ok = false
		if ok:
			chosen.append(p)
	for i in chosen.size():
		var item: Dictionary = Data.ZOMBIE_SHOP[i]
		var root := Node3D.new()
		root.position = chosen[i]
		add_child(root)
		var base := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.9, 0.9, 0.9)
		base.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.16, 0.14, 0.12)
		base.material_override = mat
		base.position.y = 0.45
		root.add_child(base)
		var glow := OmniLight3D.new()
		glow.light_color = Color(0.4, 1.0, 0.5)
		glow.omni_range = 3.5
		glow.light_energy = 0.8
		glow.position.y = 1.6
		root.add_child(glow)
		var spin := Node3D.new()
		spin.position.y = 1.35
		root.add_child(spin)
		if item["kind"] == "weapon":
			var w: Dictionary = Data.WEAPONS[item["wi"]]
			var g := Models.weapon(w.model, minf(float(w.len), 0.75))
			g.rotation.y = PI / 2.0
			spin.add_child(g)
		else:
			var icon := MeshInstance3D.new()
			var im := BoxMesh.new()
			im.size = Vector3(0.35, 0.35, 0.35)
			icon.mesh = im
			var imat := StandardMaterial3D.new()
			imat.albedo_color = Color(1.0, 0.8, 0.3) if item["kind"] == "ammo" else Color(0.3, 0.7, 1.0)
			imat.emission_enabled = true
			imat.emission = imat.albedo_color
			imat.emission_energy_multiplier = 0.6
			icon.material_override = imat
			spin.add_child(icon)
		var label := Label3D.new()
		label.text = "%s\n%d pts" % [item["name"], item["price"]]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 40
		label.outline_size = 10
		label.modulate = Color(0.6, 1.0, 0.6)
		label.position.y = 2.1
		root.add_child(label)
		shops.append({"pos": chosen[i], "item": item, "spin": spin})


## Poste d'achat à portée d'un joueur (ou {}).
func shop_near(pos: Vector3) -> Dictionary:
	for s in shops:
		if _dist2d(pos, s["pos"]) < 1.9:
			return s
	return {}


func _zombie_count() -> int:
	var n := 0
	for id in game.chars:
		var c = game.chars[id]
		if c.zombie and c.alive:
			n += 1
	return n


func _update_zombies(delta: float) -> void:
	# Plus aucun survivant : fin de la partie
	var humans_alive := 0
	var humans := 0
	for id in game.chars:
		var c = game.chars[id]
		if c.team == 0:
			humans += 1
			if c.alive:
				humans_alive += 1
	if wave > 0 and humans > 0 and humans_alive == 0:
		game._end_match("Les zombies ont gagné · vague %d atteinte" % wave)
		return
	var alive_z := _zombie_count()
	# Vague terminée : pause, puis vague suivante (les morts reviennent)
	if wave == 0 or (_to_spawn == 0 and alive_z == 0):
		var was := _wave_wait
		_wave_wait -= delta
		if wave > 0 and was == WAVE_PAUSE:
			_event("Vague %d terminée ! La suivante arrive..." % wave, 0)
		if _wave_wait <= 0.0:
			_next_wave(humans)
	# Apparition progressive des zombies
	_spawn_t -= delta
	if _to_spawn > 0 and alive_z < ZOMBIE_MAX and _spawn_t <= 0.0:
		_spawn_t = maxf(0.35, 1.6 - wave * 0.1)
		_to_spawn -= 1
		_spawn_zombie()
	# Attaques au corps à corps
	for id in game.chars:
		var z = game.chars[id]
		if not z.zombie or not z.alive:
			continue
		_zatk[id] = float(_zatk.get(id, 0.0)) - delta
		if _zatk[id] > 0.0:
			continue
		for hid in game.chars:
			var h = game.chars[hid]
			if h.team == 0 and h.alive and z.position.distance_to(h.position) < ZOMBIE_REACH:
				_zatk[id] = 1.1
				game._broadcast("melee_fx", [id])
				game._deal_damage(z, {hid: float(18 + wave * 3)}, Data.KILL_ZOMBIE)
				break
	# Achats : appui sur la touche d'action près d'un poste
	for id in game.chars:
		var c = game.chars[id]
		var inter: bool = c.interacting and c.alive and c.team == 0
		if inter and not _was_inter.get(id, false):
			var s := shop_near(c.position)
			if not s.is_empty():
				_buy(c, s["item"])
		_was_inter[id] = inter
	# État de la vague affiché aux joueurs
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 0.5
		_broadcast("zombie_tick", [wave, _to_spawn + alive_z])


func _next_wave(humans: int) -> void:
	wave += 1
	_wave_wait = WAVE_PAUSE
	_to_spawn = 4 + wave * 3 + maxi(0, humans - 1) * 2
	team_pts[0] = wave
	_sync_pts()
	# Les joueurs morts reviennent avec le pistolet
	for id in game.chars:
		var c = game.chars[id]
		if c.team == 0 and not c.alive:
			game._broadcast("on_respawn", [id, game._pick_spawn(0), c.class_id, {}])
			game._broadcast("set_loadout", [id, [START_WEAPON]])
	_event("VAGUE %d : %d zombies !" % [wave, _to_spawn], 1)


func _spawn_zombie() -> void:
	game._bot_serial += 1
	var id := "Z%d" % game._bot_serial
	# Loin des joueurs, sur un point de navigation
	var best: Vector3 = game.map.random_point()
	var best_d := -1.0
	for i in 12:
		var p: Vector3 = game.map.random_point()
		var nearest := 1e9
		for hid in game.chars:
			var h = game.chars[hid]
			if h.team == 0 and h.alive:
				nearest = minf(nearest, h.position.distance_to(p))
		if nearest > best_d and nearest < 60.0:
			best_d = nearest
			best = p
			if nearest > 18.0:
				break
	var hp := 60 + wave * 18
	var fast := wave >= 4 and randf() < minf(0.15 * (wave - 3), 0.7)
	game._broadcast("spawn_char", [id, "Zombie", 1, true, 1, best, true, hp, randi() % Data.SKINS.size(), 0, {}])
	_broadcast("make_zombie", [id, hp, fast])


## (Serveur) Achat à un poste : arme (remplace l'arme en main s'il y en a déjà 2), munitions ou armure.
func _buy(c, item: Dictionary) -> void:
	var sc: Dictionary = game.scores.get(c.char_id, {})
	var money := int(sc.get("money", 0))
	var price := int(item["price"])
	var kind: String = item["kind"]
	if kind == "weapon" and c.loadout.has(int(item["wi"])):
		kind = "ammo"  # déjà en main : on recharge
		price = price / 3
	if money < price:
		_event("Pas assez de points (%d / %d)" % [money, price], 0, c.char_id)
		return
	sc["money"] = money - price
	match kind:
		"weapon":
			var inv: Array = c.loadout.duplicate()
			inv.erase(int(item["wi"]))
			if inv.size() >= 2:
				inv.erase(c.weapon)
				if inv.size() >= 2:
					inv.resize(1)
			game._broadcast("set_loadout", [c.char_id, [int(item["wi"])] + inv])
		"ammo":
			game.items._broadcast("on_pickup", [c.char_id, "ammo", c.hp, c.armor])
		"armor":
			game.items._broadcast("on_pickup", [c.char_id, "armor", c.hp, 100])
	_event("Acheté : %s (-%d pts)" % [item["name"], price], 0, c.char_id)
	game._broadcast_scores()


@rpc("authority", "call_remote", "reliable")
func make_zombie(id: String, hp: int, fast: bool) -> void:
	var c = game.chars.get(id)
	if c != null:
		c.make_zombie(hp, fast)


@rpc("authority", "call_remote", "unreliable_ordered")
func zombie_tick(w: int, left: int) -> void:
	wave = w
	zombies_left = left


func _zombies_text() -> String:
	var c = game.local_char
	var money := 0
	if c != null and game.scores.has(c.char_id):
		money = int(game.scores[c.char_id].get("money", 0))
	var t := "ZOMBIES · VAGUE %d · %d RESTANTS · %d PTS" % [wave, zombies_left, money]
	if wave == 0:
		t = "ZOMBIES · PRÉPARE-TOI · %d PTS" % money
	if c != null and c.alive:
		var s := shop_near(c.position)
		if not s.is_empty():
			var item: Dictionary = s["item"]
			var price := int(item["price"])
			var label: String = item["name"]
			if item["kind"] == "weapon" and c.loadout.has(int(item["wi"])):
				price = price / 3
				label = "munitions " + label
			t += "  ·  %s : acheter %s (%d pts)" % [Net.binding_text("interact"), label, price]
	return t


# --- Battle Royale ------------------------------------------------------------------------

func _make_zone() -> void:
	_zone_wall = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 40.0
	cm.radial_segments = 64
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	_zone_wall.mesh = cm
	_zone_mat = StandardMaterial3D.new()
	_zone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_zone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_zone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_zone_mat.albedo_color = Color(0.2, 0.55, 1.0, 0.22)
	_zone_wall.material_override = _zone_mat
	_zone_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_zone_wall.position.y = 20.0
	add_child(_zone_wall)


## Centre et rayon actuels de la zone.
func zone_now() -> Array:
	var k := clampf((zone_clock - float(zone["t0"])) / maxf(float(zone["dur"]), 0.01), 0.0, 1.0)
	return [(zone["c0"] as Vector3).lerp(zone["c1"], k), lerpf(zone["r0"], zone["r1"], k)]


func in_zone(p: Vector3) -> bool:
	var z := zone_now()
	return _dist2d(p, z[0]) <= float(z[1])


## (Serveur) Phase suivante : nouveau cercle à l'intérieur de l'actuel, qui reste dans la carte.
func _next_zone_phase() -> void:
	var ph: int = int(zone["phase"])
	if ph >= BR_PHASES.size() - 1:
		return
	var cur := zone_now()
	var r_new: float = BR_PHASES[ph][2]
	var c_old: Vector3 = cur[0]
	var c_new := c_old
	for tries in 30:
		var a := randf() * TAU
		var d := randf() * maxf(float(cur[1]) - r_new, 0.0)
		var p := c_old + Vector3(cos(a), 0, sin(a)) * d
		var lim: float = Map_HALF() - r_new * 0.6
		if absf(p.x) < lim and absf(p.z) < lim:
			c_new = p
			break
	zone = {"c0": c_old, "c1": c_new, "r0": float(cur[1]), "r1": r_new, "t0": zone_clock + float(BR_PHASES[ph][0]),
		"dur": float(BR_PHASES[ph][1]), "phase": ph + 1, "wait": float(BR_PHASES[ph][0])}
	_broadcast("zone_state", [zone, zone_clock])


func Map_HALF() -> float:
	return 30.0


func _update_br(delta: float) -> void:
	zone_clock += delta
	if not _br_started:
		# Début : pistolet pour tous, armes au sol, première zone
		var any := false
		for id in game.chars:
			any = true
		if not any:
			return
		_br_started = true
		_spawn_loot()
		zone = {"c0": Vector3.ZERO, "c1": Vector3.ZERO, "r0": BR_START_RADIUS, "r1": BR_START_RADIUS, "t0": 0.0, "dur": 1.0, "phase": 0, "wait": 0.0}
		_next_zone_phase()
		_event("BATTLE ROYALE : ramasse des armes, reste dans la zone, sois le dernier debout !", -1)
	# Phase suivante quand le rétrécissement est fini
	if zone_clock >= float(zone["t0"]) + float(zone["dur"]):
		_next_zone_phase()
		if int(zone["phase"]) < BR_PHASES.size():
			_event("La zone va se resserrer dans %d s !" % int(zone["wait"]), -1)
	# Dégâts hors de la zone, chaque seconde
	_zone_dmg_t -= delta
	if _zone_dmg_t <= 0.0:
		_zone_dmg_t = 1.0
		var dmg: float = BR_PHASES[maxi(int(zone["phase"]) - 1, 0)][3]
		for id in game.chars.keys():
			var c = game.chars.get(id)
			if c != null and c.alive and not in_zone(c.position):
				game._deal_damage(c, {id: dmg}, Data.KILL_ZONE)
	# Ramassage : touche d'action (joueurs) ou en passant dessus (bots)
	for id in game.chars:
		var c = game.chars[id]
		if not c.alive:
			continue
		var inter: bool = c.interacting
		var press: bool = inter and not _was_inter.get(id, false)
		_was_inter[id] = inter
		if not press and not c.is_bot:
			continue
		var l := loot_near(c.position, 1.6 if not c.is_bot else 1.0)
		if l != "" and (press or not c.loadout.has(int(loot[l]["wi"]))):
			_pick_loot(c, l)
	# Survivants
	var alive := []
	for id in game.chars:
		if game.chars[id].alive:
			alive.append(game.chars[id])
	if alive.size() != br_alive:
		br_alive = alive.size()
		_broadcast("br_tick", [br_alive, zone_clock])
	if alive.size() <= 1 and game.chars.size() > 1 and not game.match_over:
		if alive.size() == 1:
			_add_pts(alive[0], 1)
			game._end_match("%s remporte le Battle Royale !" % alive[0].display_name)
		else:
			game._end_match("Personne n'a survécu")


func _spawn_loot() -> void:
	var pool := []
	for wi in Data.WEAPONS.size():
		var cat: String = Data.WEAPONS[wi].cat
		if cat == "rocket" or cat == "gl":
			continue
		pool.append(wi)
	var used: Array[Vector3] = []
	for i in BR_LOOT:
		var p: Vector3 = game.map.random_point()
		var ok := true
		for q in used:
			if q.distance_to(p) < 3.0:
				ok = false
		if not ok:
			continue
		used.append(p)
		var wi: int = pool.pick_random()
		if randf() < 0.06:
			wi = 9  # lance-roquettes rare
		_loot_serial += 1
		_broadcast("loot_add", ["L%d" % _loot_serial, wi, p + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))])


func loot_near(pos: Vector3, reach: float) -> String:
	for id in loot:
		if _dist2d(pos, loot[id]["pos"]) < reach:
			return id
	return ""


## (Serveur) Ramasse une arme : elle remplace l'arme en main si on en a déjà 2 ; l'arme lâchée reste au sol.
func _pick_loot(c, id: String) -> void:
	var wi: int = loot[id]["wi"]
	var pos: Vector3 = loot[id]["pos"]
	_broadcast("loot_remove", [id])
	var inv: Array = c.loadout.duplicate()
	inv.erase(wi)
	if inv.size() >= 2:
		var dropped: int = c.weapon if inv.has(c.weapon) else inv[0]
		inv.erase(dropped)
		_loot_serial += 1
		_broadcast("loot_add", ["L%d" % _loot_serial, dropped, pos])
	game._broadcast("set_loadout", [c.char_id, [wi] + inv])
	if not c.is_bot:
		_event("Ramassé : %s" % Data.WEAPONS[wi].name, -1, c.char_id)


@rpc("authority", "call_remote", "reliable")
func loot_add(id: String, wi: int, pos: Vector3) -> void:
	var w: Dictionary = Data.WEAPONS[wi]
	var root := Node3D.new()
	root.position = pos + Vector3(0, 0.55, 0)
	var g := Models.weapon(w.model, float(w.len))
	g.rotation.y = PI / 2.0
	root.add_child(g)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.8, 0.3)
	glow.omni_range = 2.0
	glow.light_energy = 0.7
	root.add_child(glow)
	var label := Label3D.new()
	label.text = w.name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 32
	label.outline_size = 8
	label.modulate = Color(1.0, 0.85, 0.4)
	label.position.y = 0.5
	root.add_child(label)
	add_child(root)
	loot[id] = {"wi": wi, "pos": pos, "node": root}
	shops.append({"pos": pos, "spin": root, "loot": id})  # même rotation que les postes d'achat


@rpc("authority", "call_remote", "reliable")
func loot_remove(id: String) -> void:
	if not loot.has(id):
		return
	(loot[id]["node"] as Node3D).queue_free()
	for s in shops.duplicate():
		if s.get("loot", "") == id:
			shops.erase(s)
	loot.erase(id)


@rpc("authority", "call_remote", "reliable")
func zone_state(z: Dictionary, clock: float) -> void:
	zone = z
	zone_clock = clock


@rpc("authority", "call_remote", "unreliable_ordered")
func br_tick(n: int, clock: float) -> void:
	br_alive = n
	zone_clock = clock


func _process_br(delta: float) -> void:
	if not multiplayer.is_server():
		zone_clock += delta
	var z := zone_now()
	var r: float = z[1]
	_zone_wall.position = Vector3((z[0] as Vector3).x, 20.0, (z[0] as Vector3).z)
	_zone_wall.scale = Vector3(r, 1.0, r)
	var c = game.local_char
	var outside: bool = c != null and c.alive and not in_zone(c.position)
	_zone_mat.albedo_color = Color(1.0, 0.25, 0.2, 0.3) if outside else Color(0.2, 0.55, 1.0, 0.22)


func _br_text() -> String:
	var c = game.local_char
	var t := "BATTLE ROYALE · %d EN VIE" % br_alive
	var ph: int = int(zone["phase"])
	var until := float(zone["t0"]) - zone_clock
	if until > 0.0:
		t += " · zone dans %d s" % ceili(until)
	elif zone_clock < float(zone["t0"]) + float(zone["dur"]):
		t += " · LA ZONE SE RESSERRE"
	if c != null and c.alive:
		if not in_zone(c.position):
			t = "HORS DE LA ZONE ! RENTRE VITE · " + t
		var l := loot_near(c.position, 1.6)
		if l != "":
			t += "  ·  %s : ramasser %s" % [Net.binding_text("interact"), Data.WEAPONS[loot[l]["wi"]].name]
	return t


# --- Boucle -------------------------------------------------------------------------

func _process(delta: float) -> void:
	if rules == "snd":
		_process_snd(delta)
	elif rules == "br":
		_process_br(delta)
	if rules == "zombies" or rules == "br":
		for s in shops:
			(s["spin"] as Node3D).rotation.y += delta * 0.8
		var c = game.local_char
		if c != null:
			var held: bool = Input.is_action_pressed("interact") and c.alive and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			if held != _interact_sent:
				_interact_sent = held
				game.send_interact(held)
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
	for i in _dom_marks.size():
		var col := dom_color(i)
		(_dom_marks[i][1] as StandardMaterial3D).albedo_color = Color(col, 0.3 if int(dom_owner[i]) >= 0 else 0.18)
		(_dom_marks[i][2] as Label3D).modulate = col
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
	elif rules == "dom":
		_update_dom(delta)
	elif rules == "snd":
		_update_snd(delta)
	elif rules == "zombies":
		_update_zombies(delta)
	elif rules == "br":
		_update_br(delta)


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


## (Serveur) Les joueurs présents font monter la jauge de leur équipe (plus vite à plusieurs),
## un point disputé ne bouge pas, un point vide revient vers son propriétaire.
## Chaque seconde, chaque point tenu rapporte 1 point à son équipe.
func _update_dom(delta: float) -> void:
	for i in dom_points.size():
		var n := [0, 0]
		var inside := []
		for id in game.chars:
			var c = game.chars[id]
			if c.alive and c.team >= 0 and _dist2d(c.position, dom_points[i]) < DOM_RADIUS:
				n[c.team] += 1
				inside.append(c)
		var v: float = dom_val[i]
		var old := v
		var owner: int = dom_owner[i]
		var team := -1
		if n[0] > 0 and n[1] == 0:
			team = 0
		elif n[1] > 0 and n[0] == 0:
			team = 1
		if team >= 0:
			var rate := (1.0 + 0.5 * (mini(n[team], 3) - 1)) / DOM_CAP_TIME
			v = clampf(v + (1.0 if team == 0 else -1.0) * rate * delta, -1.0, 1.0)
		elif n[0] == 0 and n[1] == 0:
			var rest := 0.0 if owner < 0 else (1.0 if owner == 0 else -1.0)
			v = move_toward(v, rest, delta * 0.5 / DOM_CAP_TIME)
		if v == old:
			continue
		dom_val[i] = v
		_dom_dirty = true
		if owner == 0 and v <= 0.0 or owner == 1 and v >= 0.0:
			dom_owner[i] = -1
			_dom_sync()
			_event("%s ont neutralisé %s" % [Data.TEAM_NAMES[1 - owner], DOM_NAMES[i]], 1 - owner)
			for c in inside:
				_add_pts(c, 5)
		elif owner != 0 and v >= 1.0 or owner != 1 and v <= -1.0:
			var t := 0 if v >= 1.0 else 1
			dom_owner[i] = t
			_dom_sync()
			_event("%s ont capturé %s" % [Data.TEAM_NAMES[t], DOM_NAMES[i]], t)
			for c in inside:
				_add_pts(c, 10)
	_dom_sync_t -= delta
	if _dom_dirty and _dom_sync_t <= 0.0:
		_dom_sync()
	_dom_t += delta
	if _dom_t < 1.0:
		return
	_dom_t = 0.0
	for o in dom_owner:
		if int(o) >= 0:
			team_pts[o] += 1
	_sync_pts()
	game.check_win()


func _dom_sync() -> void:
	_dom_dirty = false
	_dom_sync_t = 0.2
	_broadcast("dom_state", [dom_val, dom_owner])


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
	elif rules == "zombies":
		if t.zombie:
			if s.team == 0 and game.scores.has(s.char_id):
				var sc: Dictionary = game.scores[s.char_id]
				sc["money"] = int(sc.get("money", 0)) + (130 if weapon == Data.KILL_KNIFE else 100)
				_add_pts(s, 1)
			_zatk.erase(t.char_id)
			var zid: String = t.char_id
			get_tree().create_timer(2.5).timeout.connect(func() -> void:
				if game.chars.has(zid):
					game._broadcast("despawn_char", [zid]))


## (Serveur) Touche d'un zombie : quelques points à chaque balle.
func on_hit(s, t) -> void:
	if rules == "zombies" and t.zombie and s.team == 0 and game.scores.has(s.char_id):
		var sc: Dictionary = game.scores[s.char_id]
		sc["money"] = int(sc.get("money", 0)) + 10


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
	return not rules in ["elim", "snd", "zombies", "br"]


## (Serveur) Donne à un personnage l'arme de son niveau en course aux armes.
func gungame_weapon(c) -> void:
	if (rules == "zombies" and c.team == 0) or rules == "br":
		game._broadcast("set_loadout", [c.char_id, [START_WEAPON]])  # tout le monde commence au pistolet
		return
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
	elif rules == "dom" and c.team >= 0 and not dom_points.is_empty():
		var spot := func(i: int) -> Vector3:
			var a := randf() * TAU
			return dom_points[i] + Vector3(cos(a), 0, sin(a)) * randf_range(0.5, DOM_RADIUS - 1.0)
		# Sur un point pas encore à nous : y rester jusqu'à la capture
		for i in dom_points.size():
			if int(dom_owner[i]) != c.team and _dist2d(c.position, dom_points[i]) < DOM_RADIUS:
				return spot.call(i)
		var targets := []
		for i in dom_points.size():
			if int(dom_owner[i]) != c.team:
				targets.append(i)
		if targets.is_empty() or randf() < 0.2:
			return spot.call(randi() % dom_points.size())  # défendre
		# Le plus proche le plus souvent, parfois un autre pour se répartir
		targets.sort_custom(func(a: int, b: int) -> bool: return _dist2d(c.position, dom_points[a]) < _dist2d(c.position, dom_points[b]))
		return spot.call(targets[0] if randf() < 0.65 else targets[randi() % targets.size()])
	elif rules == "koth" and randf() < 0.6:
		var a := randf() * TAU
		return HILL_POS + Vector3(cos(a), 0, sin(a)) * randf_range(3.5, HILL_RADIUS - 1.0)
	elif rules == "br":
		var z := zone_now()
		var center: Vector3 = zone["c1"]
		if not in_zone(c.position) or _dist2d(c.position, center) > float(zone["r1"]):
			return center + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))  # rentrer dans la (future) zone
		if c.loadout.size() < 2 or randf() < 0.3:
			var best := ""
			var best_d := 25.0
			for id in loot:
				var d := _dist2d(c.position, loot[id]["pos"])
				if d < best_d and not c.loadout.has(int(loot[id]["wi"])) and _dist2d(loot[id]["pos"], z[0]) < float(z[1]):
					best_d = d
					best = id
			if best != "":
				return loot[best]["pos"]
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
	if rules == "dom":
		dom_state.rpc_id(peer, dom_val, dom_owner)
	if rules == "snd":
		bomb_state.rpc_id(peer, bomb["state"], bomb["pos"], bomb["carrier"], bomb["site"], float(bomb["timer"]))
	if rules == "zombies":
		for id in game.chars:
			var z = game.chars[id]
			if z.zombie:
				make_zombie.rpc_id(peer, id, z.hp, z.zombie_fast)
	if rules == "br":
		zone_state.rpc_id(peer, zone, zone_clock)
		for id in loot:
			loot_add.rpc_id(peer, id, loot[id]["wi"], loot[id]["pos"])
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
func dom_state(vals: Array, owners: Array) -> void:
	dom_val = vals
	dom_owner = owners


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
		"dom":
			return _dom_text()
		"gungame":
			if c != null and game.scores.has(c.char_id):
				var lvl := int(game.scores[c.char_id].get("pts", 0))
				return "COURSE AUX ARMES · NIVEAU %d / %d" % [mini(lvl + 1, limit()), limit()]
			return "COURSE AUX ARMES"
		"elim":
			return "ÉLIMINATION · MANCHE %d · PREMIER À %d" % [round_num, limit()]
		"snd":
			return _snd_text()
		"zombies":
			return _zombies_text()
		"br":
			return _br_text()
	return ""


func _dom_text() -> String:
	var c = game.local_char
	if c != null and c.alive and c.team >= 0:
		for i in dom_points.size():
			if _dist2d(c.position, dom_points[i]) >= DOM_RADIUS:
				continue
			var enemies := false
			for id in game.chars:
				var o = game.chars[id]
				if o.alive and o.team == 1 - c.team and _dist2d(o.position, dom_points[i]) < DOM_RADIUS:
					enemies = true
			if int(dom_owner[i]) == c.team:
				return "POINT %s TENU%s" % [DOM_NAMES[i], " · ENNEMIS SUR LE POINT !" if enemies else ""]
			var v: float = float(dom_val[i]) * (1.0 if c.team == 0 else -1.0)  # vers nous : positif
			var what := "CAPTURE DE %s" % DOM_NAMES[i] if v >= 0.0 else "NEUTRALISATION DE %s" % DOM_NAMES[i]
			var k := v if v >= 0.0 else 1.0 + v
			var n := clampi(int(k * 20.0), 0, 20)
			return "%s%s  %s%s" % [what, " (DISPUTÉ)" if enemies else "", "█".repeat(n), "░".repeat(20 - n)]
	var parts := []
	for i in dom_points.size():
		var o := int(dom_owner[i])
		parts.append("%s : %s" % [DOM_NAMES[i], Data.TEAM_NAMES[o] if o >= 0 else "—"])
	return "DOMINATION · %s · PREMIER À %d" % ["   ".join(parts), limit()]


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
