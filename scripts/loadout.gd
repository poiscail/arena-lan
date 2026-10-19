extends Control
## Éditeur « Classes et armes » : choisir sa classe et ses armes 1, 2 et 3 (parmi toutes les armes).
## Ouvert depuis le menu principal ou la pause ; en partie, les changements s'appliquent à la
## prochaine apparition. Les choix sont sauvegardés dans Net.armory["loadouts"][classe].

signal closed
signal changed  # classe ou armes modifiées
signal open_armory(wi: int)  # « Accessoires » d'une arme

const Data := preload("res://scripts/data.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")

var in_game := false
var _cls_opt: OptionButton
var _cls_info: Label
var _slots: Array[OptionButton] = []
var _stats: Array[Label] = []
var _note: Label
var _updating := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.accent_panel(Color(0.04, 0.06, 0.1, 0.97), UiTheme.ACCENT, 24))
	panel.custom_minimum_size = Vector2(720, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var title := Label.new()
	title.text = "CLASSES ET ARMES"
	title.add_theme_font_override("font", UiTheme.font_title())
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	v.add_child(_section("CLASSE"))
	_cls_opt = OptionButton.new()
	for cl in Data.CLASSES:
		_cls_opt.add_item(cl["name"])
	_cls_opt.item_selected.connect(func(i: int) -> void:
		if _updating:
			return
		Net.player_class = i
		Net.save_options()
		_refresh()
		changed.emit())
	v.add_child(_cls_opt)
	_cls_info = Label.new()
	_cls_info.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_cls_info.add_theme_font_size_override("font_size", 14)
	v.add_child(_cls_info)

	for s in 3:
		v.add_child(_section("ARME %d" % (s + 1)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		v.add_child(row)
		var opt := OptionButton.new()
		opt.custom_minimum_size = Vector2(300, 0)
		opt.fit_to_longest_item = false
		for cat in Data.CAT_ORDER:
			opt.add_separator(String(Data.CATS[cat]))
			for wi in Data.WEAPONS.size():
				if Data.WEAPONS[wi].cat == cat:
					opt.add_item(String(Data.WEAPONS[wi].name), wi)
		opt.item_selected.connect(_on_weapon_selected.bind(s))
		row.add_child(opt)
		var acc := Button.new()
		acc.text = "Accessoires…"
		acc.pressed.connect(func() -> void: open_armory.emit(_current()[s]))
		row.add_child(acc)
		var st := Label.new()
		st.add_theme_font_size_override("font_size", 13)
		st.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(st)
		_slots.append(opt)
		_stats.append(st)

	_note = Label.new()
	_note.add_theme_color_override("font_color", UiTheme.ACCENT)
	_note.add_theme_font_size_override("font_size", 14)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_note)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	v.add_child(buttons)
	var reset := Button.new()
	reset.text = "Armes par défaut de la classe"
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(func() -> void:
		var lo = Net.armory.get("loadouts", {})
		if lo is Dictionary:
			lo.erase(str(Net.player_class))
		Net.save_options()
		_refresh()
		changed.emit())
	buttons.add_child(reset)
	var close := Button.new()
	close.text = "Fermer"
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(_close)
	buttons.add_child(close)


func open() -> void:
	visible = true
	_refresh()


func _close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()


func _current() -> Array:
	return Data.class_weapons(Net.player_class, Net.armory)


func _refresh() -> void:
	_updating = true
	var cls: int = clampi(Net.player_class, 0, Data.CLASSES.size() - 1)
	_cls_opt.select(cls)
	var cl: Dictionary = Data.CLASSES[cls]
	var speed := float(cl["speed"])
	var speed_txt := "vitesse normale" if is_equal_approx(speed, 1.0) else ("vitesse %+d %%" % int(round((speed - 1.0) * 100.0)))
	_cls_info.text = "%s · par défaut : %s" % [speed_txt, cl["desc"].split(" · ")[0]]
	var cur := _current()
	for s in 3:
		_slots[s].select(_slots[s].get_item_index(cur[s]))
		var w: Dictionary = Data.weapon_stats(cur[s], Net.armory.get(str(cur[s]), {}))
		_stats[s].text = "%d dégâts · %d tirs/min · chargeur %d" % [int(w.damage) * int(w.pellets), int(60.0 / float(w.rate)), int(w.mag)]
	_note.text = "Les changements s'appliquent à ta prochaine apparition." if in_game else ""
	_updating = false


## Choix d'une arme pour un emplacement ; si elle est déjà dans un autre, les deux s'échangent.
func _on_weapon_selected(index: int, s: int) -> void:
	if _updating:
		return
	var wi := _slots[s].get_item_id(index)
	var cur := _current()
	var other := cur.find(wi)
	if other >= 0 and other != s:
		cur[other] = cur[s]
	cur[s] = wi
	var lo = Net.armory.get("loadouts", {})
	if not (lo is Dictionary):
		lo = {}
	lo[str(Net.player_class)] = cur
	Net.armory["loadouts"] = lo
	Net.save_options()
	_refresh()
	changed.emit()


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.font_bold())
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", UiTheme.ACCENT)
	return l
