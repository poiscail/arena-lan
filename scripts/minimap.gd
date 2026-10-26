extends Control
## Mini-carte (haut gauche du HUD) : tournée dans le sens du regard, centrée sur le joueur.
## Décor, coéquipiers, ennemis qui tirent sans silencieux, radar, signalements et objectifs du mode.

const Data := preload("res://scripts/data.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
const MapScript := preload("res://scripts/map.gd")
const ModesScript := preload("res://scripts/modes.gd")

const SIZE := 220.0
const RANGE := 30.0      # mètres visibles du centre au bord
const SHOT_SHOW := 2.5   # un ennemi qui tire reste visible ce temps (s)

var game
var hud
var _shots := {}  # char_id -> temps restant affiché après un tir
var _bg: StyleBoxFlat


func _init() -> void:
	_bg = UiTheme.panel(Color(0.03, 0.05, 0.09, 0.72), Color(1, 1, 1, 0.12), 0)
	_bg.set_corner_radius_all(6)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SIZE, SIZE)


## Un tir non silencieux révèle le tireur sur la mini-carte des autres.
func mark_shot(char_id: String) -> void:
	_shots[char_id] = SHOT_SHOW


func _process(delta: float) -> void:
	for id in _shots.keys():
		_shots[id] -= delta
		if _shots[id] <= 0.0:
			_shots.erase(id)
	if visible:
		queue_redraw()


func _draw() -> void:
	var c = game.local_char
	var cam: Camera3D = get_viewport().get_camera_3d()
	if c == null or cam == null:
		return
	var center := Vector2(SIZE, SIZE) / 2.0
	var ppm := center.x / RANGE
	var fwd := -cam.global_transform.basis.z
	var yaw := atan2(fwd.x, fwd.z)
	var me := Vector2(c.global_position.x, c.global_position.z)
	# Monde (x, z) -> écran : le regard pointe vers le haut
	var to_screen := func(p: Vector2) -> Vector2:
		var d := (p - me).rotated(yaw)
		return center + Vector2(-d.x, -d.y) * ppm

	draw_style_box(_bg, Rect2(Vector2.ZERO, size))

	# Limites de l'arène et décor
	var h: float = MapScript.HALF
	var border := PackedVector2Array()
	for k in [Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h), Vector2(-h, -h)]:
		border.append(to_screen.call(k))
	draw_colored_polygon(border.slice(0, 4), Color(1, 1, 1, 0.05))
	draw_polyline(border, Color(1, 1, 1, 0.35), 1.5)
	var reach := RANGE * 1.5
	for o in game.map.obstacles():
		var oc: Vector2 = o[0]
		var oh: Vector2 = o[1]
		if oc.distance_to(me) > reach + oh.length():
			continue
		var pts := PackedVector2Array([to_screen.call(oc + Vector2(-oh.x, -oh.y)), to_screen.call(oc + Vector2(oh.x, -oh.y)),
			to_screen.call(oc + Vector2(oh.x, oh.y)), to_screen.call(oc + Vector2(-oh.x, oh.y))])
		draw_colored_polygon(pts, Color(0.62, 0.66, 0.72, 0.55))

	# Véhicules
	for id in game.vehicles.vehicles:
		var body: Node3D = game.vehicles.vehicles[id]["body"]
		if is_instance_valid(body):
			_square(to_screen.call(Vector2(body.global_position.x, body.global_position.z)), 4.0, Color(0.85, 0.85, 0.9, 0.8))

	_draw_objectives(c, to_screen, ppm)

	# Signalements
	for p in hud._pings:
		var col := Color(1, 0.3, 0.25) if p["enemy"] else Color(1, 0.85, 0.3)
		col.a = clampf(p["t"], 0.0, 1.0)
		var s: Vector2 = _clamp_edge(to_screen.call(Vector2(p["pos"].x, p["pos"].z)), center)
		draw_arc(s, 6.0, 0.0, TAU, 16, col, 2.0)
		draw_string(UiTheme.font_title(), s + Vector2(-3, 5), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)

	# Personnages
	for id in game.chars:
		var o = game.chars[id]
		if o == c or not o.alive:
			continue
		var p: Vector2 = to_screen.call(Vector2(o.global_position.x, o.global_position.z))
		if not game.is_enemy(c, o):
			_arrow(p, _yaw_of(o) - yaw, 6.0, Data.TEAM_COLORS[o.team] if o.team >= 0 else Color(0.4, 0.8, 1.0))
		elif hud.radar_t > 0.0 or o.zombie or _shots.has(id):
			var a := 1.0 if hud.radar_t > 0.0 or o.zombie else clampf(_shots[id] / 0.8, 0.0, 1.0)
			draw_circle(p, 4.5, Color(1, 0.22, 0.18, a))
			draw_arc(p, 4.5, 0.0, TAU, 14, Color(0, 0, 0, 0.6 * a), 1.2)

	# Le joueur, au centre, regarde toujours vers le haut
	_arrow(center, 0.0, 8.0, Color.WHITE)


func _draw_objectives(c, to_screen: Callable, ppm: float) -> void:
	var m = game.modes
	var font := UiTheme.font_title()
	match m.rules:
		"ctf":
			for f in m._flags:
				var p: Vector3 = f["pos"]
				if f["state"] == "carried" and game.chars.has(f["carrier"]):
					p = game.chars[f["carrier"]].global_position
				var s := _clamp_edge(to_screen.call(Vector2(p.x, p.z)), size / 2.0)
				var col: Color = Data.TEAM_COLORS[f["team"]]
				draw_line(s + Vector2(-3, 7), s + Vector2(-3, -7), Color.WHITE, 1.5)
				draw_colored_polygon(PackedVector2Array([s + Vector2(-3, -7), s + Vector2(7, -3.5), s + Vector2(-3, 0)]), col)
		"koth":
			var col := Color(1, 1, 1, 0.6)
			if m.hill_owner >= 0:
				col = Data.TEAM_COLORS[m.hill_owner]
			elif m.hill_owner == -1 or m.hill_owner <= -10:
				col = Color(1, 0.75, 0.25)
			var s: Vector2 = to_screen.call(Vector2(ModesScript.HILL_POS.x, ModesScript.HILL_POS.z))
			draw_circle(s, ModesScript.HILL_RADIUS * ppm, Color(col, 0.18))
			draw_arc(s, ModesScript.HILL_RADIUS * ppm, 0.0, TAU, 40, col, 2.0)
		"dom":
			for i in m.dom_points.size():
				var dp: Vector3 = m.dom_points[i]
				var s := _clamp_edge(to_screen.call(Vector2(dp.x, dp.z)), size / 2.0)
				var col: Color = m.dom_color(i)
				draw_circle(s, 8.0, Color(col, 0.3))
				draw_arc(s, 8.0, 0.0, TAU, 20, col, 1.5)
				draw_string(font, s + Vector2(-4.5, 5), ModesScript.DOM_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		"snd":
			for i in m.sites.size():
				var sp: Vector3 = m.sites[i]
				var s := _clamp_edge(to_screen.call(Vector2(sp.x, sp.z)), size / 2.0)
				draw_arc(s, 8.0, 0.0, TAU, 20, Color(1, 0.8, 0.3), 1.5)
				draw_string(font, s + Vector2(-4.5, 5), "AB"[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.8, 0.3))
			var st: String = m.bomb["state"]
			# Les attaquants savent toujours où est la bombe ; tout le monde la voit une fois posée
			if (st == "carried" or st == "dropped") and c.team == m.attackers() or st == "planted":
				var bp: Vector3 = m.bomb["pos"]
				if st == "carried" and game.chars.has(m.bomb["carrier"]):
					bp = game.chars[m.bomb["carrier"]].global_position
				var blink := st != "planted" or fmod(Time.get_ticks_msec() / 1000.0, 0.6) < 0.35
				if blink:
					_square(_clamp_edge(to_screen.call(Vector2(bp.x, bp.z)), size / 2.0), 4.5, Color(1, 0.3, 0.2))
		"zombies":
			for sh in m.shops:
				var s: Vector2 = to_screen.call(Vector2(sh["pos"].x, sh["pos"].z))
				draw_string(font, s + Vector2(-4, 5), "$", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.85, 0.3))
		"br":
			var z: Array = m.zone_now()
			var zc: Vector3 = z[0]
			draw_arc(to_screen.call(Vector2(zc.x, zc.z)), float(z[1]) * ppm, 0.0, TAU, 64, Color(0.3, 0.6, 1.0), 2.0)
			var nc: Vector3 = m.zone["c1"]
			if float(m.zone["r1"]) < float(z[1]) - 0.1:
				draw_arc(to_screen.call(Vector2(nc.x, nc.z)), float(m.zone["r1"]) * ppm, 0.0, TAU, 64, Color(1, 1, 1, 0.7), 1.2)


func _yaw_of(o) -> float:
	var f: Vector3 = -o.global_transform.basis.z
	return atan2(f.x, f.z)


## Flèche pointant vers le haut pour un angle nul (rot en radians, sens du regard du monde).
func _arrow(p: Vector2, rot: float, r: float, col: Color) -> void:
	var pts := PackedVector2Array([Vector2(0, -r), Vector2(r * 0.7, r * 0.75), Vector2(0, r * 0.35), Vector2(-r * 0.7, r * 0.75)])
	for i in pts.size():
		pts[i] = p + pts[i].rotated(-rot)
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, Color(0, 0, 0, 0.7), 1.2)


func _square(p: Vector2, r: float, col: Color) -> void:
	draw_rect(Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), col)


## Garde un repère important au bord de la mini-carte quand il est trop loin.
func _clamp_edge(s: Vector2, center: Vector2) -> Vector2:
	var m := 9.0
	return Vector2(clampf(s.x, m, center.x * 2.0 - m), clampf(s.y, m, center.y * 2.0 - m))
