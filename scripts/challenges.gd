extends RefCounted
## Défis du jour : 3 défis tirés au sort chaque jour (les mêmes pour tout le monde ce jour-là),
## suivis sur ce PC (Net.daily) et récompensés en expérience dès qu'ils sont accomplis.

const Data := preload("res://scripts/data.gd")

# kind : événement compté (voir add) ; goals : objectifs possibles ; text : %d = objectif
const POOL := [
	{"kind": "kills", "goals": [15, 25], "xp": 150, "text": "Fais %d éliminations"},
	{"kind": "head", "goals": [5, 10], "xp": 200, "text": "Élimine %d ennemis d'un tir à la tête"},
	{"kind": "cat:ar", "goals": [8, 12], "xp": 150, "text": "Fais %d éliminations au fusil d'assaut"},
	{"kind": "cat:smg", "goals": [8, 12], "xp": 150, "text": "Fais %d éliminations à la mitraillette"},
	{"kind": "cat:pistol", "goals": [5, 8], "xp": 200, "text": "Fais %d éliminations au pistolet"},
	{"kind": "cat:shotgun", "goals": [6, 10], "xp": 150, "text": "Fais %d éliminations au fusil à pompe"},
	{"kind": "cat:sniper", "goals": [5, 8], "xp": 200, "text": "Fais %d éliminations au sniper"},
	{"kind": "knife", "goals": [3, 5], "xp": 200, "text": "Élimine %d ennemis au couteau"},
	{"kind": "grenade", "goals": [3], "xp": 200, "text": "Élimine %d ennemis à la grenade"},
	{"kind": "multi", "goals": [2, 3], "xp": 250, "text": "Fais %d doubles éliminations (ou mieux)"},
	{"kind": "long", "goals": [3, 5], "xp": 200, "text": "Fais %d éliminations à longue distance"},
	{"kind": "revenge", "goals": [3], "xp": 150, "text": "Prends %d revanches"},
	{"kind": "medals", "goals": [15, 25], "xp": 150, "text": "Gagne %d médailles"},
	{"kind": "matches", "goals": [3], "xp": 150, "text": "Termine %d matchs"},
	{"kind": "wins", "goals": [2], "xp": 250, "text": "Gagne %d matchs"},
]
const PER_DAY := 3


static func _today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


## Défis du jour : [{"kind", "goal", "xp", "text", "prog"}]. Nouveau tirage quand la date change.
static func today() -> Array:
	var day := _today()
	if String(Net.daily.get("date", "")) != day or not (Net.daily.get("list") is Array):
		var rng := RandomNumberGenerator.new()
		rng.seed = day.hash()
		var picks := []
		var order := range(POOL.size())
		for i in range(order.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = order[i]
			order[i] = order[j]
			order[j] = tmp
		for i in PER_DAY:
			var p: Dictionary = POOL[order[i]]
			var goals: Array = p["goals"]
			var goal: int = goals[rng.randi_range(0, goals.size() - 1)]
			picks.append({"kind": p["kind"], "goal": goal, "xp": p["xp"], "text": p["text"] % goal, "prog": 0})
		Net.daily = {"date": day, "list": picks}
		Net.save_options()
	return Net.daily["list"]


## Compte n événements « kind » ; renvoie les défis accomplis à l'instant (leur XP est déjà ajoutée).
static func add(kind: String, n := 1) -> Array:
	var done := []
	for ch in today():
		if ch["kind"] != kind or int(ch["prog"]) >= int(ch["goal"]):
			continue
		ch["prog"] = mini(int(ch["prog"]) + n, int(ch["goal"]))
		if int(ch["prog"]) >= int(ch["goal"]):
			Net.xp += int(ch["xp"])
			done.append(ch)
	Net.save_options()
	return done


## Texte BBCode des défis (menu principal, fin de match).
static func bbcode() -> String:
	var lines := []
	for ch in today():
		var p := int(ch["prog"])
		var g := int(ch["goal"])
		if p >= g:
			lines.append("[color=#7fe08a]FAIT · %s[/color]  [color=#8890a0]+%d XP[/color]" % [ch["text"], int(ch["xp"])])
		else:
			lines.append("%s  [color=#ffcc55]%d / %d[/color]  [color=#8890a0]+%d XP[/color]" % [ch["text"], p, g, int(ch["xp"])])
	return "\n".join(lines)
