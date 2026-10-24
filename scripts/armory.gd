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
var _charm_opt: OptionButton
var _sticker_opt: OptionButton
var _progress: Label
var _progress_bar: ProgressBar
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
	_progress = Label.new()
	_progress.add_theme_font_size_override("font_size", 13)
	_progress.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_progress)
	_progress_bar = ProgressBar.new()
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size = Vector2(0, 8)
	side.add_child(_progress_bar)
	var all := Button.new()
	all.text = "Mettre ce skin sur toutes les armes qui l'ont"
	all.pressed.connect(func() -> void:
		var sk := int(_custom().get("skin", 0))
		for wi in Data.WEAPONS.size():
			if Net.kills_with(wi) < Data.skin_kills(sk):
				continue  # pas encore débloqué pour cette arme
			var key := str(wi)
			if not (Net.armory.get(key) is Dictionary):
				Net.armory[key] = {"skin": 0, "att": []}
			Net.armory[key]["skin"] = sk
		_save())
	side.add_child(all)
	side.add_child(_section("BRELOQUE ET AUTOCOLLANT"))
	_charm_opt = _trinket_option("charm")
	side.add_child(_charm_opt)
	_sticker_opt = _trinket_option("sticker")
	side.add_child(_sticker_opt)
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
	# Skins débloqués par les éliminations faites avec cette arme
	var kills := Net.kills_with(_wi)
	var skin := clampi(int(c.get("skin", 0)), 0, Data.CAMOS.size() - 1)
	_skin_opt.clear()
	var next := -1
	for k in Data.CAMOS.size():
		var cm: Dictionary = Data.CAMOS[k]
		var need := Data.skin_kills(k)
		var locked: bool = kills < need and k != skin  # le skin déjà équipé reste disponible
		if kills < need and (next < 0 or need < Data.skin_kills(next)):
			next = k
		var rar: String = Data.RARITIES[int(cm.get("r", 0))]["name"]
		_skin_opt.add_icon_item(_swatch(k), "%s  ·  %s%s" % [cm["name"], rar, ("   (%d / %d élim.)" % [kills, need] if kills < need else "")])
		_skin_opt.set_item_disabled(k, locked)
	_skin_opt.select(skin)
	var weapon_name: String = Data.WEAPONS[_wi].name
	if next < 0:
		_progress.text = "%d éliminations avec %s · tous les skins sont débloqués !" % [kills, weapon_name]
		_progress_bar.min_value = 0
		_progress_bar.max_value = 1
		_progress_bar.value = 1
	else:
		var prev := 0
		for k in Data.CAMOS.size():
			if Data.skin_kills(k) <= kills:
				prev = maxi(prev, Data.skin_kills(k))
		_progress.text = "%d éliminations avec %s · prochain skin : %s à %d" % [kills, weapon_name, Data.CAMOS[next]["name"], Data.skin_kills(next)]
		_progress_bar.max_value = Data.skin_kills(next)
		_progress_bar.min_value = prev
		_progress_bar.value = kills
	_fill_trinkets(_charm_opt, Data.CHARMS, int(c.get("charm", 0)))
	_fill_trinkets(_sticker_opt, Data.STICKERS, int(c.get("sticker", 0)))
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
	Models.add_trinkets(_gun.get_child(0).get_child(0), c)
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


static var _swatches := {}

## Petite pastille du skin : ses couleurs, avec un liseré de la couleur de sa rareté.
func _swatch(k: int) -> ImageTexture:
	if _swatches.has(k):
		return _swatches[k]
	var cm: Dictionary = Data.CAMOS[k]
	var img := Image.create_empty(28, 18, false, Image.FORMAT_RGBA8)
	var cols: Array = [cm.get("c1", Color(0.35, 0.33, 0.3)), cm.get("c2", cm.get("c1", Color(0.25, 0.25, 0.25))), cm.get("c3", cm.get("c2", cm.get("c1", Color(0.2, 0.2, 0.2))))]
	var rc: Color = Data.RARITIES[int(cm.get("r", 0))]["color"]
	for y in 18:
		for x in 28:
			var c: Color = cols[clampi(int((x + y * 0.5) / 10.0), 0, 2)]
			if x < 2 or y < 2 or x > 25 or y > 15:
				c = rc
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_swatches[k] = tex
	return tex


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


## Liste déroulante d'une breloque ou d'un autocollant (même choix pour cette arme seulement).
func _trinket_option(key: String) -> OptionButton:
	var opt := OptionButton.new()
	opt.item_selected.connect(func(i: int) -> void:
		if not _updating:
			_custom()[key] = i
			_save())
	return opt


## Remplit la liste : débloqués par le niveau du joueur, le choix actuel reste disponible.
func _fill_trinkets(opt: OptionButton, items: Array, current: int) -> void:
	var lvl: int = Data.level_info(Net.xp)[0]
	opt.clear()
	for k in items.size():
		var it: Dictionary = items[k]
		var need := int(it.get("lvl", 1))
		var rar: String = Data.RARITIES[int(it.get("r", 0))]["name"]
		var label: String = it["name"] if k == 0 else "%s  ·  %s%s" % [it["name"], rar, ("   (niveau %d)" % need if lvl < need else "")]
		opt.add_item(label)
		opt.set_item_disabled(k, lvl < need and k != current)
	opt.select(clampi(current, 0, items.size() - 1))
