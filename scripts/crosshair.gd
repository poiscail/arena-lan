extends RefCounted
## Réticule personnalisable (Options > Réticule) : forme, couleur, taille, écart, épaisseur, contour.
## Dessiné par le HUD et par l'aperçu des options.

const STYLES := ["Croix", "Croix + point", "Point", "Cercle", "Cercle + point", "Croix en T"]
const COLORS := [Color(1, 1, 1), Color(0.3, 1.0, 0.4), Color(1.0, 0.92, 0.25), Color(0.3, 0.95, 1.0),
	Color(1.0, 0.4, 0.85), Color(1.0, 0.3, 0.25), Color(1.0, 0.6, 0.2)]
const COLOR_NAMES := ["Blanc", "Vert", "Jaune", "Cyan", "Rose", "Rouge", "Orange"]


## Écart de base (px) choisi dans les options.
static func base_gap() -> float:
	return float(Net.gfx.get("xh_gap", 7))


## Vrai si le réticule s'écarte quand on bouge.
static func dynamic() -> bool:
	return bool(Net.gfx.get("xh_dynamic", true))


static func draw(ci: CanvasItem, gap: float) -> void:
	var g: Dictionary = Net.gfx
	var style := int(g.get("xh_style", 1))
	var col: Color = COLORS[clampi(int(g.get("xh_color", 0)), 0, COLORS.size() - 1)]
	col.a = clampf(float(g.get("xh_alpha", 95)) / 100.0, 0.1, 1.0)
	var length := float(g.get("xh_size", 10))
	var thick := float(g.get("xh_thick", 2))
	var outline := bool(g.get("xh_outline", true))
	var shadow := Color(0, 0, 0, 0.6 * col.a)
	if style in [0, 1, 5]:
		var dirs := [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN] if style == 5 else [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
		for d in dirs:
			if outline:
				ci.draw_line(d * (gap - 1.0), d * (gap + length + 1.0), shadow, thick + 2.0)
			ci.draw_line(d * gap, d * (gap + length), col, thick)
	if style in [3, 4]:
		var r := gap + length * 0.5
		if outline:
			ci.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, shadow, thick + 2.0)
		ci.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, col, thick)
	if style in [1, 2, 4, 5]:
		var dr := maxf(1.2, thick * 0.8) if style != 2 else maxf(2.0, thick * 1.3)
		if outline:
			ci.draw_circle(Vector2.ZERO, dr + 1.0, shadow)
		ci.draw_circle(Vector2.ZERO, dr, col)
