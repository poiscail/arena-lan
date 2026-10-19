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
var _health := []  # trousses de soin : {"node", "pos", "active", "timer"}
var _anim_t := 0.0

const HEAL_AMOUNT := 50
const HEAL_RESPAWN := 20.0


func _ready() -> void:
	settings = Net.settings.duplicate()
	time_left = float(settings.time_limit) * 60.0
	map = MapScript.new()
	map.build(self, multiplayer.is_server())
	_chars_root = Node3D.new()
	_chars_root.name = "Characters"
	add_child(_chars_root)
	_make_effects()
	_spawn_health_packs()
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
	_anim_t += delta
	for h in _health:
		h["node"].rotation.y = _anim_t * 1.5
		h["node"].position.y = 0.35 + sin(_anim_t * 2.5) * 0.12


func _physics_process(delta: float) -> void:
	if multiplayer.is_server() and not match_over:
		_update_health_packs(delta)
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
			data.append([id, c.position, c.rotation.y, c.head.rotation.x])
		for p in ready_peers:
			snapshot.rpc_id(p, data)
	elif local_char != null and local_char.alive:
		client_state.rpc_id(1, local_char.position, local_char.rotation.y, local_char.head.rotation.x)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		hud.toggle_pause()
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
	return _ray(from, to, _no_exclude, 1).is_empty()


func team_scores() -> Array:
	var t := [0, 0]
	for id in scores:
		var team: int = scores[id]["team"]
		if team >= 0:
			t[team] += int(scores[id]["kills"])
	return t


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
	var w: Dictionary = Data.WEAPONS[weapon]
	var muzzle: Vector3 = c.muzzle_position()
	var ex: Array[RID] = [c.get_rid()]
	for d in dirs:
		var to: Vector3 = origin + d * float(w.range)
		var hit := _ray(origin, to, ex, 3)
		_spawn_tracer(muzzle, hit.position if not hit.is_empty() else to)
	play_shot_sound(weapon, muzzle, true)
	if multiplayer.is_server():
		_server_shoot(c.char_id, weapon, origin, dirs)
	else:
		req_shoot.rpc_id(1, weapon, origin, dirs)


## Appelé (sur le serveur) par le cerveau d'un bot.
func bot_fire(c, dir: Vector3) -> void:
	_server_shoot(c.char_id, 0, c.eye_position(), PackedVector3Array([dir]))


func _server_shoot(shooter_id: String, weapon: int, origin: Vector3, dirs: PackedVector3Array) -> void:
	var s = chars.get(shooter_id)
	if s == null or not s.alive or match_over:
		return
	weapon = clampi(weapon, 0, Data.WEAPONS.size() - 1)
	var w: Dictionary = Data.WEAPONS[weapon]
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
		if t is CharacterScript and t.alive and is_enemy(s, t):
			var head: bool = hit.position.y > t.position.y + 1.45
			var dmg := float(w.damage) * (float(w.head) if head else 1.0)
			damage[t.char_id] = damage.get(t.char_id, 0.0) + dmg
			head_hit = head_hit or head
	_broadcast("shot_fx", [shooter_id, weapon, ends])
	if damage.is_empty():
		return
	var killed := false
	for tid in damage:
		if chars.has(tid) and _apply_damage(chars[tid], s, int(round(damage[tid])), weapon):
			killed = true
	if not s.is_bot:
		if s.owner_peer == multiplayer.get_unique_id():
			hit_confirm(head_hit, killed)
		elif ready_peers.has(s.owner_peer):
			hit_confirm.rpc_id(s.owner_peer, head_hit, killed)


func _apply_damage(t, s, dmg: int, weapon: int) -> bool:
	t.hp = maxi(0, t.hp - dmg)
	_broadcast("on_health", [t.char_id, t.hp, true])
	if t.bot != null:
		t.bot.alert(s)
	if t.hp > 0:
		return false
	if scores.has(t.char_id):
		scores[t.char_id]["deaths"] += 1
	if scores.has(s.char_id):
		scores[s.char_id]["kills"] += 1
	print("[kill] %s -> %s (%s)" % [s.display_name, t.display_name, Data.WEAPONS[weapon].name])
	_broadcast("on_died", [t.char_id, s.char_id, weapon])
	_broadcast_scores()
	_check_win()
	if not match_over:
		get_tree().create_timer(Data.RESPAWN_TIME).timeout.connect(_respawn.bind(t.char_id))
	return true


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
	var id := _pid(peer)
	if not scores.has(id):
		scores[id] = {"name": info["name"], "team": team, "kills": 0, "deaths": 0, "bot": false}
	_broadcast("spawn_char", [id, info["name"], team, false, peer, _pick_spawn(team), true, 100, int(info.get("skin", 0))])
	_broadcast_scores()


func _server_add_bot(team: int) -> String:
	_bot_serial += 1
	var id := "B%d" % _bot_serial
	var bname := "%s (bot)" % BOT_NAMES[(_bot_serial - 1) % BOT_NAMES.size()]
	scores[id] = {"name": bname, "team": team, "kills": 0, "deaths": 0, "bot": true}
	_broadcast("spawn_char", [id, bname, team, true, 1, _pick_spawn(team), true, 100, randi() % Data.SKINS.size()])
	return id


## Ajoute ou retire des bots pour que chaque équipe (ou la mêlée) soit complète.
func _rebalance_bots() -> void:
	if not multiplayer.is_server() or match_over:
		return
	var teams := [0, 1] if settings.mode == "team" else [-1]
	for t in teams:
		var humans := 0
		for pid in Net.players:
			if t == -1 or Net.players[pid]["team"] == t:
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
	_broadcast("on_respawn", [id, _pick_spawn(chars[id].team)])


func _check_win() -> void:
	var limit: int = settings.score_limit
	if settings.mode == "team":
		var t := team_scores()
		if t[0] >= limit or t[1] >= limit:
			_end_match()
	else:
		var leader := _ffa_leader()
		if not leader.is_empty() and leader["kills"] >= limit:
			_end_match()


func _ffa_leader() -> Dictionary:
	var best := {}
	for id in scores:
		if best.is_empty() or scores[id]["kills"] > best["kills"]:
			best = scores[id]
	return best


func _end_match() -> void:
	if match_over:
		return
	var text := ""
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
			text = "%s gagne avec %d éliminations" % [leader["name"], leader["kills"]]
	print("[match] " + text)
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
		spawn_char.rpc_id(peer, id, c.display_name, c.team, c.is_bot, c.owner_peer, c.position, c.alive, c.hp, c.skin)
	sync_scores.rpc_id(peer, scores, time_left)
	for i in _health.size():
		pickup_state.rpc_id(peer, i, _health[i]["active"])
	if match_over:
		on_match_end.rpc_id(peer, end_text)
	if not chars.has(_pid(peer)):
		_server_add_human(peer)
	_rebalance_bots()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func client_state(pos: Vector3, yaw: float, pitch: float) -> void:
	var c = chars.get(_pid(multiplayer.get_remote_sender_id()))
	if c != null and c.alive:
		c.net_target(pos, yaw, pitch)


@rpc("any_peer", "call_remote", "reliable")
func req_shoot(weapon: int, origin: Vector3, dirs: PackedVector3Array) -> void:
	if multiplayer.is_server():
		_server_shoot(_pid(multiplayer.get_remote_sender_id()), weapon, origin, dirs)


# --- RPC serveur -> clients -----------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func spawn_char(id: String, dname: String, team: int, is_bot: bool, owner_peer: int, pos: Vector3, alive: bool, hp: int, skin: int) -> void:
	if chars.has(id):
		return
	var c = CharacterScript.new()
	c.name = id
	c.char_id = id
	c.skin = skin
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


@rpc("authority", "call_remote", "reliable")
func on_health(id: String, hp: int, hurt: bool) -> void:
	var c = chars.get(id)
	if c == null:
		return
	c.hp = hp
	if c == local_char:
		if hurt:
			hud.damage_flash()
		else:
			hud.heal_flash()


@rpc("authority", "call_remote", "reliable")
func pickup_state(index: int, active: bool) -> void:
	if index >= 0 and index < _health.size():
		_health[index]["active"] = active
		_health[index]["node"].visible = active


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
		khex, Data.esc(kname), Data.esc(Data.WEAPONS[weapon].name), vhex, Data.esc(v.display_name)])
	if v == local_char:
		hud.show_death(kname)


@rpc("authority", "call_remote", "reliable")
func on_respawn(id: String, pos: Vector3) -> void:
	var c = chars.get(id)
	if c != null:
		c.respawn(pos)


@rpc("authority", "call_remote", "reliable")
func shot_fx(shooter_id: String, weapon: int, ends: PackedVector3Array) -> void:
	var s = chars.get(shooter_id)
	if s == null or s.is_local:
		return
	s.play_shoot()
	var from: Vector3 = s.muzzle_position()
	for e in ends:
		_spawn_tracer(from, e)
	play_shot_sound(weapon, from, false)


@rpc("authority", "call_remote", "reliable")
func hit_confirm(head: bool, killed: bool) -> void:
	hud.hit_marker(head, killed)


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
	match_over = true
	end_text = text
	hud.refresh_scores()


# --- Effets -------------------------------------------------------------------------

func _spawn_health_packs() -> void:
	for p in map.HEALTH_POINTS:
		var node: Node3D = load(map.ENV_PATH % "Health").instantiate()
		node.position = p
		node.scale = Vector3.ONE * 0.8
		add_child(node)
		var glow := OmniLight3D.new()
		glow.light_color = Color(0.4, 1.0, 0.5)
		glow.light_energy = 0.8
		glow.omni_range = 2.5
		glow.position.y = 0.5
		node.add_child(glow)
		_health.append({"node": node, "pos": p, "active": true, "timer": 0.0})


## (Serveur) Soigne qui touche une trousse, puis la fait réapparaître après un délai.
func _update_health_packs(delta: float) -> void:
	for i in _health.size():
		var h: Dictionary = _health[i]
		if not h["active"]:
			h["timer"] -= delta
			if h["timer"] <= 0.0:
				_broadcast("pickup_state", [i, true])
			continue
		for id in chars:
			var c = chars[id]
			if not c.alive or c.hp >= 100:
				continue
			var d: Vector3 = c.position - h["pos"]
			if Vector2(d.x, d.z).length() < 1.3 and absf(d.y) < 1.5:
				c.hp = mini(100, c.hp + HEAL_AMOUNT)
				print("[soin] %s -> %d PV" % [c.display_name, c.hp])
				_broadcast("on_health", [c.char_id, c.hp, false])
				h["timer"] = HEAL_RESPAWN
				_broadcast("pickup_state", [i, false])
				break


func _make_effects() -> void:
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.albedo_color = Color(1.0, 0.88, 0.45)
	_impact_mat = StandardMaterial3D.new()
	_impact_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_impact_mat.albedo_color = Color(1.0, 0.65, 0.25)
	_sounds = [_noise_sound(0.14, 0.4), _noise_sound(0.3, 0.22), _noise_sound(0.5, 0.14)]


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


func play_shot_sound(weapon: int, pos: Vector3, local: bool) -> void:
	var p: Node
	if local:
		var p2 := AudioStreamPlayer.new()
		p2.stream = _sounds[weapon]
		p2.volume_db = -8.0
		add_child(p2)
		p2.play()
		p = p2
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = _sounds[weapon]
		p3.unit_size = 12.0
		p3.max_distance = 150.0
		p3.volume_db = -2.0
		add_child(p3)
		p3.global_position = pos
		p3.play()
		p = p3
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


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

