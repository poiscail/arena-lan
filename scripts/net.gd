extends Node
## Autoload "Net" : hébergement / connexion LAN, salon et paramètres de partie.

signal lobby_changed
signal game_started
signal game_ended
signal disconnected(reason: String)

const DEFAULT_PORT := 7777
const MAX_HUMANS := 12

var player_name := "Joueur"
var player_skin := 0
var player_class := 0
var port := DEFAULT_PORT
var players := {}  # peer_id -> {"name": String, "team": int}
var settings := {
	"mode": "team",      # "team" (équipes) ou "ffa" (chacun pour soi)
	"slots": 3,          # équipes : joueurs par équipe (1-6) / ffa : combattants au total (2-12)
	"bots": true,        # compléter les places vides avec des bots
	"difficulty": 1,     # 0 facile, 1 normal, 2 difficile
	"score_limit": 30,
	"time_limit": 10,    # minutes
	"map": 0,            # 0 base militaire, 1 ville
	"rules": "dm",       # mode de jeu : voir Data.RULES
}
var in_game := false
var mouse_sensitivity := 0.0025

signal graphics_changed

const CONFIG_PATH := "user://options.cfg"
const SHADOW_SIZES := [0, 1024, 2048, 4096]
const SHADOW_DISTANCES := [0.0, 40.0, 70.0, 110.0]
const MSAA_MODES := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X]
const FPS_LIMITS := [0, 60, 120, 144, 240]
const VIEW_DISTANCES := [80.0, 160.0, 400.0]

# Réglages graphiques (sauvegardés dans user://options.cfg)
var gfx := {
	"shadows": 2,        # 0 aucune, 1 basse, 2 moyenne, 3 haute
	"msaa": 1,           # 0 non, 1 2x, 2 4x, 3 8x
	"scale": 100,        # résolution 3D en %
	"fog": true,
	"view": 1,           # distance de vue : 0 courte, 1 moyenne, 2 longue
	"brightness": 100,   # %
	"fov": 80,
	"fullscreen": false,
	"vsync": true,
	"fps_limit": 0,      # index dans FPS_LIMITS (0 = illimité)
	"show_fps": false,
}


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_setup_inputs()
	load_options()
	apply_graphics()


# --- Options ------------------------------------------------------------------

func load_options() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	for k in gfx:
		gfx[k] = cfg.get_value("graphics", k, gfx[k])
	mouse_sensitivity = cfg.get_value("controls", "sensitivity", mouse_sensitivity)
	if cfg.has_section("keys"):
		for a in cfg.get_section_keys("keys"):
			bindings[a] = String(cfg.get_value("keys", a))
		_apply_bindings()
	player_class = cfg.get_value("player", "class", player_class)
	player_skin = cfg.get_value("player", "skin", player_skin)


func save_options() -> void:
	var cfg := ConfigFile.new()
	for k in gfx:
		cfg.set_value("graphics", k, gfx[k])
	cfg.set_value("controls", "sensitivity", mouse_sensitivity)
	for a in bindings:
		cfg.set_value("keys", a, bindings[a])
	cfg.set_value("player", "class", player_class)
	cfg.set_value("player", "skin", player_skin)
	cfg.save(CONFIG_PATH)


func set_gfx(key: String, value) -> void:
	gfx[key] = value
	apply_graphics()
	save_options()


## Applique les réglages à la fenêtre et à la scène 3D en cours (lumière, environnement).
func apply_graphics() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var vp := get_viewport()
	vp.msaa_3d = MSAA_MODES[clampi(int(gfx.msaa), 0, 3)]
	vp.scaling_3d_scale = clampf(float(gfx.scale) / 100.0, 0.5, 1.0)
	var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if bool(gfx.fullscreen) != fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if gfx.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if gfx.vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = FPS_LIMITS[clampi(int(gfx.fps_limit), 0, FPS_LIMITS.size() - 1)]
	var q := clampi(int(gfx.shadows), 0, 3)
	if q > 0:
		RenderingServer.directional_shadow_atlas_set_size(SHADOW_SIZES[q], true)
	for sun in get_tree().get_nodes_in_group("gfx_sun"):
		sun.shadow_enabled = q > 0
		sun.directional_shadow_max_distance = SHADOW_DISTANCES[q]
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if q == 1 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	for we in get_tree().get_nodes_in_group("gfx_env"):
		var env: Environment = we.environment
		env.fog_enabled = gfx.fog
		env.adjustment_enabled = int(gfx.brightness) != 100
		env.adjustment_brightness = float(gfx.brightness) / 100.0
	graphics_changed.emit()


# --- Découverte des parties sur le réseau local -------------------------------------
# L'hôte annonce sa partie chaque seconde en UDP broadcast ; le menu écoute et liste les parties.

signal games_changed

const DISCOVERY_PORT := 7778
const DISCOVERY_TAG := "ARENALAN1"

var found_games := {}  # ip -> {"name", "port", "players", "map", "mode", "in_game", "seen"}
var _announcer: PacketPeerUDP
var _listener: PacketPeerUDP
var _announce_t := 0.0


func start_discovery() -> void:
	if _listener != null:
		return
	_listener = PacketPeerUDP.new()
	if _listener.bind(DISCOVERY_PORT) != OK:
		_listener = null


func stop_discovery() -> void:
	if _listener != null:
		_listener.close()
		_listener = null
	found_games.clear()


func _process(delta: float) -> void:
	# Hôte : annonce de la partie
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.is_server():
		_announce_t -= delta
		if _announce_t <= 0.0:
			_announce_t = 1.0
			if _announcer == null:
				_announcer = PacketPeerUDP.new()
				_announcer.set_broadcast_enabled(true)
				_announcer.set_dest_address("255.255.255.255", DISCOVERY_PORT)
			var info := {"tag": DISCOVERY_TAG, "name": player_name, "port": port, "players": players.size(),
				"map": int(settings.get("map", 0)), "mode": settings.get("mode", "team"), "in_game": in_game}
			_announcer.put_packet(JSON.stringify(info).to_utf8_buffer())
	# Menu : réception des annonces
	if _listener != null:
		var changed := false
		while _listener.get_available_packet_count() > 0:
			var data := _listener.get_packet().get_string_from_utf8()
			var ip := _listener.get_packet_ip()
			var info = JSON.parse_string(data)
			if info is Dictionary and info.get("tag", "") == DISCOVERY_TAG:
				if not found_games.has(ip):
					changed = true
				info["seen"] = Time.get_ticks_msec()
				found_games[ip] = info
		for ip in found_games.keys():
			if Time.get_ticks_msec() - int(found_games[ip]["seen"]) > 3500:
				found_games.erase(ip)
				changed = true
		if changed:
			games_changed.emit()


func view_distance() -> float:
	return VIEW_DISTANCES[clampi(int(gfx.view), 0, 2)]


func host(p_port: int) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(p_port, MAX_HUMANS - 1) != OK:
		return "Impossible d'héberger sur le port %d (déjà utilisé ?)." % p_port
	multiplayer.multiplayer_peer = peer
	port = p_port
	players = {1: {"name": player_name, "team": 0, "skin": player_skin, "class": player_class}}
	in_game = false
	print("[net] Serveur ouvert sur le port %d" % p_port)
	lobby_changed.emit()
	return ""


func join(address: String, p_port: int) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, p_port) != OK:
		return "Adresse invalide."
	multiplayer.multiplayer_peer = peer
	port = p_port
	return ""


func leave() -> void:
	var p := multiplayer.multiplayer_peer
	if p != null and not (p is OfflineMultiplayerPeer):
		p.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players = {}
	in_game = false


func quit_to_menu() -> void:
	leave()
	disconnected.emit("")


func local_ips() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


# --- Salon -------------------------------------------------------------------

func set_settings(s: Dictionary) -> void:
	if not multiplayer.is_server() or in_game:
		return
	settings = s
	_broadcast_lobby()


func request_team_change() -> void:
	if multiplayer.is_server():
		_change_team(1)
	else:
		rpc_change_team.rpc_id(1)


func start_match() -> void:
	if not multiplayer.is_server() or in_game:
		return
	in_game = true
	start_game.rpc(settings)


func end_match_to_lobby() -> void:
	if not multiplayer.is_server() or not in_game:
		return
	back_to_lobby.rpc()


@rpc("any_peer", "call_remote", "reliable")
func register_player(pname: String, skin: int, cls: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	pname = pname.strip_edges().substr(0, 16)
	if pname == "":
		pname = "Joueur%d" % id
	players[id] = {"name": pname, "team": _smallest_team(), "skin": clampi(skin, 0, 99), "class": clampi(cls, 0, 99)}
	print("[net] %s a rejoint (id %d)" % [pname, id])
	_broadcast_lobby()
	if in_game:
		start_game.rpc_id(id, settings)


@rpc("any_peer", "call_remote", "reliable")
func rpc_change_team() -> void:
	_change_team(multiplayer.get_remote_sender_id())


@rpc("authority", "call_remote", "reliable")
func sync_lobby(p: Dictionary, s: Dictionary) -> void:
	players = p
	settings = s
	lobby_changed.emit()


@rpc("authority", "call_local", "reliable")
func start_game(s: Dictionary) -> void:
	settings = s
	in_game = true
	print("[net] Partie lancée")
	game_started.emit()


@rpc("authority", "call_local", "reliable")
func back_to_lobby() -> void:
	in_game = false
	game_ended.emit()


func _change_team(id: int) -> void:
	if in_game or not players.has(id):
		return
	players[id]["team"] = 1 - int(players[id]["team"])
	_broadcast_lobby()


func _smallest_team() -> int:
	var counts := [0, 0]
	for id in players:
		counts[players[id]["team"]] += 1
	return 0 if counts[0] <= counts[1] else 1


func _broadcast_lobby() -> void:
	sync_lobby.rpc(players, settings)
	lobby_changed.emit()


func _on_connected_ok() -> void:
	print("[net] Connecté au serveur")
	register_player.rpc_id(1, player_name, player_skin, player_class)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server() and players.has(id):
		print("[net] %s est parti" % players[id]["name"])
		players.erase(id)
		_broadcast_lobby()


func _on_connected_fail() -> void:
	leave()
	disconnected.emit("Impossible de se connecter à l'hôte.")


func _on_server_disconnected() -> void:
	leave()
	disconnected.emit("La connexion avec l'hôte a été perdue.")


# --- Touches personnalisables ------------------------------------------------------------

const REBINDABLE := [
	["move_forward", "Avancer"], ["move_back", "Reculer"], ["move_left", "Gauche"], ["move_right", "Droite"],
	["jump", "Sauter"], ["sprint", "Sprinter"], ["slide", "Glisser"], ["shoot", "Tirer"], ["zoom", "Zoom"],
	["reload", "Recharger"], ["weapon_1", "Arme 1"], ["weapon_2", "Arme 2"], ["weapon_3", "Arme 3"],
	["grenade", "Grenade"], ["smoke", "Fumigène"], ["melee", "Couteau"], ["ping", "Signaler"],
	["chat", "Chat"], ["scoreboard", "Scores"],
]

var bindings := {}  # action -> "k:<touche physique>" ou "m:<bouton souris>"


## Remplace la touche d'une action et sauvegarde.
func set_binding(action: String, event: InputEvent) -> void:
	if event is InputEventKey:
		bindings[action] = "k:%d" % int(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
	elif event is InputEventMouseButton:
		bindings[action] = "m:%d" % int(event.button_index)
	else:
		return
	_apply_bindings()
	save_options()


func reset_bindings() -> void:
	bindings.clear()
	for a in REBINDABLE:
		InputMap.action_erase_events(a[0])
	_setup_inputs()
	save_options()


func _apply_bindings() -> void:
	for action in bindings:
		if not InputMap.has_action(action):
			continue
		var parts: PackedStringArray = String(bindings[action]).split(":")
		if parts.size() != 2:
			continue
		InputMap.action_erase_events(action)
		if parts[0] == "k":
			var ev := InputEventKey.new()
			ev.physical_keycode = int(parts[1])
			InputMap.action_add_event(action, ev)
		else:
			var mb := InputEventMouseButton.new()
			mb.button_index = int(parts[1])
			InputMap.action_add_event(action, mb)


## Nom lisible de la touche d'une action (selon la disposition du clavier).
func binding_text(action: String) -> String:
	var names := []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
			var shown := code
			if ev.physical_keycode != 0 and DisplayServer.get_name() != "headless":
				shown = DisplayServer.keyboard_get_keycode_from_physical(code)
			names.append(OS.get_keycode_string(shown))
		elif ev is InputEventMouseButton:
			names.append({1: "Clic gauche", 2: "Clic droit", 3: "Clic molette", 8: "Souris 4", 9: "Souris 5"}.get(int(ev.button_index), "Souris %d" % ev.button_index))
	return " / ".join(names) if names.size() > 0 else "—"


# --- Touches (positions physiques : ZQSD en AZERTY, WASD en QWERTY) ---------

func _setup_inputs() -> void:
	_keys("move_forward", [KEY_W, KEY_UP])
	_keys("move_back", [KEY_S, KEY_DOWN])
	_keys("move_left", [KEY_A, KEY_LEFT])
	_keys("move_right", [KEY_D, KEY_RIGHT])
	_keys("jump", [KEY_SPACE])
	_keys("sprint", [KEY_SHIFT])
	_keys("slide", [KEY_CTRL, KEY_C])
	_keys("grenade", [KEY_G])
	_keys("smoke", [KEY_H])
	_keys("melee", [KEY_V])
	_keys("chat", [KEY_T])
	_keys("ping", [KEY_X])
	_mouse("ping", MOUSE_BUTTON_MIDDLE)
	_keys("reload", [KEY_R])
	_keys("weapon_1", [KEY_1])
	_keys("weapon_2", [KEY_2])
	_keys("weapon_3", [KEY_3])
	_keys("scoreboard", [KEY_TAB])
	_keys("pause", [KEY_ESCAPE])
	_mouse("shoot", MOUSE_BUTTON_LEFT)
	_mouse("zoom", MOUSE_BUTTON_RIGHT)


func _keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
