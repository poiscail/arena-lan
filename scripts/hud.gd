extends CanvasLayer
## Interface en jeu : viseur, vie, munitions, scores, fil des éliminations, pause.

const Data := preload("res://scripts/data.gd")

var game
var paused := false

var _crosshair: Control
var _scope: Control
var _hp: Label
var _ammo: Label
var _timer: Label
var _top: RichTextLabel
var _feed: VBoxContainer
var _center: Label
var _big: Label
var _board: PanelContainer
var _board_text: RichTextLabel
var _damage: ColorRect
var _pause: PanelContainer

var _hit_t := 0.0
var _hit_color := Color.WHITE
var _death_t := 0.0
var _death_by := ""


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_damage = ColorRect.new()
	_damage.color = Color(1, 0, 0, 0)
	_place(_damage, 0, 0, 1, 1)
	root.add_child(_damage)

	_scope = Control.new()
	_place(_scope, 0, 0, 1, 1)
	_scope.visible = false
	_scope.draw.connect(_draw_scope)
	root.add_child(_scope)

	_crosshair = Control.new()
	_place(_crosshair, 0.5, 0.5, 0.5, 0.5)
	_crosshair.draw.connect(_draw_crosshair)
	root.add_child(_crosshair)

	_hp = _label(30)
	_place(_hp, 0, 1, 0, 1, 28, -70, 400, -20)
	root.add_child(_hp)

	_ammo = _label(30)
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(_ammo, 1, 1, 1, 1, -600, -70, -28, -20)
	root.add_child(_ammo)

	_timer = _label(26)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_timer, 0.5, 0, 0.5, 0, -100, 10, 100, 44)
	root.add_child(_timer)

	_top = _rich(22)
	_place(_top, 0.5, 0, 0.5, 0, -400, 48, 400, 90)
	root.add_child(_top)

	_feed = VBoxContainer.new()
	_place(_feed, 1, 0, 1, 0, -480, 12, -16, 320)
	root.add_child(_feed)

	_center = _label(26)
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_center, 0, 0.5, 1, 0.5, 0, 50, 0, 100)
	root.add_child(_center)

	_big = _label(46)
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.modulate = Color(1, 0.9, 0.45)
	_place(_big, 0, 0.18, 1, 0.18, 0, -40, 0, 30)
	root.add_child(_big)

	_board = PanelContainer.new()
	_board.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.06, 0.09, 0.85)))
	_place(_board, 0.5, 0.5, 0.5, 0.5, -340, -230, 340, 250)
	_board.visible = false
	root.add_child(_board)
	_board_text = _rich(18)
	_board.add_child(_board_text)

	_build_pause(root)
	refresh_scores()


func _build_pause(root: Control) -> void:
	_pause = PanelContainer.new()
	_pause.add_theme_stylebox_override("panel", _panel_style(Color(0.1, 0.11, 0.15, 0.95)))
	_place(_pause, 0.5, 0.5, 0.5, 0.5, -200, -150, 200, 150)
	_pause.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause.visible = false
	root.add_child(_pause)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_pause.add_child(v)
	var title := _label(30)
	title.text = "Pause"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var resume := Button.new()
	resume.text = "Reprendre"
	resume.pressed.connect(toggle_pause)
	v.add_child(resume)
	var sens := _label(18)
	sens.text = "Sensibilité de la souris"
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
	_damage.color.a = 0.35


func show_death(killer: String) -> void:
	_death_t = Data.RESPAWN_TIME
	_death_by = killer


func add_kill(bbcode: String) -> void:
	var r := _rich(18)
	r.text = "[right]%s[/right]" % bbcode
	r.custom_minimum_size = Vector2(460, 0)
	r.set_meta("t", 6.0)
	_feed.add_child(r)
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
	var txt := "[center][font_size=26]Scores[/font_size][/center]\n"
	var groups := [0, 1] if game.settings.mode == "team" else [-1]
	var totals: Array = game.team_scores()
	for g in groups:
		if g >= 0:
			txt += "\n[color=%s][b]%s   %d[/b][/color]\n" % [Data.TEAM_HEX[g], Data.TEAM_NAMES[g], totals[g]]
		txt += "[table=3][cell][color=#999999]Joueur          [/color][/cell][cell][color=#999999]Élim.   [/color][/cell][cell][color=#999999]Morts[/color][/cell]"
		for s in rows:
			if g >= 0 and s["team"] != g:
				continue
			var n := Data.esc(s["name"])
			if s["id"] == me:
				n = "[color=#ffd75e][b]%s[/b][/color]" % n
			txt += "[cell]%s[/cell][cell]%d[/cell][cell]%d[/cell]" % [n, s["kills"], s["deaths"]]
		txt += "[/table]\n"
	_board_text.text = txt


# --- Boucle -----------------------------------------------------------------------

func _process(delta: float) -> void:
	var c = game.local_char
	if c != null:
		_hp.text = "PV  %d" % c.hp
		_hp.modulate = Color(1, 0.35, 0.3) if c.hp <= 30 else Color.WHITE
		var w: Dictionary = Data.WEAPONS[c.weapon]
		if c.reloading > 0.0:
			_ammo.text = "%s   rechargement..." % w.name
		else:
			_ammo.text = "%s   %d / %d" % [w.name, c.ammo[c.weapon], w.mag]
		_scope.visible = c.zoomed and c.alive
	var t := int(ceil(game.time_left))
	_timer.text = "%d:%02d" % [t / 60, t % 60]
	_top.text = "[center]%s[/center]" % game.score_summary()
	_board.visible = game.match_over or Input.is_action_pressed("scoreboard")
	_big.text = game.end_text if game.match_over else ""

	if game.match_over:
		_center.text = "Retour au salon dans quelques secondes..."
	elif _death_t > 0.0:
		_death_t -= delta
		var by := ("Éliminé par %s  —  " % _death_by) if _death_by != "" else ""
		_center.text = by + "réapparition dans %d" % int(ceil(maxf(_death_t, 0.0)))
	else:
		_center.text = ""

	_hit_t = maxf(0.0, _hit_t - delta)
	_damage.color.a = move_toward(_damage.color.a, 0.0, delta * 1.5)
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


func _draw_crosshair() -> void:
	var c = game.local_char
	if c != null and c.alive and not c.zoomed and not game.match_over:
		var gap := 6.0
		var col := Color(1, 1, 1, 0.9)
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			_crosshair.draw_line(d * gap, d * (gap + 9.0), Color(0, 0, 0, 0.7), 4.0)
			_crosshair.draw_line(d * gap, d * (gap + 9.0), col, 2.0)
		_crosshair.draw_circle(Vector2.ZERO, 1.5, col)
	if _hit_t > 0.0:
		var hc := _hit_color
		hc.a = _hit_t / 0.25
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_crosshair.draw_line(d * 6.0, d * 14.0, hc, 2.5)


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


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
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
	r.add_theme_constant_override("outline_size", 6)
	r.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _panel_style(color: Color) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = color
	st.set_corner_radius_all(10)
	st.set_content_margin_all(20)
	return st
