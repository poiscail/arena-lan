extends CanvasLayer
## Interface en jeu : viseur, vie, munitions, scores, fil des éliminations, pause.

const Data := preload("res://scripts/data.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
const OptionsScript := preload("res://scripts/options.gd")
const LoadoutScript := preload("res://scripts/loadout.gd")
const ArmoryScript := preload("res://scripts/armory.gd")
const MinimapScript := preload("res://scripts/minimap.gd")

var game
var paused := false

var _crosshair: Control
var _scope: Control
var _hp_value: Label
var _hp_bar: ProgressBar
var _hp_fill: StyleBoxFlat
var _weapon_name: Label
var _ammo_value: Label
var _ammo_max: Label
var _reload_label: Label
var _slots := []
var _timer: Label
var _score_left: Label
var _score_right: Label
var _score_left_box: PanelContainer
var _score_right_box: PanelContainer
var _goal: Label
var _feed: VBoxContainer
var _center_box: PanelContainer
var _center: Label
var _big: Label
var _board: PanelContainer
var _board_text: RichTextLabel
var _vignette: TextureRect
var _pause: PanelContainer
var _options: Control
var _loadout: Control
var _armory: Control
var _pause_cls: OptionButton
var _fps: Label
var _armor_bar: ProgressBar
var _grenade_label: Label
var _buffs: Label
var _announce: Label
var _announce_t := 0.0
var _radar: Control
var minimap: Control
var radar_t := 0.0
var chat_open := false
var _chat_box: VBoxContainer
var _chat_edit: LineEdit
var _pings := []  # {"pos", "name", "enemy", "t"}
var _spec_label: Label
var _post: ColorRect
var _dmg_numbers := []  # {"pos", "text", "color", "size", "t", "dx"}
var _bottom: Control

var _hit_t := 0.0
var _hit_color := Color.WHITE
var _damage_a := 0.0
var _heal_t := 0.0
var _heal_label: Label
var _inspect_box: PanelContainer
var _inspect_text: RichTextLabel
var _death_t := 0.0
var _death_by := ""


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Post-traitement de l'image (shader assets/shaders/post.gdshader), sous le reste de l'interface
	_post = ColorRect.new()
	_post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pm := ShaderMaterial.new()
	pm.shader = load("res://assets/shaders/post.gdshader")
	_post.material = pm
	root.add_child(_post)

	# Vignette rouge quand on prend des dégâts
	_vignette = TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.8, 0, 0, 0))
	grad.set_color(1, Color(0.8, 0, 0, 0.85))
	grad.add_point(0.55, Color(0.8, 0, 0, 0))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(1.0, 1.0)
	_vignette.texture = gtex
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.modulate.a = 0.0
	_place(_vignette, 0, 0, 1, 1)
	root.add_child(_vignette)

	_scope = Control.new()
	_place(_scope, 0, 0, 1, 1)
	_scope.visible = false
	_scope.draw.connect(_draw_scope)
	root.add_child(_scope)

	_crosshair = Control.new()
	_place(_crosshair, 0.5, 0.5, 0.5, 0.5)
	_crosshair.draw.connect(_draw_crosshair)
	root.add_child(_crosshair)

	_build_bottom(root)
	_build_top(root)

	_feed = VBoxContainer.new()
	_feed.add_theme_constant_override("separation", 4)
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_place(_feed, 1, 0, 1, 0, -470, 16, -16, 320)
	root.add_child(_feed)

	_center_box = PanelContainer.new()
	_center_box.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.03, 0.04, 0.07, 0.75), Color(1, 1, 1, 0.08), 14))
	_place(_center_box, 0.5, 0.5, 0.5, 0.5, -260, 70, 260, 120)
	_center_box.visible = false
	root.add_child(_center_box)
	_center = _label(24, UiTheme.font_bold())
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_box.add_child(_center)

	_big = _label(48, UiTheme.font_title())
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.add_theme_color_override("font_color", UiTheme.ACCENT)
	_place(_big, 0, 0.13, 1, 0.13, 0, -40, 0, 30)
	root.add_child(_big)

	# Fiche de l'arme pendant l'inspection
	_inspect_box = PanelContainer.new()
	_inspect_box.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.03, 0.05, 0.09, 0.72), Color(1, 1, 1, 0.08), 8))
	_place(_inspect_box, 1, 0.5, 1, 0.5, -430, -40, -40, 100)
	_inspect_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect_box.visible = false
	root.add_child(_inspect_box)
	_inspect_text = _rich(18)
	_inspect_box.add_child(_inspect_text)

	_board = PanelContainer.new()
	_board.add_theme_stylebox_override("panel", UiTheme.accent_panel(Color(0.03, 0.05, 0.09, 0.9), UiTheme.ACCENT, 22))
	_place(_board, 0.5, 0.5, 0.5, 0.5, -360, -220, 360, 260)
	_board.visible = false
	root.add_child(_board)
	_board_text = _rich(19)
	_board.add_child(_board_text)

	_heal_label = _label(30, UiTheme.font_title())
	_heal_label.text = "+50 PV"
	_heal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heal_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.55))
	_place(_heal_label, 0, 0.5, 1, 0.5, 0, -90, 0, -50)
	_heal_label.visible = false
	root.add_child(_heal_label)

	_fps = _label(15, UiTheme.font_bold())
	_place(_fps, 0, 0, 0, 0, 12, 8, 140, 30)
	root.add_child(_fps)

	# Mini-carte (haut gauche)
	minimap = MinimapScript.new()
	minimap.game = game
	minimap.hud = self
	_place(minimap, 0, 0, 0, 0, 16, 34, 16 + MinimapScript.SIZE, 34 + MinimapScript.SIZE)
	root.add_child(minimap)

	# Bonus actifs (au-dessus de la santé)
	_buffs = _label(17, UiTheme.font_bold())
	_buffs.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_place(_buffs, 0, 1, 0, 1, 26, -170, 600, -140)
	root.add_child(_buffs)

	# Annonces (séries d'éliminations)
	_announce = _label(34, UiTheme.font_title())
	_announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	_announce.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_announce.add_theme_constant_override("outline_size", 8)
	_place(_announce, 0, 0.24, 1, 0.24, 0, -24, 0, 24)
	_announce.visible = false
	root.add_child(_announce)

	# Radar : ennemis marqués à travers les murs
	_radar = Control.new()
	_place(_radar, 0, 0, 1, 1)
	_radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar.draw.connect(_draw_radar)
	root.add_child(_radar)

	# Mode spectateur (après la mort)
	_spec_label = _label(17, UiTheme.font_bold())
	_spec_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spec_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_spec_label.add_theme_constant_override("outline_size", 6)
	_place(_spec_label, 0, 1, 1, 1, 0, -60, 0, -30)
	root.add_child(_spec_label)

	# Chat (bas gauche, au-dessus des bonus)
	_chat_box = VBoxContainer.new()
	_chat_box.alignment = BoxContainer.ALIGNMENT_END
	_chat_box.add_theme_constant_override("separation", 2)
	_place(_chat_box, 0, 1, 0, 1, 26, -420, 620, -200)
	_chat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_chat_box)
	_chat_edit = LineEdit.new()
	_chat_edit.placeholder_text = "Message (Entrée pour envoyer, Échap pour annuler)"
	_chat_edit.max_length = 120
	_place(_chat_edit, 0, 1, 0, 1, 26, -196, 620, -164)
	_chat_edit.visible = false
	_chat_edit.text_submitted.connect(func(t: String) -> void:
		game.send_chat(t)
		close_chat())
	_chat_edit.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			_chat_edit.accept_event()
			close_chat())
	root.add_child(_chat_edit)

	_build_pause(root)
	_options = OptionsScript.new()
	_options.visible = false
	root.add_child(_options)
	# Classes et armes / armurerie en pleine partie : envoyés à l'hôte, appliqués à la prochaine apparition
	_loadout = LoadoutScript.new()
	_loadout.in_game = true
	_loadout.visible = false
	_loadout.changed.connect(func() -> void:
		_pause_cls.select(Net.player_class)
		game.request_class(Net.player_class)
		game.send_armory(Net.armory))
	_loadout.open_armory.connect(func(wi: int) -> void:
		_armory._wi = wi
		_armory.open())
	root.add_child(_loadout)
	_armory = ArmoryScript.new()
	_armory.visible = false
	_armory.closed.connect(func() -> void:
		game.send_armory(Net.armory)
		if _loadout.visible:
			_loadout.open())
	root.add_child(_armory)
	refresh_scores()


func _build_bottom(root: Control) -> void:
	_bottom = Control.new()
	_place(_bottom, 0, 1, 1, 1, 24, -136, -24, -20)
	root.add_child(_bottom)

	# Santé (bas gauche)
	var hp_box := PanelContainer.new()
	hp_box.add_theme_stylebox_override("panel", UiTheme.accent_panel(Color(0.03, 0.05, 0.09, 0.78), Color(0.35, 0.9, 0.5), 14))
	_place(hp_box, 0, 0, 0, 1, 0, 0, 320, 0)
	_bottom.add_child(hp_box)
	var hp_v := VBoxContainer.new()
	hp_v.add_theme_constant_override("separation", 2)
	hp_box.add_child(hp_v)
	var hp_row := HBoxContainer.new()
	hp_v.add_child(hp_row)
	var hp_title := _label(15, UiTheme.font_bold())
	hp_title.text = "SANTÉ"
	hp_title.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	hp_title.size_flags_vertical = Control.SIZE_SHRINK_END
	hp_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_row.add_child(hp_title)
	_hp_value = _label(40, UiTheme.font_title())
	hp_row.add_child(_hp_value)
	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(0, 10)
	_hp_bar.max_value = 100
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(1, 1, 1, 0.1)
	_hp_fill = StyleBoxFlat.new()
	_hp_fill.bg_color = Color(0.35, 0.9, 0.5)
	_hp_bar.add_theme_stylebox_override("background", bar_bg)
	_hp_bar.add_theme_stylebox_override("fill", _hp_fill)
	hp_v.add_child(_hp_bar)
	_armor_bar = ProgressBar.new()
	_armor_bar.show_percentage = false
	_armor_bar.custom_minimum_size = Vector2(0, 6)
	_armor_bar.max_value = 100
	var armor_fill := StyleBoxFlat.new()
	armor_fill.bg_color = Color(0.35, 0.65, 1.0)
	_armor_bar.add_theme_stylebox_override("background", bar_bg)
	_armor_bar.add_theme_stylebox_override("fill", armor_fill)
	hp_v.add_child(_armor_bar)

	# Arme et munitions (bas droite)
	var ammo_box := PanelContainer.new()
	ammo_box.add_theme_stylebox_override("panel", UiTheme.accent_panel(Color(0.03, 0.05, 0.09, 0.78), UiTheme.ACCENT, 14))
	_place(ammo_box, 1, 0, 1, 1, -360, 0, 0, 0)
	_bottom.add_child(ammo_box)
	var ammo_v := VBoxContainer.new()
	ammo_v.add_theme_constant_override("separation", 0)
	ammo_box.add_child(ammo_v)
	var top_row := HBoxContainer.new()
	ammo_v.add_child(top_row)
	_weapon_name = _label(22, UiTheme.font_bold())
	_weapon_name.add_theme_color_override("font_color", UiTheme.ACCENT)
	_weapon_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weapon_name.size_flags_vertical = Control.SIZE_SHRINK_END
	top_row.add_child(_weapon_name)
	_reload_label = _label(18, UiTheme.font_bold())
	_reload_label.size_flags_vertical = Control.SIZE_SHRINK_END
	_reload_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	top_row.add_child(_reload_label)
	_ammo_value = _label(40, UiTheme.font_title())
	_ammo_value.size_flags_vertical = Control.SIZE_SHRINK_END
	top_row.add_child(_ammo_value)
	_ammo_max = _label(20, UiTheme.font_bold())
	_ammo_max.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_ammo_max.size_flags_vertical = Control.SIZE_SHRINK_END
	top_row.add_child(_ammo_max)
	var slots_row := HBoxContainer.new()
	slots_row.add_theme_constant_override("separation", 14)
	ammo_v.add_child(slots_row)
	for i in 3:
		var s := _label(15, UiTheme.font_bold())
		s.text = "%d  %s" % [i + 1, String(Data.WEAPONS[i].name).to_upper()]
		slots_row.add_child(s)
		_slots.append(s)

	_grenade_label = _label(15, UiTheme.font_bold())
	_grenade_label.add_theme_color_override("font_color", Color(0.75, 0.95, 0.6))
	_hp_bar.get_parent().add_child(_grenade_label)


func _build_top(root: Control) -> void:
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 6)
	_place(top, 0, 0, 1, 0, 0, 14, 0, 70)
	root.add_child(top)

	_score_left_box = _score_box()
	_score_left = _label(30, UiTheme.font_title())
	_score_left.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_left_box.add_child(_score_left)
	top.add_child(_score_left_box)

	var timer_box := PanelContainer.new()
	timer_box.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.03, 0.05, 0.09, 0.82), Color(1, 1, 1, 0.12), 10))
	timer_box.custom_minimum_size = Vector2(130, 0)
	_timer = _label(28, UiTheme.font_title())
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_box.add_child(_timer)
	top.add_child(timer_box)

	_score_right_box = _score_box()
	_score_right = _label(30, UiTheme.font_title())
	_score_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_right_box.add_child(_score_right)
	top.add_child(_score_right_box)

	_goal = _label(15, UiTheme.font_bold())
	_goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_goal.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_place(_goal, 0, 0, 1, 0, 0, 72, 0, 96)
	root.add_child(_goal)

	if game.settings.mode == "team":
		_score_left_box.add_theme_stylebox_override("panel", UiTheme.panel(Color(Data.TEAM_COLORS[0].darkened(0.45), 0.85), Data.TEAM_COLORS[0], 10))
		_score_right_box.add_theme_stylebox_override("panel", UiTheme.panel(Color(Data.TEAM_COLORS[1].darkened(0.45), 0.85), Data.TEAM_COLORS[1], 10))


func _score_box() -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(220, 0)
	p.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.03, 0.05, 0.09, 0.82), Color(1, 1, 1, 0.12), 10))
	return p


func _build_pause(root: Control) -> void:
	_pause = PanelContainer.new()
	_pause.add_theme_stylebox_override("panel", UiTheme.accent_panel(Color(0.04, 0.06, 0.1, 0.96), UiTheme.ACCENT, 26))
	_place(_pause, 0.5, 0.5, 0.5, 0.5, -230, -230, 230, 230)
	_pause.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause.visible = false
	root.add_child(_pause)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_pause.add_child(v)
	var title := _label(30, UiTheme.font_title())
	title.text = "PAUSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var resume := Button.new()
	resume.text = "Reprendre"
	resume.pressed.connect(toggle_pause)
	v.add_child(resume)
	var cls_title := _label(16, UiTheme.font_bold())
	cls_title.text = "CLASSE (À LA PROCHAINE APPARITION)"
	cls_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	v.add_child(cls_title)
	_pause_cls = OptionButton.new()
	for cl in Data.CLASSES:
		_pause_cls.add_item(cl["name"])
	_pause_cls.select(Net.player_class)
	_pause_cls.item_selected.connect(func(i: int) -> void:
		Net.player_class = i
		Net.save_options()
		game.request_class(i))
	v.add_child(_pause_cls)
	var weapons := Button.new()
	weapons.text = "Classes et armes (armes 1, 2, 3)"
	weapons.pressed.connect(func() -> void: _loadout.open())
	v.add_child(weapons)
	var armory := Button.new()
	armory.text = "Armurerie (skins et accessoires)"
	armory.pressed.connect(func() -> void: _armory.open())
	v.add_child(armory)
	var opts := Button.new()
	opts.text = "Options"
	opts.pressed.connect(func() -> void: _options.open())
	v.add_child(opts)
	var quit := Button.new()
	quit.text = "Quitter la partie"
	quit.pressed.connect(func() -> void: Net.quit_to_menu.call_deferred())
	v.add_child(quit)


# --- API appelée par game.gd ------------------------------------------------------

func toggle_pause() -> void:
	paused = not paused
	_pause.visible = paused
	if not paused:
		_options.visible = false
		_loadout.visible = false
		if _armory.visible:
			_armory.visible = false
			game.send_armory(Net.armory)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED


func hit_marker(head: bool, killed: bool) -> void:
	_hit_t = 0.25
	if killed:
		_hit_color = Color(1, 0.25, 0.2)
	elif head:
		_hit_color = Color(1, 0.85, 0.2)
	else:
		_hit_color = Color.WHITE


func damage_flash() -> void:
	_damage_a = 0.9


func heal_flash() -> void:
	_heal_t = 1.2


func pickup_flash(text: String, color: Color) -> void:
	_heal_label.text = text
	_heal_label.add_theme_color_override("font_color", color)
	_heal_t = 1.2


func open_chat() -> void:
	chat_open = true
	_chat_edit.text = ""
	_chat_edit.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_chat_edit.grab_focus.call_deferred()


func close_chat() -> void:
	chat_open = false
	_chat_edit.visible = false
	_chat_edit.release_focus()
	if not paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func add_chat(pname: String, team: int, text: String) -> void:
	var l := _rich(17)
	var hex: String = Data.TEAM_HEX[team] if team >= 0 else "#ffa64d"
	l.text = "[color=%s][b]%s[/b][/color] : %s" % [hex, Data.esc(pname), Data.esc(text)]
	l.set_meta("t", 10.0)
	_chat_box.add_child(l)
	while _chat_box.get_child_count() > 7:
		_chat_box.get_child(0).free()


## Chiffre de dégâts au-dessus de l'ennemi touché (jaune à la tête, rouge s'il est éliminé).
func add_damage_number(pos: Vector3, dmg: int, head: bool, killed: bool) -> void:
	var col := Color(1, 1, 1)
	if killed:
		col = Color(1, 0.3, 0.25)
	elif head:
		col = Color(1, 0.85, 0.2)
	_dmg_numbers.append({"pos": pos, "text": str(dmg), "color": col, "size": 30 if (head or killed) else 24,
		"t": 0.9, "dx": randf_range(-18.0, 18.0)})


func add_ping(pos: Vector3, pname: String, enemy: bool) -> void:
	_pings.append({"pos": pos, "name": pname, "enemy": enemy, "t": 6.0})


func announce(text: String) -> void:
	_announce.text = text
	_announce_t = 3.0


func _draw_radar() -> void:
	var c = game.local_char
	if c == null or c.camera == null:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	# Signalements des coéquipiers
	for p in _pings:
		var pos: Vector3 = p["pos"] + Vector3(0, 0.6, 0)
		if cam.is_position_behind(pos):
			continue
		var s := cam.unproject_position(pos)
		var col := Color(1, 0.3, 0.25) if p["enemy"] else Color(1, 0.85, 0.3)
		col.a = clampf(p["t"], 0.0, 1.0)
		_radar.draw_circle(s, 11.0, Color(0, 0, 0, 0.5 * col.a))
		_radar.draw_arc(s, 11.0, 0.0, TAU, 24, col, 2.5)
		_radar.draw_string(UiTheme.font_title(), s + Vector2(-5, 7), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
		var label := "%s%s · %d m" % ["ENNEMI · " if p["enemy"] else "", p["name"], int(c.position.distance_to(p["pos"]))]
		_radar.draw_string(UiTheme.font_bold(), s + Vector2(16, 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
	# Chiffres de dégâts : montent et s'effacent
	for n in _dmg_numbers:
		var np: Vector3 = n["pos"]
		if cam.is_position_behind(np):
			continue
		var age: float = 0.9 - n["t"]
		var sp := cam.unproject_position(np) + Vector2(n["dx"], -age * 60.0)
		var col: Color = n["color"]
		col.a = clampf(n["t"] / 0.4, 0.0, 1.0)
		var font := UiTheme.font_title()
		var fs: int = n["size"]
		var w := font.get_string_size(n["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_radar.draw_string_outline(font, sp - Vector2(w / 2.0, 0), n["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, col.a * 0.8))
		_radar.draw_string(font, sp - Vector2(w / 2.0, 0), n["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	if radar_t <= 0.0:
		return
	for id in game.chars:
		var o = game.chars[id]
		if not o.alive or not game.is_enemy(c, o):
			continue
		var p: Vector3 = o.global_position + Vector3(0, 1.2, 0)
		if cam.is_position_behind(p):
			continue
		var s := cam.unproject_position(p)
		var d := 9.0
		var pts := PackedVector2Array([s + Vector2(0, -d), s + Vector2(d, 0), s + Vector2(0, d), s + Vector2(-d, 0)])
		_radar.draw_colored_polygon(pts, Color(1, 0.2, 0.15, 0.85))
		_radar.draw_string(UiTheme.font_bold(), s + Vector2(-14, -14), "%d m" % int(c.position.distance_to(o.position)), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.5, 0.45))


func show_death(killer: String) -> void:
	_death_t = Data.RESPAWN_TIME
	_death_by = killer


func add_kill(bbcode: String) -> void:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.03, 0.05, 0.09, 0.72), Color(1, 1, 1, 0.06), 6))
	box.size_flags_horizontal = Control.SIZE_SHRINK_END
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := _rich(18)
	r.text = bbcode
	box.add_child(r)
	box.set_meta("t", 6.0)
	_feed.add_child(box)
	if _feed.get_child_count() > 6:
		_feed.get_child(0).queue_free()


## Récompenses et statistiques personnelles affichées à la fin du match.
func _stats_text() -> String:
	var best := {}
	var acc_best := ["", -1.0]
	for id in game.scores:
		var s: Dictionary = game.scores[id]
		for k in ["dmg", "best_streak", "heads"]:
			if not best.has(k) or int(s.get(k, 0)) > int(best[k][1]):
				best[k] = [s["name"], int(s.get(k, 0))]
		var shots := int(s.get("shots", 0))
		if shots >= 10:
			var acc := float(s.get("hits", 0)) / shots
			if acc > acc_best[1]:
				acc_best = [s["name"], acc]
	var leader: Dictionary = game._ffa_leader()
	var t := "\n[center][font_size=24][b]RÉCOMPENSES[/b][/font_size][/center]\n[table=2]"
	var line := func(title: String, who: String, val: String) -> String:
		return "[cell][color=#ffcc55]%s[/color]      [/cell][cell]%s  [color=#8890a0]%s[/color][/cell]" % [title, Data.esc(who), val]
	if not leader.is_empty():
		t += line.call("MEILLEUR JOUEUR", leader["name"], "%d %s" % [int(leader[game.score_key()]), Data.RULES[game.rules]["unit"]])
	if acc_best[1] >= 0.0:
		t += line.call("PLUS PRÉCIS", acc_best[0], "%d %%" % int(acc_best[1] * 100.0))
	if best.has("best_streak"):
		t += line.call("PLUS LONGUE SÉRIE", best["best_streak"][0], "%d d'affilée" % best["best_streak"][1])
	if best.has("dmg"):
		t += line.call("PLUS DE DÉGÂTS", best["dmg"][0], "%d" % best["dmg"][1])
	if best.has("heads") and int(best["heads"][1]) > 0:
		t += line.call("TIREUR D'ÉLITE", best["heads"][0], "%d tirs à la tête" % best["heads"][1])
	t += "[/table]\n"
	var c = game.local_char
	if c != null and game.scores.has(c.char_id):
		var m: Dictionary = game.scores[c.char_id]
		var shots := int(m.get("shots", 0))
		var acc := 0 if shots == 0 else int(100.0 * float(m.get("hits", 0)) / shots)
		var fav := "-"
		var fav_n := 0
		var wk: Dictionary = m.get("wkills", {})
		for k in wk:
			if int(wk[k]) > fav_n:
				fav_n = int(wk[k])
				fav = Data.kill_name(int(k))
		if game.xp_text != "":
			t += "\n[center][color=#7fe08a][b]%s[/b][/color][/center]" % game.xp_text
		t += "\n[center][color=#ffa64d][b]TOI[/b][/color] :  précision %d %%  ·  %d tirs à la tête  ·  %d dégâts  ·  série max %d  ·  arme préférée : %s[/center]" % [
			acc, int(m.get("heads", 0)), int(m.get("dmg", 0)), int(m.get("best_streak", 0)), fav]
	return t


func refresh_scores() -> void:
	if _board_text == null:
		return
	var rows := []
	for id in game.scores:
		var s: Dictionary = game.scores[id].duplicate()
		s["id"] = id
		rows.append(s)
	var key: String = game.score_key()
	var pts := key == "pts"
	rows.sort_custom(func(a, b): return int(a[key]) > int(b[key]) or (int(a[key]) == int(b[key]) and a["kills"] > b["kills"]))
	var me: String = game.local_char.char_id if game.local_char != null else ""
	var txt := "[center][font_size=28][b]SCORES[/b][/font_size][/center]\n"
	var groups := [0, 1] if game.settings.mode == "team" else [-1]
	var totals: Array = game.team_scores()
	for g in groups:
		if g >= 0:
			txt += "\n[color=%s][b][font_size=22]%s   %d[/font_size][/b][/color]\n" % [Data.TEAM_HEX[g], Data.TEAM_NAMES[g], totals[g]]
		txt += "[table=%d][cell][color=#8890a0]JOUEUR                    [/color][/cell]" % (4 if pts else 3)
		if pts:
			txt += "[cell][color=#8890a0]%s     [/color][/cell]" % String(Data.RULES[game.rules]["unit"]).to_upper()
		txt += "[cell][color=#8890a0]ÉLIM.     [/color][/cell][cell][color=#8890a0]MORTS[/color][/cell]"
		for s in rows:
			if g >= 0 and s["team"] != g:
				continue
			var n := Data.esc(s["name"])
			if s["id"] == me:
				n = "[color=#ffa64d][b]%s[/b][/color]" % n
			txt += "[cell]%s[/cell]" % n
			if pts:
				txt += "[cell]%d[/cell]" % int(s.get("pts", 0))
			txt += "[cell]%d[/cell][cell]%d[/cell]" % [s["kills"], s["deaths"]]
		txt += "[/table]\n"
	if game.match_over:
		txt += _stats_text() + "\n[center][color=#8890a0]Retour au salon dans quelques secondes...[/color][/center]"
		_place(_board, 0.5, 0.5, 0.5, 0.5, -450, -248, 450, 354)
		_board_text.add_theme_font_size_override("normal_font_size", 15)
		_board_text.add_theme_font_size_override("bold_font_size", 15)
		txt = txt.replace("[font_size=28][b]SCORES[/b][/font_size]", "[font_size=20][b]SCORES[/b][/font_size]").replace("[font_size=22]", "[font_size=17]").replace("\n\n", "\n")
	_board_text.text = txt


# --- Boucle -----------------------------------------------------------------------

func _process(delta: float) -> void:
	_fps.visible = Net.gfx.show_fps
	if _fps.visible:
		_fps.text = "%d IPS" % Engine.get_frames_per_second()
	var c = game.local_char
	if c != null:
		_hp_value.text = str(c.hp)
		_update_inspect(c)
		_hp_bar.value = c.hp
		_armor_bar.value = c.armor
		_armor_bar.visible = c.armor > 0
		_grenade_label.text = "GRENADES (G) %d    FUMIGÈNES (H) %d" % [c.grenades[0], c.grenades[1]]
		var b := []
		if c.speed_t > 0.0:
			b.append("ADRÉNALINE %d s" % int(ceil(c.speed_t)))
		if c.damage_t > 0.0:
			b.append("DÉGÂTS x2 %d s" % int(ceil(c.damage_t)))
		if radar_t > 0.0:
			b.append("RADAR %d s" % int(ceil(radar_t)))
		_buffs.text = "   ·   ".join(b)
		_buffs.visible = c.alive
		var hp_col := Color(0.35, 0.9, 0.5) if c.hp > 60 else (Color(1, 0.75, 0.25) if c.hp > 30 else Color(1, 0.3, 0.25))
		_hp_fill.bg_color = hp_col
		_hp_value.add_theme_color_override("font_color", hp_col if c.hp <= 30 else Color.WHITE)
		var w: Dictionary = c.wstats(c.weapon)
		_weapon_name.text = String(w.name).to_upper()
		_ammo_value.text = str(c.ammo[c.weapon])
		_ammo_max.text = " / %d" % w.mag
		_reload_label.text = "RECHARGEMENT  " if c.reloading > 0.0 else ""
		_ammo_value.add_theme_color_override("font_color", Color(1, 0.35, 0.3) if c.ammo[c.weapon] <= w.mag / 4 else Color.WHITE)
		for i in _slots.size():
			_slots[i].visible = i < c.loadout.size()
			if i >= c.loadout.size():
				continue
			_slots[i].text = "%d  %s" % [i + 1, String(Data.WEAPONS[c.loadout[i]].name).to_upper()]
			_slots[i].add_theme_color_override("font_color", UiTheme.ACCENT if i == c.slot else Color(1, 1, 1, 0.35))
		_scope.visible = c.zoomed and c.alive and not c.wstats(c.weapon).get("optic", false)
		_bottom.visible = c.alive and not c.zoomed and not game.match_over
	minimap.visible = c != null and c.alive and not c.zoomed and not game.match_over and bool(Net.gfx.get("minimap", true))
	var t := int(ceil(game.time_left))
	_timer.text = "%d:%02d" % [t / 60, t % 60]
	_timer.add_theme_color_override("font_color", Color(1, 0.4, 0.3) if t <= 30 else Color.WHITE)
	_update_scores_top()
	_board.visible = game.match_over or Input.is_action_pressed("scoreboard")
	_big.text = game.end_text if game.match_over else ""

	var dead: bool = c != null and not c.alive
	if game.match_over or not dead:
		_center.text = ""
	else:
		_death_t -= delta
		var by := ("Éliminé par %s\n" % _death_by) if _death_by != "" else ""
		if not game.modes.allows_respawn():
			_center.text = by + "Attends la manche suivante"
		elif _death_t > 0.0:
			_center.text = by + "Réapparition dans %d" % int(ceil(maxf(_death_t, 0.0)))
		else:
			_center.text = ""
	_center_box.visible = _center.text != ""
	# En spectateur, le message descend en bas de l'écran pour ne pas cacher la vue
	if game.killcam != null and game.killcam.active:
		_place(_center_box, 0.5, 1, 0.5, 1, -260, -240, 260, -150)
	elif game.spectator != null and game.spectator.active:
		_place(_center_box, 0.5, 1, 0.5, 1, -260, -160, 260, -76)
	else:
		_place(_center_box, 0.5, 0.5, 0.5, 0.5, -260, 70, 260, 120)

	_hit_t = maxf(0.0, _hit_t - delta)
	_heal_t = maxf(0.0, _heal_t - delta)
	_heal_label.visible = _heal_t > 0.0
	_heal_label.modulate.a = minf(1.0, _heal_t * 2.0)
	_heal_label.offset_top = -90.0 - (1.2 - _heal_t) * 30.0
	_heal_label.offset_bottom = _heal_label.offset_top + 40.0
	_damage_a = move_toward(_damage_a, 0.0, delta * 1.6)
	var low := 0.0
	if c != null and c.alive and c.hp <= 30:
		low = 0.35 + 0.15 * sin(Time.get_ticks_msec() / 200.0)
	_vignette.modulate.a = maxf(_damage_a, low)
	_post.visible = bool(Net.gfx.get("post", true))
	if _post.visible:
		(_post.material as ShaderMaterial).set_shader_parameter("damage", clampf(_damage_a * 1.5, 0.0, 1.0))
	_crosshair.queue_redraw()
	radar_t = maxf(0.0, radar_t - delta)
	_radar.queue_redraw()
	_spec_label.text = game.spectator.info_text() if game.spectator != null and game.spectator.active and not game.match_over else ""
	for i in range(_dmg_numbers.size() - 1, -1, -1):
		_dmg_numbers[i]["t"] -= delta
		if _dmg_numbers[i]["t"] <= 0.0:
			_dmg_numbers.remove_at(i)
	for i in range(_pings.size() - 1, -1, -1):
		_pings[i]["t"] -= delta
		if _pings[i]["t"] <= 0.0:
			_pings.remove_at(i)
	for e in _chat_box.get_children():
		var left: float = e.get_meta("t", 0.0) - delta
		e.set_meta("t", left)
		if left <= 0.0 and not chat_open:
			e.queue_free()
		elif left < 1.0:
			e.modulate.a = 1.0 if chat_open else maxf(left, 0.0)
	_announce_t = maxf(0.0, _announce_t - delta)
	_announce.visible = _announce_t > 0.0
	_announce.modulate.a = minf(1.0, _announce_t * 1.5)
	if _scope.visible:
		_scope.queue_redraw()
	for e in _feed.get_children():
		var left: float = e.get_meta("t", 0.0) - delta
		e.set_meta("t", left)
		if left <= 0.0:
			e.queue_free()
		elif left < 1.0:
			e.modulate.a = left


func _update_scores_top() -> void:
	if game.settings.mode == "team":
		var t: Array = game.team_scores()
		_score_left.text = "%s  %d" % [Data.TEAM_NAMES[0], t[0]]
		_score_right.text = "%d  %s" % [t[1], Data.TEAM_NAMES[1]]
	else:
		var mine := 0
		if game.local_char != null and game.scores.has(game.local_char.char_id):
			mine = int(game.scores[game.local_char.char_id][game.score_key()])
		var best := 0
		for id in game.scores:
			best = maxi(best, int(game.scores[id][game.score_key()]))
		_score_left.text = "TOI  %d" % mine
		_score_right.text = "%d  MENEUR" % best
	_goal.text = game.goal_text()


func _draw_crosshair() -> void:
	var c = game.local_char
	# En visée avec le point rouge, le viseur 3D affiche lui-même son point (pas de réticule ici)
	if c != null and c.alive and not c.zoomed and not game.match_over and c.driving == "":
		var gap := 7.0
		if int(Data.WEAPONS[c.weapon].pellets) > 1:
			gap = 16.0
		var spd: float = Vector2(c.velocity.x, c.velocity.z).length()
		gap += minf(spd, 9.0) * 0.8
		var col := Color(1, 1, 1, 0.95)
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			_crosshair.draw_line(d * gap, d * (gap + 10.0), Color(0, 0, 0, 0.6), 4.0)
			_crosshair.draw_line(d * gap, d * (gap + 10.0), col, 2.0)
		_crosshair.draw_circle(Vector2.ZERO, 1.6, UiTheme.ACCENT)
	if _hit_t > 0.0:
		var hc := _hit_color
		hc.a = _hit_t / 0.25
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_crosshair.draw_line(d * 7.0, d * 16.0, hc, 3.0)


func _draw_scope() -> void:
	var s := _scope.size
	var cen := s / 2.0
	var r := s.y * 0.45
	var black := Color(0, 0, 0)
	_scope.draw_rect(Rect2(0, 0, cen.x - r, s.y), black)
	_scope.draw_rect(Rect2(cen.x + r, 0, s.x - cen.x - r, s.y), black)
	_scope.draw_arc(cen, r + 100.0, 0.0, TAU, 96, black, 200.0)
	_scope.draw_line(Vector2(cen.x - r, cen.y), Vector2(cen.x + r, cen.y), black, 1.5)
	_scope.draw_line(Vector2(cen.x, cen.y - r), Vector2(cen.x, cen.y + r), black, 1.5)
	_scope.draw_circle(cen, 2.0, Color(1, 0.2, 0.2))


# --- Aides de construction ----------------------------------------------------------

## Fiche affichée pendant l'inspection : arme, skin et sa rareté, éliminations et prochain skin.
func _update_inspect(c) -> void:
	_inspect_box.visible = c.inspect > 0.0 and c.alive
	if not _inspect_box.visible:
		return
	var wi: int = c.weapon
	var cm: Dictionary = Data.CAMOS[c.custom(wi)["skin"]]
	var rar: Dictionary = Data.RARITIES[int(cm.get("r", 0))]
	var k: int = Net.kills_with(wi)
	var next := ""
	var best := -1
	for i in Data.CAMOS.size():
		var need := Data.skin_kills(i)
		if need > k and (best < 0 or need < Data.skin_kills(best)):
			best = i
	if best >= 0:
		next = "
[color=#9aa4b2]Prochain skin : %s dans %d élim.[/color]" % [Data.esc(Data.CAMOS[best]["name"]), Data.skin_kills(best) - k]
	var att: Array = c.custom(wi)["att"]
	var att_txt := ("
[color=#9aa4b2]Accessoires : %d[/color]" % att.size()) if not att.is_empty() else ""
	var cu: Dictionary = c.custom(wi)
	var extra := PackedStringArray()
	if int(cu["charm"]) > 0:
		extra.append("breloque " + String(Data.CHARMS[int(cu["charm"])]["name"]))
	if int(cu["sticker"]) > 0:
		extra.append("autocollant " + String(Data.STICKERS[int(cu["sticker"])]["name"]))
	if not extra.is_empty():
		att_txt += "
[color=#9aa4b2]%s[/color]" % Data.esc(", ".join(extra))
	_inspect_text.text = "[b]%s[/b]
[color=#%s]%s · %s[/color]
%d éliminations avec cette arme%s%s" % [
		Data.esc(Data.WEAPONS[wi].name), rar["color"].to_html(false), Data.esc(cm["name"]), rar["name"], k, next, att_txt]


func _place(c: Control, al: float, at: float, ar: float, ab: float, ol := 0.0, ot := 0.0, o_r := 0.0, ob := 0.0) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = o_r
	c.offset_bottom = ob
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _label(size: int, font: Font = null) -> Label:
	var l := Label.new()
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _rich(size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_constant_override("outline_size", 4)
	r.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
