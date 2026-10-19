extends RefCounted
## Données partagées : armes, équipes, règles.

const RESPAWN_TIME := 3.0

const TEAM_NAMES := ["BLEUS", "ROUGES"]
const TEAM_COLORS := [Color(0.25, 0.5, 1.0), Color(1.0, 0.32, 0.26)]
const TEAM_HEX := ["#6f9bff", "#ff6b5e"]

# Armes. "model"/"len" : modèle 3D (Quaternius Toon Shooter) et sa longueur en vue à la première personne.
# "zoom" : champ de vision en visée (0 = pas de lunette), "splash" : rayon d'explosion, "recoil" : recul (radians).
const WEAPONS := [
	{"name": "Fusil d'assaut", "model": "AK", "sfx": "rifle", "len": 0.62, "damage": 20, "rate": 0.1, "mag": 30, "reload": 1.8, "spread": 0.7, "pellets": 1, "range": 150.0, "auto": true, "head": 1.6, "zoom": 0, "splash": 0.0, "recoil": 0.012, "sound": 0},
	{"name": "Pompe", "model": "Shotgun", "sfx": "shotgun", "len": 0.62, "damage": 12, "rate": 0.8, "mag": 6, "reload": 2.2, "spread": 5.5, "pellets": 9, "range": 35.0, "auto": false, "head": 1.3, "zoom": 0, "splash": 0.0, "recoil": 0.05, "sound": 1},
	{"name": "Sniper", "model": "Sniper", "sfx": "sniper", "len": 0.8, "damage": 80, "rate": 1.3, "mag": 5, "reload": 2.6, "spread": 0.0, "pellets": 1, "range": 300.0, "auto": false, "head": 2.0, "zoom": 25, "splash": 0.0, "recoil": 0.09, "sound": 2},
	{"name": "Mitraillette", "model": "SMG", "sfx": "smg", "len": 0.5, "damage": 14, "rate": 0.065, "mag": 35, "reload": 1.5, "spread": 1.6, "pellets": 1, "range": 80.0, "auto": true, "head": 1.5, "zoom": 0, "splash": 0.0, "recoil": 0.008, "sound": 0},
	{"name": "Pistolet", "model": "Pistol", "sfx": "pistol", "len": 0.32, "damage": 26, "rate": 0.18, "mag": 12, "reload": 1.2, "spread": 0.9, "pellets": 1, "range": 90.0, "auto": false, "head": 1.8, "zoom": 0, "splash": 0.0, "recoil": 0.025, "sound": 0},
	{"name": "Revolver", "model": "Revolver", "sfx": "revolver", "len": 0.38, "damage": 48, "rate": 0.5, "mag": 6, "reload": 2.0, "spread": 0.4, "pellets": 1, "range": 120.0, "auto": false, "head": 2.0, "zoom": 0, "splash": 0.0, "recoil": 0.07, "sound": 1},
	{"name": "Fusil de précision", "model": "Sniper_2", "sfx": "dmr", "len": 0.75, "damage": 45, "rate": 0.35, "mag": 10, "reload": 2.2, "spread": 0.2, "pellets": 1, "range": 220.0, "auto": false, "head": 1.8, "zoom": 45, "splash": 0.0, "recoil": 0.04, "sound": 2},
	{"name": "Canon court", "model": "ShortCannon", "sfx": "cannon", "len": 0.5, "damage": 10, "rate": 0.3, "mag": 2, "reload": 1.9, "spread": 8.0, "pellets": 14, "range": 20.0, "auto": false, "head": 1.2, "zoom": 0, "splash": 0.0, "recoil": 0.1, "sound": 1},
	{"name": "Lance-grenades", "model": "GrenadeLauncher", "sfx": "", "len": 0.52, "damage": 90, "rate": 0.9, "mag": 4, "reload": 2.6, "spread": 0.5, "pellets": 1, "range": 60.0, "auto": false, "head": 1.0, "zoom": 0, "splash": 4.0, "recoil": 0.06, "sound": 3},
	{"name": "Lance-roquettes", "model": "RocketLauncher", "sfx": "", "len": 0.62, "damage": 120, "rate": 1.0, "mag": 1, "reload": 2.8, "spread": 0.0, "pellets": 1, "range": 150.0, "auto": false, "head": 1.0, "zoom": 0, "splash": 5.0, "recoil": 0.08, "sound": 3},
]

# Classes : 3 armes chacune (touches 1, 2, 3) et un bonus de vitesse
const CLASSES := [
	{"name": "Assaut", "weapons": [0, 4, 8], "speed": 1.0, "desc": "Fusil d'assaut, pistolet, lance-grenades"},
	{"name": "Commando", "weapons": [3, 7, 5], "speed": 1.1, "desc": "Mitraillette, canon court, revolver · plus rapide"},
	{"name": "Tireur d'élite", "weapons": [2, 6, 4], "speed": 1.0, "desc": "Sniper, fusil de précision, pistolet"},
	{"name": "Lourd", "weapons": [1, 9, 5], "speed": 0.9, "desc": "Pompe, lance-roquettes, revolver · plus lent"},
	{"name": "Classique", "weapons": [0, 1, 2], "speed": 1.0, "desc": "Fusil d'assaut, pompe, sniper"},
]


# Skins (Quaternius Universal Base Characters + tenues), animés par la Universal Animation Library
const SKINS := [
	{"name": "Rôdeur", "parts": ["Superhero_Male_FullBody", "Male_Ranger"]},
	{"name": "Rôdeuse", "parts": ["Superhero_Female_FullBody", "Female_Ranger"]},
	{"name": "Agent", "parts": ["Superhero_Male_FullBody"]},
	{"name": "Agente", "parts": ["Superhero_Female_FullBody"]},
]



static func esc(text: String) -> String:
	return text.replace("[", "[lb]")

# Cartes disponibles (index utilisé dans les paramètres de partie)
const MAPS := ["Base militaire", "Ville", "Entrepôt", "Base militaire (nuit)", "Ville (nuit)"]

# Autres causes d'élimination (en plus des armes)
const KILL_GRENADE := 100
const KILL_KNIFE := 101
const KILL_BARREL := 102
const KILL_AIRSTRIKE := 103
const KILL_NAMES := {100: "Grenade", 101: "Couteau", 102: "Baril", 103: "Frappe aérienne"}

# Grenades : [explosives, fumigènes] au début de chaque vie
const GRENADES_START := [2, 1]
const GRENADE := {"damage": 100, "splash": 5.0}
const BARREL := {"damage": 110, "splash": 5.5}
const AIRSTRIKE := {"damage": 75, "splash": 4.0}
const KNIFE_DAMAGE := 55
const KNIFE_RANGE := 2.2

# Bonus ramassables : [nom affiché, couleur, délai de réapparition (s)]
const PICKUPS := {
	"health": ["+50 PV", Color(0.35, 1.0, 0.5), 20.0],
	"armor": ["+50 ARMURE", Color(0.35, 0.65, 1.0), 30.0],
	"ammo": ["MUNITIONS", Color(1.0, 0.8, 0.3), 15.0],
	"damage": ["DÉGÂTS x2", Color(1.0, 0.3, 0.9), 45.0],
}
const DAMAGE_BOOST_TIME := 15.0

# Séries d'éliminations sans mourir
const STREAKS := {3: "ADRÉNALINE", 5: "RADAR", 7: "FRAPPE AÉRIENNE"}
const ADRENALINE_TIME := 20.0
const RADAR_TIME := 12.0


static func kill_name(i: int) -> String:
	if KILL_NAMES.has(i):
		return KILL_NAMES[i]
	return String(WEAPONS[clampi(i, 0, WEAPONS.size() - 1)].name)

# Modes de jeu (règles). "teams" : uniquement en équipes. "limit" : 0 = score réglé dans le salon.
const RULES := {
	"dm": {"name": "Match à mort", "unit": "éliminations", "limit": 0, "teams": false,
		"desc": "Le plus d'éliminations gagne."},
	"ctf": {"name": "Capture du drapeau", "unit": "captures", "limit": 3, "teams": true,
		"desc": "Rapporte le drapeau ennemi à ta base pendant que le tien y est."},
	"koth": {"name": "Roi de la colline", "unit": "points", "limit": 100, "teams": false,
		"desc": "Reste seul dans la zone du centre : 1 point par seconde."},
	"gungame": {"name": "Course aux armes", "unit": "niveaux", "limit": 10, "teams": false,
		"desc": "Chaque élimination donne l'arme suivante. Le couteau fait reculer la victime."},
	"elim": {"name": "Élimination", "unit": "manches", "limit": 5, "teams": true,
		"desc": "Une vie par manche. La dernière équipe debout gagne la manche."},
}
const RULE_ORDER := ["dm", "ctf", "koth", "gungame", "elim"]
# Course aux armes : ordre des armes (indices dans WEAPONS)
const GUNGAME_LADDER := [0, 3, 1, 6, 2, 7, 5, 8, 9, 4]

# Camouflages d'armes, débloqués en montant de niveau. "add" : couleur lumineuse ajoutée (néon).
const CAMOS := [
	{"name": "Standard", "level": 1, "color": Color(1, 1, 1), "add": false},
	{"name": "Désert", "level": 2, "color": Color(0.95, 0.8, 0.55), "add": false},
	{"name": "Forêt", "level": 3, "color": Color(0.55, 0.75, 0.45), "add": false},
	{"name": "Urbain", "level": 4, "color": Color(0.72, 0.74, 0.8), "add": false},
	{"name": "Nuit", "level": 6, "color": Color(0.35, 0.38, 0.52), "add": false},
	{"name": "Rouge", "level": 8, "color": Color(0.95, 0.42, 0.36), "add": false},
	{"name": "Or", "level": 10, "color": Color(1.0, 0.8, 0.32), "add": false},
	{"name": "Néon", "level": 15, "color": Color(0.05, 0.45, 0.6), "add": true},
]


## Niveau du joueur à partir de son expérience : [niveau, XP dans le niveau, XP pour le suivant].
static func level_info(xp: int) -> Array:
	var lvl := 1
	var need := 150
	while xp >= need:
		xp -= need
		lvl += 1
		need = 150 + 50 * (lvl - 1)
	return [lvl, xp, need]
