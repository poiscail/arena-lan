extends Node3D
## Météo de la partie : pluie (avec flaques), orage (éclairs et tonnerre), neige (sol enneigé)
## ou brouillard. Le ciel couvert et le brouillard sont réglés par la carte (map.gd) ; ici, les
## précipitations qui suivent la caméra, les sons d'ambiance (générés) et les éclairs, qui
## tombent aux mêmes moments sur toutes les machines (tirés d'une graine commune).

const MapScript := preload("res://scripts/map.gd")

const NONE := 0
const RAIN := 1
const STORM := 2
const SNOW := 3
const FOG := 4
const NAMES := ["Beau temps", "Pluie", "Orage", "Neige", "Brouillard"]
# Distance à laquelle les bots repèrent un ennemi, selon la météo
const BOT_VIEW := [70.0, 55.0, 50.0, 45.0, 28.0]
# Nombre de gouttes / flocons selon la qualité des effets (bas, moyen, élevé, ultra)
const AMOUNTS := {RAIN: [500, 1000, 1800, 2800], STORM: [700, 1400, 2400, 3600], SNOW: [600, 1200, 2000, 3000]}

var kind := NONE
var game
var _night := false
var _fall: CPUParticles3D
var _splash: CPUParticles3D
var _flash: DirectionalLight3D
var _bolt: MeshInstance3D
var _sky: Material
var _strikes := []  # [instant (s depuis le début de la partie), direction (rad), distance (m)]
var _next := 0
var _flash_t := -1.0
var _thunder: AudioStreamWAV
var _rng := RandomNumberGenerator.new()


func setup(g, map, seed: int) -> void:
	game = g
	kind = map.weather
	_night = map.night
	if kind == NONE or DisplayServer.get_name() == "headless":
		return
	_rng.seed = seed
	var we := get_tree().get_first_node_in_group("gfx_env") as WorldEnvironment
	_sky = we.environment.sky.sky_material
	match kind:
		RAIN, STORM:
			_build_rain()
			_build_puddles(map)
		SNOW:
			_build_snow()
			_build_snow_cover(map)
	if kind == STORM:
		_plan_strikes()
		_build_flash()
	var amb := AudioStreamPlayer.new()
	amb.stream = _ambience_loop()
	amb.volume_db = [0.0, -9.0, -6.0, -16.0, -18.0][kind]
	amb.autoplay = true
	add_child(amb)
	Net.graphics_changed.connect(_update_amount)
	_update_amount()


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var p := cam.global_position
		if _fall != null:
			_fall.global_position = p + Vector3(0, 10.0 if kind != SNOW else 5.0, 0)
		if _splash != null:
			_splash.global_position = Vector3(p.x, 0.06, p.z)
	if kind == STORM:
		_update_storm(delta)


func _update_amount() -> void:
	if _fall == null:
		return
	var fx := clampi(int(Net.gfx.get("fx", 2)), 0, 3)
	var n: int = AMOUNTS[kind][fx]
	if _fall.amount != n:
		_fall.amount = n
	if _splash != null and _splash.amount != n / 4:
		_splash.amount = n / 4


# --- Pluie ------------------------------------------------------------------------------

func _build_rain() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.7, 0.76, 0.86, 0.3) * (Color(0.35, 0.35, 0.4, 1.0) if _night else Color.WHITE)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	var qm := QuadMesh.new()
	qm.size = Vector2(0.016, 0.55)
	qm.material = mat
	_fall = _particles(qm, Vector3(16, 0.5, 16), 0.9)
	_fall.direction = Vector3(0.25 if kind == STORM else 0.08, -1, 0)
	_fall.spread = 3.0
	_fall.initial_velocity_min = 17.0
	_fall.initial_velocity_max = 21.0
	# Éclaboussures au sol autour du joueur
	var smat := mat.duplicate() as StandardMaterial3D
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smat.albedo_color.a = 0.28
	var sq := QuadMesh.new()
	sq.size = Vector2(0.06, 0.035)
	sq.material = smat
	_splash = _particles(sq, Vector3(12, 0, 12), 0.22)
	_splash.direction = Vector3.UP
	_splash.spread = 50.0
	_splash.initial_velocity_min = 0.5
	_splash.initial_velocity_max = 1.2
	_splash.gravity = Vector3(0, -6, 0)
	_splash.scale_amount_min = 0.6
	_splash.scale_amount_max = 1.4


## Flaques (même place sur toutes les machines) : surface sombre qui reflète le ciel, avec des ronds.
func _build_puddles(map) -> void:
	var shader: Shader = load("res://assets/shaders/puddle.gdshader")
	var forest: bool = map.layout == 3
	var placed := 0
	for i in 200:
		if placed >= 18:
			break
		var p := Vector3(_rng.randf_range(-MapScript.HALF + 2, MapScript.HALF - 2), 0, _rng.randf_range(-MapScript.HALF + 2, MapScript.HALF - 2))
		var s := Vector2(_rng.randf_range(1.6, 4.2), _rng.randf_range(1.2, 3.0))
		if not map.is_clear(p) or (forest and absf(p.z) < 3.5):
			continue
		var m := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = s
		m.mesh = pm
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("seed", _rng.randf() * 50.0)
		mat.set_shader_parameter("size", s)
		if forest:
			mat.set_shader_parameter("tint", Color(0.05, 0.04, 0.025))
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.position = Vector3(p.x, 0.05, p.z)
		m.rotation.y = _rng.randf() * TAU
		add_child(m)
		placed += 1


# --- Neige ------------------------------------------------------------------------------

func _build_snow() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 32
	tex.height = 32
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.3, 0.32, 0.38) if _night else Color(0.97, 0.98, 1.0)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	var qm := QuadMesh.new()
	qm.size = Vector2(0.12, 0.12)
	qm.material = mat
	_fall = _particles(qm, Vector3(18, 6, 18), 9.0)
	_fall.direction = Vector3(0.15, -1, 0.05)
	_fall.spread = 30.0
	_fall.initial_velocity_min = 0.8
	_fall.initial_velocity_max = 1.6
	_fall.scale_amount_min = 0.5
	_fall.scale_amount_max = 1.5


## Couche de neige irrégulière sur le sol (pas sur la mer du port ni dans le ruisseau de la forêt).
func _build_snow_cover(map) -> void:
	var m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/snow.gdshader")
	mat.set_shader_parameter("brightness", 0.35 if _night else 1.0)
	if map.layout == 4:
		var east: float = MapScript.HALF + 3.0
		pm.size = Vector2(east + 70.0, 140.0)
		m.position = Vector3((east - 70.0) / 2.0, 0.045, 0)
	else:
		pm.size = Vector2(140, 140)
		m.position = Vector3(0, 0.045, 0)
	if map.layout == 3:
		mat.set_shader_parameter("clear_band", Vector2(2.2, 0.8))
	m.mesh = pm
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)


func _particles(mesh: Mesh, box: Vector3, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = 100
	p.lifetime = life
	p.preprocess = life
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
	p.gravity = Vector3.ZERO
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.extra_cull_margin = 40.0
	add_child(p)
	return p


# --- Orage ------------------------------------------------------------------------------

func _plan_strikes() -> void:
	var total := float(game.settings.get("time_limit", 10)) * 60.0 + 120.0
	var t := _rng.randf_range(4.0, 10.0)
	while t < total:
		_strikes.append([t, _rng.randf() * TAU, _rng.randf_range(70.0, 160.0)])
		t += _rng.randf_range(8.0, 22.0)


func _build_flash() -> void:
	_flash = DirectionalLight3D.new()
	_flash.light_color = Color(0.82, 0.86, 1.0)
	_flash.shadow_enabled = false
	_flash.visible = false
	add_child(_flash)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.BLACK
	mat.emission_enabled = true
	mat.emission = Color(0.85, 0.9, 1.0)
	mat.emission_energy_multiplier = 8.0
	mat.disable_fog = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bolt = MeshInstance3D.new()
	_bolt.material_override = mat
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.visible = false
	add_child(_bolt)


func _update_storm(delta: float) -> void:
	var elapsed := float(game.settings.get("time_limit", 10)) * 60.0 - float(game.time_left)
	while _next < _strikes.size() and float(_strikes[_next][0]) <= elapsed:
		if elapsed - float(_strikes[_next][0]) < 1.0:
			_strike(_strikes[_next][1], _strikes[_next][2])
		_next += 1
	if _flash_t < 0.0:
		return
	_flash_t += delta
	var t := _flash_t
	var f := 0.0
	if t < 0.08:
		f = 1.0
	elif t < 0.14:
		f = 0.15
	elif t < 0.24:
		f = 0.8
	elif t < 0.6:
		f = 0.8 * (1.0 - (t - 0.24) / 0.36)
	else:
		_flash_t = -1.0
	_flash.visible = f > 0.0
	_flash.light_energy = f * (1.6 if _night else 2.4)
	_bolt.visible = t < 0.24 and f > 0.2
	_sky.set("energy_multiplier", 1.0 + f * (6.0 if _night else 2.5))


func _strike(angle: float, dist: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var origin := cam.global_position if cam != null else Vector3.ZERO
	var dir := Vector3(cos(angle), 0, sin(angle))
	var base := Vector3(origin.x, 0, origin.z) + dir * dist
	_bolt.mesh = _bolt_mesh(base, dir)
	_flash.rotation = Vector3(deg_to_rad(-65.0), -angle + PI / 2.0, 0)
	_flash_t = 0.0
	if _thunder == null:
		_thunder = _thunder_sound()
	var delay := dist / 120.0
	var vol := lerpf(-1.0, -9.0, (dist - 70.0) / 90.0)
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		var p := AudioStreamPlayer.new()
		p.stream = _thunder
		p.volume_db = vol
		p.pitch_scale = randf_range(0.8, 1.1)
		add_child(p)
		p.play()
		p.finished.connect(p.queue_free))


## Éclair : ligne brisée du ciel jusqu'au sol (deux rubans en croix pour être vu de partout),
## avec une branche.
func _bolt_mesh(base: Vector3, dir: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := base + Vector3(_rng.randf_range(-10, 10), 75.0, _rng.randf_range(-10, 10))
	var pts := [top]
	var steps := 12
	for i in range(1, steps + 1):
		var k := float(i) / steps
		var p := top.lerp(base, k)
		if i < steps:
			p += Vector3(_rng.randf_range(-4, 4), _rng.randf_range(-1.5, 1.5), _rng.randf_range(-4, 4))
		pts.append(p)
	_ribbon(st, pts, 0.7)
	var b := randi_range(3, 6)
	var branch := [pts[b]]
	var side := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
	for i in 4:
		branch.append(branch[-1] + side * _rng.randf_range(3, 6) + Vector3(0, -_rng.randf_range(4, 8), 0))
	_ribbon(st, branch, 0.35)
	return st.commit()


func _ribbon(st: SurfaceTool, pts: Array, w: float) -> void:
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		for off in [Vector3(w, 0, 0), Vector3(0, 0, w)]:
			st.add_vertex(a - off)
			st.add_vertex(a + off)
			st.add_vertex(b + off)
			st.add_vertex(a - off)
			st.add_vertex(b + off)
			st.add_vertex(b - off)


# --- Sons générés -----------------------------------------------------------------------

## Boucle d'ambiance (pluie ou vent) : bruit filtré, calculé deux fois pour que la fin
## rejoigne exactement le début (pas de clic à la reprise).
func _ambience_loop() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 3
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var data := PackedByteArray()
	data.resize(n * 4)
	var rain := kind == RAIN or kind == STORM
	for ch in 2:
		var noise := PackedFloat32Array()
		noise.resize(n)
		for i in n:
			noise[i] = rng.randf_range(-1.0, 1.0)
		var lo := 0.0
		var hi := 0.0
		for pass_i in 2:
			for i in n:
				var w := noise[i]
				var v := 0.0
				if rain:
					# Bruissement : bande moyenne, plus grave pendant l'orage
					hi += (w - hi) * (0.3 if kind == RAIN else 0.2)
					lo += (w - lo) * 0.03
					v = (hi - lo) * 0.9 + lo * (0.8 if kind == STORM else 0.4)
				else:
					# Vent : bruit très grave qui monte et descend
					lo += (w - lo) * 0.012
					var gust := 0.55 + 0.45 * sin(TAU * 2.0 * float(i) / n + ch * 1.3)
					v = lo * 5.0 * gust
				if pass_i == 1:
					data.encode_s16((i * 2 + ch) * 2, int(clampf(v, -1.0, 1.0) * 26000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.stereo = true
	s.mix_rate = rate
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = n
	return s


## Tonnerre : un craquement puis un grondement grave qui roule et s'éteint.
func _thunder_sound() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 4.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var vals := PackedFloat32Array()
	vals.resize(n)
	var lo := 0.0
	var lo2 := 0.0
	var crack := 0.0
	var peak := 0.001
	for i in n:
		var t := float(i) / rate
		var w := rng.randf_range(-1.0, 1.0)
		lo += (w - lo) * 0.02
		lo2 += (lo - lo2) * 0.05
		crack += (w - crack) * 0.5
		var roll := 0.6 + 0.4 * sin(t * 5.0) * sin(t * 2.3 + 1.0)
		var v := lo2 * 12.0 * exp(-t * 0.8) * roll * minf(1.0, t * 8.0)
		v += crack * exp(-t * 14.0) * 0.6
		vals[i] = v
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(vals[i] / peak * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	return s
