extends RefCounted
## Construit l'arène (sol, enceinte, décor Quaternius, lumière) et fournit
## les points d'apparition, les trousses de soin et le graphe de navigation des bots.

const Models := preload("res://scripts/models.gd")

const HALF := 30.0
const WALL_HEIGHT := 6.0
const NAV_STEP := 2.5
const NAV_RADIUS := 0.9
const ENV_PATH := "res://assets/env/%s.gltf"

# Décor avec collision : [modèle, x, z, rotation (0/90/180/270), échelle]
const PROPS := [
	# Centre
	["Tank", 0, 0, 0, 1.3],
	# Conteneurs autour du centre
	["Container_Long", -11, 0, 90, 1.2], ["Container_Long", 11, 0, 90, 1.2],
	["Container_Long", 0, -11, 0, 1.2], ["Container_Long", 0, 11, 0, 1.2],
	# Sacs de sable bas (on peut sauter dessus)
	["SackTrench_Small", -6, -6, 0, 1.0], ["SackTrench_Small", 6, 6, 180, 1.0],
	["SackTrench_Small", -6, 6, 90, 1.0], ["SackTrench_Small", 6, -6, 270, 1.0],
	# Coins
	["Debris_BrokenCar", -19, -19, 0, 1.0], ["Debris_BrokenCar", 19, 19, 180, 1.0],
	["Container_Small", -19, 19, 90, 1.4], ["Container_Small", 19, -19, 90, 1.4],
	# Châteaux d'eau sur les côtés
	["WaterTank_Platform", -22, 0, 0, 1.0], ["WaterTank_Platform", 22, 0, 180, 1.0],
	# Bennes près des bases
	["TrashContainer", -6, -20, 0, 1.0], ["TrashContainer", 6, 20, 180, 1.0],
	["TrashContainer", 6, -20, 0, 1.0], ["TrashContainer", -6, 20, 180, 1.0],
	# Murets de sacs de sable
	["SackTrench", -16, -8, 0, 1.0], ["SackTrench", 16, 8, 180, 1.0],
	["SackTrench", -16, 8, 180, 1.0], ["SackTrench", 16, -8, 0, 1.0],
	# Caisses et barricades près des bases
	["Crate", -12, 22, 0, 1.3], ["Crate", 12, 22, 90, 1.3], ["Crate", -12, -22, 0, 1.3], ["Crate", 12, -22, 90, 1.3],
	["Barrier_Single", -4, 24, 0, 1.0], ["Barrier_Single", 4, -24, 0, 1.0],
	["Barrier_Single", 4, 24, 0, 1.0], ["Barrier_Single", -4, -24, 0, 1.0],
	["ExplodingBarrel", -24, 14, 0, 1.0], ["ExplodingBarrel", 24, -14, 0, 1.0],
	["GasTank", -25, -14, 0, 1.0], ["GasTank", 25, 14, 0, 1.0],
]

# Décor sans collision (au sol ou hors de l'arène) : [modèle, x, z, rotation, échelle]
const DECOR := [
	["Debris_Papers_1", -3, 8, 0, 1.0], ["Debris_Papers_2", 4, -8, 40, 1.0], ["Debris_Papers_3", 14, 3, 0, 1.0],
	["Debris_Pile", -14, -3, 30, 1.0], ["Debris_Pile", 15, -2, 200, 1.0],
	["Pallet", -21, -24, 15, 1.0], ["Pallet_Broken", 21, 24, 70, 1.0], ["WoodPlanks", -9, -14, 30, 1.0],
	["TrafficCone", -2, 16, 0, 1.0], ["TrafficCone", 2, -16, 0, 1.0], ["TrafficCone", 9, 15, 0, 1.0],
	["StreetLight", -29.3, -12, 90, 1.0], ["StreetLight", -29.3, 12, 90, 1.0],
	["StreetLight", 29.3, -12, 270, 1.0], ["StreetLight", 29.3, 12, 270, 1.0],
	# Hors de l'arène
	["Structure_2", 0, -42, 0, 1.0], ["Structure_4", 0, 42, 180, 1.0],
	["Structure_1", -42, -14, 90, 1.0], ["Structure_3", -42, 14, 90, 1.0],
	["Structure_3", 42, -14, 270, 1.0], ["Structure_1", 42, 14, 270, 1.0],
	["Tree_1", -36, -34, 0, 1.2], ["Tree_2", 36, 34, 0, 1.3], ["Tree_3", -36, 34, 90, 1.2], ["Tree_4", 36, -34, 0, 1.3],
	["Tree_2", -20, -36, 0, 1.2], ["Tree_1", 20, 36, 0, 1.1], ["Tree_4", -20, 36, 0, 1.2], ["Tree_3", 20, -36, 0, 1.1],
	["Tree_1", -36, 0, 0, 1.0], ["Tree_2", 36, 0, 0, 1.0],
]

const HEALTH_POINTS := [Vector3(-8, 0, 0), Vector3(8, 0, 0), Vector3(0, 0, -7), Vector3(0, 0, 7)]

# --- Carte « Ville » (Kenney City Kit, Car Kit et City Kit Roads, CC0) -------------
# Chemins relatifs à res://assets/ ; disposition symétrique par rapport au centre.
const B := "city/buildings/%s.glb"
const S := "city/street/%s.glb"
const C := "city/cars/%s.glb"
const CITY_PROPS := [
	# Immeubles (échelle 7)
	[B % "building-k", 20, 12, 0, 7.0], [B % "building-k", -20, -12, 180, 7.0],
	[B % "building-a", 11.5, 20, 0, 7.0], [B % "building-a", -11.5, -20, 180, 7.0],
	[B % "building-e", -19, 13, 0, 7.0], [B % "building-e", 19, -13, 180, 7.0],
	[B % "building-c", -12, 21, 0, 7.0], [B % "building-c", 12, -21, 180, 7.0],
	[B % "building-skyscraper-b", 25.5, 25.5, 0, 6.0], [B % "building-skyscraper-b", -25.5, -25.5, 180, 6.0],
	[B % "building-skyscraper-d", -25.5, 25.5, 0, 6.0], [B % "building-skyscraper-d", 25.5, -25.5, 180, 6.0],
	# Véhicules (échelle 1.3)
	[C % "taxi", 3.5, 5, 0, 1.3], [C % "taxi", -3.5, -5, 180, 1.3],
	[C % "garbage-truck", -5, 3, 90, 1.3], [C % "garbage-truck", 5, -3, 270, 1.3],
	[C % "police", 17, -2, 90, 1.3], [C % "police", -17, 2, 270, 1.3],
	[C % "ambulance", 2, 16, 0, 1.3], [C % "ambulance", -2, -16, 180, 1.3],
	[C % "van", 24, -4, 0, 1.3], [C % "van", -24, 4, 180, 1.3],
	# Mobilier urbain (échelle 8)
	[S % "dumpster", 8, -10, 90, 8.0], [S % "dumpster", -8, 10, 270, 8.0],
	[S % "construction-barrier", 6, 10, 0, 8.0], [S % "construction-barrier", -6, -10, 180, 8.0],
	[S % "construction-fence", 5, 23, 90, 8.0], [S % "construction-fence", -5, -23, 90, 8.0],
	[S % "construction-fence", -5, 23, 90, 8.0], [S % "construction-fence", 5, -23, 90, 8.0],
	[C % "box", 10, 3, 0, 1.4], [C % "box", -10, -3, 0, 1.4],
	[C % "box", 24, 6.5, 0, 1.4], [C % "box", -24, -6.5, 0, 1.4],
]
const CITY_DECOR := [
	[S % "traffic-light", 5.6, 5.6, 0, 5.0], [S % "traffic-light", -5.6, -5.6, 180, 5.0],
	[S % "traffic-light", -5.6, 5.6, 90, 5.0], [S % "traffic-light", 5.6, -5.6, 270, 5.0],
	[S % "light-square", 6, 18, 90, 8.0], [S % "light-square", -6, -18, 270, 8.0],
	[S % "light-square", 18, 6, 0, 8.0], [S % "light-square", -18, -6, 180, 8.0],
	[S % "road-sign-stop", -6, 7, 0, 5.0], [S % "road-sign-stop", 6, -7, 180, 5.0],
	[S % "construction-cone", 8, 13, 0, 8.0], [S % "construction-cone", 9, 14, 0, 8.0],
	[S % "construction-cone", -8, -13, 0, 8.0], [S % "construction-cone", -9, -14, 0, 8.0],
	[B % "detail-parasol-a", 14, 26, 0, 7.0], [B % "detail-parasol-b", -14, -26, 0, 7.0],
	# Arrière-plan (hors de l'arène)
	[B % "building-skyscraper-a", -10, -44, 0, 9.0], [B % "building-skyscraper-c", 12, -46, 0, 9.0],
	[B % "building-skyscraper-e", -14, 45, 180, 9.0], [B % "building-skyscraper-a", 10, 44, 180, 9.0],
	[B % "building-n", 44, -12, 270, 8.0], [B % "building-j", 44, 14, 270, 8.0],
	[B % "building-n", -44, 12, 90, 8.0], [B % "building-j", -44, -14, 90, 8.0],
	[B % "building-skyscraper-d", 42, 40, 0, 8.0], [B % "building-skyscraper-b", -42, -40, 0, 8.0],
	[B % "building-skyscraper-c", -42, 40, 0, 8.0], [B % "building-skyscraper-e", 42, -40, 0, 8.0],
]
const CITY_HEALTH := [Vector3(-10, 0, 0), Vector3(10, 0, 0), Vector3(0, 0, -10), Vector3(0, 0, 10)]
const CITY_FFA := [[0, 27], [0, -27], [27, 0], [-27, 0], [15, 27], [-15, -27], [-15, 27], [15, -27],
		[0, 13], [0, -13], [13, -5], [-13, 5]]

const MIL_FFA := [[-27, -27], [27, 27], [-27, 27], [27, -27], [0, 27], [0, -27], [27, 0], [-27, 0],
		[-14, -14], [14, 14], [-14, 14], [14, -14], [0, -16], [0, 16], [-16, 0], [16, 0]]

var team_spawns := [[], []]
var ffa_spawns := []
var health_points := []
var nav_points := []
var astar := AStar3D.new()

var _obstacles := []  # [centre Vector2(x, z), demi-taille Vector2]
var _checker: ImageTexture


## map_index : 0 = base militaire, 1 = ville.
func build(root: Node3D, with_nav: bool, map_index := 0) -> void:
	_build_environment(root)
	_checker = _make_checker()
	var city := map_index == 1

	# Sol : béton (texture Poly Haven) dans l'arène, terrain autour
	_box(root, Vector3(0, -0.52, 0), Vector3(140, 1, 140), Color(0.5, 0.48, 0.42), false, true)
	var floor_body := _box(root, Vector3(0, -0.5, 0), Vector3(HALF * 2 + 1, 1, HALF * 2 + 1), Color.WHITE, false, true)
	_set_textured(floor_body, "concrete_floor_02", Color(0.62, 0.62, 0.62), 0.25)
	if city:
		# Deux rues en asphalte qui se croisent, avec un marquage au sol
		for road in [Vector3(HALF * 2, 0.02, 10), Vector3(10, 0.02, HALF * 2)]:
			var r := _patch(root, Vector3(0, 0.012, 0), road, Color.WHITE)
			_set_textured(r, "asphalt_02", Color(0.75, 0.75, 0.75), 0.2)
		for i in range(-13, 14):
			if absi(i) < 3:
				continue
			_patch(root, Vector3(i * 2.2, 0.026, 0), Vector3(1.2, 0.01, 0.18), Color(1, 0.85, 0.2))
			_patch(root, Vector3(0, 0.026, i * 2.2), Vector3(0.18, 0.01, 1.2), Color(1, 0.85, 0.2))
	_patch(root, Vector3(0, 0.03, 26.5), Vector3(36, 0.02, 7), Color(0.25, 0.4, 0.85, 0.35))
	_patch(root, Vector3(0, 0.03, -26.5), Vector3(36, 0.02, 7), Color(0.85, 0.3, 0.25, 0.35))

	# Enceinte : murs invisibles + grillages
	var size := HALF * 2.0 + 2.0
	var h := WALL_HEIGHT
	_box(root, Vector3(0, h / 2.0, -HALF - 0.5), Vector3(size, h, 1), Color.WHITE, false, false)
	_box(root, Vector3(0, h / 2.0, HALF + 0.5), Vector3(size, h, 1), Color.WHITE, false, false)
	_box(root, Vector3(-HALF - 0.5, h / 2.0, 0), Vector3(1, h, size), Color.WHITE, false, false)
	_box(root, Vector3(HALF + 0.5, h / 2.0, 0), Vector3(1, h, size), Color.WHITE, false, false)
	var fence_w := 3.55
	var count := int(ceil(HALF * 2.0 / fence_w))
	for i in count:
		var t := -HALF + fence_w / 2.0 + i * fence_w
		_prop(root, "MetalFence", t, -HALF, 0, 1.0, false)
		_prop(root, "MetalFence", t, HALF, 180, 1.0, false)
		_prop(root, "MetalFence", -HALF, t, 90, 1.0, false)
		_prop(root, "MetalFence", HALF, t, 270, 1.0, false)

	for p in (CITY_PROPS if city else PROPS):
		_prop(root, p[0], p[1], p[2], p[3], p[4], true)
	for d in (CITY_DECOR if city else DECOR):
		_prop(root, d[0], d[1], d[2], d[3], d[4], false)

	for x in [-15, -9, -3, 3, 9, 15]:
		team_spawns[0].append(Vector3(x, 0.1, 27))
		team_spawns[1].append(Vector3(x, 0.1, -27))
	for p in (CITY_FFA if city else MIL_FFA):
		ffa_spawns.append(Vector3(p[0], 0.1, p[1]))
	health_points = (CITY_HEALTH if city else HEALTH_POINTS).duplicate()

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

## Place un élément du kit ; avec collision, ajoute une boîte qui l'englobe (et un obstacle pour les bots).
func _prop(root: Node3D, model: String, x: float, z: float, rot_deg: float, scale: float, collide: bool) -> void:
	var path := ("res://assets/" + model) if "/" in model else (ENV_PATH % model)
	var inst: Node3D = load(path).instantiate()
	inst.position = Vector3(x, 0, z)
	inst.rotation.y = deg_to_rad(rot_deg)
	inst.scale = Vector3.ONE * scale
	root.add_child(inst)
	if not collide:
		return
	var box := Models._local_aabb(inst)
	var center := box.get_center() * scale
	var size := box.size * scale
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = inst.position
	body.rotation.y = inst.rotation.y
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	shape.position = center
	body.add_child(shape)
	root.add_child(body)
	var c2 := Vector2(center.x, center.z).rotated(-inst.rotation.y)
	var half := Vector2(size.x, size.z) / 2.0
	if int(round(rot_deg)) % 180 != 0:
		half = Vector2(half.y, half.x)
	_obstacles.append([Vector2(x, z) + c2, half])


func _build_environment(root: Node3D) -> void:
	# Ciel photographique (HDRI Poly Haven « Kloofendal 48d Partly Cloudy (Pure Sky) », CC0)
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/sky/sky_day.hdr")
	sky_mat.energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.78, 0.86)
	env.fog_density = 0.003
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	we.add_to_group("gfx_env")
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.add_to_group("gfx_sun")
	root.add_child(sun)
	# Ombres, brouillard et luminosité selon les options du joueur
	Net.apply_graphics.call_deferred()


func _make_checker() -> ImageTexture:
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var v := 1.0 if ((x >> 5) + (y >> 5)) % 2 == 0 else 0.93
			if x % 32 == 0 or y % 32 == 0:
				v = 0.8
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
	mat.roughness = 0.95
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


## Applique une texture Poly Haven (couleur + relief) répétée dans l'espace du monde.
func _set_textured(node: Node, tex: String, tint: Color, uv_scale: float) -> void:
	var mesh := node as MeshInstance3D
	for c in node.get_children():
		if c is MeshInstance3D:
			mesh = c
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = load("res://assets/textures/%s_diff_1k.jpg" % tex)
	mat.normal_enabled = true
	mat.normal_texture = load("res://assets/textures/%s_nor_gl_1k.jpg" % tex)
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * uv_scale
	mat.roughness = 0.95
	mesh.material_override = mat


func _box(root: Node3D, center: Vector3, size: Vector3, color: Color, obstacle: bool, visible: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	if visible:
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
	return body


func _patch(root: Node3D, center: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	var mat := _material(color)
	mat.albedo_texture = null
	mesh.material_override = mat
	mesh.position = center
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)
	return mesh
