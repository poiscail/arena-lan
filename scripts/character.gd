extends CharacterBody3D
## Personnage : joueur local (contrôlé au clavier/souris), joueur distant
## (positions reçues du réseau) ou bot (piloté par le serveur).

const BotScript := preload("res://scripts/bot.gd")
const Data := preload("res://scripts/data.gd")

const GRAVITY := 20.0
const JUMP_VELOCITY := 7.0
const WALK_SPEED := 6.0
const SPRINT_SPEED := 9.0
const EYE_HEIGHT := 1.6
const FOV := 80.0
const ZOOM_FOV := 25.0
const VIEWMODEL_POS := Vector3(0.2, -0.17, -0.55)

var game
var char_id := ""
var display_name := ""
var team := -1
var is_bot := false
var owner_peer := 1
var is_local := false
var hp := 100
var alive := true
var bot = null

var head: Node3D
var camera: Camera3D
var viewmodel: MeshInstance3D

var weapon := 0
var ammo := []
var reloading := 0.0
var zoomed := false

var _body: MeshInstance3D
var _visor: MeshInstance3D
var _gun: MeshInstance3D
var _label: Label3D
var _shape: CollisionShape3D
var _fire_cd := 0.0
var _trigger_released := true
var _kick := 0.0
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

	_body = MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.4
	cm.height = 1.8
	_body.mesh = cm
	_body.position.y = 0.9
	_body.material_override = _mat(color)
	add_child(_body)

	head = Node3D.new()
	head.position.y = EYE_HEIGHT
	add_child(head)
	_visor = _box_mesh(Vector3(0.46, 0.14, 0.2), Color(0.08, 0.08, 0.1))
	_visor.position = Vector3(0, 0, -0.3)
	head.add_child(_visor)
	_gun = _box_mesh(Data.GUN_LOOKS[0][0], Data.GUN_LOOKS[0][1])
	_gun.position = Vector3(0.3, -0.3, -0.5)
	head.add_child(_gun)

	_label = Label3D.new()
	_label.text = display_name
	_label.position.y = 2.2
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

	if is_bot and multiplayer.is_server():
		bot = BotScript.new()
		bot.c = self
		bot.game = game
		bot.map = game.map
		bot.difficulty = clampi(int(game.settings.difficulty), 0, 2)

	if is_local:
		_body.visible = false
		_visor.visible = false
		_gun.visible = false
		_label.visible = false
		camera = Camera3D.new()
		camera.fov = FOV
		camera.near = 0.05
		head.add_child(camera)
		camera.make_current()
		viewmodel = MeshInstance3D.new()
		viewmodel.position = VIEWMODEL_POS
		viewmodel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		camera.add_child(viewmodel)
		_update_viewmodel()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func get_color() -> Color:
	if team >= 0:
		return Data.TEAM_COLORS[team]
	return Color.from_hsv(float(absi(char_id.hash()) % 360) / 360.0, 0.65, 0.95)


func eye_position() -> Vector3:
	return global_position + Vector3(0, EYE_HEIGHT, 0)


func muzzle_position() -> Vector3:
	if is_local and viewmodel != null and viewmodel.visible:
		var length: float = Data.GUN_LOOKS[weapon][0].z
		return viewmodel.global_position - camera.global_transform.basis.z * (length / 2.0)
	return _gun.global_position - head.global_transform.basis.z * 0.35


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
	visible = not dead
	_shape.set_deferred("disabled", dead)
	if dead:
		zoomed = false
		velocity = Vector3.ZERO


func respawn(pos: Vector3) -> void:
	position = pos
	_net_pos = pos
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
	viewmodel.visible = not zoomed
	viewmodel.position = VIEWMODEL_POS + Vector3(0, 0, _kick)

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
	if weapon != 1 and (not is_on_floor() or Vector2(velocity.x, velocity.z).length() > 6.5):
		spread += 2.5
	var b := camera.global_transform.basis
	var dirs := PackedVector3Array()
	for i in int(w.pellets):
		dirs.append(_spread_dir(b, spread))
	game.local_fire(self, weapon, camera.global_position, dirs)

	head.rotation.x = clampf(head.rotation.x + Data.RECOIL[weapon], -1.5, 1.5)
	_kick = 0.08
	if ammo[weapon] <= 0:
		start_reload()


func _spread_dir(b: Basis, degrees: float) -> Vector3:
	var a := deg_to_rad(degrees) * sqrt(randf())
	var t := randf() * TAU
	return (b * Vector3(sin(a) * cos(t), sin(a) * sin(t), -cos(a))).normalized()


func _update_viewmodel() -> void:
	if viewmodel == null:
		return
	var look: Array = Data.GUN_LOOKS[weapon]
	var bm := BoxMesh.new()
	bm.size = look[0]
	viewmodel.mesh = bm
	viewmodel.material_override = _mat(look[1])


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	return m


func _box_mesh(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	return mi
