extends Node
## Écran principal : menu, salon d'attente, puis lancement de la partie.

const GameScript := preload("res://scripts/game.gd")
const Data := preload("res://scripts/data.gd")

var game: Node = null

var _ui: Control
var _menu: VBoxContainer
var _lobby: VBoxContainer
var _status: Label
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _port_spin: SpinBox
var _address: Label
var _players: RichTextLabel
var _mode: OptionButton
var _slots_label: Label
var _slots: SpinBox
var _bots: CheckBox
var _difficulty: OptionButton
var _score: SpinBox
var _time: SpinBox
var _team_btn: Button
var _start_btn: Button
var _updating := false


func _ready() -> void:
	Net.lobby_changed.connect(_on_lobby_changed)
	Net.game_started.connect(_on_game_started)
	Net.game_ended.connect(_on_game_ended)
	Net.disconnected.connect(_on_disconnected)
	_build_ui()
	_show_menu("")
	_apply_cmdline()


# --- Construction de l'interface ----------------------------------------------

func _build_ui() -> void:
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_ui)

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.14, 0.19)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	panel.add_child(stack)

	var title := _label("ARENA LAN", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)

	# Menu principal
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 10)
	stack.add_child(_menu)

	_menu.add_child(_label("Pseudo", 16))
	_name_edit = LineEdit.new()
	_name_edit.max_length = 16
	_name_edit.text = "Joueur%d" % randi_range(10, 99)
	_menu.add_child(_name_edit)

	var port_row := HBoxContainer.new()
	port_row.add_theme_constant_override("separation", 10)
	port_row.add_child(_label("Port", 16))
	_port_spin = SpinBox.new()
	_port_spin.min_value = 1024
	_port_spin.max_value = 65535
	_port_spin.value = Net.DEFAULT_PORT
	port_row.add_child(_port_spin)
	_menu.add_child(port_row)

	_menu.add_child(_button("Héberger une partie", _on_host_pressed))
	_menu.add_child(HSeparator.new())
	_menu.add_child(_label("Rejoindre : adresse IP de l'hôte", 16))

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.placeholder_text = "ex : 192.168.1.20"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_ip_edit)
	join_row.add_child(_button("Rejoindre", _on_join_pressed))
	_menu.add_child(join_row)

	var help := _label("ZQSD : bouger    Souris : viser    Clic gauche : tirer    Clic droit : zoom (sniper)\nEspace : sauter    Maj : sprint    R : recharger    1 / 2 / 3 ou molette : armes\nTab : scores    Échap : pause", 14)
	help.modulate = Color(0.7, 0.72, 0.8)
	_menu.add_child(help)

	# Salon
	_lobby = VBoxContainer.new()
	_lobby.add_theme_constant_override("separation", 12)
	stack.add_child(_lobby)

	_address = _label("", 16)
	_address.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby.add_child(_address)

	_players = RichTextLabel.new()
	_players.bbcode_enabled = true
	_players.fit_content = true
	_players.scroll_active = false
	_players.custom_minimum_size = Vector2(0, 80)
	_players.add_theme_font_size_override("normal_font_size", 18)
	_players.add_theme_font_size_override("bold_font_size", 18)
	_lobby.add_child(_players)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	_lobby.add_child(grid)

	_mode = OptionButton.new()
	_mode.add_item("Équipes")
	_mode.add_item("Chacun pour soi")
	_mode.item_selected.connect(_on_mode_changed)
	_add_row(grid, "Mode", _mode)

	_slots = _spin(1, 6)
	_slots_label = _add_row(grid, "Joueurs par équipe", _slots)

	_bots = CheckBox.new()
	_bots.text = "Compléter avec des bots"
	_bots.toggled.connect(func(_on: bool) -> void: _on_setting_changed(0))
	_add_row(grid, "Bots", _bots)

	_difficulty = OptionButton.new()
	_difficulty.add_item("Facile")
	_difficulty.add_item("Normal")
	_difficulty.add_item("Difficile")
	_difficulty.item_selected.connect(_on_setting_changed)
	_add_row(grid, "Difficulté des bots", _difficulty)

	_score = _spin(5, 200)
	_add_row(grid, "Score à atteindre", _score)
	_time = _spin(1, 60)
	_add_row(grid, "Durée (minutes)", _time)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	_team_btn = _button("Changer d'équipe", Net.request_team_change)
	_start_btn = _button("Lancer la partie", Net.start_match)
	buttons.add_child(_team_btn)
	buttons.add_child(_start_btn)
	buttons.add_child(_button("Quitter", Net.quit_to_menu))
	_lobby.add_child(buttons)

	_status = _label("", 16)
	_status.modulate = Color(1, 0.65, 0.55)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_status)


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 38
	b.pressed.connect(callback)
	return b


func _spin(min_v: int, max_v: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = 1
	s.rounded = true
	s.value_changed.connect(_on_setting_changed)
	return s


func _add_row(grid: GridContainer, text: String, control: Control) -> Label:
	var l := _label(text, 16)
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)
	return l


# --- Écrans ---------------------------------------------------------------------

func _show_menu(message: String) -> void:
	_ui.show()
	_menu.visible = true
	_lobby.visible = false
	_status.text = message
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _show_lobby() -> void:
	_ui.show()
	_menu.visible = false
	_lobby.visible = true
	_status.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_lobby()


func _refresh_lobby() -> void:
	_updating = true
	var s := Net.settings
	var is_host := multiplayer.is_server()
	var team: bool = s.mode == "team"
	_mode.select(0 if team else 1)
	_slots_label.text = "Joueurs par équipe" if team else "Combattants au total"
	_slots.min_value = 1 if team else 2
	_slots.max_value = 6 if team else 12
	_slots.set_value_no_signal(s.slots)
	_bots.set_pressed_no_signal(s.bots)
	_difficulty.select(s.difficulty)
	_score.set_value_no_signal(s.score_limit)
	_time.set_value_no_signal(s.time_limit)
	_mode.disabled = not is_host
	_difficulty.disabled = not is_host
	_bots.disabled = not is_host
	_slots.editable = is_host
	_score.editable = is_host
	_time.editable = is_host
	_start_btn.visible = is_host
	_team_btn.visible = team
	_players.text = _players_text()
	if is_host:
		var ips := Net.local_ips()
		var where := " ou ".join(ips) if ips.size() > 0 else "ton adresse IP locale"
		_address.text = "Tu héberges. Les autres joueurs doivent rejoindre :  %s   (port %d)" % [where, Net.port]
	else:
		_address.text = "Connecté au salon. En attente du lancement par l'hôte..."
	_updating = false


func _players_text() -> String:
	var s := Net.settings
	var txt := ""
	if s.mode == "team":
		for t in 2:
			var names := PackedStringArray()
			for id in Net.players:
				if Net.players[id]["team"] == t:
					names.append(Data.esc(Net.players[id]["name"]))
			var bots := maxi(0, int(s.slots) - names.size()) if s.bots else 0
			txt += "[color=%s][b]%s[/b][/color] : %s" % [Data.TEAM_HEX[t], Data.TEAM_NAMES[t], ", ".join(names) if names.size() > 0 else "personne"]
			if bots > 0:
				txt += "   [color=#999999](+%d bot%s)[/color]" % [bots, "s" if bots > 1 else ""]
			txt += "\n"
	else:
		var names := PackedStringArray()
		for id in Net.players:
			names.append(Data.esc(Net.players[id]["name"]))
		var bots := maxi(0, int(s.slots) - names.size()) if s.bots else 0
		txt = "[b]Joueurs[/b] : %s" % ", ".join(names)
		if bots > 0:
			txt += "   [color=#999999](+%d bot%s)[/color]" % [bots, "s" if bots > 1 else ""]
	return txt


# --- Actions --------------------------------------------------------------------

func _clean_name() -> String:
	var n := _name_edit.text.strip_edges()
	return n if n != "" else "Joueur"


func _on_host_pressed() -> void:
	Net.player_name = _clean_name()
	var err := Net.host(int(_port_spin.value))
	if err != "":
		_status.text = err
		return
	_show_lobby()


func _on_join_pressed() -> void:
	Net.player_name = _clean_name()
	var ip := _ip_edit.text.strip_edges()
	var err := Net.join(ip, int(_port_spin.value))
	if err != "":
		_status.text = err
		return
	_status.text = "Connexion à %s..." % ip


func _on_mode_changed(index: int) -> void:
	if _updating or not multiplayer.is_server():
		return
	var s := Net.settings.duplicate()
	s["mode"] = "team" if index == 0 else "ffa"
	s["slots"] = 3 if index == 0 else 6
	s["score_limit"] = 30 if index == 0 else 20
	Net.set_settings(s)


func _on_setting_changed(_value) -> void:
	if _updating or not multiplayer.is_server():
		return
	var s := Net.settings.duplicate()
	s["slots"] = int(_slots.value)
	s["bots"] = _bots.button_pressed
	s["difficulty"] = _difficulty.selected
	s["score_limit"] = int(_score.value)
	s["time_limit"] = int(_time.value)
	Net.set_settings(s)


func _on_lobby_changed() -> void:
	if game != null:
		return
	if not Net.players.has(multiplayer.get_unique_id()):
		return
	if _lobby.visible:
		_refresh_lobby()
	else:
		_show_lobby()


func _on_game_started() -> void:
	_remove_game()
	_ui.hide()
	game = GameScript.new()
	game.name = "Game"
	add_child(game)


func _on_game_ended() -> void:
	_remove_game()
	if Net.players.has(multiplayer.get_unique_id()):
		_show_lobby()
	else:
		_show_menu("")


func _on_disconnected(reason: String) -> void:
	_remove_game()
	_show_menu(reason)


func _remove_game() -> void:
	if game != null:
		remove_child(game)
		game.queue_free()
		game = null


# --- Options de ligne de commande (tests automatiques) --------------------------
# Exemple : Godot --path . -- --host --start --mode=ffa --slots=8 --quit-after=20

func _apply_cmdline() -> void:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		var parts := a.trim_prefix("--").split("=", true, 1)
		opts[parts[0]] = parts[1] if parts.size() > 1 else ""
	if opts.has("name"):
		_name_edit.text = opts["name"]
	if opts.has("host"):
		_on_host_pressed()
		var s := Net.settings.duplicate()
		if opts.has("mode"):
			s["mode"] = opts["mode"]
		if opts.has("slots"):
			s["slots"] = int(opts["slots"])
		if opts.has("difficulty"):
			s["difficulty"] = int(opts["difficulty"])
		if opts.has("time"):
			s["time_limit"] = int(opts["time"])
		if opts.has("score"):
			s["score_limit"] = int(opts["score"])
		Net.set_settings(s)
		if opts.has("start"):
			var delay: float = float(opts["start"]) if opts["start"] != "" else 0.5
			get_tree().create_timer(delay).timeout.connect(Net.start_match)
	elif opts.has("join"):
		_ip_edit.text = opts["join"]
		_on_join_pressed()
	if opts.has("quit-after"):
		get_tree().create_timer(float(opts["quit-after"])).timeout.connect(_quit.bind(opts.get("screenshot", "")))


func _quit(screenshot: String) -> void:
	if screenshot != "":
		var img := get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(screenshot)
	get_tree().quit()
