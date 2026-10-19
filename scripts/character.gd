extends CharacterBody3D
## Personnage : joueur local (contrôlé au clavier/souris), joueur distant
## (positions reçues du réseau) ou bot (piloté par le serveur).

const BotScript := preload("res://scripts/bot.gd")
const Data := preload("res://scripts/data.gd")
const Models := preload("res://scripts/models.gd")
const People := preload("res://scripts/people.gd")

const GRAVITY := 20.0
const JUMP_VELOCITY := 7.0
const WALK_SPEED := 6.0
const SPRINT_SPEED := 9.0
const EYE_HEIGHT := 1.6
const FOV := 80.0
const ZOOM_FOV := 25.0
const VIEWMODEL_POS := Vector3(0.2, -0.2, -0.5)
const DEATH_SHOW_TIME := 1.6

var game
var char_id := ""
var display_name := ""
var team := -1
var is_bot := false
var owner_peer := 1
var is_local := false
var skin := 0
var hp := 100
var alive := true
var bot = null

var head: Node3D
var camera: Camera3D

var weapon := 0
var ammo := []
var reloading := 0.0
var zoomed := false

var _model: Node3D
var _tree: AnimationTree
var _state := "alive"
var _gun: Node3D
var _ring: MeshInstance3D
var _label: Label3D
var _shape: CollisionShape3D
var _viewmodel: Node3D
var _view_guns := []
var _fire_cd := 0.0
var _trigger_released := true
var _kick := 0.0
var _bob := 0.0
var _hide_t := 0.0
var _prev_pos := Vector3.ZERO
var _speed := 0.0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_pitch := 0.0
var _net_ignore_until := 0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var color := get_color()

	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	_shape.shape = cap
	_shape.position.y = 0.9
	add_child(_shape)

	var parts: Array = Data.SKINS[clampi(skin, 0, Data.SKINS.size() - 1)]["parts"]
	_model = People.build(parts, 1.8)
	add_child(_model)
	_tree = _model.get_meta("tree")
	_gun = People.hold_gun(_model, Data.WEAPON_MODELS[0][0])

	# Anneau de couleur au sol pour repérer l'équipe
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.45
	torus.outer_radius = 0.55
	_ring.mesh = torus
	_ring.scale = Vector3(1, 0.15, 1)
	_ring.position.y = 0.04
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = color
	_ring.material_override = ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	head = Node3D.new()
	head.position.y = EYE_HEIGHT
	add_child(head)

	_label = Label3D.new()
	_label.text = display_name
	_label.position.y = 2.15
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.outline_size = 10
	_label.modulate = color.lightened(0.35)
	add_child(_label)

	for w in Data.WEAPONS:
		ammo.append(w.mag)
	face_center()
	_net_pos = position
	_net_yaw = rotation.y
	_prev_pos = position

	if is_bot and multiplayer.is_server():
		bot = BotScript.new()
		bot.c = self
		bot.game = game
		bot.map = game.map
		bot.difficulty = clampi(int(game.settings.difficulty), 0, 2)

	if is_local:
		_model.visible = false
		_gun.visible = false
		_label.visible = false
		_ring.visible = false
		camera = Camera3D.new()
		camera.fov = FOV
		camera.near = 0.03
		head.add_child(camera)
		camera.make_current()
		_viewmodel = Node3D.new()
		_viewmodel.position = VIEWMODEL_POS
		camera.add_child(_viewmodel)
		for wm in Data.WEAPON_MODELS:
			var g := Models.weapon(wm[0], wm[1])
			_viewmodel.add_child(g)
			_view_guns.append(g)
		_update_viewmodel()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func get_color() -> Color:
	if team >= 0:
		return Data.TEAM_COLORS[team]
	return Color.from_hsv(float(absi(char_id.hash()) % 360) / 360.0, 0.65, 0.95)


func eye_position() -> Vector3:
	return global_position + Vector3(0, EYE_HEIGHT, 0)


func muzzle_position() -> Vector3:
	if is_local and _viewmodel != null and _viewmodel.visible:
		var length: float = Data.WEAPON_MODELS[weapon][1]
		return _viewmodel.global_position - camera.global_transform.basis.z * (length / 2.0)
	return _gun.global_position - head.global_transform.basis.z * 0.55 + Vector3(0, 0.1, 0)


func face_center() -> void:
	rotation.y = atan2(position.x, position.z)


# --- Réseau -----------------------------------------------------------------------

func net_target(pos: Vector3, yaw: float, pitch: float) -> void:
	if Time.get_ticks_msec() < _net_ignore_until:
		return
	_net_pos = pos
	_net_yaw = yaw
	_net_pitch = pitch
	if position.distance_to(pos) > 8.0:
		position = pos


func set_dead(dead: bool) -> void:
	alive = not dead
	_shape.set_deferred("disabled", dead)
	if dead:
		zoomed = false
		velocity = Vector3.ZERO
		if is_local:
			visible = false
		else:
			_set_state("dead")
			_label.visible = false
			_ring.visible = false
			_hide_t = DEATH_SHOW_TIME
	else:
		visible = true
		_hide_t = 0.0
		if not is_local:
			_label.visible = true
			_ring.visible = true
		_set_state("alive")


func respawn(pos: Vector3) -> void:
	position = pos
	_net_pos = pos
	_prev_pos = pos
	velocity = Vector3.ZERO
	hp = 100
	_net_ignore_until = Time.get_ticks_msec() + 300
	face_center()
	_net_yaw = rotation.y
	set_dead(false)
	if is_local:
		for i in ammo.size():
			ammo[i] = Data.WEAPONS[i].mag
		reloading = 0.0
		head.rotation.x = 0.0
	if bot != null:
		bot.reset()


# --- Boucle ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if is_local:
		if alive:
			_local_control(delta)
	elif bot != null:
		if alive:
			bot.think(delta)
			_move(delta, bot.move_dir, bot.jump, bot.sprint)
	else:
		var k := minf(1.0, delta * 15.0)
		position = position.lerp(_net_pos, k)
		rotation.y = lerp_angle(rotation.y, _net_yaw, k)
		head.rotation.x = lerpf(head.rotation.x, _net_pitch, k)

	if not is_local:
		_update_animation(delta)


func _update_animation(delta: float) -> void:
	var moved := Vector2(position.x - _prev_pos.x, position.z - _prev_pos.z).length() / maxf(delta, 0.001)
	_prev_pos = position
	_speed = lerpf(_speed, moved, minf(1.0, delta * 10.0))
	if not alive:
		if _hide_t > 0.0:
			_hide_t -= delta
			if _hide_t <= 0.0:
				visible = false
		return
	# Jambes selon la vitesse (0 arrêt, 2.5 marche, 6 jogging, 9.5 sprint), buste selon l'angle de visée
	_tree.set("parameters/loco/blend_position", clampf(_speed, 0.0, 10.0))
	_tree.set("parameters/aim/blend_position", clampf(head.rotation.x, -1.0, 1.0))


## Joue l'animation de tir du haut du corps (vue par les autres joueurs).
func play_shoot() -> void:
	if _tree != null and alive:
		_tree.set("parameters/shoot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _set_state(state: String) -> void:
	if _tree == null or _state == state:
		return
	_state = state
	_tree.set("parameters/state/transition_request", state)


func _unhandled_input(event: InputEvent) -> void:
	if not is_local or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var s: float = Net.mouse_sensitivity * (ZOOM_FOV / FOV if zoomed else 1.0)
		rotation.y -= event.relative.x * s
		head.rotation.x = clampf(head.rotation.x - event.relative.y * s, -1.5, 1.5)
		return
	if not alive:
		return
	if event.is_action_pressed("weapon_1"):
		switch_weapon(0)
	elif event.is_action_pressed("weapon_2"):
		switch_weapon(1)
	elif event.is_action_pressed("weapon_3"):
		switch_weapon(2)
	elif event.is_action_pressed("reload"):
		start_reload()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			switch_weapon((weapon + 2) % 3)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			switch_weapon((weapon + 1) % 3)


func _local_control(delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var input := Vector2.ZERO
	if captured:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := transform.basis * Vector3(input.x, 0, input.y)
	dir.y = 0
	var sprint := captured and Input.is_action_pressed("sprint") and input.y < -0.1
	_move(delta, dir, captured and Input.is_action_pressed("jump"), sprint)
	_weapons(delta, captured)


func _move(delta: float, dir: Vector3, want_jump: bool, want_sprint: bool) -> void:
	if is_on_floor():
		if want_jump:
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * delta
	var speed := SPRINT_SPEED if want_sprint else WALK_SPEED
	var accel := (60.0 if is_on_floor() else 15.0) * delta
	velocity.x = move_toward(velocity.x, dir.x * speed, accel)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel)
	move_and_slide()


# --- Armes (joueur local) ----------------------------------------------------------

func switch_weapon(i: int) -> void:
	if i == weapon or not alive:
		return
	weapon = i
	reloading = 0.0
	zoomed = false
	_fire_cd = 0.25
	_kick = 0.15
	_update_viewmodel()


func start_reload() -> void:
	var w: Dictionary = Data.WEAPONS[weapon]
	if reloading > 0.0 or ammo[weapon] >= w.mag:
		return
	reloading = w.reload
	zoomed = false


func _weapons(delta: float, captured: bool) -> void:
	var w: Dictionary = Data.WEAPONS[weapon]
	_fire_cd -= delta
	_kick = move_toward(_kick, 0.0, delta * 0.6)
	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0:
			reloading = 0.0
			ammo[weapon] = w.mag
	zoomed = captured and weapon == 2 and reloading <= 0.0 and Input.is_action_pressed("zoom")
	camera.fov = lerpf(camera.fov, ZOOM_FOV if zoomed else FOV, minf(1.0, delta * 18.0))
	_viewmodel.visible = not zoomed

	# Balancement de l'arme en marchant, recul et abaissement pendant le rechargement
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hspeed > 0.5:
		_bob += delta * hspeed * 1.6
	var bob := Vector3(sin(_bob) * 0.012, -absf(cos(_bob)) * 0.012, 0) * minf(hspeed / WALK_SPEED, 1.5)
	var reload_drop := Vector3(0, -0.12, 0.05) if reloading > 0.0 else Vector3.ZERO
	_viewmodel.position = _viewmodel.position.lerp(VIEWMODEL_POS + bob + reload_drop + Vector3(0, 0, _kick), minf(1.0, delta * 20.0))
	_viewmodel.rotation.x = lerpf(_viewmodel.rotation.x, _kick * 2.0 + (-0.5 if reloading > 0.0 else 0.0), minf(1.0, delta * 15.0))

	var trigger := captured and Input.is_action_pressed("shoot")
	if not trigger:
		_trigger_released = true
		return
	if _fire_cd > 0.0 or reloading > 0.0 or (not w.auto and not _trigger_released):
		return
	if ammo[weapon] <= 0:
		start_reload()
		return
	_trigger_released = false
	_fire_cd = w.rate
	ammo[weapon] -= 1

	var spread: float = w.spread
	if weapon == 2 and not zoomed:
		spread = 6.0
	if weapon != 1 and (not is_on_floor() or hspeed > 6.5):
		spread += 2.5
	var b := camera.global_transform.basis
	var dirs := PackedVector3Array()
	for i in int(w.pellets):
		dirs.append(_spread_dir(b, spread))
	game.local_fire(self, weapon, camera.global_position, dirs)

	head.rotation.x = clampf(head.rotation.x + Data.RECOIL[weapon], -1.5, 1.5)
	_kick = 0.06 if weapon == 0 else 0.12
	if ammo[weapon] <= 0:
		start_reload()


func _spread_dir(b: Basis, degrees: float) -> Vector3:
	var a := deg_to_rad(degrees) * sqrt(randf())
	var t := randf() * TAU
	return (b * Vector3(sin(a) * cos(t), sin(a) * sin(t), -cos(a))).normalized()


func _update_viewmodel() -> void:
	for i in _view_guns.size():
		_view_guns[i].visible = i == weapon
