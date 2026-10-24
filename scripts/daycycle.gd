## Cycle jour/nuit : une journée complète défile pendant la durée de la partie.
## L'heure se calcule à partir du temps restant (synchronisé par le serveur) : même ciel chez tous les joueurs.
extends Node

const DAY_START := 14.0    # heure de départ sur les cartes de jour : coucher du soleil peu après
const NIGHT_START := 1.0   # heure de départ sur les cartes de nuit : aube peu après
const UPDATE := 0.2
const SKY_STEP := 0.01     # le ciel recalcule son éclairage à chaque changement : seulement par petits paliers
const NIGHT_FOG := Color(0.04, 0.05, 0.09)
const NIGHT_AMBIENT := Color(0.3, 0.36, 0.55)
const SUN_COLOR := Color(1.0, 0.95, 0.86)
const DUSK_COLOR := Color(1.0, 0.55, 0.3)
const MOON_COLOR := Color(0.6, 0.7, 1.0)
const WEATHER_SUN := [1.0, 0.35, 0.25, 0.5, 0.4]

var game
var active := false
var hour := 12.0
var dark := 0.0  # 0 plein jour, 1 nuit noire

var _map
var _start := DAY_START
var _length := 600.0
var _env: Environment
var _sun: DirectionalLight3D
var _sky_mat: Material
var _weather := 0
var _base_top: Color
var _base_horizon: Color
var _day_fog_color: Color
var _day_fog_density := 0.003
var _night_fog_color := NIGHT_FOG
var _night_fog_density := 0.01
var _day_amb_color := Color.WHITE
var _day_amb_energy := 0.55
var _day_amb_contrib := 1.0
var _sky_day := -1.0
var _sky_warm := -1.0
var _weather_dark := -1.0
var _torch := -1  # état des lampes torches imposé au dernier passage jour/nuit (la touche reste libre entre deux)
var _t := 0.0


func setup(g, map, start_hour := -1.0) -> void:
	game = g
	_map = map
	active = map.cycle
	if not active or DisplayServer.get_name() == "headless":
		active = false
		return
	_start = start_hour if start_hour >= 0.0 else (NIGHT_START if map.start_night else DAY_START)
	_length = maxf(60.0, float(g.settings.time_limit) * 60.0)
	_env = (get_tree().get_first_node_in_group("gfx_env") as WorldEnvironment).environment
	_sun = get_tree().get_first_node_in_group("gfx_sun") as DirectionalLight3D
	_weather = map.weather
	_day_fog_color = _env.fog_light_color
	_day_fog_density = _env.fog_density
	if _weather == 0:
		# Ciel de jour photographique + ciel étoilé de la carte de nuit, mélangés par le shader
		var old := _env.sky.sky_material as PanoramaSkyMaterial
		var sm := ShaderMaterial.new()
		sm.shader = load("res://assets/shaders/daynight_sky.gdshader")
		sm.set_shader_parameter("day_sky", old.panorama)
		sm.set_shader_parameter("night_sky", map._night_sky())
		_env.sky.sky_material = sm
		_sky_mat = sm
	else:
		# Ciel couvert : les couleurs du ciel s'assombrissent simplement la nuit
		var pm := _env.sky.sky_material as ProceduralSkyMaterial
		_sky_mat = pm
		_base_top = pm.sky_top_color
		_base_horizon = pm.sky_horizon_color
		_night_fog_color = _day_fog_color * 0.1
		_night_fog_density = _day_fog_density * 1.3
	_read_ambient()
	Net.graphics_changed.connect(_on_graphics_changed)
	_update()


## Lumière ambiante de jour choisie par les options graphiques (relue à chaque changement d'options).
func _read_ambient() -> void:
	_day_amb_color = _env.ambient_light_color
	_day_amb_energy = _env.ambient_light_energy
	_day_amb_contrib = _env.ambient_light_sky_contribution


func _on_graphics_changed() -> void:
	_read_ambient()
	_update()


func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	if _t >= UPDATE:
		_t = 0.0
		_update()


func _update() -> void:
	var elapsed: float = _length - game.time_left
	hour = fposmod(_start + elapsed / _length * 24.0, 24.0)
	var e := sin((hour - 6.0) / 24.0 * TAU)  # hauteur du soleil : 1 à midi, 0 au lever et au coucher, -1 à minuit
	var day := smoothstep(-0.2, 0.12, e)
	dark = 1.0 - day
	var warm := clampf(1.0 - absf(e - 0.03) / 0.28, 0.0, 1.0)

	# Soleil (de l'est vers l'ouest) puis lune
	if e > -0.12:
		var az := (hour - 6.0) / 12.0 * 180.0
		var elev := maxf(rad_to_deg(asin(clampf(e, -1.0, 1.0))) * 0.85, 8.0)
		_sun.rotation_degrees = Vector3(-elev, 90.0 - az, 0)
		_sun.light_energy = 1.35 * smoothstep(-0.12, 0.25, e)
		_sun.light_color = SUN_COLOR.lerp(DUSK_COLOR, warm)
	else:
		_sun.rotation_degrees = Vector3(-35, -60, 0)
		_sun.light_energy = 0.2 * (1.0 - smoothstep(-0.32, -0.12, e))
		_sun.light_color = MOON_COLOR
	if _weather > 0:
		_sun.light_energy *= WEATHER_SUN[_weather]
		_sun.light_color = _sun.light_color.lerp(Color(0.85, 0.88, 0.95), 0.6)

	_env.ambient_light_color = _day_amb_color.lerp(NIGHT_AMBIENT, dark)
	_env.ambient_light_energy = lerpf(_day_amb_energy, 0.32, dark)
	_env.ambient_light_sky_contribution = _day_amb_contrib * day
	_env.fog_light_color = _day_fog_color.lerp(_night_fog_color, dark)
	_env.fog_density = lerpf(_day_fog_density, _night_fog_density, dark)

	if absf(day - _sky_day) >= SKY_STEP or absf(warm - _sky_warm) >= SKY_STEP * 3.0:
		_sky_day = day
		_sky_warm = warm
		if _sky_mat is ShaderMaterial:
			_sky_mat.set_shader_parameter("day", smoothstep(-0.24, 0.05, e))
			_sky_mat.set_shader_parameter("warm", warm)
			_sky_mat.set_shader_parameter("sun_dir", _sun.global_basis.z)
		else:
			var f := lerpf(1.0, 0.09, dark)
			var top := _base_top * f
			var hor := _base_horizon * f
			top.a = 1.0
			hor.a = 1.0
			_sky_mat.sky_top_color = top
			_sky_mat.sky_horizon_color = hor
			_sky_mat.ground_horizon_color = hor
			_sky_mat.ground_bottom_color = hor.darkened(0.4)

	# Lampadaires qui s'allument au crépuscule, lampes torches la nuit
	var lamps := smoothstep(0.3, 0.6, dark)
	for l in _map.lamp_lights:
		l.light_energy = 2.2 * lamps
		l.visible = lamps > 0.01
	if _map.lamp_mat != null:
		_map.lamp_mat.emission_energy_multiplier = 4.0 * lamps
	var torch := 1 if dark > 0.6 else 0
	if torch != _torch:
		_torch = torch
		for fl in get_tree().get_nodes_in_group("flashlights"):
			fl.visible = torch == 1
	if game.weather != null and absf(dark - _weather_dark) >= 0.02:
		_weather_dark = dark
		game.weather.set_dark(dark)
