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

# Barils explosifs (placés par items.gd, on peut les faire sauter) et bonus : candidats par paires symétriques,
# seuls ceux qui ne touchent aucun obstacle sont gardés.
const MIL_BARRELS := [[-24, 14], [24, -14], [-14, 13], [14, -13], [-3, -17], [3, 17], [-20, -5], [20, 5]]
const CITY_BARRELS := [[-7, 7], [7, -7], [-20, 6.5], [20, -6.5], [6.5, 20], [-6.5, -20]]
const MIL_BONUS := [["armor", -26, 0], ["armor", 26, 0], ["ammo", -14, -14], ["ammo", 14, 14],
		["damage", 0, -15], ["damage", 0, 15], ["ammo", -14, 14], ["ammo", 14, -14]]
const CITY_BONUS := [["armor", -26, 0], ["armor", 26, 0], ["ammo", 0, -22], ["ammo", 0, 22],
		["damage", -20, 0], ["damage", 20, 0]]
const CITY_FFA := [[0, 27], [0, -27], [27, 0], [-27, 0], [15, 27], [-15, -27], [-15, 27], [15, -27],
		[0, 13], [0, -13], [13, -5], [-13, 5]]

const MIL_FFA := [[-27, -27], [27, 27], [-27, 27], [27, -27], [0, 27], [0, -27], [27, 0], [-27, 0],
		[-14, -14], [14, 14], [-14, 14], [14, -14], [0, -16], [0, 16], [-16, 0], [16, 0]]


# --- Entrepôt (carte 3) : grand hangar fermé, éclairé par des lampes au plafond ---------------
const ROOF_HEIGHT := 8.0
# Murs intérieurs : [x, z, largeur x, profondeur z, hauteur]
const WH_WALLS := [
	[-14, 12, 16, 0.6, 4.5], [14, 12, 16, 0.6, 4.5], [-14, -12, 16, 0.6, 4.5], [14, -12, 16, 0.6, 4.5],
	[20, 0, 0.6, 12, 4.5], [-20, 0, 0.6, 12, 4.5],
	[6, 5, 1.2, 1.2, ROOF_HEIGHT], [-6, 5, 1.2, 1.2, ROOF_HEIGHT], [6, -5, 1.2, 1.2, ROOF_HEIGHT], [-6, -5, 1.2, 1.2, ROOF_HEIGHT],
]
const WH_PROPS := [
	["Container_Long", 0, 0, 0, 1.2],
	["Crate", -10, 4, 0, 1.3], ["Crate", 10, -4, 90, 1.3], ["Crate", -14, -20, 0, 1.3], ["Crate", 14, 20, 90, 1.3],
	["Crate", -25, -8, 45, 1.3], ["Crate", 25, 8, 45, 1.3],
	["CardboardBoxes_1", -4, 18, 0, 1.2], ["CardboardBoxes_2", 4, -18, 0, 1.2],
	["CardboardBoxes_3", -24, 18, 0, 1.2], ["CardboardBoxes_4", 24, -18, 0, 1.2],
	["Container_Small", -25, 22, 90, 1.3], ["Container_Small", 25, -22, 90, 1.3],
	["SackTrench_Small", -9, -19, 0, 1.0], ["SackTrench_Small", 9, 19, 180, 1.0],
	["Sofa", 26, -3, 270, 1.0], ["Sofa_Small", -26, 3, 90, 1.0],
	["TrashContainer", -16, 6, 90, 1.0], ["TrashContainer", 16, -6, 270, 1.0],
]
const WH_DECOR := [
	["Pallet", -18, -26, 15, 1.0], ["Pallet_Broken", 18, 26, 70, 1.0], ["WoodPlanks", -2, -8, 30, 1.0],
	["Debris_Papers_1", 3, 9, 0, 1.0], ["Debris_Papers_2", -12, -16, 40, 1.0], ["Debris_Papers_3", 22, 3, 0, 1.0],
	["TrafficCone", -3, 22, 0, 1.0], ["TrafficCone", 3, -22, 0, 1.0], ["Sign", 27, 10, 270, 1.0], ["Sign", -27, -10, 90, 1.0],
]
const WH_HEALTH := [Vector3(-16, 0, 0), Vector3(16, 0, 0), Vector3(0, 0, -8), Vector3(0, 0, 8)]
const WH_BARRELS := [[-6, -15], [6, 15], [-22, -10], [22, 10], [-24, 26], [24, -26]]
const WH_BONUS := [["armor", -25, 0], ["armor", 25, 0], ["ammo", -8, -16], ["ammo", 8, 16],
		["damage", 0, -20], ["damage", 0, 20]]


# --- Forêt (carte 4) : Kenney Nature Kit + Survival Kit -----------------------------------------
const F := "forest/%s.glb"
const FS := "forest/survival/%s.glb"
const FOREST_PROPS := [
	[F % "rock_largeD", -8, 6, 0, 4.0], [F % "rock_largeB", 8, -6, 180, 4.0],
	[F % "rock_tallA", -18, -4, 30, 3.5], [F % "rock_tallB", 18, 4, 210, 3.5],
	[F % "rock_largeC", -2, 15, 60, 3.5], [F % "rock_largeA", 2, -15, 240, 3.5],
	[F % "log_large", -4, -9, 90, 3.0], [F % "log_large", 4, 9, 90, 3.0],
	[F % "log_stackLarge", -20, 14, 0, 3.5], [F % "log_stackLarge", 20, -14, 180, 3.5],
	[F % "tent_detailedOpen", -23, 22, 135, 4.5], [F % "tent_detailedClosed", 23, -22, 315, 4.5],
	[FS % "structure", -12, 19, 0, 6.0], [FS % "structure", 12, -19, 180, 6.0],
	[FS % "fence-fortified", -6, 20, 0, 4.0], [FS % "fence-fortified", 6, -20, 180, 4.0],
	[FS % "fence-fortified", -25, -9, 90, 4.0], [FS % "fence-fortified", 25, 9, 90, 4.0],
	[FS % "workbench", -14, -15, 30, 4.0], [FS % "workbench", 14, 15, 210, 4.0],
	[FS % "box-large", 11, 3, 0, 4.0], [FS % "box-large", -11, -3, 0, 4.0],
	[F % "tree_pineTallB", -14, 7, 0, 5.0], [F % "tree_pineTallB", 14, -7, 0, 5.0],
	[F % "tree_oak", -26, -19, 0, 5.5], [F % "tree_oak", 26, 19, 0, 5.5],
	[F % "tree_default", -5, -21, 0, 5.0], [F % "tree_default", 5, 21, 0, 5.0],
	[F % "tree_fat", -24, 3, 0, 5.0], [F % "tree_fat", 24, -3, 0, 5.0],
	[F % "tree_pineRoundA", -26, 12, 0, 5.0], [F % "tree_pineRoundA", 26, -12, 0, 5.0],
	[F % "tree_detailed", -16, -12, 0, 5.5], [F % "tree_detailed", 16, 12, 0, 5.5],
	[F % "tree_cone", -7, -3, 0, 4.5], [F % "tree_cone", 7, 3, 0, 4.5],
]
const FOREST_DECOR := [
	[F % "plant_bushLarge", -10, 10, 0, 4.0], [F % "plant_bushLarge", 10, -10, 0, 4.0],
	[F % "plant_bush", -20, -2, 0, 4.0], [F % "plant_bush", 20, 2, 0, 4.0], [F % "plant_bush", -3, 24, 0, 3.5],
	[F % "plant_bush", 3, -24, 0, 3.5], [F % "grass_large", -16, 2, 0, 4.0], [F % "grass_large", 16, -2, 0, 4.0],
	[F % "grass_large", -8, -18, 0, 4.0], [F % "grass_large", 8, 18, 0, 4.0], [F % "grass_large", -22, -24, 0, 4.0],
	[F % "stump_round", -12, 2, 0, 3.5], [F % "stump_old", 12, -2, 0, 3.5], [F % "stump_round", 20, 22, 0, 3.5],
	[F % "campfire_stones", 0, -4, 0, 4.0], [FS % "campfire-pit", 0, -4, 0, 4.5],
	[F % "ground_riverRocks", -12, 0, 0, 4.0], [F % "ground_riverRocks", 12, 0, 90, 4.0], [F % "ground_riverRocks", 22, 0, 0, 4.0],
	[F % "ground_riverRocks", -22, 0, 90, 4.0], [F % "fence_planks", 0, 0.6, 0, 4.0],
]
const FOREST_HEALTH := [Vector3(-10, 0, 1), Vector3(10, 0, -1), Vector3(0, 0, -11), Vector3(0, 0, 11)]
const FOREST_BARRELS := [[-17, 0], [17, 0], [-6, -16], [6, 16], [-22, -16], [22, 16]]
const FOREST_BONUS := [["armor", -26, -1], ["armor", 26, 1], ["ammo", -12, -13], ["ammo", 12, 13],
		["damage", 0, -19], ["damage", 0, 19]]

# --- Port industriel (carte 5) : Kenney City Kit Industrial + Watercraft Pack -------------------
const PI_ := "port/industrial/%s.glb"
const PB := "port/boats/%s.glb"
const PORT_PROPS := [
	# Conteneurs, certains empilés : [modèle, x, z, rotation, échelle, hauteur]
	[PI_ % "shipping-container-a", -10, 6, 0, 7.5], [PI_ % "shipping-container-b", -10, 6, 0, 7.5, 2.62],
	[PI_ % "shipping-container-c", 10, -6, 180, 7.5], [PI_ % "shipping-container-a", 10, -6, 180, 7.5, 2.62],
	[PI_ % "shipping-container-b", -18, -10, 90, 7.5], [PI_ % "shipping-container-c", 18, 10, 90, 7.5],
	[PI_ % "shipping-container-a", 0, 14, 90, 7.5], [PI_ % "shipping-container-b", 0, -14, 90, 7.5],
	[PI_ % "shipping-container-c", -22, 18, 0, 7.5], [PI_ % "shipping-container-a", 22, -18, 0, 7.5],
	[PI_ % "shipping-container-b", -22, 18, 0, 7.5, 2.62], [PI_ % "shipping-container-c", 22, -18, 0, 7.5, 2.62],
	[PB % "cargo-container-a", 0, -1.6, 90, 2.0], [PB % "cargo-container-b", 0, 1.6, 90, 2.0],
	[PI_ % "detail-tank-large", -21, 4, 0, 4.0], [PI_ % "detail-tank-large", 21, -4, 180, 4.0],
	[PB % "cargo-container-a", 8, 21, 90, 2.2], [PB % "cargo-container-b", -8, -21, 90, 2.2],
	[PI_ % "building-k", -24, -23, 0, 5.0], [PI_ % "building-k", 24, 23, 180, 5.0],
	[PI_ % "detail-tank", 13, 3, 0, 4.0], [PI_ % "detail-tank", -13, -3, 180, 4.0],
	[PI_ % "detail-tank", -6, 23, 90, 4.0], [PI_ % "detail-tank", 6, -23, 270, 4.0],
]
const PORT_DECOR := [
	# Mer à l'est : cargo, remorqueurs, bouées
	[PB % "ship-cargo-a", 58, -6, 0, 3.0], [PB % "boat-tug-a", 41, -24, 25, 2.0], [PB % "boat-tug-a", 44, 18, 160, 2.0],
	[PB % "boat-fishing-small", 38, 34, 70, 1.6], [PB % "buoy-flag", 35, -8, 0, 1.0], [PB % "buoy", 35, 9, 0, 1.0],
	[PB % "buoy", 36, -30, 0, 1.0],
	# Zone industrielle autour
	[PI_ % "water-tower", -42, -32, 0, 5.0], [PI_ % "chimney-large", -44, 8, 0, 6.0], [PI_ % "chimney-medium", -40, 24, 0, 6.0],
	[PI_ % "building-n", -46, -6, 90, 6.0], [PI_ % "building-c", -2, -46, 0, 6.0], [PI_ % "building-a", 2, 46, 180, 6.0],
	[PI_ % "building-e", -36, 44, 180, 6.0], [PI_ % "building-g", -38, -46, 0, 6.0], [PI_ % "building-c", 20, -46, 0, 6.0],
	[PI_ % "building-e", 20, 46, 180, 6.0],
]
const PORT_HEALTH := [Vector3(-8, 0, 0), Vector3(8, 0, 0), Vector3(0, 0, -9), Vector3(0, 0, 9)]
const PORT_BARRELS := [[-16, 0], [16, 0], [-5, -18], [5, 18], [-26, 10], [26, -10]]
const PORT_BONUS := [["armor", -27, -2], ["armor", 27, 2], ["ammo", -14, -14], ["ammo", 14, 14],
		["damage", -4, -7], ["damage", 4, 7]]

# Disposition (0 base militaire, 1 ville, 2 entrepôt, 3 forêt, 4 port) et nuit, pour chaque carte de Data.MAPS
const MAP_LAYOUT := [0, 1, 2, 0, 1, 3, 4]
const MAP_NIGHT := [false, false, false, true, true, false, false]
# Lampadaires allumés la nuit : [x, hauteur, z]
const MIL_LAMPS := [[-27.8, 5.2, -12], [-27.8, 5.2, 12], [27.8, 5.2, -12], [27.8, 5.2, 12],
		[0, 6.5, -22], [0, 6.5, 22], [-17, 6.0, 0], [17, 6.0, 0], [0, 7.0, 6]]
const CITY_LAMPS := [[6, 5.5, 16.5], [-6, 5.5, -16.5], [16.5, 5.5, 6], [-16.5, 5.5, -6],
		[5, 4.0, 5], [-5, 4.0, -5], [-5, 4.0, 5], [5, 4.0, -5], [0, 6.0, 26], [0, 6.0, -26]]

var night := false
var layout := 0
var weather := 0  # 0 beau temps, 1 pluie, 2 orage, 3 neige, 4 brouillard (voir weather.gd)
var cycle := false        # cycle jour/nuit pendant la partie (voir daycycle.gd)
var start_night := false  # la carte commence de nuit
var lamp_lights := []     # lumières des lampadaires (allumées et éteintes par le cycle)
var lamp_mat: StandardMaterial3D

var team_spawns := [[], []]
var ffa_spawns := []
var health_points := []
var barrel_points := []
var bonus_points := []  # [type, Vector3]
var nav_points := []
var astar := AStar3D.new()

var _obstacles := []  # [centre Vector2(x, z), demi-taille Vector2]
var _checker: ImageTexture


## map_index : 0 = base militaire, 1 = ville.
func build(root: Node3D, with_nav: bool, map_index := 0, weather_kind := 0, day_cycle := false) -> void:
	map_index = clampi(map_index, 0, MAP_LAYOUT.size() - 1)
	layout = MAP_LAYOUT[map_index]
	start_night = MAP_NIGHT[map_index]
	night = start_night
	weather = 0 if layout == 2 else weather_kind  # pas de météo dans l'entrepôt fermé
	cycle = day_cycle and layout != 2  # pas de ciel dans l'entrepôt
	if cycle:
		night = false  # carte construite de jour, le cycle règle ensuite la lumière
	var city := layout == 1
	var wh := layout == 2
	var forest := layout == 3
	var port := layout == 4
	_build_environment(root)
	_checker = _make_checker()

	# Sol : béton (texture Poly Haven) dans l'arène, terrain autour
	_box(root, Vector3(0, -0.52, 0), Vector3(140, 1, 140), Color(0.5, 0.48, 0.42), false, not wh)
	var floor_body := _box(root, Vector3(0, -0.5, 0), Vector3(HALF * 2 + 1, 1, HALF * 2 + 1), Color.WHITE, false, not wh)
	if wh:
		# Dalles séparées : chaque lampe n'éclaire qu'un nombre limité d'objets (rendu Compatibilité)
		for ix in 6:
			for iz in 6:
				var tile := _patch(root, Vector3(-25 + ix * 10, -0.05, -25 + iz * 10), Vector3(10.2, 0.1, 10.2), Color.WHITE)
				_set_textured(tile, "concrete_floor_02", Color(0.55, 0.55, 0.55), 0.25)
	else:
		if forest:
			_set_textured(floor_body, "forrest_ground_01", Color(0.8, 0.85, 0.7), 0.2)
		else:
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
	if forest:
		# Ruisseau peu profond qui traverse la forêt
		_patch(root, Vector3(0, 0.015, 0), Vector3(HALF * 2, 0.02, 4.2), Color(0.18, 0.16, 0.12))
		_water(root, Vector3(0, 0.06, 0), Vector2(HALF * 2, 4.0), 0.03)
	if port:
		# Allées en asphalte, quai et mer à l'est
		for lane in [Vector3(HALF * 2, 0.02, 6), Vector3(6, 0.02, HALF * 2)]:
			var r := _patch(root, Vector3(0, 0.012, 0), lane, Color.WHITE)
			_set_textured(r, "asphalt_02", Color(0.7, 0.7, 0.7), 0.2)
		_box(root, Vector3(HALF + 1.5, -0.4, 0), Vector3(3, 1.0, 140), Color(0.55, 0.55, 0.55), false, true)
		_water(root, Vector3(HALF + 38, 0.0, 0), Vector2(74, 140), 0.18)
	_patch(root, Vector3(0, 0.03, 26.5), Vector3(36, 0.02, 7), Color(0.25, 0.4, 0.85, 0.35))
	_patch(root, Vector3(0, 0.03, -26.5), Vector3(36, 0.02, 7), Color(0.85, 0.3, 0.25, 0.35))

	# Enceinte : murs invisibles + grillages
	var size := HALF * 2.0 + 2.0
	var h := WALL_HEIGHT
	_box(root, Vector3(0, h / 2.0, -HALF - 0.5), Vector3(size, h, 1), Color.WHITE, false, false)
	_box(root, Vector3(0, h / 2.0, HALF + 0.5), Vector3(size, h, 1), Color.WHITE, false, false)
	_box(root, Vector3(-HALF - 0.5, h / 2.0, 0), Vector3(1, h, size), Color.WHITE, false, false)
	_box(root, Vector3(HALF + 0.5, h / 2.0, 0), Vector3(1, h, size), Color.WHITE, false, false)
	if wh:
		_build_warehouse(root)
	else:
		var fence_w := 2.0 if forest else 3.55
		var fence_model := FS % "fence-fortified" if forest else "MetalFence"
		var fence_scale := 4.0 if forest else 1.0
		var count := int(ceil(HALF * 2.0 / fence_w))
		for i in count:
			var t := -HALF + fence_w / 2.0 + i * fence_w
			_prop(root, fence_model, t, -HALF, 0, fence_scale, false)
			_prop(root, fence_model, t, HALF, 180, fence_scale, false)
			_prop(root, fence_model, -HALF, t, 90, fence_scale, false)
			_prop(root, fence_model, HALF, t, 270, fence_scale, false)

	var props: Array = CITY_PROPS if city else (WH_PROPS if wh else (FOREST_PROPS if forest else (PORT_PROPS if port else PROPS)))
	var decor: Array = CITY_DECOR if city else (WH_DECOR if wh else (FOREST_DECOR if forest else (PORT_DECOR if port else DECOR)))
	for p in props:
		_prop(root, p[0], p[1], p[2], p[3], p[4], true, p[5] if p.size() > 5 else 0.0)
	for d in decor:
		_prop(root, d[0], d[1], d[2], d[3], d[4], false)
	if forest:
		_build_forest_extras(root)
	if (night or cycle) and layout <= 1:
		_build_night_lights(root, CITY_LAMPS if city else MIL_LAMPS)

	for x in [-15, -9, -3, 3, 9, 15]:
		team_spawns[0].append(Vector3(x, 0.1, 27))
		team_spawns[1].append(Vector3(x, 0.1, -27))
	for p in (CITY_FFA if city else MIL_FFA):
		ffa_spawns.append(Vector3(p[0], 0.1, p[1]))
	health_points = (CITY_HEALTH if city else (WH_HEALTH if wh else (FOREST_HEALTH if forest else (PORT_HEALTH if port else HEALTH_POINTS)))).duplicate()
	for b in (CITY_BARRELS if city else (WH_BARRELS if wh else (FOREST_BARRELS if forest else (PORT_BARRELS if port else MIL_BARRELS)))):
		var p := Vector3(b[0], 0, b[1])
		if is_clear(p):
			barrel_points.append(p)
	for b in (CITY_BONUS if city else (WH_BONUS if wh else (FOREST_BONUS if forest else (PORT_BONUS if port else MIL_BONUS)))):
		var p := Vector3(b[1], 0, b[2])
		if is_clear(p):
			bonus_points.append([b[0], p])
	# Les barils gênent le passage des bots
	for p in barrel_points:
		_obstacles.append([Vector2(p.x, p.z), Vector2(0.45, 0.45)])
	_place_breakables()

	if with_nav:
		_build_nav()


# --- Pénétration des balles ------------------------------------------------------------

## Matière d'un objet pour la pénétration des balles (d'après le nom du modèle) :
## "wood" bois, "fabric" toile, "metal" tôle fine, "" rien ne traverse (béton, pierre...).
static func penetration_material(model: String) -> String:
	var n := model.to_lower()
	for k in ["tent", "canvas", "awning", "umbrella", "parasol", "cardboard"]:
		if k in n:
			return "fabric"
	for k in ["crate", "wood", "fence", "pallet", "plank", "bench", "table", "log", "cabin", "hut"]:
		if k in n:
			return "wood"
	for k in ["container", "car", "taxi", "police", "van", "suv", "truck", "ambulance", "dumpster", "garbage", "sedan", "firetruck", "tank"]:
		if k in n:
			return "metal"
	return ""


# --- Objets destructibles ------------------------------------------------------------

# Taille (largeur, hauteur, épaisseur) de chaque type d'objet destructible
const BREAKABLE_SIZES := {"planks": Vector3(2.6, 1.4, 0.22), "crate": Vector3(1.1, 1.1, 1.1), "glass": Vector3(2.2, 2.0, 0.14)}
const BREAKABLE_COUNT := {"planks": 8, "crate": 8, "glass": 5}
var breakable_points := []  # [type, position, angle en degrés]


## Barricades en planches, caisses en bois et vitres placées sur des endroits libres
## (tirage avec une graine fixe : mêmes positions sur toutes les machines).
func _place_breakables() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + layout * 17
	var avoid: Array[Vector3] = []
	for t in team_spawns:
		for p in t:
			avoid.append(p)
	for p in ffa_spawns:
		avoid.append(p)
	for p in health_points:
		avoid.append(p)
	for b in bonus_points:
		avoid.append(b[1])
	var placed: Array[Vector3] = []
	for kind in BREAKABLE_COUNT:
		var size: Vector3 = BREAKABLE_SIZES[kind]
		var n := 0
		for tries in 300:
			if n >= int(BREAKABLE_COUNT[kind]):
				break
			var p := Vector3(rng.randf_range(-HALF + 3, HALF - 3), 0, rng.randf_range(-HALF + 3, HALF - 3))
			var yaw := 0.0 if rng.randf() < 0.5 else 90.0
			var along := Vector3(1, 0, 0) if yaw == 0.0 else Vector3(0, 0, 1)
			var ok := is_clear(p) and is_clear(p + along * size.x * 0.5) and is_clear(p - along * size.x * 0.5)
			for q in avoid:
				if q.distance_to(p) < 5.0:
					ok = false
			for q in placed:
				if q.distance_to(p) < 5.0:
					ok = false
			if not ok:
				continue
			placed.append(p)
			breakable_points.append([kind, p, yaw])
			var half := Vector2(size.x, size.z) / 2.0 if yaw == 0.0 else Vector2(size.z, size.x) / 2.0
			_obstacles.append([Vector2(p.x, p.z), half])
			n += 1


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
func _prop(root: Node3D, model: String, x: float, z: float, rot_deg: float, scale: float, collide: bool, y := 0.0) -> Node3D:
	var path := ("res://assets/" + model) if "/" in model else (ENV_PATH % model)
	var inst: Node3D = load(path).instantiate()
	inst.position = Vector3(x, y, z)
	if "tree" in model:
		_apply_wind(inst)
	elif model.begins_with("forest/") and not model.begins_with("forest/survival"):
		_fix_nature(inst)
	inst.rotation.y = deg_to_rad(rot_deg)
	inst.scale = Vector3.ONE * scale
	root.add_child(inst)
	if not collide:
		return inst
	var box := Models._local_aabb(inst)
	var center := box.get_center() * scale
	var size := box.size * scale
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = inst.position
	body.rotation.y = inst.rotation.y
	# Collision qui suit la vraie forme du modèle (on peut tirer au-dessus d'un capot, sous un auvent...)
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		if not m.visible or m.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = m
		while n != inst and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var shape := CollisionShape3D.new()
		shape.shape = m.mesh.create_trimesh_shape()
		shape.transform = Transform3D(Basis().scaled(Vector3.ONE * scale), Vector3.ZERO) * xf
		body.add_child(shape)
	var pen := penetration_material(model)
	if pen != "":
		body.set_meta("pen", pen)
	root.add_child(body)
	var c2 := Vector2(center.x, center.z).rotated(-inst.rotation.y)
	var half := Vector2(size.x, size.z) / 2.0
	if int(round(rot_deg)) % 180 != 0:
		half = Vector2(half.y, half.x)
	_obstacles.append([Vector2(x, z) + c2, half])
	return inst


## Plan d'eau animé (shader assets/shaders/water.gdshader), subdivisé pour que les vagues bougent.
func _water(root: Node3D, pos: Vector3, size: Vector2, wave: float) -> void:
	var m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = int(size.x / 1.5)
	pm.subdivide_depth = int(size.y / 1.5)
	m.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/water.gdshader")
	mat.set_shader_parameter("wave_height", wave)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = pos
	root.add_child(m)


## Arbres qui bougent avec le vent : chaque matériau est remplacé par le shader « wind »
## (même couleur et même texture).
func _apply_wind(inst: Node3D) -> void:
	var shader: Shader = load("res://assets/shaders/wind.gdshader")
	var box := Models._local_aabb(inst)
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src = mi.get_active_material(s)
			var sm := ShaderMaterial.new()
			sm.shader = shader
			sm.set_shader_parameter("model_height", maxf(box.size.y, 0.1))
			sm.set_shader_parameter("strength", box.size.y * 0.035)
			if src is BaseMaterial3D:
				sm.set_shader_parameter("albedo", _nature_color(String(src.resource_name), src.albedo_color))
				if src.albedo_texture != null:
					sm.set_shader_parameter("albedo_texture", src.albedo_texture)
					sm.set_shader_parameter("use_texture", true)
			mi.set_surface_override_material(s, sm)


## Forêt : arbres tout autour de l'arène (décor) et feu de camp allumé.
func _build_forest_extras(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var models := ["tree_pineTallA", "tree_pineTallB", "tree_pineRoundA", "tree_default", "tree_oak", "tree_cone", "tree_fat"]
	for i in 70:
		var a := rng.randf() * TAU
		var d := rng.randf_range(34.0, 55.0)
		_prop(root, F % models[rng.randi() % models.size()], cos(a) * d, sin(a) * d, rng.randf() * 360.0, rng.randf_range(5.0, 7.5), false)
	var fire := OmniLight3D.new()
	fire.light_color = Color(1.0, 0.55, 0.2)
	fire.light_energy = 2.0
	fire.omni_range = 7.0
	fire.position = Vector3(0, 0.8, -4)
	root.add_child(fire)
	var flames := CPUParticles3D.new()
	flames.amount = 24
	flames.lifetime = 0.8
	flames.direction = Vector3.UP
	flames.spread = 15.0
	flames.initial_velocity_min = 0.8
	flames.initial_velocity_max = 1.6
	flames.gravity = Vector3(0, 0.5, 0)
	flames.scale_amount_min = 0.6
	flames.scale_amount_max = 1.2
	var fm := SphereMesh.new()
	fm.radius = 0.12
	fm.height = 0.24
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.vertex_color_use_as_albedo = true
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.material = fmat
	flames.mesh = fm
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.3, 1.0))
	ramp.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	flames.color_ramp = ramp
	flames.position = Vector3(0, 0.25, -4)
	root.add_child(flames)


## Entrepôt : murs extérieurs, toit, cloisons et piliers en béton, lampes au plafond.
func _build_warehouse(root: Node3D) -> void:
	var h := ROOF_HEIGHT
	var size := HALF * 2.0 + 2.0
	var walls := [
		[Vector3(0, h / 2.0, -HALF - 0.5), Vector3(size, h, 1)], [Vector3(0, h / 2.0, HALF + 0.5), Vector3(size, h, 1)],
		[Vector3(-HALF - 0.5, h / 2.0, 0), Vector3(1, h, size)], [Vector3(HALF + 0.5, h / 2.0, 0), Vector3(1, h, size)],
	]
	for w in walls:
		# Murs découpés en panneaux de 10 m pour l'éclairage
		var long_x: bool = w[1].x > w[1].z
		var length: float = w[1].x if long_x else w[1].z
		var n := int(ceil(length / 10.0))
		for i in n:
			var off := -length / 2.0 + (i + 0.5) * length / n
			var c: Vector3 = w[0] + (Vector3(off, 0, 0) if long_x else Vector3(0, 0, off))
			var s: Vector3 = Vector3(length / n, h, 1) if long_x else Vector3(1, h, length / n)
			var b := _box(root, c, s, Color.WHITE, false, true)
			_set_textured(b, "concrete_floor_02", Color(0.75, 0.73, 0.7), 0.3)
	# Toit (dalles) avec des poutres
	for ix in 6:
		for iz in 6:
			var r := _box(root, Vector3(-25 + ix * 10, h + 0.25, -25 + iz * 10), Vector3(10.2, 0.5, 10.2), Color(0.3, 0.3, 0.32), false, true)
			r.get_child(1).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for x in [-20, -10, 0, 10, 20]:
		_patch(root, Vector3(x, h - 0.3, 0), Vector3(0.4, 0.6, HALF * 2), Color(0.35, 0.33, 0.3))
	for wl in WH_WALLS:
		var b := _box(root, Vector3(wl[0], wl[4] / 2.0, wl[1]), Vector3(wl[2], wl[4], wl[3]), Color.WHITE, true, true)
		_set_textured(b, "concrete_floor_02", Color(0.8, 0.78, 0.74), 0.3)
	# Lampes du plafond
	var ceiling_mat := StandardMaterial3D.new()
	ceiling_mat.emission_enabled = true
	ceiling_mat.emission = Color(1.0, 0.92, 0.75)
	ceiling_mat.emission_energy_multiplier = 3.0
	ceiling_mat.albedo_color = Color(1, 0.95, 0.85)
	for x in [-22.5, -7.5, 7.5, 22.5]:
		for z in [-22.5, -7.5, 7.5, 22.5]:
			var lamp := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(1.6, 0.12, 0.5)
			lamp.mesh = bm
			lamp.material_override = ceiling_mat
			lamp.position = Vector3(x, h - 0.1, z)
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(lamp)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.9, 0.75)
			l.light_energy = 1.6
			l.omni_range = 17.0
			l.omni_attenuation = 1.2
			l.position = Vector3(x, h - 0.6, z)
			root.add_child(l)


## Nuit : ampoules et lumières sur les lampadaires et les projecteurs.
func _build_night_lights(root: Node3D, lamps: Array) -> void:
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.8, 0.5)
	bulb_mat.emission_energy_multiplier = 4.0
	lamp_mat = bulb_mat
	for p in lamps:
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		bulb.mesh = sm
		bulb.material_override = bulb_mat
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bulb.position = Vector3(p[0], p[1], p[2])
		root.add_child(bulb)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.82, 0.55)
		l.light_energy = 2.2
		l.omni_range = 16.0
		l.omni_attenuation = 1.3
		l.position = Vector3(p[0], p[1] - 0.3, p[2])
		root.add_child(l)
		lamp_lights.append(l)


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
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.78, 0.86)
	env.fog_density = 0.003
	env.fog_sky_affect = 0.0
	if night:
		# Nuit : ciel très sombre, clair de lune bleuté, brouillard nocturne
		sky_mat.panorama = _night_sky()
		sky_mat.energy_multiplier = 1.0
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.3, 0.36, 0.55)
		env.ambient_light_energy = 0.32
		env.fog_light_color = Color(0.04, 0.05, 0.09)
		env.fog_density = 0.01
	elif layout == 2:
		# Entrepôt fermé : pas de ciel visible, lumière des lampes et un peu de poussière
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.02, 0.02, 0.025)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.55, 0.53, 0.5)
		env.ambient_light_energy = 0.35
		env.fog_light_color = Color(0.25, 0.23, 0.2)
		env.fog_density = 0.008
	if weather > 0:
		_weather_environment(env, sky)
	var we := WorldEnvironment.new()
	we.environment = env
	we.add_to_group("gfx_env")
	we.set_meta("sky_ambient", env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY)
	# Brouillard volumétrique (rendu avancé, ultra) : halos des lampes la nuit, poussière dans l'entrepôt
	if night:
		we.set_meta("volfog", 0.012)
		we.set_meta("volfog_color", Color(0.55, 0.6, 0.75))
	elif layout == 2:
		we.set_meta("volfog", 0.02)
		we.set_meta("volfog_color", Color(0.9, 0.85, 0.75))
		we.set_meta("indoor", true)
	elif layout == 3:
		we.set_meta("volfog", 0.006)
		we.set_meta("volfog_color", Color(0.85, 0.9, 0.85))
	if weather == 4:
		we.set_meta("volfog", 0.05)
		we.set_meta("volfog_color", Color(0.8, 0.82, 0.85))
		we.set_meta("force_fog", true)  # le brouillard fait partie du jeu : pas désactivable
	elif weather > 0:
		we.set_meta("volfog", 0.015)
		we.set_meta("volfog_color", Color(0.75, 0.78, 0.82))
	root.add_child(we)

	if layout == 2:
		Net.apply_graphics.call_deferred()
		return
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.95, 0.86)
	if night:
		# Lune
		sun.rotation_degrees = Vector3(-35, -60, 0)
		sun.light_energy = 0.2
		sun.light_color = Color(0.6, 0.7, 1.0)
	if weather > 0:
		# Ciel couvert : soleil voilé, caché dans le ciel
		sun.light_energy *= [1.0, 0.35, 0.25, 0.5, 0.4][weather]
		sun.light_color = sun.light_color.lerp(Color(0.85, 0.88, 0.95), 0.6)
		sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.add_to_group("gfx_sun")
	root.add_child(sun)
	# Ombres, brouillard et luminosité selon les options du joueur
	Net.apply_graphics.call_deferred()


## Météo : ciel couvert, brouillard plus épais et couleurs ternes (pluie, orage, neige, brouillard).
func _weather_environment(env: Environment, sky: Sky) -> void:
	var k := weather
	var top: Color = [Color(), Color(0.3, 0.33, 0.38), Color(0.19, 0.21, 0.25), Color(0.6, 0.63, 0.68), Color(0.62, 0.64, 0.66)][k]
	var horizon: Color = [Color(), Color(0.5, 0.53, 0.57), Color(0.35, 0.37, 0.41), Color(0.8, 0.82, 0.86), Color(0.74, 0.76, 0.78)][k]
	if night:
		top = top * 0.08
		horizon = horizon * 0.1
	top.a = 1.0
	horizon.a = 1.0
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = top
	sm.sky_horizon_color = horizon
	sm.ground_horizon_color = horizon
	sm.ground_bottom_color = horizon.darkened(0.4)
	sky.sky_material = sm
	env.fog_light_color = horizon
	env.fog_density = [0.003, 0.012, 0.016, 0.013, 0.045][k] * (1.3 if night else 1.0)
	env.fog_sky_affect = 0.7 if k == 4 else 0.3
	env.adjustment_saturation = 0.82


## Ciel de nuit généré : dégradé bleu nuit et étoiles (même ciel sur toutes les machines).
func _night_sky() -> ImageTexture:
	var w := 2048
	var h := 1024
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		var t := float(y) / h
		var c := Color(0.004, 0.006, 0.018).lerp(Color(0.03, 0.04, 0.08), clampf(t * 2.0, 0.0, 1.0))
		if t > 0.5:
			c = Color(0.01, 0.01, 0.015)
		for x in w:
			img.set_pixel(x, y, c)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in 2600:
		var x := rng.randi_range(0, w - 1)
		var y := int(pow(rng.randf(), 1.4) * h * 0.48)
		var b := rng.randf_range(0.35, 1.0)
		img.set_pixel(x, y, Color(b, b, b * 1.05))
	# Lune
	for dy in range(-9, 10):
		for dx in range(-9, 10):
			if dx * dx + dy * dy <= 81:
				img.set_pixel(1500 + dx, 180 + dy, Color(0.95, 0.95, 0.88))
	return ImageTexture.create_from_image(img)


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
	if weather == 1 or weather == 2:
		# Sol mouillé : plus sombre et brillant
		mat.albedo_color = tint.darkened(0.3)
		mat.roughness = 0.35
	elif weather == 3:
		mat.albedo_color = tint.lerp(Color.WHITE, 0.25)
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


## Couleurs du Nature Kit adaptées à notre éclairage : feuilles plus vertes, bois plus brun.
func _nature_color(mat_name: String, c: Color) -> Color:
	var n := mat_name.to_lower()
	if "leaf" in n or "leafs" in n or "grass" in n or "plant" in n:
		return Color(c.r * 0.6, c.g * 0.72, c.b * 0.32)
	if "wood" in n or "bark" in n or "trunk" in n:
		return Color(c.r * 0.62, c.g * 0.5, c.b * 0.4)
	return c


## Applique la même correction aux modèles du Nature Kit sans vent (rochers, bûches, buissons…).
func _fix_nature(inst: Node3D) -> void:
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src = mi.get_active_material(s)
			if src is BaseMaterial3D:
				var mat: BaseMaterial3D = src.duplicate()
				mat.albedo_color = _nature_color(String(src.resource_name), src.albedo_color)
				mi.set_surface_override_material(s, mat)
