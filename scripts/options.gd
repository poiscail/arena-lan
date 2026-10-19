extends Control
## Fenêtre d'options (graphismes et souris), ouverte depuis le menu principal ou la pause.
## Chaque réglage est appliqué tout de suite et sauvegardé (Net.set_gfx).

signal closed

const UiTheme := preload("res://scripts/ui_theme.gd")

const PRESETS := {
	"Basse": {"shadows": 0, "msaa": 0, "scale": 70, "fog": false, "view": 0},
	"Moyenne": {"shadows": 1, "msaa": 0, "scale": 100, "fog": true, "view": 1},
	"Haute": {"shadows": 2, "msaa": 1, "scale": 100, "fog": true, "view": 1},
	"Ultra": {"shadows": 3, "msaa": 2, "scale": 100, "fog": true, "view": 2},
}

var _controls := {}
var _refreshing := false
var _key_buttons := {}
var _waiting := ""  # action dont on attend la nouvelle touche


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.accent_panel(Color(0.04, 0.06, 0.1, 0.97), UiTheme.ACCENT, 26))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	panel.custom_minimum_size = Vector2(600, 0)
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var title := Label.new()
	title.text = "OPTIONS"
	title.add_theme_font_override("font", UiTheme.font_title())
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 520)
	v.add_child(tabs)
	var gv := VBoxContainer.new()
	gv.name = "Graphismes"
	gv.add_theme_constant_override("separation", 12)
	tabs.add_child(gv)
	_build_keys(tabs)

	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 8)
	var pl := _dim_label("Préréglage")
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	presets.add_child(pl)
	for name in PRESETS:
		var b := Button.new()
		b.text = name
		b.pressed.connect(_apply_preset.bind(name))
		presets.add_child(b)
	gv.add_child(presets)
	gv.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 8)
	gv.add_child(grid)

	_option(grid, "shadows", "Ombres", ["Désactivées", "Basses", "Moyennes", "Hautes"])
	_option(grid, "msaa", "Anticrénelage", ["Non", "MSAA 2x", "MSAA 4x", "MSAA 8x"])
	_slider(grid, "scale", "Résolution 3D", 50, 100, 5, "%d %%")
	_option(grid, "view", "Distance de vue", ["Courte", "Moyenne", "Longue"])
	_check(grid, "fog", "Brouillard")
	_slider(grid, "brightness", "Luminosité", 60, 150, 5, "%d %%")
	_slider(grid, "fov", "Champ de vision", 65, 110, 1, "%d°")
	_check(grid, "fullscreen", "Plein écran")
	_check(grid, "vsync", "Synchro verticale")
	var fps_names := []
	for f in Net.FPS_LIMITS:
		fps_names.append("Illimité" if f == 0 else "%d IPS" % f)
	_option(grid, "fps_limit", "Limite d'images", fps_names)
	_check(grid, "show_fps", "Afficher les IPS")

	grid.add_child(_dim_label("Sensibilité souris"))
	var sens := _slider_box(0.5, 8.0, 0.1, "%.1f")
	sens[0].value = Net.mouse_sensitivity * 1000.0
	sens[0].value_changed.emit(sens[0].value)
	sens[0].value_changed.connect(func(val: float) -> void:
		Net.mouse_sensitivity = val / 1000.0
		Net.save_options())
	grid.add_child(sens[1])

	var close := Button.new()
	close.text = "Fermer"
	close.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	v.add_child(close)
	_refresh()


func open() -> void:
	_refresh()
	visible = true


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		visible = false
		closed.emit()


func _apply_preset(name: String) -> void:
	for k in PRESETS[name]:
		Net.gfx[k] = PRESETS[name][k]
	Net.set_gfx("shadows", Net.gfx.shadows)
	_refresh()


func _refresh() -> void:
	_refreshing = true
	for k in _controls:
		var c = _controls[k]
		if c is OptionButton:
			c.select(int(Net.gfx[k]))
		elif c is CheckButton:
			c.button_pressed = bool(Net.gfx[k])
		elif c is HSlider:
			c.value = float(Net.gfx[k])
			c.value_changed.emit(c.value)
	_refreshing = false


func _changed(value, key: String) -> void:
	if not _refreshing:
		Net.set_gfx(key, value)


func _option(grid: GridContainer, key: String, text: String, items: Array) -> void:
	grid.add_child(_dim_label(text))
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.item_selected.connect(_changed.bind(key))
	grid.add_child(o)
	_controls[key] = o


func _check(grid: GridContainer, key: String, text: String) -> void:
	grid.add_child(_dim_label(text))
	var c := CheckButton.new()
	c.toggled.connect(_changed.bind(key))
	grid.add_child(c)
	_controls[key] = c


func _slider(grid: GridContainer, key: String, text: String, lo: float, hi: float, step: float, fmt: String) -> void:
	grid.add_child(_dim_label(text))
	var s := _slider_box(lo, hi, step, fmt)
	s[0].value_changed.connect(func(val: float) -> void: _changed(int(val), key))
	grid.add_child(s[1])
	_controls[key] = s[0]


## Renvoie [HSlider, conteneur] : le curseur et sa valeur affichée à droite.
func _slider_box(lo: float, hi: float, step: float, fmt: String) -> Array:
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var lab := Label.new()
	lab.custom_minimum_size.x = 64
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lab.text = fmt % lo
	s.value_changed.connect(func(val: float) -> void: lab.text = fmt % val)
	box.add_child(s)
	box.add_child(lab)
	return [s, box]


func _dim_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.font_bold())
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	return l


# --- Touches ---------------------------------------------------------------------------

func _build_keys(tabs: TabContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Touches"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var kv := VBoxContainer.new()
	kv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kv.add_theme_constant_override("separation", 10)
	scroll.add_child(kv)
	var help := _dim_label("Clique sur une touche puis appuie sur la nouvelle (Échap pour annuler).")
	help.add_theme_font_size_override("font_size", 14)
	kv.add_child(help)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kv.add_child(grid)
	for a in Net.REBINDABLE:
		var l := _dim_label(a[1])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(l)
		var b := Button.new()
		b.custom_minimum_size = Vector2(220, 0)
		b.pressed.connect(func() -> void:
			_waiting = a[0]
			_refresh_keys()
			b.text = "Appuie sur une touche...")
		grid.add_child(b)
		_key_buttons[a[0]] = b
	var reset := Button.new()
	reset.text = "Touches par défaut"
	reset.pressed.connect(func() -> void:
		Net.reset_bindings()
		_waiting = ""
		_refresh_keys())
	kv.add_child(reset)
	_refresh_keys()


func _refresh_keys() -> void:
	for a in _key_buttons:
		_key_buttons[a].text = Net.binding_text(a)


func _input(event: InputEvent) -> void:
	if _waiting == "" or not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode != KEY_ESCAPE:
			Net.set_binding(_waiting, event)
	elif event is InputEventMouseButton and event.pressed:
		Net.set_binding(_waiting, event)
	else:
		return
	get_viewport().set_input_as_handled()
	_waiting = ""
	_refresh_keys()
