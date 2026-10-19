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
const SLIDE_SPEED := 13.0
const SLIDE_END_SPEED := 4.5
const SLIDE_TIME := 0.85
const SLIDE_COOLDOWN := 0.5
const SLIDE_EYE := 0.85

var game
var char_id := ""
var display_name := ""
var team := -1
var is_bot := false
var owner_peer := 1
var is_local := false
var skin := 0
var class_id := 0
var next_class := -1  # classe demandée pour la prochaine réapparition (serveur)
var loadout: Array = [0, 1, 2]
var slot := 0
var hp := 100
var armor := 0
var grenades := [2, 1]  # explosives, fumigènes
var speed_t := 0.0   # adrénaline (série de 3)
var damage_t := 0.0  # bonus dégâts x2
var _melee_cd := 0.0
var _knife: Node3D
var _swing := 0.0
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
var sliding := false
var _slide_t := 0.0
var _slide_cd := 0.0
var _slide_dir := Vector3.ZERO
var _slide_blend := 0.0


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
	_set_loadout(class_id)

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
		_label.visible = false
		_ring.visible = false
		camera = Camera3D.new()
		camera.fov = float(Net.gfx.fov)
		camera.far = Net.view_distance()
		Net.graphics_changed.connect(_on_graphics_changed)
		camera.near = 0.03
		head.add_child(camera)
		camera.make_current()
		_viewmodel = Node3D.new()
		_viewmodel.position = VIEWMODEL_POS
		camera.add_child(_viewmodel)
		_build_viewmodel()
		_update_viewmodel()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func get_color() -> Color:
	if team >= 0:
		return Data.TEAM_COLORS[team]
	return Color.from_hsv(float(absi(char_id.hash()) % 360) / 360.0, 0.65, 0.95)


func eye_position() -> Vector3:
	return global_position + Vector3(0, EYE_HEIGHT, 0)


## Hauteur du torse visée par les bots (plus basse pendant une glissade).
func aim_height() -> float:
	return 0.7 if sliding else 1.3


func muzzle_position() -> Vector3:
	if is_local and _viewmodel != null and _viewmodel.visible:
		var length: float = Data.WEAPONS[weapon].len
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
	set_sliding(false)
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


func respawn(pos: Vector3, cls := -1) -> void:
	if cls >= 0 and cls != class_id:
		_set_loadout(cls)
	position = pos
	_net_pos = pos
	_prev_pos = pos
	velocity = Vector3.ZERO
	hp = 100
	armor = 0
	grenades = Data.GRENADES_START.duplicate()
	speed_t = 0.0
	damage_t = 0.0
	_net_ignore_until = Time.get_ticks_msec() + 300
	face_center()
	_net_yaw = rotation.y
	set_dead(false)
	if is_local:
		for i in ammo.size():
			ammo[i] = Data.WEAPONS[i].mag
		reloading = 0.0
		head.rotation.x = 0.0
		head.rotation.z = 0.0
		head.position.y = EYE_HEIGHT
	if bot != null:
		bot.reset()


# --- Boucle ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	speed_t = maxf(0.0, speed_t - delta)
	damage_t = maxf(0.0, damage_t - delta)
	_melee_cd -= delta
	if is_local:
		if alive:
			_local_control(delta)
	elif bot != null:
		if alive:
			bot.think(delta)
			# Les bots glissent de temps en temps pendant un combat
			if bot._enemy != null and bot.difficulty > 0 and randf() < delta * 0.25:
				start_slide()
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
	_slide_blend = move_toward(_slide_blend, 1.0 if sliding else 0.0, delta * 8.0)
	_tree.set("parameters/slide/blend_amount", _slide_blend)


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
		var s: float = Net.mouse_sensitivity * (_zoom_fov() / float(Net.gfx.fov) if zoomed else 1.0)
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
	elif event.is_action_pressed("grenade"):
		throw_grenade(0)
	elif event.is_action_pressed("smoke"):
		throw_grenade(1)
	elif event.is_action_pressed("melee"):
		melee()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			switch_weapon((slot + 2) % 3)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			switch_weapon((slot + 1) % 3)


func _local_control(delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var input := Vector2.ZERO
	if captured:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := transform.basis * Vector3(input.x, 0, input.y)
	dir.y = 0
	var sprint := captured and Input.is_action_pressed("sprint") and input.y < -0.1
	if captured and Input.is_action_just_pressed("slide"):
		start_slide()
	_move(delta, dir, captured and Input.is_action_pressed("jump"), sprint)
	_weapons(delta, captured)
	# Caméra plus basse et légèrement penchée pendant la glissade
	var k := minf(1.0, delta * 12.0)
	head.position.y = lerpf(head.position.y, SLIDE_EYE if sliding else EYE_HEIGHT, k)
	head.rotation.z = lerpf(head.rotation.z, 0.06 if sliding else 0.0, k)


## Glissade : possible au sol en courant, garde l'élan puis ralentit.
func start_slide() -> void:
	var hvel := Vector3(velocity.x, 0, velocity.z)
	if sliding or _slide_cd > 0.0 or not is_on_floor() or hvel.length() < 4.0:
		return
	_slide_dir = hvel.normalized()
	_slide_t = SLIDE_TIME
	set_sliding(true)


func set_sliding(on: bool) -> void:
	if sliding == on:
		return
	sliding = on
	# Hitbox plus basse pendant la glissade (aussi sur l'hôte, qui valide les tirs)
	var cap: CapsuleShape3D = _shape.shape
	cap.height = 1.1 if on else 1.8
	_shape.position.y = cap.height / 2.0
	if not on:
		_slide_cd = SLIDE_COOLDOWN


func _move(delta: float, dir: Vector3, want_jump: bool, want_sprint: bool) -> void:
	_slide_cd -= delta
	if sliding:
		_slide_move(delta, dir, want_jump)
		return
	if is_on_floor():
		if want_jump:
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * delta
	var speed := (SPRINT_SPEED if want_sprint else WALK_SPEED) * float(Data.CLASSES[class_id].speed)
	if speed_t > 0.0:
		speed *= 1.3
	var accel := (60.0 if is_on_floor() else 15.0) * delta
	velocity.x = move_toward(velocity.x, dir.x * speed, accel)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel)
	move_and_slide()


func _slide_move(delta: float, dir: Vector3, want_jump: bool) -> void:
	_slide_t -= delta
	var t := 1.0 - _slide_t / SLIDE_TIME
	var speed := lerpf(SLIDE_SPEED, SLIDE_END_SPEED, t * t)
	# On peut un peu orienter la glissade avec les touches
	if dir.length() > 0.1:
		_slide_dir = _slide_dir.slerp(dir.normalized(), minf(1.0, delta * 2.0)).normalized()
	velocity.x = _slide_dir.x * speed
	velocity.z = _slide_dir.z * speed
	if is_on_floor():
		velocity.y = -1.0
		if want_jump:
			# Saut glissé : on garde l'élan
			velocity.y = JUMP_VELOCITY
			set_sliding(false)
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	var real := Vector2(get_real_velocity().x, get_real_velocity().z).length()
	if _slide_t <= 0.0 or (real < 2.0 and _slide_t < SLIDE_TIME - 0.1):
		set_sliding(false)


# --- Armes (joueur local) ----------------------------------------------------------

func switch_weapon(i: int) -> void:
	if i == slot or not alive or i < 0 or i >= loadout.size():
		return
	slot = i
	weapon = loadout[i]
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
	zoomed = captured and int(w.zoom) > 0 and reloading <= 0.0 and Input.is_action_pressed("zoom")
	var base_fov := float(Net.gfx.fov) + (8.0 if sliding else 0.0)
	camera.fov = lerpf(camera.fov, _zoom_fov() if zoomed else base_fov, minf(1.0, delta * (18.0 if zoomed else 8.0)))
	_viewmodel.visible = not zoomed

	# Balancement de l'arme en marchant, recul et abaissement pendant le rechargement
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hspeed > 0.5:
		_bob += delta * hspeed * 1.6
	var bob := Vector3(sin(_bob) * 0.012, -absf(cos(_bob)) * 0.012, 0) * minf(hspeed / WALK_SPEED, 1.5)
	var reload_drop := Vector3(0, -0.12, 0.05) if reloading > 0.0 else Vector3.ZERO
	_viewmodel.position = _viewmodel.position.lerp(VIEWMODEL_POS + bob + reload_drop + Vector3(0, 0, _kick), minf(1.0, delta * 20.0))
	_viewmodel.rotation.x = lerpf(_viewmodel.rotation.x, _kick * 2.0 + (-0.5 if reloading > 0.0 else 0.0), minf(1.0, delta * 15.0))
	_update_swing(delta)

	var trigger := captured and Input.is_action_pressed("shoot")
	if not trigger:
		_trigger_released = true
		return
	if _fire_cd > 0.0 or reloading > 0.0 or _swing > 0.3 or (not w.auto and not _trigger_released):
		return
	if ammo[weapon] <= 0:
		start_reload()
		return
	_trigger_released = false
	_fire_cd = w.rate
	ammo[weapon] -= 1

	var spread: float = w.spread
	if int(w.zoom) > 0 and not zoomed:
		spread = 6.0
	if int(w.pellets) == 1 and (not is_on_floor() or (hspeed > 6.5 and not sliding)):
		spread += 2.5
	var b := camera.global_transform.basis
	var dirs := PackedVector3Array()
	for i in int(w.pellets):
		dirs.append(_spread_dir(b, spread))
	game.local_fire(self, weapon, camera.global_position, dirs)

	head.rotation.x = clampf(head.rotation.x + float(w.recoil), -1.5, 1.5)
	_kick = clampf(float(w.recoil) * 1.5, 0.04, 0.14)
	if ammo[weapon] <= 0:
		start_reload()


func _spread_dir(b: Basis, degrees: float) -> Vector3:
	var a := deg_to_rad(degrees) * sqrt(randf())
	var t := randf() * TAU
	return (b * Vector3(sin(a) * cos(t), sin(a) * sin(t), -cos(a))).normalized()


func _update_viewmodel() -> void:
	for i in _view_guns.size():
		_view_guns[i].visible = i == slot


func _zoom_fov() -> float:
	var z := int(Data.WEAPONS[weapon].zoom)
	return float(z) if z > 0 else ZOOM_FOV


## Change de classe : 3 nouvelles armes, chargeurs pleins.
func _set_loadout(cls: int) -> void:
	class_id = clampi(cls, 0, Data.CLASSES.size() - 1)
	loadout = Data.CLASSES[class_id]["weapons"].duplicate()
	slot = 0
	weapon = bot_weapon() if is_bot else loadout[0]
	slot = loadout.find(weapon)
	reloading = 0.0
	zoomed = false
	ammo.clear()
	for w in Data.WEAPONS:
		ammo.append(w.mag)
	show_weapon(weapon)
	if _viewmodel != null:
		_build_viewmodel()
		_update_viewmodel()


func _build_viewmodel() -> void:
	for g in _view_guns:
		g.queue_free()
	_view_guns.clear()
	for wi in loadout:
		var g := Models.weapon(Data.WEAPONS[wi].model, Data.WEAPONS[wi].len)
		_viewmodel.add_child(g)
		_view_guns.append(g)


## Arme tenue en main vue par les autres joueurs.
func show_weapon(wi: int) -> void:
	if _gun != null and _gun.get_meta("weapon", -1) == wi:
		return
	_gun = People.hold_gun(_model, Data.WEAPONS[wi].model, float(Data.WEAPONS[wi].len) * 1.2)
	_gun.set_meta("weapon", wi)


func _on_graphics_changed() -> void:
	camera.far = Net.view_distance()


func _process(_delta: float) -> void:
	# L'arme pointe toujours dans la direction visée (et pas selon la rotation de la main)
	if not is_local and alive and visible:
		People.aim_gun(_gun, _model, -head.global_transform.basis.z)


## Arme utilisée par un bot : la première arme « simple » (une balle, sans explosion) de sa classe.
func bot_weapon() -> int:
	for wi in loadout:
		if int(Data.WEAPONS[wi].pellets) == 1 and float(Data.WEAPONS[wi].splash) == 0.0:
			return wi
	return loadout[0]


# --- Grenades, couteau, bonus ---------------------------------------------------------

func throw_grenade(kind: int) -> void:
	if grenades[kind] <= 0 or _melee_cd > 0.0:
		return
	if not multiplayer.is_server():
		grenades[kind] -= 1  # le serveur décompte lui-même sa copie
	_melee_cd = 0.6
	_swing = 1.0  # l'arme s'abaisse pendant le lancer
	game.items.throw_grenade(self, kind)


func melee() -> void:
	if _melee_cd > 0.0:
		return
	_melee_cd = 0.6
	_swing = 1.0
	zoomed = false
	if _knife == null:
		_knife = Models.weapon("Knife_1", 0.32)
		_knife.scale = Vector3.ONE * 0.28  # le modèle est mesuré sur sa largeur : on le réduit
		_viewmodel.get_parent().add_child(_knife)
	_knife.visible = true
	game.local_melee(self)


## Animation du couteau et abaissement de l'arme (appelé chaque image pour le joueur local).
func _update_swing(delta: float) -> void:
	if _swing <= 0.0:
		if _knife != null:
			_knife.visible = false
		return
	_swing = maxf(0.0, _swing - delta * 2.5)
	var t := 1.0 - _swing
	if _knife != null and _knife.visible:
		# Coup de droite à gauche devant la caméra
		_knife.position = Vector3(lerpf(0.35, -0.25, t), -0.18 + sin(t * PI) * 0.06, -0.45)
		_knife.rotation = Vector3(-0.3, lerpf(0.9, -0.9, t), -0.5)
	_viewmodel.position.y -= sin(t * PI) * 0.25


## Effet d'un bonus ramassé (appelé sur toutes les machines).
func apply_pickup(kind: String) -> void:
	match kind:
		"ammo":
			for i in ammo.size():
				ammo[i] = Data.WEAPONS[i].mag
			grenades = Data.GRENADES_START.duplicate()
			reloading = 0.0
		"damage":
			damage_t = Data.DAMAGE_BOOST_TIME
