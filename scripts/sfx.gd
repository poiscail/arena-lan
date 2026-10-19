extends Node3D
## Sons et petits effets visuels de la partie : tirs, impacts, pas, flash du canon, douilles,
## traces de balles et tremblement de caméra.
## Sons : The Free Firearm Sound Library (CC0) et Kenney (CC0), dans assets/sfx/.

const SFX_PATH := "res://assets/sfx/%s"
const MAX_DECALS := 80

var _cache := {}
var _decals := []
var _decal_mat: StandardMaterial3D
var _flash_mat: StandardMaterial3D
var _shell_mat: StandardMaterial3D
var _spark_mat: StandardMaterial3D
var shake := 0.0  # tremblement de caméra du joueur local (0..1)


func _ready() -> void:
	_decal_mat = StandardMaterial3D.new()
	_decal_mat.albedo_color = Color(0.05, 0.05, 0.05, 0.85)
	_decal_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_decal_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_color = Color(1.0, 0.75, 0.35, 1.0)
	_flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 0.9, 1))
	g.set_color(1, Color(1, 0.5, 0.1, 0))
	g.add_point(0.35, Color(1, 0.8, 0.4, 0.8))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	_flash_mat.albedo_texture = gt
	_shell_mat = StandardMaterial3D.new()
	_shell_mat.albedo_color = Color(0.85, 0.65, 0.25)
	_shell_mat.metallic = 0.8
	_shell_mat.roughness = 0.35
	_spark_mat = StandardMaterial3D.new()
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mat.albedo_color = Color(1.0, 0.8, 0.4)


func _stream(name: String) -> AudioStream:
	if not _cache.has(name):
		var path := SFX_PATH % name
		if not ResourceLoader.exists(path):
			path = SFX_PATH % (name + ".ogg")
		if not ResourceLoader.exists(path):
			path = SFX_PATH % (name + ".wav")
		_cache[name] = load(path) if ResourceLoader.exists(path) else null
	return _cache[name]


## Joue un son : en 2D (pos = null, pour le joueur local) ou placé dans le monde.
func play(name: String, pos = null, volume_db := 0.0, pitch_var := 0.06, max_dist := 120.0) -> void:
	var s := _stream(name)
	if s == null:
		return
	var p: Node
	if pos == null:
		var p2 := AudioStreamPlayer.new()
		p2.stream = s
		p2.volume_db = volume_db
		p2.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
		add_child(p2)
		p2.play()
		p2.finished.connect(p2.queue_free)
		p = p2
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = s
		p3.volume_db = volume_db
		p3.unit_size = 10.0
		p3.max_distance = max_dist
		p3.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
		add_child(p3)
		p3.global_position = pos
		p3.play()
		p3.finished.connect(p3.queue_free)
		p = p3


func play_random(base: String, count: int, pos = null, volume_db := 0.0) -> void:
	play("%s_%03d" % [base, randi() % count], pos, volume_db)


## Flash au bout du canon : une étoile lumineuse et une lumière très brève.
func muzzle_flash(pos: Vector3, big := false, local := false) -> void:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	var s := (0.55 if big else 0.32) * (0.4 if local else 1.0)
	qm.size = Vector2(s, s)
	q.mesh = qm
	q.material_override = _flash_mat
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.rotation.z = randf() * TAU
	add_child(q)
	q.global_position = pos
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.35)
	light.light_energy = 2.5
	light.omni_range = 4.0
	q.add_child(light)
	get_tree().create_timer(0.045).timeout.connect(q.queue_free)


## Impact de balle : trace sombre sur la surface et quelques étincelles.
func bullet_impact(pos: Vector3, normal: Vector3, on_character: bool) -> void:
	if not on_character and normal != Vector3.ZERO:
		var d := MeshInstance3D.new()
		var qm := QuadMesh.new()
		var s := randf_range(0.07, 0.11)
		qm.size = Vector2(s, s)
		d.mesh = qm
		d.material_override = _decal_mat
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(d)
		d.global_position = pos + normal * 0.01
		var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT
		d.look_at(pos + normal, up)
		d.rotate_object_local(Vector3.FORWARD, randf() * TAU)
		_decals.append(d)
		if _decals.size() > MAX_DECALS:
			var old = _decals.pop_front()
			if is_instance_valid(old):
				old.queue_free()
	var sp := CPUParticles3D.new()
	sp.one_shot = true
	sp.emitting = true
	sp.amount = 8
	sp.lifetime = 0.25
	sp.explosiveness = 1.0
	sp.direction = normal if normal != Vector3.ZERO else Vector3.UP
	sp.spread = 50.0
	sp.initial_velocity_min = 2.0
	sp.initial_velocity_max = 5.0
	sp.gravity = Vector3(0, -12, 0)
	sp.scale_amount_min = 0.5
	sp.scale_amount_max = 1.0
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, 0.025)
	bm.material = _spark_mat if not on_character else _blood_mat()
	sp.mesh = bm
	add_child(sp)
	sp.global_position = pos
	get_tree().create_timer(0.6).timeout.connect(sp.queue_free)


var _blood: StandardMaterial3D
func _blood_mat() -> StandardMaterial3D:
	if _blood == null:
		_blood = StandardMaterial3D.new()
		_blood.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blood.albedo_color = Color(0.6, 0.05, 0.05)
	return _blood


## Douille éjectée par l'arme du joueur local.
func eject_shell(pos: Vector3, side: Vector3, big := false) -> void:
	var b := RigidBody3D.new()
	b.collision_layer = 0
	b.collision_mask = 1
	b.mass = 0.02
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.02, 0.02, 0.05)
	cs.shape = bs
	b.add_child(cs)
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.006 if not big else 0.01
	cm.bottom_radius = cm.top_radius
	cm.height = 0.025 if not big else 0.04
	m.mesh = cm
	m.material_override = _shell_mat
	m.rotation.x = PI / 2.0
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.add_child(m)
	add_child(b)
	b.global_position = pos
	b.linear_velocity = side * randf_range(2.0, 3.0) + Vector3(0, randf_range(1.5, 2.5), 0)
	b.angular_velocity = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
	get_tree().create_timer(1.5).timeout.connect(b.queue_free)
	get_tree().create_timer(0.35).timeout.connect(func() -> void:
		if is_instance_valid(b):
			play("impactMetal_light_00%d" % (randi() % 2), b.global_position, -18.0, 0.15, 15.0))


func _process(delta: float) -> void:
	shake = move_toward(shake, 0.0, delta * 1.8)
