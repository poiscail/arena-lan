extends Node3D
## Une partie : carte, personnages, règles (décidées par le serveur) et réplication réseau.
##
## Réseau : chaque joueur simule son propre personnage et envoie sa position au serveur.
## Le serveur fait tourner les bots, valide les tirs, gère vie / morts / scores,
## puis renvoie à tout le monde un instantané des positions 30 fois par seconde.

const CharacterScript := preload("res://scripts/character.gd")
const MapScript := preload("res://scripts/map.gd")
const HudScript := preload("res://scripts/hud.gd")
const Data := preload("res://scripts/data.gd")
const ItemsScript := preload("res://scripts/items.gd")
const SfxScript := preload("res://scripts/sfx.gd")
const ModesScript := preload("res://scripts/modes.gd")
const SpectatorScript := preload("res://scripts/spectator.gd")

const NET_RATE := 1.0 / 30.0
const BOT_NAMES := ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel",
		"India", "Juliett", "Kilo", "Lima", "Mike", "November", "Oscar", "Papa"]

var settings: Dictionary
var map
var hud
var chars := {}        # id ("P<peer>" ou "B<n>") -> personnage
var scores := {}       # id -> {"name", "team", "kills", "deaths", "bot"}
var ready_peers := {}  # (serveur) clients dont la partie est chargée
var local_char = null
var time_left := 600.0
var match_over := false
var end_text := ""

var _chars_root: Node3D
var _net_t := 0.0
var _time_sync_t := 0.0
var _bot_serial := 0
var _tracer_mat: StandardMaterial3D
var _impact_mat: StandardMaterial3D
var _sounds := []
var _no_exclude: Array[RID] = []
var items
var sfx
var modes
var spectator
var rules := "dm"
var streaks := {}  # (serveur) id -> éliminations sans mourir



func _ready() -> void:
	settings = Net.settings.duplicate()
	time_left = float(settings.time_limit) * 60.0
	map = MapScript.new()
	map.build(self, multiplayer.is_server(), int(settings.get("map", 0)))
	_chars_root = Node3D.new()
	_chars_root.name = "Characters"
	add_child(_chars_root)
	_make_effects()
	sfx = SfxScript.new()
	sfx.name = "Sfx"
	add_child(sfx)
	items = ItemsScript.new()
	items.name = "Items"
	items.game = self
	add_child(items)
	items.setup(map)
	rules = String(settings.get("rules", "dm"))
	if not Data.RULES.has(rules) or (Data.RULES[rules]["teams"] and settings.mode != "team"):
		rules = "dm"
	modes = ModesScript.new()
	modes.name = "Modes"
	modes.game = self
	add_child(modes)
	modes.setup(rules)
	spectator = SpectatorScript.new()
	spectator.name = "Spectator"
	spectator.game = self
	add_child(spectator)
	hud = HudScript.new()
	hud.game = self
	add_child(hud)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if multiplayer.is_server():
		_server_add_human(1)
		_rebalance_bots()
	else:
		client_ready.rpc_id(1)


func _process(delta: float) -> void:
	if not match_over:
		time_left = maxf(0.0, time_left - delta)


func _physics_process(delta: float) -> void:
	if multiplayer.is_server() and not match_over:
		_time_sync_t += delta
		if _time_sync_t >= 1.0:
			_time_sync_t = 0.0
			_broadcast("sync_time", [time_left])
		if time_left <= 0.0:
			_end_match()

	_net_t += delta
	if _net_t < NET_RATE:
		return
	_net_t = 0.0
	if multiplayer.is_server():
		if ready_peers.is_empty():
			return
		var data := []
		for id in chars:
			var c = chars[id]
			data.append([id, c.position, c.rotation.y, c.head.rotation.x, c.sliding, c.lean])
		for p in ready_peers:
			snapshot.rpc_id(p, data)
	elif local_char != null and local_char.alive:
		client_state.rpc_id(1, local_char.position, local_char.rotation.y, local_char.head.rotation.x, local_char.sliding, local_char.lean)


func _unhandled_input(event: InputEvent) -> void:
	if hud.chat_open:
		return
	if event.is_action_pressed("pause"):
		hud.toggle_pause()
	elif event.is_action_pressed("chat") and not hud.paused:
		get_viewport().set_input_as_handled()
		hud.open_chat()
	elif event.is_action_pressed("ping") and not hud.paused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		send_ping()
	elif event is InputEventMouseButton and event.pressed and not hud.paused \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Utilitaires publics --------------------------------------------------------

func is_enemy(a, b) -> bool:
	if a == b:
		return false
	if settings.mode == "team":
		return a.team != b.team
	return true


func line_clear(from: Vector3, to: Vector3) -> bool:
	return _ray(from, to, _no_exclude, 1).is_empty() and not items.smoke_blocks(from, to)


## Clé de classement des joueurs : éliminations en match à mort, points sinon.
func score_key() -> String:
	return "kills" if rules == "dm" else "pts"


func team_scores() -> Array:
	if rules == "gungame":
		var best := [0, 0]
		for id in scores:
			var team: int = scores[id]["team"]
			if team >= 0:
				best[team] = maxi(best[team], int(scores[id].get("pts", 0)))
		return best
	if rules != "dm":
		return modes.team_pts
	var t := [0, 0]
	for id in scores:
		var team: int = scores[id]["team"]
		if team >= 0:
			t[team] += int(scores[id]["kills"])
	return t


func goal_text() -> String:
	if rules == "dm":
		return "PREMIER À %d ÉLIMINATIONS" % int(settings.score_limit)
	return modes.objective_text()


func _new_score(pname: String, team: int, is_bot: bool) -> Dictionary:
	return {"name": pname, "team": team, "kills": 0, "deaths": 0, "bot": is_bot, "pts": 0,
		"shots": 0, "hits": 0, "heads": 0, "dmg": 0, "streak": 0, "best_streak": 0, "wkills": {}}


func score_summary() -> String:
	var limit: int = settings.score_limit
	if settings.mode == "team":
		var t := team_scores()
		return "[color=%s]%s  %d[/color]      [color=#999999]objectif %d[/color]      [color=%s]%d  %s[/color]" % [
			Data.TEAM_HEX[0], Data.TEAM_NAMES[0], t[0], limit, Data.TEAM_HEX[1], t[1], Data.TEAM_NAMES[1]]
	var mine := 0
	if local_char != null and scores.has(local_char.char_id):
		mine = scores[local_char.char_id]["kills"]
	var leader := _ffa_leader()
	var lead := ""
	if not leader.is_empty():
		lead = "Meneur : %s (%d)" % [Data.esc(leader["name"]), leader["kills"]]
	return "Toi : %d      [color=#999999]objectif %d[/color]      %s" % [mine, limit, lead]


# --- Tirs -------------------------------------------------------------------------

## Appelé par le personnage local quand le joueur tire.
func local_fire(c, weapon: int, origin: Vector3, dirs: PackedVector3Array) -> void:
	var w: Dictionary = c.wstats(weapon)
	var silenced: bool = c.custom(weapon)["att"].has("silencer")
	var muzzle: Vector3 = c.muzzle_position()
	var ex: Array[RID] = [c.get_rid()]
	for d in dirs:
		var to: Vector3 = origin + d * float(w.range)
		var hit := _ray(origin, to, ex, 3)
		_spawn_tracer(muzzle, hit.position if not hit.is_empty() else to)
		if float(w.splash) > 0.0 and not hit.is_empty():
			spawn_explosion(hit.position + hit.normal * 0.3, float(w.splash))
		elif not hit.is_empty():
			var on_char: bool = hit.collider is CharacterScript
			sfx.bullet_impact(hit.position, hit.normal, on_char)
			if not on_char and randf() < 0.5:
				sfx.play_random("impactGeneric_light", 3, hit.position, -14.0)
	play_shot_sound(weapon, muzzle, true, silenced)
	if not silenced:
		sfx.muzzle_flash(muzzle, int(w.pellets) > 1 or float(w.splash) > 0.0, true)
	if float(w.splash) == 0.0:
		var b: Basis = c.camera.global_transform.basis
		sfx.eject_shell(muzzle - b.z * -0.25 + b.x * 0.05, b.x, int(w.pellets) > 1)
	if multiplayer.is_server():
		_server_shoot(c.char_id, weapon, origin, dirs)
	else:
		req_shoot.rpc_id(1, weapon, origin, dirs)


## Touche d'action du joueur local (poser / désamorcer la bombe), envoyée à l'hôte.
func send_interact(held: bool) -> void:
	if multiplayer.is_server():
		_set_interact(_pid(1), held)
	else:
		req_interact.rpc_id(1, held)


@rpc("any_peer", "call_remote", "reliable")
func req_interact(held: bool) -> void:
	if multiplayer.is_server():
		_set_interact(_pid(multiplayer.get_remote_sender_id()), held)


func _set_interact(id: String, held: bool) -> void:
	var c = chars.get(id)
	if c != null:
		c.interacting = held


## Changement de classe demandé par le joueur local : appliqué à sa prochaine réapparition.
func request_class(cls: int) -> void:
	if multiplayer.is_server():
		_set_next_class(_pid(1), cls)
	else:
		req_class.rpc_id(1, cls)


@rpc("any_peer", "call_remote", "reliable")
func req_class(cls: int) -> void:
	if multiplayer.is_server():
		_set_next_class(_pid(multiplayer.get_remote_sender_id()), cls)


## Armes de classe / skins / accessoires modifiés en jeu par le joueur local : envoyés à l'hôte,
## appliqués à sa prochaine réapparition.
func send_armory(arm: Dictionary) -> void:
	if multiplayer.is_server():
		_set_next_armory(_pid(1), arm)
	else:
		req_armory.rpc_id(1, arm)


@rpc("any_peer", "call_remote", "reliable")
func req_armory(arm: Dictionary) -> void:
	if multiplayer.is_server():
		_set_next_armory(_pid(multiplayer.get_remote_sender_id()), arm)


func _set_next_armory(id: String, arm: Dictionary) -> void:
	if arm.size() > 200:
		return
	var c = chars.get(id)
	if c != null:
		c.next_armory = arm
	var peer := int(id.substr(1))
	if Net.players.has(peer):
		Net.players[peer]["armory"] = arm


func _set_next_class(id: String, cls: int) -> void:
	var c = chars.get(id)
	if c != null:
		c.next_class = clampi(cls, 0, Data.CLASSES.size() - 1)
	var peer := int(id.substr(1))
	if Net.players.has(peer):
		Net.players[peer]["class"] = clampi(cls, 0, Data.CLASSES.size() - 1)


## Appelé (sur le serveur) par le cerveau d'un bot.
func bot_fire(c, dir: Vector3) -> void:
	_server_shoot(c.char_id, c.bot_weapon(), c.eye_position(), PackedVector3Array([dir]))


func _server_shoot(shooter_id: String, weapon: int, origin: Vector3, dirs: PackedVector3Array) -> void:
	var s = chars.get(shooter_id)
	if s == null or not s.alive or match_over:
		return
	if not s.loadout.has(weapon):
		return  # arme qui n'appartient pas à la classe du tireur
	var w: Dictionary = s.wstats(weapon)
	var splash := float(w.splash)
	if origin.distance_to(s.eye_position()) > 3.0:
		origin = s.eye_position()
	var ex: Array[RID] = [s.get_rid()]
	var ends := PackedVector3Array()
	var damage := {}
	var head_hit := false
	for i in mini(dirs.size(), int(w.pellets)):
		var d := dirs[i].normalized()
		var to := origin + d * float(w.range)
		var hit := _ray(origin, to, ex, 3)
		if hit.is_empty():
			ends.append(to)
			continue
		ends.append(hit.position)
		var t = hit.collider
		if splash > 0.0:
			_explosion_damage(s, hit.position + hit.normal * 0.3, w, damage)
			items.server_explosion_barrels(hit.position, splash, s)
			continue
		items.server_hit_barrel(t, float(w.damage), s)
		if t is CharacterScript and t.alive and is_enemy(s, t):
			var head: bool = hit.position.y > t.position.y + (0.8 if t.sliding else 1.45)
			var dmg := float(w.damage) * (float(w.head) if head else 1.0)
			if s.damage_t > 0.0:
				dmg *= 2.0
			damage[t.char_id] = damage.get(t.char_id, 0.0) + dmg
			head_hit = head_hit or head
	_broadcast("shot_fx", [shooter_id, weapon, ends])
	if scores.has(shooter_id):
		var st: Dictionary = scores[shooter_id]
		st["shots"] = int(st.get("shots", 0)) + 1
		if not damage.is_empty():
			st["hits"] = int(st.get("hits", 0)) + 1
		if head_hit:
			st["heads"] = int(st.get("heads", 0)) + 1
	if damage.is_empty():
		return
	_deal_damage(s, damage, weapon, head_hit)


## (Serveur) Applique des dégâts { id: points } et prévient le tireur (marqueur de touche).
func _deal_damage(s, damage: Dictionary, weapon: int, head_hit := false) -> void:
	if damage.is_empty():
		return
	var killed := false
	var hits := []  # [position au-dessus de la cible, dégâts, éliminé] pour l'affichage chez le tireur
	for tid in damage:
		if not chars.has(tid):
			continue
		var t = chars[tid]
		var dmg := int(round(damage[tid]))
		var was_alive: bool = t.alive
		var k := _apply_damage(t, s, dmg, weapon)
		if was_alive:
			hits.append([t.global_position + Vector3(0, 2.0, 0), dmg, k])
		killed = killed or k
	if s != null and not s.is_bot:
		if s.owner_peer == multiplayer.get_unique_id():
			hit_confirm(head_hit, killed, hits)
		elif ready_peers.has(s.owner_peer):
			hit_confirm.rpc_id(s.owner_peer, head_hit, killed, hits)


## Explosion (lance-grenades, lance-roquettes) : dégâts qui diminuent avec la distance,
## bloqués par les murs. Le tireur ne se blesse pas lui-même.
func _explosion_damage(s, center: Vector3, w: Dictionary, damage: Dictionary) -> void:
	var radius := float(w.splash)
	var mult := 2.0 if s != null and s.damage_t > 0.0 else 1.0
	for id in chars:
		var t = chars[id]
		if not t.alive or not is_enemy(s, t):
			continue
		var body: Vector3 = t.global_position + Vector3(0, 0.9, 0)
		var dist := center.distance_to(body)
		if dist > radius + 0.4:
			continue
		if not _ray(center, body, [] as Array[RID], 1).is_empty():
			continue
		var k := clampf(1.0 - maxf(dist - 0.4, 0.0) / radius, 0.25, 1.0)
		damage[t.char_id] = damage.get(t.char_id, 0.0) + float(w.damage) * k * mult


## (Serveur) Explosion de grenade, de baril ou de frappe aérienne, attribuée au tireur « s ».
func server_explosion(s, at: Vector3, w: Dictionary, kill_id: int) -> void:
	if match_over:
		return
	if s == null:
		return  # tireur parti
	var damage := {}
	_explosion_damage(s, at, w, damage)
	_deal_damage(s, damage, kill_id)
	items.server_explosion_barrels(at, float(w.splash), s)


## (Serveur) Coup de couteau : touche l'ennemi le plus proche devant soi.
## Dans le dos, il élimine d'un coup.
func _server_melee(s) -> void:
	if s == null or not s.alive or match_over:
		return
	var fwd: Vector3 = -s.global_transform.basis.z
	var best = null
	var bayonet: bool = s.loadout.size() > 0 and s.custom(s.loadout[0])["att"].has("bayonet")
	var best_d := Data.KNIFE_RANGE + (0.6 if bayonet else 0.0)
	for id in chars:
		var t = chars[id]
		if not t.alive or not is_enemy(s, t):
			continue
		var to: Vector3 = t.position - s.position
		to.y = 0.0
		var d := to.length()
		if d < best_d and (d < 0.6 or fwd.dot(to / d) > 0.5):
			best = t
			best_d = d
	_broadcast("melee_fx", [s.char_id])
	if best == null:
		return
	var behind: bool = (-best.global_transform.basis.z).dot(fwd) > 0.5
	_deal_damage(s, {best.char_id: 200.0 if behind else float(Data.KNIFE_DAMAGE) * (1.5 if bayonet else 1.0)}, Data.KILL_KNIFE, behind)


func local_melee(c) -> void:
	if multiplayer.is_server():
		_server_melee(c)
	else:
		req_melee.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func req_melee() -> void:
	if multiplayer.is_server():
		_server_melee(chars.get(_pid(multiplayer.get_remote_sender_id())))


@rpc("authority", "call_remote", "reliable")
func melee_fx(id: String) -> void:
	var c = chars.get(id)
	if c != null:
		sfx.play("knifeSlice", null if c.is_local else c.global_position + Vector3(0, 1.2, 0), -4.0)
	if c != null and not c.is_local:
		c.play_shoot()


func _apply_damage(t, s, dmg: int, weapon: int) -> bool:
	if not t.alive:
		return false
	# L'armure absorbe la moitié des dégâts tant qu'il en reste
	var absorbed := mini(t.armor, dmg / 2)
	t.armor -= absorbed
	dmg -= absorbed
	var dealt := mini(dmg, t.hp)
	t.hp = maxi(0, t.hp - dmg)
	if scores.has(s.char_id):
		scores[s.char_id]["dmg"] = int(scores[s.char_id].get("dmg", 0)) + dealt + absorbed
	_broadcast("on_health", [t.char_id, t.hp, t.armor, true])
	modes.on_hit(s, t)
	if t.bot != null:
		t.bot.alert(s)
	if t.hp > 0:
		return false
	t.alive = false  # (évite une double élimination dans la même salve ; set_dead suit par RPC)
	if scores.has(t.char_id):
		scores[t.char_id]["deaths"] += 1
	if scores.has(s.char_id):
		var sc: Dictionary = scores[s.char_id]
		sc["kills"] += 1
		var wk: Dictionary = sc.get("wkills", {})
		wk[str(weapon)] = int(wk.get(str(weapon), 0)) + 1
		sc["wkills"] = wk
	# Séries d'éliminations sans mourir
	streaks[t.char_id] = 0
	streaks[s.char_id] = int(streaks.get(s.char_id, 0)) + 1
	var n: int = streaks[s.char_id]
	if scores.has(s.char_id):
		scores[s.char_id]["best_streak"] = maxi(int(scores[s.char_id].get("best_streak", 0)), n)
	print("[kill] %s -> %s (%s)" % [s.display_name, t.display_name, Data.kill_name(weapon)])
	_broadcast("on_died", [t.char_id, s.char_id, weapon])
	modes.on_kill(s, t, weapon)
	_broadcast_scores()
	check_win()
	if not match_over:
		if modes.allows_respawn():
			get_tree().create_timer(Data.RESPAWN_TIME).timeout.connect(_respawn.bind(t.char_id))
		if Data.STREAKS.has(n):
			print("[série] %s : %d (%s)" % [s.display_name, n, Data.STREAKS[n]])
			_broadcast("on_streak", [s.char_id, n])
			if n == 7:
				_airstrike(s)
	return true


## (Serveur) Frappe aérienne : une explosion sur chaque ennemi vivant, 2 secondes après l'alerte.
func _airstrike(s) -> void:
	var targets := []
	for id in chars:
		var t = chars[id]
		if t.alive and is_enemy(s, t):
			targets.append(t.position)
	for p in targets:
		_broadcast("airstrike_mark", [p])
	await get_tree().create_timer(2.0).timeout
	if not is_instance_valid(s):
		return
	for p in targets:
		items._broadcast("explosion_fx", [p + Vector3(0, 0.5, 0), float(Data.AIRSTRIKE.splash)])
		server_explosion(s, p + Vector3(0, 0.5, 0), Data.AIRSTRIKE, Data.KILL_AIRSTRIKE)


@rpc("authority", "call_remote", "reliable")
func on_streak(id: String, n: int) -> void:
	var c = chars.get(id)
	if c == null:
		return
	if n == 3:
		c.speed_t = Data.ADRENALINE_TIME
	if c.is_local:
		hud.announce("SÉRIE DE %d : %s" % [n, Data.STREAKS[n]])
		sfx.play("maximize_006", null, -2.0, 0.0)
		if n == 5:
			hud.radar_t = Data.RADAR_TIME
	else:
		hud.add_kill("[color=#ffcc55]%s : série de %d (%s)[/color]" % [Data.esc(c.display_name), n, Data.STREAKS[n].to_lower()])


@rpc("authority", "call_remote", "reliable")
func airstrike_mark(p: Vector3) -> void:
	# Fumée rouge au sol : la frappe arrive
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 4.0
	cm.bottom_radius = 4.0
	cm.height = 0.05
	m.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 0.15, 0.1, 0.35)
	m.material_override = mat
	add_child(m)
	m.global_position = p + Vector3(0, 0.06, 0)
	get_tree().create_timer(2.0).timeout.connect(m.queue_free)


func _ray(from: Vector3, to: Vector3, exclude: Array[RID], mask: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	return get_world_3d().direct_space_state.intersect_ray(q)


# --- Gestion serveur ------------------------------------------------------------

func _pid(peer: int) -> String:
	return "P%d" % peer


func _broadcast(method: String, args: Array) -> void:
	for p in ready_peers:
		callv("rpc_id", [p, method] + args)
	callv(method, args)


func _broadcast_scores() -> void:
	_broadcast("sync_scores", [scores, time_left])


func _server_add_human(peer: int) -> void:
	if not Net.players.has(peer):
		return
	var info: Dictionary = Net.players[peer]
	var team: int = info["team"] if settings.mode == "team" else -1
	if rules == "zombies":
		team = 0  # tous les joueurs ensemble contre les zombies
	var id := _pid(peer)
	if not scores.has(id):
		scores[id] = _new_score(info["name"], team, false)
	_broadcast("spawn_char", [id, info["name"], team, false, peer, _pick_spawn(team), true, 100, int(info.get("skin", 0)), int(info.get("class", 0)), info.get("armory", {})])
	if chars.has(id):
		modes.gungame_weapon(chars[id])
	_broadcast_scores()


func _server_add_bot(team: int) -> String:
	_bot_serial += 1
	var id := "B%d" % _bot_serial
	var bname := "%s (bot)" % BOT_NAMES[(_bot_serial - 1) % BOT_NAMES.size()]
	scores[id] = _new_score(bname, team, true)
	_broadcast("spawn_char", [id, bname, team, true, 1, _pick_spawn(team), true, 100, randi() % Data.SKINS.size(), randi() % Data.CLASSES.size(), _bot_armory()])
	modes.gungame_weapon(chars[id])
	return id


## Ajoute ou retire des bots pour que chaque équipe (ou la mêlée) soit complète.
func _rebalance_bots() -> void:
	if not multiplayer.is_server() or match_over:
		return
	var teams := [0, 1] if settings.mode == "team" else [-1]
	if rules == "zombies":
		teams = [0]  # des bots alliés complètent l'équipe ; les zombies sont gérés par le mode
	for t in teams:
		var humans := 0
		for pid in Net.players:
			if t == -1 or Net.players[pid]["team"] == t or rules == "zombies":
				humans += 1
		var want := 0
		if settings.bots:
			want = maxi(0, int(settings.slots) - humans)
		var bots := []
		for id in chars:
			if chars[id].is_bot and chars[id].team == t:
				bots.append(id)
		while bots.size() < want:
			bots.append(_server_add_bot(t))
		while bots.size() > want:
			var id = bots.pop_back()
			_broadcast("despawn_char", [id])
			scores.erase(id)
	_broadcast_scores()


func _pick_spawn(team: int) -> Vector3:
	var candidates: Array = map.team_spawns[team] if team >= 0 else map.ffa_spawns
	var best: Vector3 = candidates[0]
	var best_score := -1.0
	for p in candidates:
		var nearest := 80.0
		for id in chars:
			var c = chars[id]
			if c.alive and (team == -1 or c.team != team):
				nearest = minf(nearest, c.position.distance_to(p))
		var score := nearest + randf() * 8.0
		if score > best_score:
			best_score = score
			best = p
	return best


func _respawn(id: String) -> void:
	if match_over or not chars.has(id):
		return
	var c = chars[id]
	var cls: int = c.next_class if c.next_class >= 0 else c.class_id
	if rules == "gungame":
		cls = -1
	c.next_class = -1
	var arm: Dictionary = c.next_armory
	c.next_armory = {}
	if rules == "gungame" and not arm.is_empty():
		c.armory = arm  # course aux armes : seulement skins / accessoires
	_broadcast("on_respawn", [id, _pick_spawn(c.team), cls, arm])


func check_win() -> void:
	if match_over:
		return
	var limit: int = modes.limit()
	if settings.mode == "team":
		var t := team_scores()
		if t[0] >= limit or t[1] >= limit:
			_end_match()
	else:
		var leader := _ffa_leader()
		if not leader.is_empty() and int(leader[score_key()]) >= limit:
			_end_match()


func _ffa_leader() -> Dictionary:
	var key := score_key()
	var best := {}
	for id in scores:
		if best.is_empty() or int(scores[id][key]) > int(best[key]):
			best = scores[id]
	return best


func _end_match(text_override := "") -> void:
	if match_over:
		return
	var text := ""
	var unit: String = Data.RULES[rules]["unit"]
	if settings.mode == "team":
		var t := team_scores()
		if t[0] > t[1]:
			text = "Victoire des BLEUS  %d - %d" % [t[0], t[1]]
		elif t[1] > t[0]:
			text = "Victoire des ROUGES  %d - %d" % [t[1], t[0]]
		else:
			text = "Égalité  %d - %d" % [t[0], t[1]]
	else:
		var leader := _ffa_leader()
		if leader.is_empty():
			text = "Fin de la partie"
		else:
			text = "%s gagne avec %d %s" % [leader["name"], int(leader[score_key()]), unit]
	if text_override != "":
		text = text_override
	print("[match] " + text)
	_broadcast_scores()
	_broadcast("on_match_end", [text])
	get_tree().create_timer(10.0).timeout.connect(_return_to_lobby)


func _return_to_lobby() -> void:
	Net.end_match_to_lobby()


func _on_peer_disconnected(peer: int) -> void:
	if not multiplayer.is_server():
		return
	ready_peers.erase(peer)
	var id := _pid(peer)
	if chars.has(id):
		_broadcast("despawn_char", [id])
	scores.erase(id)
	_rebalance_bots()


# --- RPC client -> serveur ------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func client_ready() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	ready_peers[peer] = true
	for id in chars:
		var c = chars[id]
		spawn_char.rpc_id(peer, id, c.display_name, c.team, c.is_bot, c.owner_peer, c.position, c.alive, c.hp, c.skin, c.class_id, c.armory)
	sync_scores.rpc_id(peer, scores, time_left)
	items.sync_to(peer)
	modes.sync_to(peer)
	if match_over:
		on_match_end.rpc_id(peer, end_text)
	if not chars.has(_pid(peer)):
		_server_add_human(peer)
	_rebalance_bots()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func client_state(pos: Vector3, yaw: float, pitch: float, slide: bool, lean: float) -> void:
	var c = chars.get(_pid(multiplayer.get_remote_sender_id()))
	if c != null and c.alive:
		c.net_target(pos, yaw, pitch)
		c.set_sliding(slide)
		c.set_lean(lean)


@rpc("any_peer", "call_remote", "reliable")
func req_shoot(weapon: int, origin: Vector3, dirs: PackedVector3Array) -> void:
	if multiplayer.is_server():
		_server_shoot(_pid(multiplayer.get_remote_sender_id()), weapon, origin, dirs)


# --- RPC serveur -> clients -----------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func spawn_char(id: String, dname: String, team: int, is_bot: bool, owner_peer: int, pos: Vector3, alive: bool, hp: int, skin: int, cls: int, arm: Dictionary) -> void:
	if chars.has(id):
		return
	var c = CharacterScript.new()
	c.name = id
	c.char_id = id
	c.skin = skin
	c.class_id = cls
	c.armory = arm
	c.display_name = dname
	c.team = team
	c.is_bot = is_bot
	c.owner_peer = owner_peer
	c.is_local = not is_bot and owner_peer == multiplayer.get_unique_id()
	c.game = self
	c.position = pos
	c.hp = hp
	_chars_root.add_child(c)
	chars[id] = c
	if not alive:
		c.set_dead(true)
	if c.is_local:
		local_char = c
	hud.refresh_scores()


@rpc("authority", "call_remote", "reliable")
func despawn_char(id: String) -> void:
	var c = chars.get(id)
	if c == null:
		return
	chars.erase(id)
	if c == local_char:
		local_char = null
	c.queue_free()


@rpc("authority", "call_remote", "unreliable_ordered")
func snapshot(data: Array) -> void:
	for e in data:
		var c = chars.get(e[0])
		if c != null and not c.is_local:
			c.net_target(e[1], e[2], e[3])
			c.set_sliding(e[4])
			c.set_lean(e[5])


@rpc("authority", "call_remote", "reliable")
func on_health(id: String, hp: int, armor: int, hurt: bool) -> void:
	var c = chars.get(id)
	if c == null:
		return
	c.hp = hp
	c.armor = armor
	if c == local_char:
		if hurt:
			hud.damage_flash()
		else:
			hud.heal_flash()


@rpc("authority", "call_remote", "reliable")
func on_died(victim_id: String, killer_id: String, weapon: int) -> void:
	var v = chars.get(victim_id)
	if v == null:
		return
	var k = chars.get(killer_id)
	v.set_dead(true)
	var kname := "?"
	var khex := "#ffffff"
	if k != null:
		kname = k.display_name
		khex = "#" + k.get_color().lightened(0.25).to_html(false)
	var vhex: String = "#" + v.get_color().lightened(0.25).to_html(false)
	hud.add_kill("[color=%s]%s[/color][color=#bbbbbb]   > %s >   [/color][color=%s]%s[/color]" % [
		khex, Data.esc(kname), Data.esc(Data.kill_name(weapon)), vhex, Data.esc(v.display_name)])
	# Défis d'armes : chaque élimination avec une arme rapproche du skin suivant de cette arme
	if k != null and k == local_char and v != local_char and weapon >= 0 and weapon < Data.WEAPONS.size():
		var unlocked: int = Net.add_weapon_kill(weapon)
		if unlocked >= 0:
			var cm: Dictionary = Data.CAMOS[unlocked]
			hud.announce("SKIN DÉBLOQUÉ : %s (%s) · %s" % [String(cm["name"]).to_upper(), Data.RARITIES[int(cm.get("r", 0))]["name"], Data.WEAPONS[weapon].name])
			sfx.play("select_001", null, -2.0, 0.0)
	if v == local_char:
		hud.show_death(kname)
		get_tree().create_timer(1.3).timeout.connect(func() -> void:
			if local_char != null and not local_char.alive and not match_over:
				spectator.start())


@rpc("authority", "call_remote", "reliable")
func on_respawn(id: String, pos: Vector3, cls: int, arm: Dictionary = {}) -> void:
	var c = chars.get(id)
	if c != null:
		c.respawn(pos, cls, arm)
		if c == local_char:
			spectator.stop()


@rpc("authority", "call_remote", "reliable")
func shot_fx(shooter_id: String, weapon: int, ends: PackedVector3Array) -> void:
	var s = chars.get(shooter_id)
	if s == null or s.is_local:
		return
	s.show_weapon(weapon)
	s.play_shoot()
	var from: Vector3 = s.muzzle_position()
	var splash := float(Data.WEAPONS[weapon].splash)
	for e in ends:
		_spawn_tracer(from, e)
		var hit_something := from.distance_to(e) < float(Data.WEAPONS[weapon].range) - 1.5
		if splash > 0.0 and hit_something:
			spawn_explosion(e, splash)
		elif hit_something and from.distance_to(e) < 60.0:
			sfx.bullet_impact(e, Vector3.ZERO, false)
	var silenced: bool = s.custom(weapon)["att"].has("silencer")
	play_shot_sound(weapon, from, false, silenced)
	if not silenced:
		sfx.muzzle_flash(from, int(Data.WEAPONS[weapon].pellets) > 1 or splash > 0.0)


@rpc("authority", "call_remote", "reliable")
func hit_confirm(head: bool, killed: bool, hits: Array) -> void:
	hud.hit_marker(head, killed)
	for h in hits:
		hud.add_damage_number(h[0], int(h[1]), head, bool(h[2]))


@rpc("authority", "call_remote", "reliable")
func sync_scores(sc: Dictionary, tl: float) -> void:
	scores = sc
	time_left = tl
	hud.refresh_scores()


@rpc("authority", "call_remote", "unreliable_ordered")
func sync_time(tl: float) -> void:
	time_left = tl


@rpc("authority", "call_remote", "reliable")
func on_match_end(text: String) -> void:
	if not match_over:
		_award_xp()
	match_over = true
	end_text = text
	hud.refresh_scores()


## Expérience gagnée par le joueur local à la fin du match (sauvegardée sur son PC).
var xp_text := ""
func _award_xp() -> void:
	if local_char == null or not scores.has(local_char.char_id):
		return
	var m: Dictionary = scores[local_char.char_id]
	var gain := 25 + int(m["kills"]) * 10
	var pts := int(m.get("pts", 0))
	gain += pts * {"ctf": 50, "koth": 1, "gungame": 10, "elim": 0, "dm": 0, "snd": 30, "zombies": 2}.get(rules, 0)
	var won := false
	if settings.mode == "team":
		var t := team_scores()
		won = t[local_char.team] > t[1 - local_char.team]
	else:
		won = _ffa_leader().get("name", "") == m["name"]
	if won:
		gain += 50
	var before: int = Data.level_info(Net.xp)[0]
	Net.xp += gain
	Net.save_options()
	var after: Array = Data.level_info(Net.xp)
	xp_text = "+%d XP%s   ·   niveau %d  (%d / %d)" % [gain, "  (victoire +50)" if won else "", after[0], after[1], after[2]]
	if after[0] > before:
		xp_text += "   ·   NIVEAU SUPÉRIEUR !"



func _make_effects() -> void:
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.albedo_color = Color(1.0, 0.88, 0.45)
	_impact_mat = StandardMaterial3D.new()
	_impact_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_impact_mat.albedo_color = Color(1.0, 0.65, 0.25)
	_sounds = [_noise_sound(0.14, 0.4), _noise_sound(0.3, 0.22), _noise_sound(0.5, 0.14), _noise_sound(0.9, 0.08)]


## Génère un bruit de tir (bruit filtré qui décroît) sans fichier audio externe.
func _noise_sound(duration: float, brightness: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * duration)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var y := 0.0
	var peak := 0.001
	for i in n:
		var t := float(i) / n
		y += brightness * ((randf() * 2.0 - 1.0) - y)
		var v := y * pow(1.0 - t, 2.5) + sin(float(i) / rate * TAU * 70.0) * pow(1.0 - t, 8.0) * 0.3
		samples[i] = v
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(samples[i] / peak * 0.9 * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	return s


func play_shot_sound(weapon: int, pos: Vector3, local: bool, silenced := false) -> void:
	var name := String(Data.WEAPONS[weapon].get("sfx", ""))
	if name != "":
		if silenced:
			# Silencieux : son étouffé (plus grave, bien moins fort, porte moins loin)
			sfx.play(name, null if local else pos, -20.0 if local else -16.0, 0.03, 40.0, 1.6)
		else:
			sfx.play(name, null if local else pos, -7.0 if local else 0.0, 0.05, 160.0)
		return
	var p: Node
	if local:
		var p2 := AudioStreamPlayer.new()
		p2.stream = _sounds[int(Data.WEAPONS[weapon].sound)]
		p2.volume_db = -8.0
		add_child(p2)
		p2.play()
		p = p2
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = _sounds[int(Data.WEAPONS[weapon].sound)]
		p3.unit_size = 12.0
		p3.max_distance = 150.0
		p3.volume_db = -2.0
		add_child(p3)
		p3.global_position = pos
		p3.play()
		p = p3
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


## Boule de feu qui grossit et s'efface, avec un flash de lumière et le bruit de l'explosion.
func spawn_explosion(pos: Vector3, radius: float) -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	m.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.55, 0.15, 0.9)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.global_position = pos
	m.scale = Vector3.ONE * 0.3
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 6.0
	light.omni_range = radius * 2.5
	m.add_child(light)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(m, "scale", Vector3.ONE * radius * 1.6, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.45)
	tw.tween_property(light, "light_energy", 0.0, 0.4)
	tw.chain().tween_callback(m.queue_free)
	play_shot_sound(9, pos, false)
	# Fumée et débris
	var smoke := CPUParticles3D.new()
	smoke.one_shot = true
	smoke.emitting = true
	smoke.amount = 14
	smoke.lifetime = 1.6
	smoke.explosiveness = 0.9
	smoke.direction = Vector3.UP
	smoke.spread = 70.0
	smoke.initial_velocity_min = 1.5
	smoke.initial_velocity_max = 4.0
	smoke.gravity = Vector3(0, 0.6, 0)
	smoke.damping_min = 2.0
	smoke.damping_max = 3.0
	smoke.scale_amount_min = 1.5
	smoke.scale_amount_max = 3.0
	var sm2 := SphereMesh.new()
	sm2.radius = 0.35
	sm2.height = 0.7
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0.25, 0.23, 0.22, 0.55)
	smat.vertex_color_use_as_albedo = true
	sm2.material = smat
	smoke.mesh = sm2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.9))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	smoke.color_ramp = ramp
	add_child(smoke)
	smoke.global_position = pos
	get_tree().create_timer(2.0).timeout.connect(smoke.queue_free)
	# Tremblement de caméra selon la distance
	if local_char != null and local_char.alive:
		var d: float = local_char.global_position.distance_to(pos)
		sfx.shake = maxf(sfx.shake, clampf(1.0 - d / (radius * 4.0), 0.0, 1.0))


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.2:
		return
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, length)
	m.mesh = bm
	m.material_override = _tracer_mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.global_position = (from + to) / 2.0
	var dir := (to - from).normalized()
	m.look_at(to, Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP)
	get_tree().create_timer(0.05).timeout.connect(m.queue_free)

	var impact := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	impact.mesh = sm
	impact.material_override = _impact_mat
	impact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(impact)
	impact.global_position = to
	get_tree().create_timer(0.15).timeout.connect(impact.queue_free)



## Armes imposées par le mode (course aux armes).
@rpc("authority", "call_remote", "reliable")
func set_loadout(id: String, weapons: Array) -> void:
	var c = chars.get(id)
	if c != null:
		c.set_custom_loadout(weapons)
		if c.is_local:
			sfx.play("drawKnife1", null, -6.0)


# --- Chat et signalements (ping) ---------------------------------------------------------

func send_chat(text: String) -> void:
	text = text.strip_edges().substr(0, 120)
	if text == "":
		return
	if multiplayer.is_server():
		_server_chat(1, text)
	else:
		req_chat.rpc_id(1, text)


@rpc("any_peer", "call_remote", "reliable")
func req_chat(text: String) -> void:
	if multiplayer.is_server():
		_server_chat(multiplayer.get_remote_sender_id(), text.strip_edges().substr(0, 120))


func _server_chat(peer: int, text: String) -> void:
	if text == "" or not Net.players.has(peer):
		return
	var c = chars.get(_pid(peer))
	var team: int = c.team if c != null else -1
	print("[chat] %s : %s" % [Net.players[peer]["name"], text])
	_broadcast("chat_msg", [String(Net.players[peer]["name"]), team, text])


@rpc("authority", "call_remote", "reliable")
func chat_msg(pname: String, team: int, text: String) -> void:
	hud.add_chat(pname, team, text)
	sfx.play("select_001", null, -12.0, 0.0)


## Le joueur local signale l'endroit qu'il vise à son équipe.
func send_ping() -> void:
	var c = local_char
	if c == null or not c.alive:
		return
	var from: Vector3 = c.camera.global_position
	var to: Vector3 = from - c.camera.global_transform.basis.z * 200.0
	var hit := _ray(from, to, [c.get_rid()] as Array[RID], 3)
	var pos: Vector3 = hit.position if not hit.is_empty() else to
	var enemy: bool = not hit.is_empty() and hit.collider is CharacterScript and is_enemy(c, hit.collider)
	if multiplayer.is_server():
		_server_ping(1, pos, enemy)
	else:
		req_ping.rpc_id(1, pos, enemy)


@rpc("any_peer", "call_remote", "reliable")
func req_ping(pos: Vector3, enemy: bool) -> void:
	if multiplayer.is_server():
		_server_ping(multiplayer.get_remote_sender_id(), pos, enemy)


func _server_ping(peer: int, pos: Vector3, enemy: bool) -> void:
	var c = chars.get(_pid(peer))
	if c == null:
		return
	_broadcast("ping_mark", [c.char_id, pos, enemy])


@rpc("authority", "call_remote", "reliable")
func ping_mark(from_id: String, pos: Vector3, enemy: bool) -> void:
	var c = chars.get(from_id)
	if c == null or local_char == null:
		return
	# Visible par l'auteur et ses coéquipiers seulement
	if c != local_char and (c.team < 0 or c.team != local_char.team):
		return
	hud.add_ping(pos, c.display_name, enemy)
	sfx.play("select_001", null, -6.0, 0.0)


## Armes personnalisées au hasard pour un bot (skins simples et quelques accessoires).
func _bot_armory() -> Dictionary:
	var out := {}
	for wi in Data.WEAPONS.size():
		var att := []
		for a in Data.attachments_for(wi):
			if randf() < 0.3:
				att.append(a)
		out[str(wi)] = {"skin": randi() % Data.CAMOS.size(), "att": att}
	var picks := {}
	for cat in Data.CAT_ORDER:
		var options := []
		for wi in Data.WEAPONS.size():
			if Data.WEAPONS[wi].cat == cat:
				options.append(wi)
		picks[cat] = options.pick_random()
	out["pick"] = picks
	return out
