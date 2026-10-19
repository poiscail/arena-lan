extends Node3D
## Caméra spectateur quand le joueur local est mort : suit un coéquipier (vue derrière lui)
## ou se déplace librement. Clic gauche / droit : joueur suivant / précédent. Espace : caméra libre.

const FOLLOW_DIST := 3.4
const FREE_SPEED := 12.0

var game
var active := false
var free := false
var target = null
var cam: Camera3D
var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = float(Net.gfx.fov)
	cam.far = Net.view_distance()
	add_child(cam)


func start() -> void:
	var me = game.local_char
	active = true
	free = false
	cam.fov = float(Net.gfx.fov)
	cam.far = Net.view_distance()
	if me != null and me.camera != null:
		cam.global_transform = me.camera.global_transform
	_yaw = cam.global_rotation.y
	_pitch = cam.global_rotation.x
	target = null
	_next(1)
	if target == null:
		free = true
	cam.make_current()


func stop() -> void:
	active = false
	target = null
	var me = game.local_char
	if me != null and me.camera != null:
		me.camera.make_current()


## Personnages qu'on peut regarder : ses coéquipiers vivants (tout le monde en chacun pour soi).
func _candidates() -> Array:
	var me = game.local_char
	var out := []
	for id in game.chars:
		var c = game.chars[id]
		if c == me or not c.alive:
			continue
		if me != null and me.team >= 0 and c.team != me.team:
			continue
		out.append(c)
	out.sort_custom(func(a, b): return a.char_id < b.char_id)
	return out


func _next(step: int) -> void:
	var list := _candidates()
	if list.is_empty():
		target = null
		return
	var i := list.find(target)
	target = list[(i + step + list.size()) % list.size()] if i >= 0 else list[0]
	free = false


func _unhandled_input(event: InputEvent) -> void:
	if not active or game.hud.chat_open or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion and free:
		_yaw -= event.relative.x * Net.mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * Net.mouse_sensitivity, -1.5, 1.5)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_next(1)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_next(-1)
	elif event.is_action_pressed("jump"):
		free = not free
		if free:
			_yaw = cam.global_rotation.y
			_pitch = cam.global_rotation.x
		elif target == null or not target.alive:
			_next(1)


func _process(delta: float) -> void:
	if not active:
		return
	if not free and (target == null or not is_instance_valid(target) or not target.alive):
		_next(1)
		if target == null:
			free = true
	if free:
		_free_move(delta)
	else:
		_follow(delta)


func _free_move(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not game.hud.chat_open:
		var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		dir = Basis.from_euler(Vector3(_pitch, _yaw, 0)) * Vector3(v.x, 0, v.y)
	var speed := FREE_SPEED * (2.0 if Input.is_action_pressed("sprint") else 1.0)
	var pos := cam.global_position + dir * speed * delta
	# Reste dans les limites de la carte
	pos.x = clampf(pos.x, -45.0, 45.0)
	pos.z = clampf(pos.z, -45.0, 45.0)
	pos.y = clampf(pos.y, 0.5, 40.0)
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, 0)), pos)


## Vue derrière l'épaule du joueur suivi, sans traverser les murs.
func _follow(delta: float) -> void:
	var head: Vector3 = target.global_position + Vector3(0, 1.75, 0)
	var basis: Basis = Basis.from_euler(Vector3(clampf(target.head.rotation.x, -0.9, 0.9) * 0.6, target.rotation.y, 0))
	var back: Vector3 = basis * Vector3(0.45, 0.35, FOLLOW_DIST)
	var want := head + back
	var hit: Dictionary = game._ray(head, want, [target.get_rid()] as Array[RID], 1)
	if not hit.is_empty():
		want = hit.position + (head - want).normalized() * 0.3
	var k := minf(1.0, delta * 10.0)
	var pos := cam.global_position.lerp(want, k)
	var look := head + (basis * Vector3(0, 0, -10.0))
	cam.global_transform = Transform3D(Basis(), pos).looking_at(look, Vector3.UP)
	_yaw = cam.global_rotation.y
	_pitch = cam.global_rotation.x


## Texte affiché en bas de l'écran.
func info_text() -> String:
	if free:
		return "CAMÉRA LIBRE  ·  ZQSD + souris  ·  Maj : plus vite  ·  Espace : suivre un coéquipier"
	if target != null:
		return "TU REGARDES : %s  ·  Clic : joueur suivant  ·  Espace : caméra libre" % target.display_name
	return ""
