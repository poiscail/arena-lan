extends Node3D
## Véhicules pilotables (Kenney Car Kit, CC0). Touche d'action (F) pour monter / descendre.
## Le PC du conducteur simule la conduite et envoie la position à l'hôte, qui la renvoie aux autres
## (comme pour les personnages). L'hôte gère les passagers et les piétons renversés.

const Data := preload("res://scripts/data.gd")

const MODELS := ["suv", "police", "van", "taxi"]
const MAX_SPEED := 20.0       # m/s (72 km/h)
const REVERSE_SPEED := 7.0
const ACCEL := 11.0
const BRAKE := 22.0
const DRAG := 4.0
const STEER := 1.9            # rad/s à pleine vitesse
const ENTER_RANGE := 3.2
const NET_RATE := 1.0 / 30.0

var game
var vehicles := {}            # id -> {"body", "driver", "speed", "net_pos", "net_yaw", "cam", "engine"}
var _net_t := 0.0
var _ram_cd := {}             # (serveur) "vehicule|victime" -> recharge
var _orbit := 0.0             # rotation de la caméra de conduite (souris)
var _pitch := 0.25
var _engine_stream: AudioStreamWAV


## (Serveur) Deux véhicules par carte en extérieur, garés près des points d'apparition.
func setup_server() -> void:
	if game.map.layout == 2:
		return  # entrepôt : pas de place pour conduire
	var map = game.map
	var n := 0
	for team in 2:
		var sp: Array = map.team_spawns[team]
		var c := Vector3.ZERO
		for p in sp:
			c += p
		c /= maxf(sp.size(), 1)
		var to_center := -c
		to_center.y = 0
		to_center = to_center.normalized() if to_center.length() > 0.1 else Vector3.FORWARD
		var found := false
		for ring in 14:
			for k in 10:
				var a := TAU * k / 10.0
				var p: Vector3 = c + to_center * 6.0 + Vector3(cos(a), 0, sin(a)) * ring * 1.5
				p.y = 0
				var ok := true
				for d in [Vector3.ZERO, Vector3(2.2, 0, 0), Vector3(-2.2, 0, 0), Vector3(0, 0, 2.2), Vector3(0, 0, -2.2)]:
					if not map.is_clear(p + d):
						ok = false
				if ok:
					n += 1
					_broadcast("vehicle_add", ["V%d" % n, MODELS[(n - 1) % MODELS.size()], p, atan2(-to_center.x, -to_center.z)])
					found = true
					break
			if found:
				break


func sync_to(peer: int) -> void:
	for id in vehicles:
		var v: Dictionary = vehicles[id]
		var b: CharacterBody3D = v["body"]
		vehicle_add.rpc_id(peer, id, v["model"], b.position, b.rotation.y)
		if v["driver"] != "":
			vehicle_driver.rpc_id(peer, id, v["driver"])


@rpc("authority", "call_remote", "reliable")
func vehicle_add(id: String, model: String, pos: Vector3, yaw: float) -> void:
	if vehicles.has(id):
		return
	var body := CharacterBody3D.new()
	body.name = id
	body.position = pos
	body.rotation.y = yaw
	body.floor_snap_length = 0.6
	var inst: Node3D = load("res://assets/city/cars/%s.glb" % model).instantiate()
	inst.scale = Vector3.ONE * 1.35
	inst.rotation.y = PI  # avant du modèle vers -Z
	body.add_child(inst)
	# Boîte de collision à la taille du modèle
	var aabb := _aabb(inst)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(aabb.size.x, aabb.size.y * 0.8, aabb.size.z)
	shape.shape = box
	shape.position = Vector3(0, aabb.size.y * 0.4 + 0.15, 0)
	body.add_child(shape)
	var label := Label3D.new()
	label.text = "F : conduire"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 30
	label.outline_size = 8
	label.modulate = Color(0.85, 0.95, 1.0)
	label.position.y = aabb.size.y + 0.6
	label.visible = false
	body.add_child(label)
	var engine := AudioStreamPlayer3D.new()
	engine.stream = _engine()
	engine.max_distance = 45.0
	engine.volume_db = -8.0
	body.add_child(engine)
	add_child(body)
	vehicles[id] = {"body": body, "model": model, "driver": "", "speed": 0.0, "net_pos": pos, "net_yaw": yaw,
		"label": label, "engine": engine, "length": aabb.size.z}


func _aabb(top: Node3D) -> AABB:
	var r := AABB()
	var first := true
	for m in top.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = (top.transform * (m as MeshInstance3D).transform) * (m as MeshInstance3D).get_aabb()
		r = a if first else r.merge(a)
		first = false
	return r


## Bruit de moteur en boucle (généré : grondement grave), joué plus aigu avec la vitesse.
func _engine() -> AudioStreamWAV:
	if _engine_stream != null:
		return _engine_stream
	var rate := 22050
	var n := rate  # 1 s
	var data := PackedByteArray()
	data.resize(n * 2)
	var y := 0.0
	for i in n:
		var t := float(i) / rate
		y += 0.08 * ((randf() * 2.0 - 1.0) - y)
		var v := 0.45 * sin(TAU * 55.0 * t) + 0.25 * sin(TAU * 110.0 * t + sin(TAU * 7.0 * t)) + 0.6 * y
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 0.7 * 32767.0))
	_engine_stream = AudioStreamWAV.new()
	_engine_stream.format = AudioStreamWAV.FORMAT_16_BITS
	_engine_stream.mix_rate = rate
	_engine_stream.data = data
	_engine_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_engine_stream.loop_end = n
	return _engine_stream


# --- Monter / descendre -------------------------------------------------------------------

## Véhicule libre le plus proche d'un point (ou "").
func near(pos: Vector3) -> String:
	var best := ""
	var best_d := ENTER_RANGE
	for id in vehicles:
		var v: Dictionary = vehicles[id]
		if v["driver"] != "":
			continue
		var d: float = (v["body"] as Node3D).position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = id
	return best


func driving_of(char_id: String) -> String:
	for id in vehicles:
		if vehicles[id]["driver"] == char_id:
			return id
	return ""


func _unhandled_input(event: InputEvent) -> void:
	var c = game.local_char
	if c == null or not c.alive or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if c.driving != "" and event is InputEventMouseMotion:
		_orbit -= event.relative.x * Net.mouse_sensitivity
		_pitch = clampf(_pitch + event.relative.y * Net.mouse_sensitivity, -0.1, 0.9)
	if event.is_action_pressed("interact"):
		if c.driving != "":
			_request(c.driving, false)
		else:
			var id := near(c.position)
			if id != "" and not _mode_interaction_near(c):
				_request(id, true)


## Ne pas monter en voiture si la touche sert déjà au mode (bombe, achat, arme au sol).
func _mode_interaction_near(c) -> bool:
	var m = game.modes
	if m.rules == "snd" and (m.bomb["carrier"] == c.char_id or m.bomb["state"] == "planted"):
		for s in m.sites:
			if c.position.distance_to(s) < m.SITE_RADIUS + 1.0:
				return true
	if (m.rules == "zombies" and not m.shop_near(c.position).is_empty()) or (m.rules == "br" and m.loot_near(c.position, 1.6) != ""):
		return true
	return false


func _request(id: String, enter: bool) -> void:
	if multiplayer.is_server():
		_server_request(game._pid(1), id, enter)
	else:
		req_vehicle.rpc_id(1, id, enter)


@rpc("any_peer", "call_remote", "reliable")
func req_vehicle(id: String, enter: bool) -> void:
	if multiplayer.is_server():
		_server_request(game._pid(multiplayer.get_remote_sender_id()), id, enter)


func _server_request(char_id: String, id: String, enter: bool) -> void:
	var c = game.chars.get(char_id)
	if c == null or not c.alive or not vehicles.has(id):
		return
	var v: Dictionary = vehicles[id]
	if enter:
		if v["driver"] != "" or driving_of(char_id) != "" or (v["body"] as Node3D).position.distance_to(c.position) > ENTER_RANGE + 1.0:
			return
		_broadcast("vehicle_driver", [id, char_id])
	elif v["driver"] == char_id:
		_broadcast("vehicle_driver", [id, ""])


## (Serveur) Le conducteur est mort ou parti : le véhicule se vide.
func on_char_gone(char_id: String) -> void:
	var id := driving_of(char_id)
	if id != "":
		_broadcast("vehicle_driver", [id, ""])


@rpc("authority", "call_remote", "reliable")
func vehicle_driver(id: String, char_id: String) -> void:
	if not vehicles.has(id):
		return
	var v: Dictionary = vehicles[id]
	var body: CharacterBody3D = v["body"]
	var old = game.chars.get(v["driver"])
	if old != null and old.driving == id:
		# Descente : à côté de la portière (ou de l'autre côté si bloqué)
		old.set_driving("")
		var side: Vector3 = body.global_transform.basis.x
		var out: Vector3 = body.position - side * 1.9
		if not game.map.is_clear(out):
			out = body.position + side * 1.9
		old.position = Vector3(out.x, body.position.y + 0.1, out.z)
		old._net_pos = old.position
		if old.is_local:
			old.camera.make_current()
	v["driver"] = char_id
	v["speed"] = 0.0
	var c = game.chars.get(char_id)
	if c != null:
		c.set_driving(id)
		if c.is_local:
			_orbit = 0.0
			_ensure_camera(v).make_current()
	(v["engine"] as AudioStreamPlayer3D).playing = char_id != ""


func _ensure_camera(v: Dictionary) -> Camera3D:
	if v.has("cam"):
		return v["cam"]
	var cam := Camera3D.new()
	cam.fov = float(Net.gfx.fov)
	cam.far = Net.view_distance()
	add_child(cam)
	v["cam"] = cam
	return cam


# --- Conduite --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var local = game.local_char
	_net_t += delta
	var send := _net_t >= NET_RATE
	if send:
		_net_t = 0.0
	for id in vehicles:
		var v: Dictionary = vehicles[id]
		var body: CharacterBody3D = v["body"]
		if v["driver"] != "":
			# Conducteur disparu, mort ou réapparu ailleurs : le véhicule est libre
			var dc = game.chars.get(v["driver"])
			if dc == null or dc.driving != id:
				v["driver"] = ""
				v["speed"] = 0.0
				(v["engine"] as AudioStreamPlayer3D).playing = false
		var mine: bool = local != null and v["driver"] == local.char_id and local.alive
		if mine:
			_drive(v, delta)
			local.position = body.position + Vector3(0, 0.2, 0)
			local.rotation.y = body.rotation.y
			if send:
				if multiplayer.is_server():
					_relay(id, body.position, body.rotation.y, v["speed"])
				else:
					vehicle_state.rpc_id(1, id, body.position, body.rotation.y, float(v["speed"]))
		elif v["driver"] != "":
			# Véhicule conduit par quelqu'un d'autre : on suit sa position
			var k := minf(1.0, delta * 12.0)
			body.position = body.position.lerp(v["net_pos"], k)
			body.rotation.y = lerp_angle(body.rotation.y, v["net_yaw"], k)
			var d = game.chars.get(v["driver"])
			if d != null and not d.is_local:
				d.position = body.position + Vector3(0, 0.2, 0)
		var eng: AudioStreamPlayer3D = v["engine"]
		if eng.playing:
			eng.pitch_scale = 0.7 + absf(float(v["speed"])) / MAX_SPEED * 1.3
		(v["label"] as Label3D).visible = v["driver"] == "" and local != null and local.alive and local.driving == "" \
			and body.position.distance_to(local.position) < 7.0
		if multiplayer.is_server() and v["driver"] != "":
			_server_ram(id, v, delta)
	if local != null and local.driving != "" and vehicles.has(local.driving):
		_update_camera(vehicles[local.driving], delta)


func _drive(v: Dictionary, delta: float) -> void:
	var body: CharacterBody3D = v["body"]
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var throttle := 0.0
	var steer := 0.0
	var handbrake := false
	if captured:
		throttle = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
		steer = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
		handbrake = Input.is_action_pressed("jump")
	var speed: float = v["speed"]
	if throttle > 0.0:
		speed += (ACCEL if speed >= 0.0 else BRAKE) * throttle * delta
	elif throttle < 0.0:
		speed += (BRAKE if speed > 0.0 else ACCEL * 0.6) * throttle * delta
	else:
		speed = move_toward(speed, 0.0, DRAG * delta)
	if handbrake:
		speed = move_toward(speed, 0.0, BRAKE * 1.3 * delta)
	speed = clampf(speed, -REVERSE_SPEED, MAX_SPEED)
	# Le volant tourne d'autant plus qu'on roule vite (et à l'envers en marche arrière)
	var grip := clampf(absf(speed) / 6.0, 0.0, 1.0) * signf(speed)
	body.rotation.y += steer * STEER * grip * delta * (1.4 if handbrake else 1.0)
	var fwd := -body.global_transform.basis.z
	body.velocity.x = fwd.x * speed
	body.velocity.z = fwd.z * speed
	body.velocity.y = 0.0 if body.is_on_floor() else body.velocity.y - 20.0 * delta
	var before := body.position
	body.move_and_slide()
	# Choc contre un mur : la vitesse retombe
	if body.get_slide_collision_count() > 0:
		var moved := Vector2(body.position.x - before.x, body.position.z - before.z).length() / maxf(delta, 0.001)
		if moved < absf(speed) * 0.6:
			if absf(speed) > 8.0:
				game.sfx.shake = maxf(game.sfx.shake, 0.4)
				game.sfx.play("impactMetal_light_000", body.position, 0.0)
			speed = signf(speed) * moved
	v["speed"] = speed


func _update_camera(v: Dictionary, delta: float) -> void:
	var body: Node3D = v["body"]
	var cam: Camera3D = v["cam"]
	var yaw: float = body.rotation.y + _orbit
	var back := Vector3(sin(yaw), 0, cos(yaw))
	var dist := 6.5 + absf(float(v["speed"])) * 0.08
	var target := body.position + Vector3(0, 1.3, 0)
	var want := target + back * dist * cos(_pitch) + Vector3(0, 1.2 + dist * sin(_pitch), 0)
	# Ne pas traverser les murs
	var hit: Dictionary = game._ray(target, want, [body.get_rid()] as Array[RID], 1)
	if not hit.is_empty():
		want = hit.position + (target - want).normalized() * 0.3
	cam.global_position = cam.global_position.lerp(want, minf(1.0, delta * 10.0))
	cam.look_at(target, Vector3.UP)
	_orbit = lerpf(_orbit, 0.0, delta * 0.6)  # la caméra revient doucement derrière


@rpc("any_peer", "call_remote", "unreliable_ordered")
func vehicle_state(id: String, pos: Vector3, yaw: float, speed: float) -> void:
	if not multiplayer.is_server() or not vehicles.has(id):
		return
	var v: Dictionary = vehicles[id]
	if v["driver"] != game._pid(multiplayer.get_remote_sender_id()):
		return
	_relay(id, pos, yaw, speed)


func _relay(id: String, pos: Vector3, yaw: float, speed: float) -> void:
	var v: Dictionary = vehicles[id]
	v["speed"] = speed
	if not multiplayer.is_server() or game._pid(1) != v["driver"]:
		v["net_pos"] = pos
		v["net_yaw"] = yaw
	for p in game.ready_peers:
		if game._pid(p) != v["driver"]:
			vehicle_net.rpc_id(p, id, pos, yaw, speed)


@rpc("authority", "call_remote", "unreliable_ordered")
func vehicle_net(id: String, pos: Vector3, yaw: float, speed: float) -> void:
	if not vehicles.has(id):
		return
	var v: Dictionary = vehicles[id]
	v["net_pos"] = pos
	v["net_yaw"] = yaw
	v["speed"] = speed


## (Serveur) Piétons renversés : dégâts selon la vitesse, devant le véhicule.
func _server_ram(id: String, v: Dictionary, delta: float) -> void:
	for k in _ram_cd.keys():
		_ram_cd[k] -= delta
		if _ram_cd[k] <= 0.0:
			_ram_cd.erase(k)
	var speed: float = absf(float(v["speed"]))
	if speed < 5.0:
		return
	var driver = game.chars.get(v["driver"])
	if driver == null:
		return
	var body: Node3D = v["body"]
	var fwd: Vector3 = -body.global_transform.basis.z * signf(float(v["speed"]))
	var reach: float = float(v["length"]) * 0.5 + 0.9
	for cid in game.chars:
		var t = game.chars[cid]
		if t == driver or not t.alive or t.driving != "" or not game.is_enemy(driver, t):
			continue
		var to: Vector3 = t.position - body.position
		to.y = 0
		if to.length() > reach or to.normalized().dot(fwd) < 0.3:
			continue
		var key := "%s|%s" % [id, cid]
		if _ram_cd.has(key):
			continue
		_ram_cd[key] = 1.0
		game._deal_damage(driver, {cid: 30.0 + speed * 6.5}, Data.KILL_VEHICLE)


func _broadcast(method: String, args: Array) -> void:
	for p in game.ready_peers:
		callv("rpc_id", [p, method] + args)
	callv(method, args)


## Texte d'aide pour le joueur local (affiché sous le score), ou "".
func hint() -> String:
	var c = game.local_char
	if c == null or not c.alive:
		return ""
	var key: String = Net.binding_text("interact")
	if c.driving != "" and vehicles.has(c.driving):
		return "%d km/h · %s : descendre · Espace : frein à main" % [int(absf(float(vehicles[c.driving]["speed"])) * 3.6), key]
	if near(c.position) != "" and not _mode_interaction_near(c):
		return "%s : conduire" % key
	return ""
