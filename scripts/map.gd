extends RefCounted
## Construit l'arène (sol, murs, obstacles, lumière) et fournit
## les points d'apparition ainsi que le graphe de navigation des bots.

const HALF := 30.0
const WALL_HEIGHT := 6.0
const NAV_STEP := 2.5
const NAV_RADIUS := 0.9

# Obstacles : [x, z, largeur, hauteur, profondeur]
const LAYOUT := [
	# Tour centrale
	[0, 0, 6, 3.5, 6],
	# Murs autour du centre
	[-11, 0, 1.5, 3, 9], [11, 0, 1.5, 3, 9],
	[0, -11, 9, 3, 1.5], [0, 11, 9, 3, 1.5],
	# Caisses basses (on peut sauter dessus)
	[-6, -6, 2, 1, 2], [6, 6, 2, 1, 2], [-6, 6, 2, 1, 2], [6, -6, 2, 1, 2],
	# Blocs des coins
	[-19, -19, 5, 2.5, 5], [19, 19, 5, 2.5, 5], [-19, 19, 5, 2.5, 5], [19, -19, 5, 2.5, 5],
	# Piliers
	[-22, 0, 2, 4, 2], [22, 0, 2, 4, 2],
	[-6, -20, 2, 4, 2], [6, 20, 2, 4, 2], [6, -20, 2, 4, 2], [-6, 20, 2, 4, 2],
	# Murets
	[-16, -8, 4, 1.2, 1], [16, 8, 4, 1.2, 1], [-16, 8, 4, 1.2, 1], [16, -8, 4, 1.2, 1],
	# Caisses près des bases
	[-12, 22, 2, 1, 2], [12, 22, 2, 1, 2], [-12, -22, 2, 1, 2], [12, -22, 2, 1, 2],
]

var team_spawns := [[], []]
var ffa_spawns := []
var nav_points := []
var astar := AStar3D.new()

var _obstacles := []  # [centre Vector2(x, z), demi-taille Vector2]
var _checker: ImageTexture


func build(root: Node3D, with_nav: bool) -> void:
	_build_environment(root)
	_checker = _make_checker()

	var size := HALF * 2.0 + 2.0
	_box(root, Vector3(0, -0.5, 0), Vector3(size, 1, size), Color(0.5, 0.52, 0.56), false)
	var h := WALL_HEIGHT
	var wall := Color(0.32, 0.34, 0.4)
	_box(root, Vector3(0, h / 2.0, -HALF - 0.5), Vector3(size, h, 1), wall, false)
	_box(root, Vector3(0, h / 2.0, HALF + 0.5), Vector3(size, h, 1), wall, false)
	_box(root, Vector3(-HALF - 0.5, h / 2.0, 0), Vector3(1, h, size), wall, false)
	_box(root, Vector3(HALF + 0.5, h / 2.0, 0), Vector3(1, h, size), wall, false)

	# Zones de base colorées (repères visuels)
	_patch(root, Vector3(0, 0.01, 26.5), Vector3(36, 0.02, 7), Color(0.25, 0.4, 0.85))
	_patch(root, Vector3(0, 0.01, -26.5), Vector3(36, 0.02, 7), Color(0.85, 0.3, 0.25))

	for b in LAYOUT:
		var bsize := Vector3(b[2], b[3], b[4])
		var col: Color
		if bsize.y <= 1.2:
			col = Color(0.78, 0.55, 0.28)
		elif bsize.y < 3.5:
			col = Color(0.55, 0.6, 0.68)
		else:
			col = Color(0.42, 0.45, 0.52)
		_box(root, Vector3(b[0], bsize.y / 2.0, b[1]), bsize, col, true)

	for x in [-15, -9, -3, 3, 9, 15]:
		team_spawns[0].append(Vector3(x, 0.1, 27))
		team_spawns[1].append(Vector3(x, 0.1, -27))
	for p in [[-27, -27], [27, 27], [-27, 27], [27, -27], [0, 27], [0, -27], [27, 0], [-27, 0],
			[-14, -14], [14, 14], [-14, 14], [14, -14], [0, -16], [0, 16], [-16, 0], [16, 0]]:
		ffa_spawns.append(Vector3(p[0], 0.1, p[1]))

	if with_nav:
		_build_nav()


# --- Navigation des bots --------------------------------------------------------

func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if astar.get_point_count() == 0:
		return PackedVector3Array([to])
	var a := astar.get_closest_point(from)
	var b := astar.get_closest_point(to)
	var path := astar.get_point_path(a, b)
	if is_clear(to):
		path.append(to)
	return path


func random_point() -> Vector3:
	return nav_points.pick_random()


func is_clear(p: Vector3) -> bool:
	for o in _obstacles:
		if absf(p.x - o[0].x) < o[1].x + NAV_RADIUS and absf(p.z - o[0].y) < o[1].y + NAV_RADIUS:
			return false
	return absf(p.x) < HALF - 0.8 and absf(p.z) < HALF - 0.8


func segment_clear(a: Vector3, b: Vector3) -> bool:
	var steps := maxi(1, ceili(a.distance_to(b) / 0.5))
	for i in steps + 1:
		if not is_clear(a.lerp(b, float(i) / steps)):
			return false
	return true


func _build_nav() -> void:
	var n := int(floor((HALF - 1.5) * 2.0 / NAV_STEP)) + 1
	var start := -(n - 1) * NAV_STEP / 2.0
	var ids := {}
	for i in n:
		for j in n:
			var p := Vector3(start + i * NAV_STEP, 0, start + j * NAV_STEP)
			if is_clear(p):
				var id := astar.get_available_point_id()
				astar.add_point(id, p)
				ids[Vector2i(i, j)] = id
				nav_points.append(p)
	for key in ids:
		for off in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
			var other = key + off
			if ids.has(other):
				var a := astar.get_point_position(ids[key])
				var b := astar.get_point_position(ids[other])
				if segment_clear(a, b):
					astar.connect_points(ids[key], ids[other])


# --- Géométrie --------------------------------------------------------------------

func _build_environment(root: Node3D) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.42, 0.78)
	sky_mat.sky_horizon_color = Color(0.68, 0.76, 0.88)
	sky_mat.ground_horizon_color = Color(0.6, 0.65, 0.7)
	sky_mat.ground_bottom_color = Color(0.2, 0.2, 0.22)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.57, 0.62)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	root.add_child(sun)


func _make_checker() -> ImageTexture:
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var v := 1.0 if ((x >> 5) + (y >> 5)) % 2 == 0 else 0.86
			if x % 32 == 0 or y % 32 == 0:
				v = 0.7
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_texture = _checker
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(0.25, 0.25, 0.25)
	mat.roughness = 0.9
	return mat


func _box(root: Node3D, center: Vector3, size: Vector3, color: Color, obstacle: bool) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = _material(color)
	body.add_child(mesh)
	body.position = center
	root.add_child(body)
	if obstacle:
		_obstacles.append([Vector2(center.x, center.z), Vector2(size.x, size.z) / 2.0])


func _patch(root: Node3D, center: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = _material(color)
	mesh.position = center
	root.add_child(mesh)
