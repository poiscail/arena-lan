extends Control
## Armurerie : personnalisation de chaque arme (skin et accessoires) avec un aperçu 3D qui tourne.
## Les choix sont sauvegardés dans Net.armory et envoyés à l'hôte en rejoignant une partie.

signal closed

const Data := preload("res://scripts/data.gd")
const Models := preload("res://scripts/models.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")

var _list: ItemList
var _equip: Button
var _skin_opt: OptionButton
var _att_box: VBoxContainer
var _stats: RichTextLabel
var _preview_root: Node3D
var _gun: Node3D
var _wi := 0
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
	panel.add_theme_stylebox_override("panel", UiTheme.accent_panel(Color(0.04, 0.06, 0.1, 0.97), UiTheme.ACCENT, 22))
	panel.custom_minimum_size = Vector2(1060, 600)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var title := Label.new()
	title.text = "ARMURERIE"
	title.add_theme_font_override("font", UiTheme.font_title())
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)

	# Liste des armes
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(270, 0)
	_list.item_selected.connect(func(i: int) -> void:
		var wi = _list.get_item_metadata(i)
		if wi != null:
			_select(int(wi)))
	_fill_list()
	row.add_child(_list)

	# Aperçu 3D
	var vpc := SubViewportContainer.new()
	vpc.stretch = true
	vpc.custom_minimum_size = Vector2(460, 0)
	vpc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(vpc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_4X
	vpc.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.09, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.3
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.04, 1.5)
	cam.fov = 40.0
	vp.add_child(cam)
	_preview_root = Node3D.new()
	vp.add_child(_preview_root)

	# Réglages
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(320, 0)
	side.add_theme_constant_override("separation", 8)
	row.add_child(side)
	_equip = Button.new()
	_equip.pressed.connect(_equip_weapon)
	side.add_child(_equip)
	side.add_child(_section("SKIN"))
	_skin_opt = OptionButton.new()
	_skin_opt.item_selected.connect(func(i: int) -> void:
		if not _updating:
			_custom()["skin"] = i
			_save())
	side.add_child(_skin_opt)
	side.add_child(_section("ACCESSOIRES"))
	_att_box = VBoxContainer.new()
	_att_box.add_theme_constant_override("separation", 6)
	side.add_child(_att_box)
	side.add_child(_section("CARACTÉRISTIQUES"))
	_stats = RichTextLabel.new()
	_stats.bbcode_enabled = true
	_stats.fit_content = true
	_stats.scroll_active = false
	_stats.add_theme_font_size_override("normal_font_size", 15)
	side.add_child(_stats)

	var close := Button.new()
	close.text = "Fermer"
	close.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	v.add_child(close)


func open() -> void:
	visible = true
	_fill_list()
	_select(_wi)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		visible = false
		closed.emit()


func _process(delta: float) -> void:
	if visible and _gun != null:
		_preview_root.rotation.y += delta * 0.6


func _custom() -> Dictionary:
	var key := str(_wi)
	if not Net.armory.has(key) or not (Net.armory[key] is Dictionary):
		Net.armory[key] = {"skin": 0, "att": []}
	return Net.armory[key]


func _select(i: int) -> void:
	_wi = i
	_updating = true
	var c := _custom()
	var level: int = Data.level_info(Net.xp)[0]
	_skin_opt.clear()
	for k in Data.CAMOS.size():
		var cm: Dictionary = Data.CAMOS[k]
		var locked: bool = level < int(cm["level"])
		_skin_opt.add_item(cm["name"] + ("   (niveau %d)" % cm["level"] if locked else ""))
		_skin_opt.set_item_disabled(k, locked)
	var skin := clampi(int(c.get("skin", 0)), 0, Data.CAMOS.size() - 1)
	if level < int(Data.CAMOS[skin]["level"]):
		skin = 0
		c["skin"] = 0
	_skin_opt.select(skin)
	for ch in _att_box.get_children():
		ch.queue_free()
	var allowed := Data.attachments_for(_wi)
	if allowed.is_empty():
		var l := Label.new()
		l.text = "Pas d'accessoire pour cette arme."
		l.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		_att_box.add_child(l)
	for a in Data.ATTACHMENTS:
		if not allowed.has(a["id"]):
			continue
		var cb := CheckBox.new()
		cb.text = a["name"]
		cb.button_pressed = c.get("att", []).has(a["id"])
		cb.toggled.connect(_toggle_att.bind(a["id"]))
		_att_box.add_child(cb)
		var d := Label.new()
		d.text = "    " + a["desc"]
		d.add_theme_font_size_override("font_size", 13)
		d.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_att_box.add_child(d)
	_updating = false
	_refresh()
	_refresh_equip()


func _toggle_att(on: bool, id: String) -> void:
	if _updating:
		return
	var c := _custom()
	var att: Array = c.get("att", []).duplicate()
	if on and not att.has(id):
		# Un seul accessoire par emplacement : l'autre est retiré
		var slot := Data.attachment_slot(id)
		for other in att.duplicate():
			if Data.attachment_slot(other) == slot:
				att.erase(other)
		att.append(id)
	elif not on:
		att.erase(id)
	c["att"] = att
	Net.save_options()
	_select(_wi)


func _save() -> void:
	Net.save_options()
	_refresh()


func _refresh() -> void:
	var c := _custom()
	if _gun != null:
		_gun.queue_free()
	var w: Dictionary = Data.WEAPONS[_wi]
	_gun = Models.weapon(w.model, float(w.len) * 1.05)
	Models.add_attachments(_gun.get_child(0).get_child(0), c.get("att", []))
	Models.apply_camo(_gun, Data.CAMOS[clampi(int(c.get("skin", 0)), 0, Data.CAMOS.size() - 1)])
	# Vu de profil : canon vers la droite
	_gun.rotation.y = PI / 2.0
	_preview_root.add_child(_gun)
	var s := Data.weapon_stats(_wi, c)
	var line := func(name: String, base, val, better_low := false) -> String:
		var col := "#ffffff"
		if val != base:
			var good: bool = (val < base) if better_low else (val > base)
			col = "#7fe08a" if good else "#ff7a6b"
		return "%s : [color=%s]%s[/color]\n" % [name, col, str(val)]
	var t := ""
	t += line.call("Dégâts", int(w.damage), int(s.damage))
	t += line.call("Chargeur", int(w.mag), int(s.mag))
	t += line.call("Rechargement (s)", snappedf(float(w.reload), 0.01), snappedf(float(s.reload), 0.01), true)
	t += line.call("Recul", snappedf(float(w.recoil) * 1000.0, 0.1), snappedf(float(s.recoil) * 1000.0, 0.1), true)
	t += line.call("Dispersion", snappedf(float(w.spread), 0.01), snappedf(float(s.spread), 0.01), true)
	t += "Cadence : %d tirs/min" % int(60.0 / float(w.rate))
	_stats.text = t


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.font_bold())
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", UiTheme.ACCENT)
	return l


## Liste des armes rangées par famille ; ★ = arme utilisée pour sa famille.
func _fill_list() -> void:
	_list.clear()
	for cat in Data.CAT_ORDER:
		var h := _list.add_item("— " + String(Data.CATS[cat]).to_upper() + " —")
		_list.set_item_selectable(h, false)
		_list.set_item_custom_fg_color(h, UiTheme.ACCENT)
		for wi in Data.WEAPONS.size():
			if Data.WEAPONS[wi].cat != cat:
				continue
			var used := _used_for(cat) == wi
			var idx := _list.add_item(("★ " if used else "    ") + String(Data.WEAPONS[wi].name))
			_list.set_item_metadata(idx, wi)
			if wi == _wi:
				_list.select(idx)
				_list.ensure_current_is_visible()


## Arme choisie pour une famille (par défaut celle des classes).
func _used_for(cat: String) -> int:
	var picks = Net.armory.get("pick", {})
	if picks is Dictionary and picks.has(cat):
		return int(picks[cat])
	for cl in Data.CLASSES:
		for wi in cl["weapons"]:
			if Data.WEAPONS[wi].cat == cat:
				return wi
	return -1


func _equip_weapon() -> void:
	var cat: String = Data.WEAPONS[_wi].cat
	var picks = Net.armory.get("pick", {})
	if not (picks is Dictionary):
		picks = {}
	picks[cat] = _wi
	Net.armory["pick"] = picks
	Net.save_options()
	_fill_list()
	_refresh_equip()


func _refresh_equip() -> void:
	var cat: String = Data.WEAPONS[_wi].cat
	if _used_for(cat) == _wi:
		_equip.text = "✓ Utilisée pour les %s" % String(Data.CATS[cat]).to_lower()
		_equip.disabled = true
	else:
		_equip.text = "Utiliser cette arme (%s)" % String(Data.CATS[cat]).to_lower()
		_equip.disabled = false
