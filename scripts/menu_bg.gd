extends Node3D
## Fond animé du menu : l'arène filmée par une caméra qui tourne lentement, avec quelques personnages.

const MapScript := preload("res://scripts/map.gd")
const Models := preload("res://scripts/models.gd")
const Data := preload("res://scripts/data.gd")

# [position, modèle, animation, arme]
const CAST := [
	[Vector3(-2.2, 3.5, 0.6), "character-g", "holding-both", 0],
	[Vector3(1.6, 3.5, -1.2), "character-h", "idle", 2],
	[Vector3(-7.0, 0, 9.0), "character-h", "holding-both", 1],
	[Vector3(5.5, 0, 8.0), "character-g", "emote-yes", -1],
	[Vector3(8.0, 0, -7.5), "character-j", "holding-both", 0],
	[Vector3(-9.0, 0, -6.0), "character-o", "idle", -1],
]

var _cam: Camera3D
var _t := 0.0


func _ready() -> void:
	MapScript.new().build(self, false)
	for c in CAST:
		var m := Models.character(c[1], 1.8)
		add_child(m)
		m.position = c[0]
		m.rotation.y = atan2(c[0].x, c[0].z) + randf_range(-0.4, 0.4)
		var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
		if ap != null and ap.has_animation(c[2]):
			ap.get_animation(c[2]).loop_mode = Animation.LOOP_LINEAR
			ap.play(c[2])
			ap.seek(randf() * 1.0, true)
		if c[3] >= 0:
			var g := Models.weapon(Data.WEAPON_MODELS[c[3]][0], 0.6)
			g.position = Vector3(0.22, 1.1, -0.45)
			m.add_child(g)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	_cam.make_current()
	_t = randf() * TAU


func _process(delta: float) -> void:
	_t += delta * 0.05
	_cam.position = Vector3(cos(_t) * 17.0, 6.5 + sin(_t * 2.0) * 0.8, sin(_t) * 17.0)
	_cam.look_at(Vector3(0, 2.2, 0))
