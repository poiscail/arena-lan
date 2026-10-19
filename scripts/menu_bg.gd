extends Node3D
## Fond animé du menu : le skin choisi présenté sur la carte, avec quelques personnages derrière.

const MapScript := preload("res://scripts/map.gd")
const People := preload("res://scripts/people.gd")
const Data := preload("res://scripts/data.gd")

const SHOWCASE_POS := Vector3(0, 0, 16)
# Figurants : [skin, position, angle (degrés), vitesse des jambes, visée (-1..1), arme]
const EXTRAS := [
	[2, Vector3(-3.2, 0, 13.6), 30.0, 0.0, -0.6, "Shotgun"],
	[1, Vector3(3.6, 0, 13.2), -20.0, 0.0, 0.3, "Sniper"],
	[3, Vector3(6.5, 0, 9.0), 120.0, 0.0, 0.0, "AK"],
]

var _cam: Camera3D
var _showcase: Node3D
var _t := 0.0


func _ready() -> void:
	MapScript.new().build(self, false)
	for e in EXTRAS:
		var c := People.build(Data.SKINS[e[0]]["parts"], 1.8)
		add_child(c)
		c.position = e[1]
		c.rotation_degrees.y = e[2]
		People.hold_gun(c, e[5])
		var tree: AnimationTree = c.get_meta("tree")
		tree.set("parameters/loco/blend_position", e[3])
		tree.set("parameters/aim/blend_position", e[4])
	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)
	_cam.make_current()
	show_skin(Net.player_skin)


## Affiche (ou remplace) le personnage présenté au premier plan.
func show_skin(index: int) -> void:
	if _showcase != null:
		_showcase.queue_free()
	_showcase = People.build(Data.SKINS[clampi(index, 0, Data.SKINS.size() - 1)]["parts"], 1.8)
	add_child(_showcase)
	_showcase.position = SHOWCASE_POS
	People.hold_gun(_showcase, "AK")


func _process(delta: float) -> void:
	_t += delta
	# Le personnage tourne lentement sur lui-même ; la caméra le cadre à droite de l'écran (le menu est à gauche)
	_showcase.rotation.y = 0.6 + sin(_t * 0.35) * 0.9
	var cam_pos := SHOWCASE_POS + Vector3(-1.9 + sin(_t * 0.2) * 0.2, 1.45, 4.6)
	_cam.look_at_from_position(cam_pos, SHOWCASE_POS + Vector3(-1.35, 1.05, 0))
