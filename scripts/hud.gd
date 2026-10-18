extends CanvasLayer
## Interface en jeu : viseur, vie, munitions, scores, fil des éliminations, pause.

const Data := preload("res://scripts/data.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")

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
var _bottom: Control

var _hit_t := 0.0
var _hit_color := Color.WHITE
var _damage_a := 0.0
var _death_t := 0.0
var _death_by := ""


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

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

	_board = PanelContainer.new()
	_board.add_theme_stylebox_override("panel", UiTheme.accent_panel(Color(0.03, 0.05, 0.09, 0.9), UiTheme.ACCENT, 22))
	_place(_board, 0.5, 0.5, 0.5, 0.5, -360, -220, 360, 260)
	_board.visible = false
	root.add_child(_board)
	_board_text = _rich(19)
	_board.add_child(_board_text)

	_build_pause(root)
	refresh_scores()


func _build_bottom(root: Control) -> void:
	_bottom = Control.new()
	_place(_bottom, 0, 1, 1, 1, 24, -112, -24, -20)
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
	for i in Data.WEAPONS.size():
		var s := _label(15, UiTheme.font_bold())
		s.text = "%d  %s" % [i + 1, String(Data.WEAPONS[i].name).to_upper()]
		slots_row.add_child(s)
		_slots.append(s)


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
	_place(_pause, 0.5, 0.5, 0.5, 0.5, -220, -170, 220, 170)
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
	var sens := _label(16, UiTheme.font_bold())
	sens.text = "SENSIBILITÉ DE LA SOURIS"
	sens.add_theme_color_override("font_color", UiTheme.ACCENT)
	v.add_child(sens)
	var slider := HSlider.new()
	slider.min_value = 0.5
	slider.max_value = 8.0
	slider.step = 0.1
	slider.value = Net.mouse_sensitivity * 1000.0
	slider.value_changed.connect(func(val: float) -> void: Net.mouse_sensitivity = val / 1000.0)
	v.add_child(slider)
	var quit := Button.new()
	quit.text = "Quitter la partie"
	quit.pressed.connect(func() -> void: Net.quit_to_menu.call_deferred())
	v.add_child(quit)


# --- API appelée par game.gd ------------------------------------------------------

func toggle_pause() -> void:
	paused = not paused
	_pause.visible = paused
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


func refresh_scores() -> void:
	if _board_text == null:
		return
	var rows := []
	for id in game.scores:
		var s: Dictionary = game.scores[id].duplicate()
		s["id"] = id
		rows.append(s)
	rows.sort_custom(func(a, b): return a["kills"] > b["kills"] or (a["kills"] == b["kills"] and a["deaths"] < b["deaths"]))
	var me: String = game.local_char.char_id if game.local_char != null else ""
	var txt := "[center][font_size=28][b]SCORES[/b][/font_size][/center]\n"
	var groups := [0, 1] if game.settings.mode == "team" else [-1]
	var totals: Array = game.team_scores()
	for g in groups:
		if g >= 0:
			txt += "\n[color=%s][b][font_size=22]%s   %d[/font_size][/b][/color]\n" % [Data.TEAM_HEX[g], Data.TEAM_NAMES[g], totals[g]]
		txt += "[table=3][cell][color=#8890a0]JOUEUR                    [/color][/cell][cell][color=#8890a0]ÉLIM.     [/color][/cell][cell][color=#8890a0]MORTS[/color][/cell]"
		for s in rows:
			if g >= 0 and s["team"] != g:
				continue
			var n := Data.esc(s["name"])
			if s["id"] == me:
				n = "[color=#ffa64d][b]%s[/b][/color]" % n
			txt += "[cell]%s[/cell][cell]%d[/cell][cell]%d[/cell]" % [n, s["kills"], s["deaths"]]
		txt += "[/table]\n"
	_board_text.text = txt


# --- Boucle -----------------------------------------------------------------------

func _process(delta: float) -> void:
	var c = game.local_char
	if c != null:
		_hp_value.text = str(c.hp)
		_hp_bar.value = c.hp
		var hp_col := Color(0.35, 0.9, 0.5) if c.hp > 60 else (Color(1, 0.75, 0.25) if c.hp > 30 else Color(1, 0.3, 0.25))
		_hp_fill.bg_color = hp_col
		_hp_value.add_theme_color_override("font_color", hp_col if c.hp <= 30 else Color.WHITE)
		var w: Dictionary = Data.WEAPONS[c.weapon]
		_weapon_name.text = String(w.name).to_upper()
		_ammo_value.text = str(c.ammo[c.weapon])
		_ammo_max.text = " / %d" % w.mag
		_reload_label.text = "RECHARGEMENT  " if c.reloading > 0.0 else ""
		_ammo_value.add_theme_color_override("font_color", Color(1, 0.35, 0.3) if c.ammo[c.weapon] <= w.mag / 4 else Color.WHITE)
		for i in _slots.size():
			_slots[i].add_theme_color_override("font_color", UiTheme.ACCENT if i == c.weapon else Color(1, 1, 1, 0.35))
		_scope.visible = c.zoomed and c.alive
		_bottom.visible = c.alive and not c.zoomed
	var t := int(ceil(game.time_left))
	_timer.text = "%d:%02d" % [t / 60, t % 60]
	_timer.add_theme_color_override("font_color", Color(1, 0.4, 0.3) if t <= 30 else Color.WHITE)
	_update_scores_top()
	_board.visible = game.match_over or Input.is_action_pressed("scoreboard")
	_big.text = game.end_text if game.match_over else ""

	if game.match_over:
		_center.text = "Retour au salon dans quelques secondes..."
	elif _death_t > 0.0:
		_death_t -= delta
		var by := ("Éliminé par %s\n" % _death_by) if _death_by != "" else ""
		_center.text = by + "Réapparition dans %d" % int(ceil(maxf(_death_t, 0.0)))
	else:
		_center.text = ""
	_center_box.visible = _center.text != ""

	_hit_t = maxf(0.0, _hit_t - delta)
	_damage_a = move_toward(_damage_a, 0.0, delta * 1.6)
	var low := 0.0
	if c != null and c.alive and c.hp <= 30:
		low = 0.35 + 0.15 * sin(Time.get_ticks_msec() / 200.0)
	_vignette.modulate.a = maxf(_damage_a, low)
	_crosshair.queue_redraw()
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
	var limit: int = game.settings.score_limit
	if game.settings.mode == "team":
		var t: Array = game.team_scores()
		_score_left.text = "%s  %d" % [Data.TEAM_NAMES[0], t[0]]
		_score_right.text = "%d  %s" % [t[1], Data.TEAM_NAMES[1]]
	else:
		var mine := 0
		if game.local_char != null and game.scores.has(game.local_char.char_id):
			mine = game.scores[game.local_char.char_id]["kills"]
		var best := 0
		for id in game.scores:
			best = maxi(best, int(game.scores[id]["kills"]))
		_score_left.text = "TOI  %d" % mine
		_score_right.text = "%d  MENEUR" % best
	_goal.text = "PREMIER À %d ÉLIMINATIONS" % limit


func _draw_crosshair() -> void:
	var c = game.local_char
	if c != null and c.alive and not c.zoomed and not game.match_over:
		var gap := 7.0
		if c.weapon == 1:
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
