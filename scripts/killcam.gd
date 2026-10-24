extends Node3D
## Kill-cam : quand le joueur local est éliminé, rejoue les dernières secondes vues par les yeux du tueur.
## Chaque PC enregistre en continu (30 fois par seconde) la position et la visée de tous les personnages,
## ainsi que les tirs reçus du serveur. Rien n'est envoyé en plus sur le réseau.

const Data := preload("res://scripts/data.gd")
const Models := preload("res://scripts/models.gd")
const Arms := preload("res://scripts/arms.gd")
const People := preload("res://scripts/people.gd")

const RATE := 1.0 / 30.0
const KEEP := 5.0          # secondes gardées en mémoire
const VIEWMODEL_POS := Vector3(0.17, -0.165, -0.6)

var game
var active := false
var cam: Camera3D

var _t := 0.0
var _acc := 0.0
var _frames := {}  # id -> Array de [t, pos, yaw, pitch, head_y, alive]
var _shots := []   # [t, shooter_id, weapon, ends]

# Replay en cours
var _killer = null
var _killer_id := ""
var _victim_id := ""
var _weapon := -1
var _rec_k := []
var _rec_v := []
var _rec_shots := []
var _from := 0.0   # temps (enregistré) du début du replay
var _to := 0.0     # temps (enregistré) de la mort
var _speed := 1.0
var _play := 0.0   # temps enregistré actuellement montré
var _hold := 0.0   # pause sur la mort (temps réel)
var _shot_i := 0
var _ghost: Node3D
var _ghost_tree: AnimationTree
var _ghost_gun: Node3D
var _ghost_prev := Vector3.ZERO
var _ghost_speed := 0.0
var _ghost_dead := false
var _view: Node3D
var _kick := 0.0
var _then: Callable
var _layer: CanvasLayer
var _label: Label
var _bars := []


func _ready() -> void:
	cam = Camera3D.new()
	cam.near = 0.03
	add_child(cam)
	_layer = CanvasLayer.new()
	_layer.layer = 5
	_layer.visible = false
	add_child(_layer)
	# Bandes noires en haut et en bas + titre
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.82)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		if top:
			bar.anchor_bottom = 0.09
		else:
			bar.anchor_top = 0.91
			bar.anchor_bottom = 1.0
		_layer.add_child(bar)
		_bars.append(bar)
	_label = Label.new()
	_label.anchor_right = 1.0
	_label.anchor_bottom = 0.09
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_label)
	var hint := Label.new()
	hint.text = "Espace : passer"
	hint.anchor_top = 0.91
	hint.anchor_right = 1.0
	hint.anchor_bottom = 1.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.modulate = Color(1, 1, 1, 0.7)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(hint)


# --- Enregistrement -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_t += delta
	_acc += delta
	if _acc < RATE:
		return
	_acc = 0.0
	for id in game.chars:
		var c = game.chars[id]
		if not is_instance_valid(c):
			continue
		var list: Array = _frames.get(id, [])
		list.append([_t, c.global_position, c.rotation.y, c.head.rotation.x, c.head.position.y, c.alive])
		while not list.is_empty() and _t - float(list[0][0]) > KEEP:
			list.pop_front()
		_frames[id] = list
	for id in _frames.keys():
		if not game.chars.has(id):
			_frames.erase(id)
	while not _shots.is_empty() and _t - float(_shots[0][0]) > KEEP:
		_shots.pop_front()


## Tir d'un autre joueur (appelé depuis shot_fx).
func record_shot(shooter_id: String, weapon: int, ends: PackedVector3Array) -> void:
	_shots.append([_t, shooter_id, weapon, ends])


# --- Replay ---------------------------------------------------------------------

## Lance le replay de la mort du joueur local. `then` est appelé à la fin (ou si on passe).
## Renvoie false s'il n'y a rien à montrer (option désactivée, pas de tueur, suicide…).
func start(killer, victim, weapon: int, length: float, speed: float, then: Callable) -> bool:
	if not bool(Net.gfx.get("killcam", true)) or killer == null or victim == null or killer == victim:
		return false
	if not _frames.has(killer.char_id) or not _frames.has(victim.char_id):
		return false
	_killer = killer
	_killer_id = killer.char_id
	_victim_id = victim.char_id
	_weapon = weapon
	_to = _t
	_from = maxf(_to - length, float(_frames[_killer_id][0][0]))
	if _to - _from < 0.5:
		return false
	_rec_k = (_frames[_killer_id] as Array).duplicate()
	_rec_v = (_frames[_victim_id] as Array).duplicate()
	_rec_shots = []
	for s in _shots:
		if s[1] == _killer_id and float(s[0]) >= _from:
			_rec_shots.append(s)
	_speed = speed
	_play = _from
	_hold = 0.0
	_shot_i = 0
	_then = then
	_ghost_dead = false
	_build_ghost(victim)
	_build_view(killer, weapon)
	cam.fov = float(Net.gfx.fov)
	cam.far = Net.view_distance()
	_update_camera(_from)
	cam.make_current()
	# Le vrai tueur est ailleurs maintenant : on le cache pendant le replay
	killer.visible = false
	_label.text = "KILL-CAM  ·  %s  ·  %s" % [killer.display_name, _weapon_name(weapon)]
	_label.modulate = killer.get_color().lightened(0.35)
	_layer.visible = true
	active = true
	return true


func _weapon_name(weapon: int) -> String:
	return Data.kill_name(weapon)


## Arrête le replay. finish = true appelle la suite (spectateur…).
func stop(finish := false) -> void:
	if not active:
		return
	active = false
	_layer.visible = false
	if is_instance_valid(_killer):
		_killer.visible = _killer.alive
	_killer = null
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	if _view != null:
		_view.queue_free()
		_view = null
	var me = game.local_char
	if me != null and me.camera != null:
		me.camera.make_current()
	if finish and _then.is_valid():
		_then.call()


func _build_ghost(victim) -> void:
	var parts: Array = Data.SKINS[clampi(victim.skin, 0, Data.SKINS.size() - 1)]["parts"]
	_ghost = People.build(parts, 1.8)
	add_child(_ghost)
	_ghost_tree = _ghost.get_meta("tree")
	_ghost_gun = null
	if not victim.zombie:
		var wi: int = victim.weapon
		_ghost_gun = People.hold_gun(_ghost, Data.WEAPONS[wi].model, float(Data.WEAPONS[wi].len) * 1.2)
		if _ghost_gun != null:
			Models.add_attachments(_ghost_gun, victim.custom(wi)["att"])
			Models.apply_camo(_ghost_gun, Data.CAMOS[victim.custom(wi)["skin"]])
	var f: Array = _sample(_rec_v, _from)
	_ghost.global_position = f[1]
	_ghost_prev = f[1]
	_ghost_speed = 0.0


## Arme du tueur vue à la première personne (avec ses accessoires et son skin).
func _build_view(killer, weapon: int) -> void:
	_view = null
	var wi := weapon
	if wi < 0 or wi >= Data.WEAPONS.size():
		wi = -1
		if killer._gun != null:
			wi = int(killer._gun.get_meta("weapon", -1))
	if wi < 0 or killer.zombie:
		return
	_view = Node3D.new()
	_view.position = VIEWMODEL_POS
	cam.add_child(_view)
	var g := Models.weapon(Data.WEAPONS[wi].model, Data.WEAPONS[wi].len)
	Models.add_attachments(g.get_child(0).get_child(0), killer.custom(wi)["att"])
	Models.apply_camo(g, Data.CAMOS[killer.custom(wi)["skin"]])
	Arms.add_to(g, Data.WEAPONS[wi].model)
	_view.add_child(g)


## Image enregistrée au temps t (interpolée entre deux images).
func _sample(list: Array, t: float) -> Array:
	if list.is_empty():
		return [t, Vector3.ZERO, 0.0, 0.0, 1.6, false]
	if t <= float(list[0][0]):
		return list[0]
	for i in range(1, list.size()):
		var b: Array = list[i]
		if float(b[0]) >= t:
			var a: Array = list[i - 1]
			var k := (t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001)
			return [t, (a[1] as Vector3).lerp(b[1], k), lerp_angle(float(a[2]), float(b[2]), k),
				lerpf(float(a[3]), float(b[3]), k), lerpf(float(a[4]), float(b[4]), k), b[5]]
	return list[list.size() - 1]


func _update_camera(t: float) -> void:
	var f: Array = _sample(_rec_k, t)
	var eye: Vector3 = (f[1] as Vector3) + Vector3(0, float(f[4]), 0)
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(float(f[3]), float(f[2]), 0)), eye)


func _process(delta: float) -> void:
	if not active:
		return
	# Ralenti sur la dernière demi-seconde
	var rate := _speed if _to - _play > 0.5 else _speed * 0.4
	if _play >= _to:
		_hold += delta
	_play = minf(_play + delta * rate, _to)
	var t := clampf(_play, _from, _to)
	_update_camera(t)
	_update_ghost(t, delta)
	# Tirs du tueur rejoués au bon moment
	while _shot_i < _rec_shots.size() and float(_rec_shots[_shot_i][0]) <= t:
		_replay_shot(_rec_shots[_shot_i])
		_shot_i += 1
	_kick = maxf(0.0, _kick - delta * 8.0)
	if _view != null:
		_view.position = VIEWMODEL_POS + Vector3(0, 0, _kick * 0.06)
		_view.rotation.x = _kick * 0.08
	# Fin : on reste un instant sur la mort, puis on passe à la suite
	if _hold >= 0.45:
		stop(true)


func _update_ghost(t: float, delta: float) -> void:
	if _ghost == null:
		return
	var f: Array = _sample(_rec_v, t)
	var pos: Vector3 = f[1]
	_ghost.global_position = pos
	_ghost.rotation.y = float(f[2])
	var moved := Vector2(pos.x - _ghost_prev.x, pos.z - _ghost_prev.z).length() / maxf(delta * _speed, 0.001)
	_ghost_prev = pos
	_ghost_speed = lerpf(_ghost_speed, moved, minf(1.0, delta * 10.0))
	if t >= _to - 0.02 and not _ghost_dead:
		_ghost_dead = true
		_ghost_tree.set("parameters/state/transition_request", "dead")
		return
	if _ghost_dead:
		return
	_ghost_tree.set("parameters/loco/blend_position", clampf(_ghost_speed, 0.0, 10.0))
	_ghost_tree.set("parameters/aim/blend_position", clampf(float(f[3]), -1.0, 1.0))
	if _ghost_gun != null:
		People.aim_gun(_ghost_gun, _ghost, -(Basis.from_euler(Vector3(float(f[3]), float(f[2]), 0)).z))


func _replay_shot(s: Array) -> void:
	var wi: int = s[2]
	var from: Vector3 = cam.global_position - cam.global_transform.basis.y * 0.12 + cam.global_transform.basis.x * 0.12 - cam.global_transform.basis.z * 0.5
	for e in (s[3] as PackedVector3Array):
		game._spawn_tracer(from, e)
	var silenced: bool = _killer_custom_silenced(wi)
	game.play_shot_sound(wi, from, true, silenced)
	if not silenced:
		game.sfx.muzzle_flash(from, int(Data.WEAPONS[wi].pellets) > 1)
	_kick = 1.0


func _killer_custom_silenced(wi: int) -> bool:
	var k = game.chars.get(_killer_id)
	return k != null and k.custom(wi)["att"].has("silencer")


func _unhandled_input(event: InputEvent) -> void:
	if active and (event.is_action_pressed("jump") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)):
		get_viewport().set_input_as_handled()
		stop(true)
