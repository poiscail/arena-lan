extends RefCounted
## Cerveau d'un bot (exécuté uniquement sur le serveur).
## Il cherche un ennemi visible, se bat en strafant, sinon traque via le graphe de navigation.

const Data := preload("res://scripts/data.gd")

const REACTION := [0.9, 0.5, 0.25]   # secondes avant de tirer sur une nouvelle cible
const AIM_ERROR := [7.0, 3.5, 1.6]   # dispersion du tir en degrés
const TURN_SPEED := [4.0, 7.0, 12.0]
const FIRE_SLOW := [1.8, 1.3, 1.0]   # multiplicateur de cadence
const VIEW_RANGE := 70.0
const MAG := 30

var c
var map
var game
var difficulty := 1

var move_dir := Vector3.ZERO
var jump := false
var sprint := false

var _enemy = null
var _react := 0.0
var _scan_t := 0.0
var _path := PackedVector3Array()
var _path_i := 0
var _repath_t := 0.0
var _strafe_t := 0.0
var _strafe := 1.0
var _fire_cd := 0.0
var _ammo := MAG
var _reload := 0.0
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _alert = null
var _alert_t := 0.0


func reset() -> void:
	_enemy = null
	_alert = null
	_path = PackedVector3Array()
	_path_i = 0
	_repath_t = 0.0
	_ammo = MAG
	_reload = 0.0


func alert(attacker) -> void:
	_alert = attacker
	_alert_t = 2.5
	_scan_t = 0.0


func think(delta: float) -> void:
	move_dir = Vector3.ZERO
	jump = false
	sprint = false
	if not c.alive or game.match_over:
		_enemy = null
		return
	_fire_cd -= delta
	_repath_t -= delta
	_alert_t -= delta
	if _reload > 0.0:
		_reload -= delta
		if _reload <= 0.0:
			_ammo = MAG
	if _enemy != null and not is_instance_valid(_enemy):
		_enemy = null
	if _alert != null and not is_instance_valid(_alert):
		_alert = null

	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.15
		var seen = _find_enemy()
		if seen != _enemy:
			_react = REACTION[difficulty] * randf_range(0.8, 1.3)
		_enemy = seen

	if _enemy != null and _enemy.alive:
		_fight(delta)
	else:
		_roam(delta)
	_check_stuck(delta)


func _find_enemy():
	var eye: Vector3 = c.eye_position()
	var fwd: Vector3 = -c.global_transform.basis.z
	var best = null
	var best_d := VIEW_RANGE
	for o in game.chars.values():
		if not o.alive or not game.is_enemy(c, o):
			continue
		var to: Vector3 = o.position + Vector3(0, 1.2, 0) - eye
		var d := to.length()
		if d >= best_d:
			continue
		var flat := Vector3(to.x, 0, to.z).normalized()
		var in_view: bool = fwd.dot(flat) > 0.2 or d < 8.0 or o == _enemy or (o == _alert and _alert_t > 0.0)
		if in_view and game.line_clear(eye, eye + to):
			best = o
			best_d = d
	return best


func _fight(delta: float) -> void:
	var aim: Vector3 = _enemy.position + Vector3(0, 1.3, 0)
	_face(aim, delta)
	var to: Vector3 = aim - c.eye_position()
	var dist := to.length()

	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_t = randf_range(0.4, 1.4)
		_strafe = -1.0 if randf() < 0.5 else 1.0
		if randf() < 0.12 * (difficulty + 1):
			jump = true
	var right: Vector3 = c.global_transform.basis.x
	var fwd := Vector3(to.x, 0, to.z).normalized()
	move_dir = right * _strafe
	if dist > 22.0:
		move_dir += fwd
	elif dist < 7.0:
		move_dir -= fwd
	move_dir.y = 0
	move_dir = move_dir.normalized()

	_react -= delta
	if _react > 0.0 or _fire_cd > 0.0 or _reload > 0.0:
		return
	if _ammo <= 0:
		_reload = 1.8
		return
	var look: Vector3 = -c.head.global_transform.basis.z
	if look.angle_to(to) > 0.2:
		return
	_ammo -= 1
	_fire_cd = float(Data.WEAPONS[0].rate) * FIRE_SLOW[difficulty] * randf_range(1.0, 1.5)
	game.bot_fire(c, _cone(look, AIM_ERROR[difficulty]))


func _roam(delta: float) -> void:
	if _repath_t <= 0.0 or _path_i >= _path.size():
		_repath_t = 2.0
		_path = map.find_path(c.position, _pick_goal())
		_path_i = 0
		if _path.size() > 1 and map.segment_clear(c.position, _path[1]):
			_path_i = 1
	if _path_i >= _path.size():
		return
	var p := _path[_path_i]
	var to: Vector3 = p - c.position
	to.y = 0
	if to.length() < 1.0:
		_path_i += 1
		return
	move_dir = to.normalized()
	sprint = true
	if _alert != null and _alert_t > 0.0 and _alert.alive:
		_face(_alert.position + Vector3(0, 1.3, 0), delta)
	else:
		_face(Vector3(p.x, c.eye_position().y, p.z), delta)


func _pick_goal() -> Vector3:
	if _alert != null and _alert.alive and _alert_t > -3.0:
		return _alert.position
	if randf() < 0.3:
		return map.random_point()
	var best = null
	var best_d := 1e9
	for o in game.chars.values():
		if o.alive and game.is_enemy(c, o):
			var d: float = c.position.distance_to(o.position)
			if d < best_d:
				best_d = d
				best = o
	return best.position if best != null else map.random_point()


func _check_stuck(delta: float) -> void:
	_stuck_t += delta
	if _stuck_t < 1.0:
		return
	if move_dir.length() > 0.1 and c.position.distance_to(_last_pos) < 0.6:
		jump = true
		_path = map.find_path(c.position, map.random_point())
		_path_i = 0
		_repath_t = 2.0
	_stuck_t = 0.0
	_last_pos = c.position


func _face(point: Vector3, delta: float) -> void:
	var to: Vector3 = point - c.eye_position()
	var k := minf(1.0, TURN_SPEED[difficulty] * delta)
	c.rotation.y = lerp_angle(c.rotation.y, atan2(-to.x, -to.z), k)
	c.head.rotation.x = lerpf(c.head.rotation.x, atan2(to.y, Vector2(to.x, to.z).length()), k)


func _cone(dir: Vector3, degrees: float) -> Vector3:
	var a := deg_to_rad(degrees) * sqrt(randf())
	var t := randf() * TAU
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(dir).normalized()
	return (dir * cos(a) + (side * cos(t) + up * sin(t)) * sin(a)).normalized()
