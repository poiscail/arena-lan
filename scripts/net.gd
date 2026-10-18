extends Node
## Autoload "Net" : hébergement / connexion LAN, salon et paramètres de partie.

signal lobby_changed
signal game_started
signal game_ended
signal disconnected(reason: String)

const DEFAULT_PORT := 7777
const MAX_HUMANS := 12

var player_name := "Joueur"
var port := DEFAULT_PORT
var players := {}  # peer_id -> {"name": String, "team": int}
var settings := {
	"mode": "team",      # "team" (équipes) ou "ffa" (chacun pour soi)
	"slots": 3,          # équipes : joueurs par équipe (1-6) / ffa : combattants au total (2-12)
	"bots": true,        # compléter les places vides avec des bots
	"difficulty": 1,     # 0 facile, 1 normal, 2 difficile
	"score_limit": 30,
	"time_limit": 10,    # minutes
}
var in_game := false
var mouse_sensitivity := 0.0025


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_setup_inputs()


func host(p_port: int) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(p_port, MAX_HUMANS - 1) != OK:
		return "Impossible d'héberger sur le port %d (déjà utilisé ?)." % p_port
	multiplayer.multiplayer_peer = peer
	port = p_port
	players = {1: {"name": player_name, "team": 0}}
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
func register_player(pname: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	pname = pname.strip_edges().substr(0, 16)
	if pname == "":
		pname = "Joueur%d" % id
	players[id] = {"name": pname, "team": _smallest_team()}
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
	register_player.rpc_id(1, player_name)


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


# --- Touches (positions physiques : ZQSD en AZERTY, WASD en QWERTY) ---------

func _setup_inputs() -> void:
	_keys("move_forward", [KEY_W, KEY_UP])
	_keys("move_back", [KEY_S, KEY_DOWN])
	_keys("move_left", [KEY_A, KEY_LEFT])
	_keys("move_right", [KEY_D, KEY_RIGHT])
	_keys("jump", [KEY_SPACE])
	_keys("sprint", [KEY_SHIFT])
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
