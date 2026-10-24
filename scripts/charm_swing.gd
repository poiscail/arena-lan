extends Node3D
## Breloque qui pend sous son point d'accroche : un petit pendule (pesanteur + amortissement)
## qui se balance quand l'arme bouge, tourne ou recule.

const GRAVITY := 9.8
const DAMPING := 2.2

var length := 0.05  # longueur du pendule, dans le repère du parent
var _tip := Vector3.ZERO
var _vel := Vector3.ZERO
var _ready_tip := false


func _process(delta: float) -> void:
	if not is_visible_in_tree() or delta <= 0.0:
		_ready_tip = false
		return
	var parent := get_parent() as Node3D
	var scale_g := parent.global_basis.get_scale()
	var L := length * scale_g.y
	var pivot := global_position
	if not _ready_tip or _tip.distance_to(pivot) > L * 3.0 + 0.5:
		_tip = pivot + Vector3.DOWN * L  # premier affichage ou téléportation : pend droit
		_vel = Vector3.ZERO
		_ready_tip = true
	delta = minf(delta, 0.05)
	_vel += Vector3.DOWN * GRAVITY * delta
	_vel *= exp(-DAMPING * delta)
	var next := _tip + _vel * delta
	var d := next - pivot
	if d.length() < 0.0001:
		d = Vector3.DOWN
	next = pivot + d.normalized() * L
	_vel = (next - _tip) / delta
	_tip = next
	# Oriente la breloque vers son poids, en gardant le côté tourné comme l'arme
	var up := (pivot - _tip).normalized()
	var ref := parent.global_basis.z.normalized()
	var x := up.cross(ref)
	if x.length() < 0.01:
		x = parent.global_basis.x.normalized()
	x = x.normalized()
	var z := x.cross(up).normalized()
	global_basis = Basis(x * scale_g.x, up * scale_g.y, z * scale_g.z)
