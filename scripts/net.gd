extends Node
## Autoload "Net" : hébergement / connexion LAN, salon et paramètres de partie.

const Data := preload("res://scripts/data.gd")

signal lobby_changed
signal game_started
signal game_ended
signal disconnected(reason: String)

const DEFAULT_PORT := 7777
const MAX_HUMANS := 12

var player_name := "Joueur"
var player_skin := 0
var player_class := 0
var player_camo := 0
var armory := {}  # str(n° arme) -> {"skin": int, "att": [ids]} (personnalisation des armes)
var xp := 0  # expérience totale du joueur (sauvegardée)
var daily := {}  # défis du jour : {"date", "list"} (voir challenges.gd)
var weapon_kills := {}  # str(n° arme) -> éliminations avec cette arme (débloquent ses skins)
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
	"advmove": false,    # mouvements avancés : double saut et course sur les murs
	"weather": 0,        # météo : 0 beau temps, 1 pluie, 2 orage, 3 neige, 4 brouillard, 5 au hasard
	"daycycle": false,   # cycle jour/nuit : une journée complète défile pendant la partie
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
	"post": true,       # effets d'écran (couleurs, vignette, grain)
	"fx": 2,             # qualité des effets : 0 bas, 1 moyen, 2 élevé, 3 ultra
	"renderer": 0,       # 0 standard (compatibilité), 1 avancé (Forward+, au prochain lancement)
	"killcam": true,     # rejoue sa mort vue par le tueur
	"minimap": true,     # mini-carte en haut à gauche
	# Réticule (voir crosshair.gd)
	"xh_style": 1,       # index dans Crosshair.STYLES
	"xh_color": 0,       # index dans Crosshair.COLORS
	"xh_size": 10,       # longueur des branches (px)
	"xh_gap": 7,         # écart au centre (px)
	"xh_thick": 2,       # épaisseur (px)
	"xh_alpha": 95,      # opacité (%)
	"xh_outline": true,  # contour noir
	"xh_dynamic": true,  # s'écarte quand on bouge
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
	player_camo = cfg.get_value("player", "camo", player_camo)
	xp = cfg.get_value("player", "xp", xp)
	armory = cfg.get_value("player", "armory", {})
	weapon_kills = cfg.get_value("player", "weapon_kills", {})
	daily = cfg.get_value("player", "daily", {})
	# Ancien camouflage unique (v2.0) : appliqué à toutes les armes
	if armory.is_empty() and player_camo > 0:
		for wi in 10:
			armory[str(wi)] = {"skin": player_camo, "att": []}


func save_options() -> void:
	if "--no-save" in OS.get_cmdline_user_args():
		return  # lancements de test : ne pas toucher au profil du joueur
	var cfg := ConfigFile.new()
	for k in gfx:
		cfg.set_value("graphics", k, gfx[k])
	cfg.set_value("controls", "sensitivity", mouse_sensitivity)
	for a in bindings:
		cfg.set_value("keys", a, bindings[a])
	cfg.set_value("player", "class", player_class)
	cfg.set_value("player", "skin", player_skin)
	cfg.set_value("player", "camo", player_camo)
	cfg.set_value("player", "xp", xp)
	cfg.set_value("player", "armory", armory)
	cfg.set_value("player", "weapon_kills", weapon_kills)
	cfg.set_value("player", "daily", daily)
	cfg.save(CONFIG_PATH)


## Éliminations du joueur avec une arme.
func kills_with(wi: int) -> int:
	return int(weapon_kills.get(str(wi), 0))


## Compte une élimination avec une arme ; renvoie le skin débloqué à l'instant (ou -1).
func add_weapon_kill(wi: int) -> int:
	var n := kills_with(wi) + 1
	weapon_kills[str(wi)] = n
	save_options()
	for k in Data.CAMOS.size():
		if Data.skin_kills(k) == n:
			return k
	return -1


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
	var fx := clampi(int(gfx.get("fx", 2)), 0, 3)
	var adv := is_advanced()
	for sun in get_tree().get_nodes_in_group("gfx_sun"):
		# Ombres douces (rendu avancé) : plus floues loin de l'objet qui les projette
		sun.light_angular_distance = 0.6 if adv and fx >= 2 else 0.0
	for we in get_tree().get_nodes_in_group("gfx_env"):
		var env: Environment = we.environment
		var fog_on: bool = gfx.fog or we.get_meta("force_fog", false)
		env.fog_enabled = fog_on
		env.adjustment_enabled = true  # saturation de la carte + luminosité du joueur
		env.adjustment_brightness = float(gfx.brightness) / 100.0
		if we.get_meta("sky_ambient", false):
			# Le rendu standard donne une lumière ambiante du ciel trop bleue : on la mélange à un gris neutre
			env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY if adv else Environment.AMBIENT_SOURCE_BG
			env.ambient_light_sky_contribution = 1.0 if adv else 0.4
			env.ambient_light_color = Color(0.74, 0.73, 0.7)
			env.ambient_light_energy = 0.55 if adv else 0.8
		# Halo lumineux autour des lumières fortes (lampes, flammes, ciel)
		env.glow_enabled = fx >= 1
		env.glow_intensity = 0.55
		env.glow_bloom = 0.04
		env.glow_hdr_threshold = 1.0
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
		# Effets du rendu avancé (Forward+)
		env.ssao_enabled = adv and fx >= 1
		env.ssao_radius = 1.2
		env.ssao_intensity = 1.6
		env.ssil_enabled = adv and fx >= 2
		env.ssr_enabled = adv and fx >= 2
		env.ssr_max_steps = 48
		env.sdfgi_enabled = adv and fx >= 3 and not we.get_meta("indoor", false)
		var vf: float = we.get_meta("volfog", 0.0)
		env.volumetric_fog_enabled = adv and fx >= 3 and vf > 0.0 and fog_on
		env.volumetric_fog_density = vf
		env.volumetric_fog_albedo = we.get_meta("volfog_color", Color(0.8, 0.8, 0.85))
	graphics_changed.emit()


## Rendu avancé (Forward+) en cours ?
func is_advanced() -> bool:
	return RenderingServer.get_current_rendering_method() != "gl_compatibility"


## Choisit le moteur de rendu du prochain lancement (fichier override.cfg à côté du jeu).
## Si le PC ne gère pas le rendu avancé, Godot repasse tout seul en rendu standard.
func set_renderer(advanced: bool) -> bool:
	gfx["renderer"] = 1 if advanced else 0
	save_options()
	if "--no-save" in OS.get_cmdline_user_args():
		return true
	var path := ProjectSettings.globalize_path("res://override.cfg") if OS.has_feature("editor") \
		else OS.get_executable_path().get_base_dir().path_join("override.cfg")
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("rendering", "renderer/rendering_method", "forward_plus" if advanced else "gl_compatibility")
	cfg.set_value("rendering", "rendering_device/fallback_to_opengl3", true)
	return cfg.save(path) == OK


## Relance le jeu (après un changement de moteur de rendu).
func restart_game() -> void:
	OS.create_process(OS.get_executable_path(), OS.get_cmdline_args())
	get_tree().quit()


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
	players = {1: {"name": player_name, "team": 0, "skin": player_skin, "class": player_class, "armory": armory}}
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
	# Météo tirée au hasard et graine commune (éclairs, flaques) : identiques chez tous les joueurs
	settings["weather_now"] = randi_range(0, 4) if int(settings.get("weather", 0)) == 5 else int(settings.get("weather", 0))
	settings["weather_seed"] = randi()
	start_game.rpc(settings)


func end_match_to_lobby() -> void:
	if not multiplayer.is_server() or not in_game:
		return
	back_to_lobby.rpc()


@rpc("any_peer", "call_remote", "reliable")
func register_player(pname: String, skin: int, cls: int, arm: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	pname = pname.strip_edges().substr(0, 16)
	if pname == "":
		pname = "Joueur%d" % id
	players[id] = {"name": pname, "team": _smallest_team(), "skin": clampi(skin, 0, 99), "class": clampi(cls, 0, 99), "armory": arm}
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
	register_player.rpc_id(1, player_name, player_skin, player_class, armory)


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
	["chat", "Chat"], ["flashlight", "Lampe torche"], ["lean_left", "Pencher à gauche"], ["lean_right", "Pencher à droite"], ["interact", "Action (bombe)"], ["inspect", "Inspecter l'arme"], ["scoreboard", "Scores"],
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
	_keys("flashlight", [KEY_L])
	_keys("lean_left", [KEY_Q])
	_keys("lean_right", [KEY_E])
	_keys("ping", [KEY_X])
	_keys("interact", [KEY_F])
	_keys("inspect", [KEY_Y])
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
