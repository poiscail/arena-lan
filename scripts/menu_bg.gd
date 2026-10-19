extends Node3D
## Fond animé du menu : l'arène filmée par une caméra qui tourne lentement, avec quelques soldats.

const MapScript := preload("res://scripts/map.gd")
const Models := preload("res://scripts/models.gd")

# [position, modèle, animation, arme ("" = aucune)]
const CAST := [
	[Vector3(-3.2, 0, 2.6), "Character_Soldier", "Idle_Shoot", "AK"],
	[Vector3(3.0, 0, -3.0), "Character_Enemy", "Idle_Shoot", "Sniper"],
	[Vector3(-7.0, 0, 8.0), "Character_Hazmat", "Idle_Shoot", "Shotgun"],
	[Vector3(4.0, 0, 7.5), "Character_Soldier", "Wave", ""],
	[Vector3(8.0, 0, -7.5), "Character_Enemy", "Idle", "SMG"],
	[Vector3(-9.0, 0, -4.0), "Character_Hazmat", "Yes", ""],
]

var _cam: Camera3D
var _t := 0.0
var _closeup := false


func _ready() -> void:
	MapScript.new().build(self, false)
	for c in CAST:
		var m := Models.character(c[1], 1.85)
		add_child(m)
		m.position = c[0]
		m.rotation.y = atan2(c[0].x, c[0].z) + randf_range(-0.4, 0.4)
		var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
		if ap != null and ap.has_animation(c[2]):
			ap.get_animation(c[2]).loop_mode = Animation.LOOP_LINEAR
			ap.play(c[2])
			ap.seek(randf(), true)
		if c[3] != "":
			Models.attach_weapon(m, c[3])
	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	_cam.make_current()
	_t = randf() * TAU
	_closeup = "--closeup" in OS.get_cmdline_user_args()


func _process(delta: float) -> void:
	if _closeup:
		# Vue rapprochée (vérification des modèles) : soldat posé près de la tour
		var target: Vector3 = CAST[2][0] + Vector3(0, 1.1, 0)
		_cam.position = target + Vector3(2.2, 0.6, 3.2)
		_cam.look_at(target)
		return
	_t += delta * 0.05
	_cam.position = Vector3(cos(_t) * 17.0, 6.5 + sin(_t * 2.0) * 0.8, sin(_t) * 17.0)
	_cam.look_at(Vector3(0, 2.2, 0))
