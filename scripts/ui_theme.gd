extends RefCounted
## Thème visuel commun : polices (Rajdhani, Orbitron) et panneaux / boutons sci-fi à coins biseautés.

const ACCENT := Color(1.0, 0.6, 0.15)
const ACCENT_DARK := Color(0.55, 0.3, 0.05)
const CYAN := Color(0.35, 0.82, 1.0)
const TEXT := Color(0.92, 0.94, 1.0)
const TEXT_DIM := Color(0.62, 0.66, 0.76)
const BG := Color(0.05, 0.07, 0.11, 0.86)

static var _body: Font
static var _bold: Font
static var _title: Font


static func font_body() -> Font:
	if _body == null:
		_body = load("res://assets/fonts/Rajdhani-SemiBold.ttf")
	return _body


static func font_bold() -> Font:
	if _bold == null:
		_bold = load("res://assets/fonts/Rajdhani-Bold.ttf")
	return _bold


static func font_title() -> Font:
	if _title == null:
		var fv := FontVariation.new()
		fv.base_font = load("res://assets/fonts/Orbitron.ttf")
		var ts := TextServerManager.get_primary_interface()
		fv.variation_opentype = {ts.name_to_tag("wght"): 800}
		_title = fv
	return _title


## Panneau à coins biseautés (style sci-fi).
static func panel(bg := BG, border := Color(1, 1, 1, 0.1), margin := 18.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.corner_detail = 1
	sb.set_content_margin_all(margin)
	return sb


static func accent_panel(bg := BG, accent := ACCENT, margin := 18.0) -> StyleBoxFlat:
	var sb := panel(bg, Color(1, 1, 1, 0.08), margin)
	sb.border_width_left = 4
	sb.border_color = accent
	return sb


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font_body()
	t.default_font_size = 20

	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, _button(Color(0.11, 0.14, 0.2, 0.95), Color(1, 1, 1, 0.14)))
		t.set_stylebox("hover", type, _button(Color(0.16, 0.2, 0.29, 0.98), ACCENT))
		t.set_stylebox("pressed", type, _button(ACCENT_DARK, ACCENT))
		t.set_stylebox("disabled", type, _button(Color(0.1, 0.11, 0.14, 0.7), Color(1, 1, 1, 0.05)))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_font("font", type, font_bold())
		t.set_font_size("font_size", type, 21)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, ACCENT)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, TEXT_DIM)

	var le := panel(Color(0.03, 0.04, 0.07, 0.95), Color(1, 1, 1, 0.16), 8)
	le.content_margin_left = 12
	var le_focus := le.duplicate()
	le_focus.border_color = ACCENT
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le_focus)
	t.set_stylebox("read_only", "LineEdit", le)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.3))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))
	t.set_font_size("font_size", "LineEdit", 20)

	t.set_stylebox("panel", "PopupMenu", panel(Color(0.06, 0.08, 0.12, 0.98), Color(1, 1, 1, 0.15), 6))
	t.set_stylebox("hover", "PopupMenu", panel(Color(ACCENT_DARK, 0.9), Color(0, 0, 0, 0), 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", ACCENT)
	t.set_color("font_pressed_color", "CheckBox", TEXT)
	t.set_color("font_hover_pressed_color", "CheckBox", ACCENT)

	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("separator", "HSeparator", _line())

	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color(1, 1, 1, 0.15)
	slider_bg.content_margin_top = 3
	slider_bg.content_margin_bottom = 3
	var slider_fill := slider_bg.duplicate()
	slider_fill.bg_color = ACCENT
	t.set_stylebox("slider", "HSlider", slider_bg)
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)

	t.set_font("normal_font", "RichTextLabel", font_body())
	t.set_font("bold_font", "RichTextLabel", font_bold())
	t.set_color("default_color", "RichTextLabel", TEXT)
	return t


static func _button(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := panel(bg, border, 10)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.set_corner_radius_all(8)
	return sb


static func _line() -> StyleBoxLine:
	var l := StyleBoxLine.new()
	l.color = Color(1, 1, 1, 0.12)
	l.thickness = 1
	return l
