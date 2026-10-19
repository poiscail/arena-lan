extends SceneTree
## Outil de test : gros plan de profil d'un personnage armé, sauvegarde une capture.
## godot --path . --script res://tools_view.gd -- <sortie.png> [rx ry rz px py pz echelle]

const People := preload("res://scripts/people.gd")

var _frames := 0
var _out := ""
var _c: Node3D
var _args: PackedStringArray


func _initialize() -> void:
	_args = OS.get_cmdline_user_args()
	_out = _args[0]
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.55, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	world.add_child(sun)
	_c = People.build(["Superhero_Male_FullBody"], 1.8)
	world.add_child(_c)
	People.hold_gun(_c, "AK")
	var cam := Camera3D.new()
	cam.fov = 35
	world.add_child(cam)
	# Le personnage regarde vers -Z : on le filme de côté (depuis +X)
	cam.look_at_from_position(Vector3(2.6, 1.45, -0.3), Vector3(0, 1.3, -0.3))
	cam.make_current()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3 and _args.size() >= 8:
		var holder: Node3D = _c.get_meta("hand").get_child(0)
		holder.rotation_degrees = Vector3(float(_args[1]), float(_args[2]), float(_args[3]))
		holder.position = Vector3(float(_args[4]), float(_args[5]), float(_args[6]))
		holder.scale = Vector3.ONE * float(_args[7])
	if _frames == 30:
		var gun: Node3D = _c.get_meta("hand").get_child(0).get_child(0)
		print("gun world scale: ", gun.global_transform.basis.get_scale(), " hand scale: ", _c.get_meta("hand").global_transform.basis.get_scale())
		root.get_texture().get_image().save_png(_out)
		return true
	return false
