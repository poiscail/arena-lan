extends Node
## Écran principal : menu, salon d'attente, puis lancement de la partie.

const GameScript := preload("res://scripts/game.gd")
const Data := preload("res://scripts/data.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
const MenuBgScript := preload("res://scripts/menu_bg.gd")
const OptionsScript := preload("res://scripts/options.gd")
const ArmoryScript := preload("res://scripts/armory.gd")
const LoadoutScript := preload("res://scripts/loadout.gd")

var game: Node = null
var _background: Node3D = null

var _ui: Control
var _menu: VBoxContainer
var _lobby: VBoxContainer
var _status: Label
var _name_edit: LineEdit
var _skin_opt: OptionButton
var _class_opt: OptionButton
var _class_desc: Label
var _armory: Control
var _loadout: Control
var _level_label: Label
var _level_bar: ProgressBar
var _games_box: VBoxContainer
var _ip_edit: LineEdit
var _port_spin: SpinBox
var _address: Label
var _players: RichTextLabel
var _mode: OptionButton
var _map_opt: OptionButton
var _rules_opt: OptionButton
var _rules_desc: Label
var _slots_label: Label
var _slots: SpinBox
var _bots: CheckBox
var _advmove: CheckBox
var _difficulty: OptionButton
var _score: SpinBox
var _time: SpinBox
var _team_btn: Button
var _start_btn: Button
var _updating := false
var _options: Control


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
	get_tree().root.theme = UiTheme.make_theme()
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_ui)

	# Dégradé sombre à gauche pour la lisibilité, la scène 3D reste visible à droite
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.03, 0.06, 0.92))
	grad.set_color(1, Color(0.02, 0.03, 0.06, 0.0))
	grad.add_point(0.45, Color(0.02, 0.03, 0.06, 0.75))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(1, 0)
	shade.texture = gtex
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)

	var scroll := ScrollContainer.new()
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 56
	scroll.offset_top = 36
	scroll.offset_right = 56 + 600
	scroll.offset_bottom = -20
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ui.add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)

	var title := Label.new()
	title.text = "ARENA"
	title.add_theme_font_override("font", UiTheme.font_title())
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color.WHITE)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "L A N   ·   F P S   M U L T I J O U E U R"
	subtitle.add_theme_font_override("font", UiTheme.font_bold())
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", UiTheme.ACCENT)
	column.add_child(subtitle)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 10
	column.add_child(spacer)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.accent_panel(Color(0.04, 0.06, 0.1, 0.82), UiTheme.ACCENT, 24))
	column.add_child(panel)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	panel.add_child(stack)

	var credits := Label.new()
	credits.text = "Modèles et sons : Quaternius, Kenney, Free Firearm Sound Library (CC0)  ·  Ciel et textures : Poly Haven (CC0)  ·  Polices : Rajdhani, Orbitron (OFL)"
	credits.add_theme_font_size_override("font_size", 14)
	credits.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	credits.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	credits.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	credits.grow_vertical = Control.GROW_DIRECTION_BEGIN
	credits.offset_left = -700
	credits.offset_top = -34
	credits.offset_right = -16
	credits.offset_bottom = -10
	_ui.add_child(credits)

	# Menu principal
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 10)
	stack.add_child(_menu)

	_level_label = _label("", 16)
	_level_label.add_theme_font_override("font", UiTheme.font_bold())
	_level_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	_menu.add_child(_level_label)
	_level_bar = ProgressBar.new()
	_level_bar.show_percentage = false
	_level_bar.custom_minimum_size = Vector2(0, 6)
	_menu.add_child(_level_bar)
	_menu.add_child(_section("PSEUDO"))
	_name_edit = LineEdit.new()
	_name_edit.max_length = 16
	_name_edit.text = "Joueur%d" % randi_range(10, 99)
	_menu.add_child(_name_edit)

	_menu.add_child(_section("SKIN"))
	_skin_opt = OptionButton.new()
	for s in Data.SKINS:
		_skin_opt.add_item(s["name"])
	_skin_opt.item_selected.connect(_on_skin_selected)
	_menu.add_child(_skin_opt)
	_skin_opt.select(Net.player_skin)

	_menu.add_child(_section("CLASSE"))
	_class_opt = OptionButton.new()
	for cl in Data.CLASSES:
		_class_opt.add_item(cl["name"])
	_class_opt.select(Net.player_class)
	_class_opt.item_selected.connect(_on_class_selected)
	_menu.add_child(_class_opt)
	_class_desc = _label(Data.class_text(Net.player_class, Net.armory), 15)
	_class_desc.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_menu.add_child(_class_desc)

	_menu.add_child(_button("Classes et armes : choisir les armes 1, 2 et 3", func() -> void: _loadout.open()))
	_menu.add_child(_button("Armurerie : skins et accessoires des armes", func() -> void: _armory.open()))
	_refresh_profile()

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
	_menu.add_child(_section("REJOINDRE  ·  ADRESSE IP DE L'HÔTE"))

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.placeholder_text = "ex : 192.168.1.20"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_ip_edit)
	join_row.add_child(_button("Rejoindre", _on_join_pressed))
	_menu.add_child(join_row)

	_menu.add_child(_section("PARTIES TROUVÉES SUR LE RÉSEAU"))
	_games_box = VBoxContainer.new()
	_games_box.add_theme_constant_override("separation", 6)
	_menu.add_child(_games_box)
	Net.games_changed.connect(_refresh_games)
	var games_timer := Timer.new()
	games_timer.wait_time = 1.0
	games_timer.autostart = true
	games_timer.timeout.connect(_refresh_games)
	add_child(games_timer)
	_refresh_games()

	_menu.add_child(HSeparator.new())
	_menu.add_child(_button("Options (graphismes, souris)", func() -> void: _options.open()))
	_menu.add_child(HSeparator.new())
	var help := _label("ZQSD : bouger   ·   Souris : viser   ·   Clic gauche : tirer   ·   Clic droit : zoom\nEspace : sauter   ·   Maj : sprint   ·   Ctrl : glisser   ·   R : recharger   ·   1/2/3 ou molette : armes\nA / E : se pencher   ·   G : grenade   ·   H : fumigène   ·   V : couteau   ·   L : lampe   ·   T : chat   ·   X ou clic molette : signaler
Tab : scores   ·   Échap : pause   ·   Touches modifiables dans Options", 15)
	help.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
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

	_rules_opt = OptionButton.new()
	for r in Data.RULE_ORDER:
		_rules_opt.add_item(Data.RULES[r]["name"])
	_rules_opt.item_selected.connect(_on_rules_changed)
	_add_row(grid, "Jeu", _rules_opt)

	_map_opt = OptionButton.new()
	for m in Data.MAPS:
		_map_opt.add_item(m)
	_map_opt.item_selected.connect(_on_setting_changed)
	_add_row(grid, "Carte", _map_opt)

	_slots = _spin(1, 6)
	_slots_label = _add_row(grid, "Joueurs par équipe", _slots)

	_bots = CheckBox.new()
	_bots.text = "Compléter avec des bots"
	_bots.toggled.connect(func(_on: bool) -> void: _on_setting_changed(0))
	_add_row(grid, "Bots", _bots)

	_advmove = CheckBox.new()
	_advmove.text = "Double saut et course sur les murs"
	_advmove.toggled.connect(func(_on: bool) -> void: _on_setting_changed(0))
	_add_row(grid, "Mouvements", _advmove)

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
	_rules_desc = _label("", 15)
	_rules_desc.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_rules_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby.add_child(_rules_desc)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	_team_btn = _button("Changer d'équipe", Net.request_team_change)
	_start_btn = _button("Lancer la partie", Net.start_match)
	buttons.add_child(_team_btn)
	buttons.add_child(_start_btn)
	buttons.add_child(_button("Quitter", Net.quit_to_menu))
	_lobby.add_child(buttons)

	_status = _label("", 17)
	_status.add_theme_color_override("font_color", Color(1, 0.62, 0.5))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_status)

	_loadout = LoadoutScript.new()
	_loadout.visible = false
	_loadout.changed.connect(func() -> void:
		_class_opt.select(Net.player_class)
		_on_class_selected(Net.player_class))
	_loadout.open_armory.connect(func(wi: int) -> void:
		_armory._wi = wi
		_armory.open())
	_ui.add_child(_loadout)
	_armory = ArmoryScript.new()
	_armory.visible = false
	_armory.closed.connect(func() -> void:
		_class_desc.text = Data.class_text(Net.player_class, Net.armory)
		if _loadout.visible:
			_loadout.open()
		if _background != null:
			_background.show_class(Net.player_class))
	_ui.add_child(_armory)
	_options = OptionsScript.new()
	_options.visible = false
	_ui.add_child(_options)


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.font_bold())
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", UiTheme.ACCENT)
	return l


func _set_background(on: bool) -> void:
	if on and _background == null:
		_background = MenuBgScript.new()
		add_child(_background)
		move_child(_background, 0)
	elif not on and _background != null:
		remove_child(_background)
		_background.queue_free()
		_background = null


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

## Liste des parties annoncées sur le réseau local, avec un bouton pour rejoindre.
func _refresh_games() -> void:
	if _games_box == null or not _menu.visible:
		return
	for ch in _games_box.get_children():
		ch.queue_free()
	if Net.found_games.is_empty():
		var l := _label("Recherche en cours... (ou tape l'adresse IP ci-dessus)", 15)
		l.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		_games_box.add_child(l)
		return
	for ip in Net.found_games:
		var g: Dictionary = Net.found_games[ip]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var mode := "Équipes" if g.get("mode", "team") == "team" else "Chacun pour soi"
		var map_name: String = Data.MAPS[clampi(int(g.get("map", 0)), 0, Data.MAPS.size() - 1)]
		var state := "en cours" if g.get("in_game", false) else "salon"
		var l := _label("%s  ·  %s  ·  %s  ·  %d joueur(s)  ·  %s" % [String(g.get("name", "?")), map_name, mode, int(g.get("players", 0)), state], 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		var port := int(g.get("port", Net.DEFAULT_PORT))
		row.add_child(_button("Rejoindre", func() -> void:
			_ip_edit.text = ip
			_port_spin.value = port
			_on_join_pressed()))
		_games_box.add_child(row)


func _show_menu(message: String) -> void:
	_set_background(true)
	_ui.show()
	_menu.visible = true
	Net.start_discovery()
	if _level_label != null:
		_refresh_profile()
	_lobby.visible = false
	_status.text = message
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _show_lobby() -> void:
	_set_background(true)
	_ui.show()
	_menu.visible = false
	Net.stop_discovery()
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
	_map_opt.select(int(s.get("map", 0)))
	var rules: String = s.get("rules", "dm")
	_rules_opt.select(maxi(0, Data.RULE_ORDER.find(rules)))
	_rules_desc.text = Data.RULES[rules]["desc"]
	var fixed_limit: int = Data.RULES[rules]["limit"]
	_slots_label.text = "Joueurs par équipe" if team else "Combattants au total"
	_slots.min_value = 1 if team else 2
	_slots.max_value = 6 if team else 12
	_slots.set_value_no_signal(s.slots)
	_bots.set_pressed_no_signal(s.bots)
	_advmove.set_pressed_no_signal(bool(s.get("advmove", false)))
	_advmove.disabled = not multiplayer.is_server()
	_difficulty.select(s.difficulty)
	_score.set_value_no_signal(fixed_limit if fixed_limit > 0 else s.score_limit)
	_time.set_value_no_signal(s.time_limit)
	_mode.disabled = not is_host
	_map_opt.disabled = not is_host
	_rules_opt.disabled = not is_host
	_difficulty.disabled = not is_host
	_bots.disabled = not is_host
	_slots.editable = is_host
	_score.editable = is_host and fixed_limit == 0
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


func _on_skin_selected(index: int) -> void:
	Net.player_skin = index
	Net.save_options()
	if _background != null:
		_background.show_skin(index)


## Niveau, barre d'expérience et camouflages débloqués.
func _refresh_profile() -> void:
	var info := Data.level_info(Net.xp)
	_level_label.text = "NIVEAU %d   ·   %d / %d XP" % [info[0], info[1], info[2]]
	_level_bar.max_value = info[2]
	_level_bar.value = info[1]


func _on_class_selected(index: int) -> void:
	Net.player_class = index
	Net.save_options()
	_class_desc.text = Data.class_text(index, Net.armory)
	if _background != null:
		_background.show_class(index)


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
	if index == 1 and Data.RULES[s.get("rules", "dm")]["teams"]:
		s["rules"] = "dm"
	if index == 0 and Data.RULES[s.get("rules", "dm")].get("ffa", false):
		s["rules"] = "dm"
	Net.set_settings(s)


func _on_rules_changed(index: int) -> void:
	if _updating or not multiplayer.is_server():
		return
	var s := Net.settings.duplicate()
	s["rules"] = Data.RULE_ORDER[index]
	if Data.RULES[s["rules"]]["teams"] and s["mode"] != "team":
		s["mode"] = "team"
		s["slots"] = 3
	elif Data.RULES[s["rules"]].get("ffa", false) and s["mode"] == "team":
		s["mode"] = "ffa"  # chacun pour soi uniquement (Battle Royale)
		s["slots"] = 8
	Net.set_settings(s)


func _on_setting_changed(_value) -> void:
	if _updating or not multiplayer.is_server():
		return
	var s := Net.settings.duplicate()
	s["slots"] = int(_slots.value)
	s["bots"] = _bots.button_pressed
	s["advmove"] = _advmove.button_pressed
	s["difficulty"] = _difficulty.selected
	if int(Data.RULES[s.get("rules", "dm")]["limit"]) == 0:
		s["score_limit"] = int(_score.value)
	s["time_limit"] = int(_time.value)
	s["map"] = _map_opt.selected
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
	_set_background(false)
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
	if opts.has("port"):
		_port_spin.value = int(opts["port"])
	if opts.has("name"):
		_name_edit.text = opts["name"]
	if opts.has("camo"):
		var atts: Array = Array(String(opts.get("att", "")).split(",", false))
		for wi in Data.WEAPONS.size():
			Net.armory[str(wi)] = {"skin": int(opts["camo"]), "att": atts}
		if _background != null:
			_background.show_class(Net.player_class)
	if opts.has("class"):
		_class_opt.select(int(opts["class"]))
		_on_class_selected(int(opts["class"]))
	if opts.has("skin"):
		_skin_opt.select(int(opts["skin"]))
		_on_skin_selected(int(opts["skin"]))
	if opts.has("host"):
		_on_host_pressed()
		var s := Net.settings.duplicate()
		if opts.has("mode"):
			s["mode"] = opts["mode"]
		if opts.has("slots"):
			s["slots"] = int(opts["slots"])
		if opts.has("difficulty"):
			s["difficulty"] = int(opts["difficulty"])
		if opts.has("advmove"):
			s["advmove"] = true
		if opts.has("rules"):
			s["rules"] = opts["rules"]
		if opts.has("map"):
			s["map"] = int(opts["map"])
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
	if opts.has("weapons"):
		var ws := []
		for s in String(opts["weapons"]).split(",", false):
			ws.append(int(s))
		Net.armory["loadouts"] = {str(Net.player_class): ws}
		_on_class_selected(Net.player_class)
	if opts.has("wkills"):
		# Test : éliminations déjà faites avec des armes (« 0:37,26:5 »)
		for pair in String(opts["wkills"]).split(",", false):
			var kv := pair.split(":")
			Net.weapon_kills[kv[0]] = int(kv[1])
	if opts.has("kill-bot"):
		# Test : le joueur local élimine un bot ennemi avec son arme actuelle
		get_tree().create_timer(float(opts["kill-bot"])).timeout.connect(func() -> void:
			for id in game.chars:
				var b = game.chars[id]
				if b.is_bot and b.alive and game.is_enemy(game.local_char, b):
					game._deal_damage(game.local_char, {id: 500.0}, game.local_char.weapon)
					break)
	if opts.has("zbuy"):
		# Test zombies : 5000 points, le joueur va au poste n° zbuy et achète
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			var c = game.local_char
			var s: Dictionary = game.modes.shops[int(opts["zbuy"])]
			game.scores[c.char_id]["money"] = 5000
			c.position = s["pos"] + Vector3(1.5, 0.1, 0)
			c.look_at(s["pos"] + Vector3(0, 1.6, 0) - Vector3(0, 0, 0), Vector3.UP)
			c.rotation.x = 0
			c.rotation.z = 0
			game.modes._buy(c, s["item"]))
	if opts.has("drive"):
		# Test véhicules : le joueur monte dans le premier véhicule et accélère ; un bot ennemi est placé devant
		get_tree().create_timer(float(opts["drive"])).timeout.connect(func() -> void:
			var c = game.local_char
			var ids: Array = game.vehicles.vehicles.keys()
			if ids.is_empty():
				print("[test] aucun véhicule")
				return
			var body: Node3D = game.vehicles.vehicles[ids[0]]["body"]
			c.position = body.position + body.global_transform.basis.x * 2.0
			await get_tree().create_timer(0.5).timeout  # le temps que l'hôte reçoive la nouvelle position
			game.vehicles._request(ids[0], true)
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			Input.action_press("move_forward")
			if opts.has("ram"):
				for id in game.chars:
					var b = game.chars[id]
					if b.is_bot and b.alive and game.is_enemy(c, b):
						b.position = body.position - body.global_transform.basis.z * 9.0
						break)
	if opts.has("print-veh"):
		get_tree().create_timer(float(opts["print-veh"])).timeout.connect(func() -> void:
			for id in game.vehicles.vehicles:
				var v: Dictionary = game.vehicles.vehicles[id]
				print("[test] %s conducteur=%s pos=%s" % [id, v["driver"], (v["body"] as Node3D).position.snapped(Vector3.ONE * 0.1)]))
	if opts.has("break"):
		# Test destruction : face à l'objet n° « break », on casse deux morceaux puis (option) tout
		var bi := int(opts["break"])
		get_tree().create_timer(2.5).timeout.connect(func() -> void:
			var b: Dictionary = game.items._breakables[bi]
			var c = game.local_char
			var node: Node3D = b["node"]
			c.position = b["pos"] + node.global_transform.basis.z * 5.0
			c.look_at(Vector3(b["pos"].x, c.position.y, b["pos"].z), Vector3.UP)
			c.head.rotation.x = -0.15
			print("[test] objet %s" % b["kind"]))
		get_tree().create_timer(3.4).timeout.connect(func() -> void:
			var b: Dictionary = game.items._breakables[bi]
			for k in mini(2, b["hp"].size()):
				game.items._damage_piece(bi, k, 999.0, b["pos"] + Vector3(0, 0.8, 0))
			print("[test] morceaux restants : ", b["hp"]))
	if opts.has("djump"):
		# Test double saut : deux appuis sur saut, on mesure la hauteur maximale
		get_tree().create_timer(2.5).timeout.connect(func() -> void:
			var c = game.local_char
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			var y0: float = c.position.y
			var top := y0
			Input.action_press("jump")
			await get_tree().create_timer(0.1).timeout
			Input.action_release("jump")
			await get_tree().create_timer(0.3).timeout
			Input.action_press("jump")
			await get_tree().create_timer(0.1).timeout
			Input.action_release("jump")
			for i in 30:
				await get_tree().physics_frame
				top = maxf(top, c.position.y)
			for i in 30:
				await get_tree().physics_frame
				top = maxf(top, c.position.y)
			print("[test] hauteur max du saut : %.2f m" % (top - y0)))
	if opts.has("pen"):
		# Test pénétration : un bot derrière une barricade (planches entières) ou une vitre, on tire à travers
		get_tree().create_timer(2.5).timeout.connect(func() -> void:
			var kind: String = opts["pen"] if opts["pen"] != "" else "planks"
			var b: Dictionary = {}
			for x in game.items._breakables:
				if x["kind"] == kind:
					b = x
					break
			var node: Node3D = b["node"]
			var n: Vector3 = node.global_transform.basis.z
			var me = game.local_char
			var target = null
			for id in game.chars:
				if game.chars[id].is_bot and game.is_enemy(me, game.chars[id]):
					target = game.chars[id]
					break
			me.position = b["pos"] + n * 3.0
			target.position = b["pos"] - n * 1.5
			target.bot = null  # le bot ne bouge plus
			target._net_pos = target.position
			await get_tree().physics_frame
			await get_tree().physics_frame
			var dir: Vector3 = (target.position + Vector3(0, 0.6, 0) - me.eye_position()).normalized()
			var hp_before: int = target.hp
			game._server_shoot(me.char_id, me.weapon, me.eye_position(), PackedVector3Array([dir]))
			var w: Dictionary = me.wstats(me.weapon)
			print("[test] %s à travers %s : %d dégâts (normal %d)" % [Data.WEAPONS[me.weapon].name, kind, hp_before - target.hp, int(w.damage)]))
	if opts.has("wallrun"):
		# Test course sur un mur : on court le long du bord de la carte et on saute
		get_tree().create_timer(2.5).timeout.connect(func() -> void:
			var c = game.local_char
			c.position = Vector3(29.4, 0.1, 10.0)
			c.rotation.y = 0.0  # regarde vers -Z, le mur du bord est à droite
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			Input.action_press("move_forward")
			Input.action_press("sprint")
			await get_tree().create_timer(0.6).timeout
			Input.action_press("jump")
			await get_tree().create_timer(0.1).timeout
			Input.action_release("jump")
			var best := 0.0
			var air := 0
			for i in 120:
				await get_tree().physics_frame
				best = maxf(best, c._wallrun_t)
				if not c.is_on_floor():
					air += 1
			Input.action_release("move_forward")
			Input.action_release("sprint")
			print("[test] course sur le mur : %.2f s, %.2f s en l'air" % [best, air / 60.0]))
	if opts.has("mantle"):
		# Test escalade : face à la caisse destructible n° « mantle », on avance et on saute
		get_tree().create_timer(2.5).timeout.connect(func() -> void:
			var c = game.local_char
			var target := Vector3.ZERO
			var n := 0
			for b in game.items._breakables:
				if b["kind"] == "crate":
					if n == int(opts["mantle"]):
						target = b["pos"]
					n += 1
			var away := Vector3(0, 0, 1.6)
			c.position = target + away
			c.look_at(Vector3(target.x, c.position.y, target.z), Vector3.UP)
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			Input.action_press("move_forward")
			await get_tree().create_timer(0.3).timeout
			Input.action_press("jump")
			await get_tree().create_timer(0.15).timeout
			Input.action_release("jump")
			await get_tree().create_timer(0.35).timeout
			Input.action_release("move_forward")
			await get_tree().create_timer(0.3).timeout
			print("[test] hauteur après escalade : %.2f (caisse 1,1 m)" % c.position.y))
	if opts.has("slot"):
		get_tree().create_timer(2.0).timeout.connect(func() -> void: game.local_char.switch_weapon(int(opts["slot"])))
	if opts.has("loadout"):
		_loadout.open()
	if opts.has("ingame-loadout"):
		get_tree().create_timer(float(opts["ingame-loadout"])).timeout.connect(func() -> void:
			game.hud.toggle_pause()
			game.hud._loadout.open())
	if opts.has("set-weapons"):
		# En partie : change les armes de la classe (appliquées à la prochaine apparition)
		get_tree().create_timer(float(opts.get("set-at", "2"))).timeout.connect(func() -> void:
			var ws := []
			for s in String(opts["set-weapons"]).split(",", false):
				ws.append(int(s))
			Net.armory["loadouts"] = {str(Net.player_class): ws}
			game.send_armory(Net.armory))
	if opts.has("kill-humans"):
		# Hôte : élimine tous les joueurs humains (pour tester leur réapparition)
		get_tree().create_timer(float(opts["kill-humans"])).timeout.connect(func() -> void:
			for id in game.chars.keys():
				var c = game.chars[id]
				if not c.is_bot and c.alive:
					game._deal_damage(c, {c.char_id: 500.0}, 0))
	if opts.has("inspect"):
		get_tree().create_timer(float(opts["inspect"])).timeout.connect(func() -> void: game.local_char.start_inspect())
	if opts.has("killed-by"):
		# Hôte, test kill-cam : un bot ennemi se place devant le joueur, tire 3 fois et l'élimine
		get_tree().create_timer(float(opts["killed-by"])).timeout.connect(func() -> void:
			var me = game.local_char
			for id in game.chars:
				var b = game.chars[id]
				if b.is_bot and b.alive and game.is_enemy(me, b):
					b.bot = null
					var fwd: Vector3 = -me.global_transform.basis.z
					b.position = me.position + fwd * 9.0 + Vector3(2, 0, 0)
					b._net_pos = b.position
					b.look_at(me.global_position, Vector3.UP)
					b.rotation.x = 0.0
					b.rotation.z = 0.0
					for i in 3:
						get_tree().create_timer(0.5 + i * 0.35).timeout.connect(func() -> void:
							b.position += Vector3(-0.5, 0, 0)
							b._net_pos = b.position
							b.look_at(me.global_position, Vector3.UP)
							b.rotation.x = 0.0
							b.rotation.z = 0.0
							game._broadcast("shot_fx", [b.char_id, b.weapon, PackedVector3Array([me.eye_position()])])
							if i == 2:
								game._deal_damage(b, {me.char_id: 500.0}, b.weapon))
					get_tree().create_timer(2.6).timeout.connect(func() -> void:
						print("[test] killcam actif=", game.killcam.active, " tueur=", b.display_name, " cam=", game.killcam.cam.current))
					break)
	if opts.has("print-loadout"):
		get_tree().create_timer(float(opts["print-loadout"])).timeout.connect(func() -> void:
			for id in game.chars:
				var c = game.chars[id]
				if not c.is_bot:
					print("[test] ", c.display_name, " armes : ", c.loadout, " alive=", c.alive))
	if opts.has("armory"):
		_armory._wi = int(opts["armory"]) if opts["armory"] != "" else 0
		_armory.open()
	if opts.has("options"):
		_options.open()
	if opts.has("slide"):
		get_tree().create_timer(float(opts["slide"])).timeout.connect(_test_slide)
	if opts.has("say"):
		get_tree().create_timer(float(opts.get("say-at", "2.5"))).timeout.connect(func() -> void:
			game.send_chat(opts["say"])
			game.send_ping())
	if opts.has("end"):
		get_tree().create_timer(float(opts["end"])).timeout.connect(func() -> void: game._end_match())
	if opts.has("grenade"):
		get_tree().create_timer(float(opts["grenade"])).timeout.connect(func() -> void: game.local_char.throw_grenade(int(opts.get("kind", "0"))))
	if opts.has("airstrike"):
		get_tree().create_timer(float(opts["airstrike"])).timeout.connect(func() -> void:
			game.on_streak(game.local_char.char_id, 7)
			game._airstrike(game.local_char))
	if opts.has("lean"):
		get_tree().create_timer(float(opts["lean"])).timeout.connect(func() -> void:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			Input.action_press("lean_right"))
	if opts.has("ads"):
		get_tree().create_timer(float(opts["ads"])).timeout.connect(func() -> void:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			Input.action_press("zoom"))
	if opts.has("probe"):
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			var line := ""
			for i in 13:
				var z := 2.0 + i * 0.5
				var hit: Dictionary = game._ray(Vector3(3.5, 5, z), Vector3(3.5, -1, z), [] as Array[RID], 1)
				line += "z=%.1f:%s  " % [z, ("%.2f" % hit.position.y) if not hit.is_empty() else "-"]
			print("[sonde taxi] ", line))
	if opts.has("die"):
		get_tree().create_timer(float(opts["die"])).timeout.connect(func() -> void:
			for id in game.chars:
				if game.chars[id].is_bot and game.is_enemy(game.local_char, game.chars[id]):
					game._deal_damage(game.chars[id], {game.local_char.char_id: 500.0}, 0)
					break)
	if opts.has("freecam"):
		get_tree().create_timer(float(opts["freecam"])).timeout.connect(func() -> void: game.spectator.free = true)
	if opts.has("hit"):
		get_tree().create_timer(float(opts["hit"])).timeout.connect(_test_hit)
	if opts.has("knife"):
		get_tree().create_timer(float(opts["knife"])).timeout.connect(_test_knife)
	if opts.has("barrel"):
		get_tree().create_timer(float(opts["barrel"])).timeout.connect(_test_barrel)
	if opts.has("fire"):
		get_tree().create_timer(float(opts["fire"])).timeout.connect(_test_fire)
	if opts.has("quit-after"):
		get_tree().create_timer(float(opts["quit-after"])).timeout.connect(_quit.bind(opts.get("screenshot", "")))


## Test : le joueur local court tout droit puis glisse.
func _test_slide() -> void:
	if game == null or game.local_char == null:
		return
	var c = game.local_char
	c.velocity = -c.transform.basis.z * 9.0
	c.start_slide()
	print("[test] glissade : ", c.sliding, " vitesse ", c.velocity.length())


## Test : le joueur local prend sa 2e arme et tire droit devant, un peu vers le sol.
func _test_fire() -> void:
	if game == null or game.local_char == null:
		return
	var c = game.local_char
	c.switch_weapon(1)
	var dir: Vector3 = (-c.camera.global_transform.basis.z + Vector3(0, -0.25, 0)).normalized()
	game.local_fire(c, c.weapon, c.camera.global_position, PackedVector3Array([dir]))
	print("[test] tir : ", Data.WEAPONS[c.weapon].name)


## Test : le joueur local tire sur le baril le plus proche.
func _test_barrel() -> void:
	var c = game.local_char
	var best := Vector3.ZERO
	for p in game.map.barrel_points:
		var seen: bool = game._ray(c.camera.global_position, p + Vector3(0, 0.6, 0), [c.get_rid()] as Array[RID], 1).get("collider", null) is StaticBody3D and game._ray(c.camera.global_position, p + Vector3(0, 0.6, 0), [c.get_rid()] as Array[RID], 1).collider.has_meta("barrel")
		if seen and (best == Vector3.ZERO or p.distance_to(c.position) < best.distance_to(c.position)):
			best = p
	var origin: Vector3 = c.camera.global_position
	c.look_at(Vector3(best.x, c.position.y, best.z))
	var dir: Vector3 = (best + Vector3(0, 0.6, 0) - origin).normalized()
	for i in 3:
		game.local_fire(c, c.weapon, origin, PackedVector3Array([dir]))
	print("[test] tir sur le baril en ", best, " à ", int(best.distance_to(c.position)), " m")


## Test : un ennemi est placé juste devant le joueur local, qui donne un coup de couteau.
func _test_knife() -> void:
	var c = game.local_char
	for id in game.chars:
		var o = game.chars[id]
		if o.is_bot and game.is_enemy(c, o):
			o.position = c.position - c.transform.basis.z * 1.2
			o.rotation.y = c.rotation.y  # de dos
			o.bot = null
			print("[test] couteau sur ", o.display_name, " (PV ", o.hp, ")")
			break
	c.melee()


## Test : un ennemi est placé à 7 m devant le joueur local, qui lui tire dessus deux fois (corps puis tête).
func _test_hit() -> void:
	var c = game.local_char
	for id in game.chars:
		var o = game.chars[id]
		if o.is_bot and game.is_enemy(c, o):
			o.position = c.position - c.transform.basis.z * 5.0
			o._net_pos = o.position
			o.rotation.y = c.rotation.y + PI
			await get_tree().physics_frame
			await get_tree().physics_frame
			o.bot = null
			var origin: Vector3 = c.camera.global_position
			game.local_fire(c, c.weapon, origin, PackedVector3Array([(o.position + Vector3(0, 1.1, 0) - origin).normalized()]))
			game.local_fire(c, c.weapon, origin, PackedVector3Array([(o.position + Vector3(0, 1.62, 0) - origin).normalized()]))
			break


func _quit(screenshot: String) -> void:
	if screenshot != "":
		var img := get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(screenshot)
	get_tree().quit()
