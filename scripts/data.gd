extends RefCounted
## Données partagées : armes, équipes, règles.

const RESPAWN_TIME := 3.0

const TEAM_NAMES := ["BLEUS", "ROUGES"]
const TEAM_COLORS := [Color(0.25, 0.5, 1.0), Color(1.0, 0.32, 0.26)]
const TEAM_HEX := ["#6f9bff", "#ff6b5e"]

# Armes. "model"/"len" : modèle 3D (Quaternius Toon Shooter) et sa longueur en vue à la première personne.
# "zoom" : champ de vision en visée (0 = pas de lunette), "splash" : rayon d'explosion, "recoil" : recul (radians).
const WEAPONS := [
	{"name": "AK-47", "cat": "ar", "model": "q/AssaultRifle_2", "sfx": "rifle", "len": 0.62, "damage": 20, "rate": 0.1, "mag": 30, "reload": 1.8, "spread": 0.7, "pellets": 1, "range": 150.0, "auto": true, "head": 1.6, "zoom": 0, "splash": 0.0, "recoil": 0.012, "sound": 0},
	{"name": "Pompe", "cat": "shotgun", "model": "q/Shotgun_1", "sfx": "shotgun", "len": 0.62, "damage": 12, "rate": 0.8, "mag": 6, "reload": 2.2, "spread": 5.5, "pellets": 9, "range": 35.0, "auto": false, "head": 1.3, "zoom": 0, "splash": 0.0, "recoil": 0.05, "sound": 1},
	{"name": "Sniper", "cat": "sniper", "model": "q/SniperRifle_3", "sfx": "sniper", "len": 0.8, "damage": 80, "rate": 1.3, "mag": 5, "reload": 2.6, "spread": 0.0, "pellets": 1, "range": 300.0, "auto": false, "head": 2.0, "zoom": 25, "splash": 0.0, "recoil": 0.09, "sound": 2},
	{"name": "Mitraillette", "cat": "smg", "model": "q/SubmachineGun_2", "sfx": "smg", "len": 0.5, "damage": 14, "rate": 0.065, "mag": 35, "reload": 1.5, "spread": 1.6, "pellets": 1, "range": 80.0, "auto": true, "head": 1.5, "zoom": 0, "splash": 0.0, "recoil": 0.008, "sound": 0},
	{"name": "Pistolet", "cat": "pistol", "model": "q/Pistol_5", "sfx": "pistol", "len": 0.32, "damage": 26, "rate": 0.18, "mag": 12, "reload": 1.2, "spread": 0.9, "pellets": 1, "range": 90.0, "auto": false, "head": 1.8, "zoom": 0, "splash": 0.0, "recoil": 0.025, "sound": 0},
	{"name": "Revolver", "cat": "revolver", "model": "q/Revolver_2", "sfx": "revolver", "len": 0.38, "damage": 48, "rate": 0.5, "mag": 6, "reload": 2.0, "spread": 0.4, "pellets": 1, "range": 120.0, "auto": false, "head": 2.0, "zoom": 0, "splash": 0.0, "recoil": 0.07, "sound": 1},
	{"name": "Fusil de précision", "cat": "dmr", "model": "q/SniperRifle_6", "sfx": "dmr", "len": 0.75, "damage": 45, "rate": 0.35, "mag": 10, "reload": 2.2, "spread": 0.2, "pellets": 1, "range": 220.0, "auto": false, "head": 1.8, "zoom": 45, "splash": 0.0, "recoil": 0.04, "sound": 2},
	{"name": "Canon court", "cat": "sawed", "model": "q/Shotgun_SawedOff", "sfx": "cannon", "len": 0.5, "damage": 10, "rate": 0.3, "mag": 2, "reload": 1.9, "spread": 8.0, "pellets": 14, "range": 20.0, "auto": false, "head": 1.2, "zoom": 0, "splash": 0.0, "recoil": 0.1, "sound": 1},
	{"name": "Lance-grenades", "cat": "gl", "model": "GrenadeLauncher", "sfx": "", "len": 0.52, "damage": 90, "rate": 0.9, "mag": 4, "reload": 2.6, "spread": 0.5, "pellets": 1, "range": 60.0, "auto": false, "head": 1.0, "zoom": 0, "splash": 4.0, "recoil": 0.06, "sound": 3},
	{"name": "Lance-roquettes", "cat": "rocket", "model": "RocketLauncher", "sfx": "", "len": 0.62, "damage": 120, "rate": 1.0, "mag": 1, "reload": 2.8, "spread": 0.0, "pellets": 1, "range": 150.0, "auto": false, "head": 1.0, "zoom": 0, "splash": 5.0, "recoil": 0.08, "sound": 3},
	{"name": "AK compact", "cat": "ar", "model": "q/AssaultRifle_1", "sfx": "rifle", "len": 0.5, "damage": 18, "rate": 0.085, "mag": 30, "reload": 1.6, "spread": 0.9, "pellets": 1, "range": 120.0, "auto": true, "head": 1.5, "zoom": 0, "splash": 0.0, "recoil": 0.011, "sound": 0},
	{"name": "AKM", "cat": "ar", "model": "q/AssaultRifle_3", "sfx": "rifle", "len": 0.64, "damage": 21, "rate": 0.105, "mag": 30, "reload": 1.9, "spread": 0.65, "pellets": 1, "range": 150.0, "auto": true, "head": 1.6, "zoom": 0, "splash": 0.0, "recoil": 0.013, "sound": 0},
	{"name": "AK crosse pliante", "cat": "ar", "model": "q/AssaultRifle_4", "sfx": "rifle", "len": 0.6, "damage": 19, "rate": 0.095, "mag": 30, "reload": 1.7, "spread": 0.75, "pellets": 1, "range": 140.0, "auto": true, "head": 1.6, "zoom": 0, "splash": 0.0, "recoil": 0.012, "sound": 0},
	{"name": "AK-74", "cat": "ar", "model": "q/AssaultRifle_5", "sfx": "rifle", "len": 0.62, "damage": 19, "rate": 0.09, "mag": 30, "reload": 1.8, "spread": 0.6, "pellets": 1, "range": 150.0, "auto": true, "head": 1.6, "zoom": 0, "splash": 0.0, "recoil": 0.011, "sound": 0},
	{"name": "M4", "cat": "ar", "model": "q/AssaultRifle2_1", "sfx": "rifle", "len": 0.62, "damage": 18, "rate": 0.085, "mag": 30, "reload": 1.7, "spread": 0.5, "pellets": 1, "range": 150.0, "auto": true, "head": 1.6, "zoom": 0, "splash": 0.0, "recoil": 0.01, "sound": 0},
	{"name": "M16", "cat": "ar", "model": "q/AssaultRifle2_2", "sfx": "rifle", "len": 0.66, "damage": 23, "rate": 0.12, "mag": 30, "reload": 1.9, "spread": 0.4, "pellets": 1, "range": 170.0, "auto": true, "head": 1.7, "zoom": 0, "splash": 0.0, "recoil": 0.013, "sound": 0},
	{"name": "M4 court", "cat": "ar", "model": "q/AssaultRifle2_3", "sfx": "rifle", "len": 0.5, "damage": 17, "rate": 0.08, "mag": 30, "reload": 1.5, "spread": 0.8, "pellets": 1, "range": 120.0, "auto": true, "head": 1.5, "zoom": 0, "splash": 0.0, "recoil": 0.01, "sound": 0},
	{"name": "M4 tactique", "cat": "ar", "model": "q/AssaultRifle2_4", "sfx": "rifle", "len": 0.6, "damage": 19, "rate": 0.09, "mag": 30, "reload": 1.7, "spread": 0.55, "pellets": 1, "range": 150.0, "auto": true, "head": 1.6, "zoom": 0, "splash": 0.0, "recoil": 0.011, "sound": 0},
	{"name": "Bullpup", "cat": "ar", "model": "q/Bullpup_1", "sfx": "rifle", "len": 0.55, "damage": 20, "rate": 0.09, "mag": 30, "reload": 2.0, "spread": 0.6, "pellets": 1, "range": 150.0, "auto": true, "head": 1.6, "zoom": 0, "splash": 0.0, "recoil": 0.011, "sound": 0},
	{"name": "Bullpup lourd", "cat": "ar", "model": "q/Bullpup_2", "sfx": "rifle", "len": 0.58, "damage": 25, "rate": 0.125, "mag": 40, "reload": 2.4, "spread": 0.7, "pellets": 1, "range": 150.0, "auto": true, "head": 1.6, "zoom": 0, "splash": 0.0, "recoil": 0.015, "sound": 0},
	{"name": "Bullpup tactique", "cat": "ar", "model": "q/Bullpup_3", "sfx": "rifle", "len": 0.56, "damage": 21, "rate": 0.095, "mag": 30, "reload": 1.9, "spread": 0.55, "pellets": 1, "range": 150.0, "auto": true, "head": 1.6, "zoom": 0, "splash": 0.0, "recoil": 0.012, "sound": 0},
	{"name": "Mitraillette lourde", "cat": "smg", "model": "q/SubmachineGun_1", "sfx": "smg", "len": 0.48, "damage": 16, "rate": 0.075, "mag": 30, "reload": 1.6, "spread": 1.5, "pellets": 1, "range": 80.0, "auto": true, "head": 1.5, "zoom": 0, "splash": 0.0, "recoil": 0.009, "sound": 0},
	{"name": "Mini-mitraillette", "cat": "smg", "model": "q/SubmachineGun_3", "sfx": "smg", "len": 0.42, "damage": 13, "rate": 0.055, "mag": 32, "reload": 1.4, "spread": 2.0, "pellets": 1, "range": 70.0, "auto": true, "head": 1.4, "zoom": 0, "splash": 0.0, "recoil": 0.007, "sound": 0},
	{"name": "Mitraillette compacte", "cat": "smg", "model": "q/SubmachineGun_4", "sfx": "smg", "len": 0.42, "damage": 15, "rate": 0.065, "mag": 30, "reload": 1.5, "spread": 1.7, "pellets": 1, "range": 75.0, "auto": true, "head": 1.5, "zoom": 0, "splash": 0.0, "recoil": 0.008, "sound": 0},
	{"name": "Mitraillette tactique", "cat": "smg", "model": "q/SubmachineGun_5", "sfx": "smg", "len": 0.52, "damage": 14, "rate": 0.06, "mag": 35, "reload": 1.6, "spread": 1.3, "pellets": 1, "range": 85.0, "auto": true, "head": 1.5, "zoom": 0, "splash": 0.0, "recoil": 0.008, "sound": 0},
	{"name": "Pistolet noir", "cat": "pistol", "model": "q/Pistol_1", "sfx": "pistol", "len": 0.32, "damage": 28, "rate": 0.2, "mag": 10, "reload": 1.2, "spread": 0.85, "pellets": 1, "range": 90.0, "auto": false, "head": 1.8, "zoom": 0, "splash": 0.0, "recoil": 0.026, "sound": 0},
	{"name": "Pistolet classique", "cat": "pistol", "model": "q/Pistol_2", "sfx": "pistol", "len": 0.32, "damage": 25, "rate": 0.17, "mag": 12, "reload": 1.1, "spread": 0.9, "pellets": 1, "range": 90.0, "auto": false, "head": 1.8, "zoom": 0, "splash": 0.0, "recoil": 0.024, "sound": 0},
	{"name": "Pistolet lourd", "cat": "pistol", "model": "q/Pistol_3", "sfx": "pistol", "len": 0.34, "damage": 36, "rate": 0.3, "mag": 8, "reload": 1.4, "spread": 0.7, "pellets": 1, "range": 100.0, "auto": false, "head": 1.9, "zoom": 0, "splash": 0.0, "recoil": 0.04, "sound": 1},
	{"name": "Pistolet automatique", "cat": "pistol", "model": "q/Pistol_4", "sfx": "pistol", "len": 0.34, "damage": 17, "rate": 0.07, "mag": 20, "reload": 1.4, "spread": 1.7, "pellets": 1, "range": 70.0, "auto": true, "head": 1.5, "zoom": 0, "splash": 0.0, "recoil": 0.012, "sound": 0},
	{"name": "Pistolet tactique", "cat": "pistol", "model": "q/Pistol_6", "sfx": "pistol", "len": 0.38, "damage": 27, "rate": 0.18, "mag": 15, "reload": 1.2, "spread": 0.8, "pellets": 1, "range": 95.0, "auto": false, "head": 1.8, "zoom": 0, "splash": 0.0, "recoil": 0.025, "sound": 0},
	{"name": "Revolver de poche", "cat": "revolver", "model": "q/Revolver_1", "sfx": "revolver", "len": 0.3, "damage": 40, "rate": 0.4, "mag": 6, "reload": 1.8, "spread": 0.7, "pellets": 1, "range": 90.0, "auto": false, "head": 1.9, "zoom": 0, "splash": 0.0, "recoil": 0.06, "sound": 1},
	{"name": "Revolver tactique", "cat": "revolver", "model": "q/Revolver_3", "sfx": "revolver", "len": 0.38, "damage": 50, "rate": 0.5, "mag": 6, "reload": 2.0, "spread": 0.4, "pellets": 1, "range": 120.0, "auto": false, "head": 2.0, "zoom": 0, "splash": 0.0, "recoil": 0.07, "sound": 1},
	{"name": "Magnum", "cat": "revolver", "model": "q/Revolver_4", "sfx": "revolver", "len": 0.4, "damage": 62, "rate": 0.7, "mag": 6, "reload": 2.3, "spread": 0.45, "pellets": 1, "range": 130.0, "auto": false, "head": 2.0, "zoom": 0, "splash": 0.0, "recoil": 0.09, "sound": 1},
	{"name": "Revolver ancien", "cat": "revolver", "model": "q/Revolver_5", "sfx": "revolver", "len": 0.38, "damage": 45, "rate": 0.45, "mag": 6, "reload": 2.1, "spread": 0.5, "pellets": 1, "range": 110.0, "auto": false, "head": 2.0, "zoom": 0, "splash": 0.0, "recoil": 0.07, "sound": 1},
	{"name": "Pompe longue", "cat": "shotgun", "model": "q/Shotgun_2", "sfx": "shotgun", "len": 0.72, "damage": 12, "rate": 0.8, "mag": 7, "reload": 2.3, "spread": 4.5, "pellets": 9, "range": 45.0, "auto": false, "head": 1.3, "zoom": 0, "splash": 0.0, "recoil": 0.05, "sound": 1},
	{"name": "Pompe de chasse", "cat": "shotgun", "model": "q/Shotgun_3", "sfx": "shotgun", "len": 0.72, "damage": 14, "rate": 0.9, "mag": 6, "reload": 2.3, "spread": 5.0, "pellets": 8, "range": 40.0, "auto": false, "head": 1.3, "zoom": 0, "splash": 0.0, "recoil": 0.05, "sound": 1},
	{"name": "Fusil de chasse (balle)", "cat": "shotgun", "model": "q/Shotgun_4", "sfx": "shotgun", "len": 0.72, "damage": 70, "rate": 0.95, "mag": 5, "reload": 2.4, "spread": 0.35, "pellets": 1, "range": 90.0, "auto": false, "head": 1.6, "zoom": 0, "splash": 0.0, "recoil": 0.07, "sound": 1},
	{"name": "Pompe crosse courte", "cat": "shotgun", "model": "q/Shotgun_ShortStock", "sfx": "shotgun", "len": 0.58, "damage": 11, "rate": 0.7, "mag": 5, "reload": 2.0, "spread": 6.5, "pellets": 10, "range": 30.0, "auto": false, "head": 1.3, "zoom": 0, "splash": 0.0, "recoil": 0.05, "sound": 1},
	{"name": "Sniper de chasse", "cat": "sniper", "model": "q/SniperRifle_1", "sfx": "sniper", "len": 0.8, "damage": 75, "rate": 1.1, "mag": 5, "reload": 2.4, "spread": 0.0, "pellets": 1, "range": 300.0, "auto": false, "head": 2.0, "zoom": 25, "splash": 0.0, "recoil": 0.085, "sound": 2},
	{"name": "Fusil semi-automatique", "cat": "dmr", "model": "q/SniperRifle_2", "sfx": "dmr", "len": 0.78, "damage": 50, "rate": 0.42, "mag": 8, "reload": 2.3, "spread": 0.25, "pellets": 1, "range": 230.0, "auto": false, "head": 1.8, "zoom": 45, "splash": 0.0, "recoil": 0.045, "sound": 2},
	{"name": "Sniper tactique", "cat": "sniper", "model": "q/SniperRifle_4", "sfx": "sniper", "len": 0.8, "damage": 85, "rate": 1.3, "mag": 5, "reload": 2.6, "spread": 0.0, "pellets": 1, "range": 300.0, "auto": false, "head": 2.0, "zoom": 25, "splash": 0.0, "recoil": 0.09, "sound": 2},
	{"name": "Sniper à bipied", "cat": "sniper", "model": "q/SniperRifle_5", "sfx": "sniper", "len": 0.82, "damage": 92, "rate": 1.45, "mag": 5, "reload": 2.8, "spread": 0.0, "pellets": 1, "range": 320.0, "auto": false, "head": 2.0, "zoom": 22, "splash": 0.0, "recoil": 0.095, "sound": 2},
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
	{"name": "Arctique", "level": 3, "color": Color(1, 1, 1), "add": false, "pattern": "arctic"},
	{"name": "Digital", "level": 5, "color": Color(1, 1, 1), "add": false, "pattern": "digital"},
	{"name": "Bois", "level": 7, "color": Color(1, 1, 1), "add": false, "pattern": "woodland"},
	{"name": "Tigre", "level": 9, "color": Color(1, 1, 1), "add": false, "pattern": "tiger"},
	{"name": "Carbone", "level": 11, "color": Color(1, 1, 1), "add": false, "pattern": "carbon"},
	{"name": "Lave", "level": 13, "color": Color(1, 1, 1), "add": false, "pattern": "lava"},
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

# Accessoires d'armes (armurerie). Les lance-grenades / roquettes n'en ont pas.
const ATTACHMENTS := [
	{"id": "silencer", "name": "Silencieux", "desc": "Tir discret : son faible, pas de flash · dégâts -10 %"},
	{"id": "mag", "name": "Chargeur étendu", "desc": "+50 % de munitions · rechargement +15 %"},
	{"id": "grip", "name": "Poignée", "desc": "Recul -35 % · dispersion -20 %"},
	{"id": "optic", "name": "Viseur point rouge", "desc": "Visée précise au clic droit (zoom léger) · dispersion -25 % en visée"},
]


## Accessoires possibles pour une arme.
static func attachments_for(wi: int) -> Array:
	var w: Dictionary = WEAPONS[wi]
	if float(w.splash) > 0.0:
		return []
	var out := []
	for a in ATTACHMENTS:
		if a["id"] == "optic" and int(w.zoom) > 0:
			continue  # déjà une lunette
		out.append(a["id"])
	return out


## Caractéristiques d'une arme avec ses accessoires. « custom » : {"skin": int, "att": [ids]}.
static func weapon_stats(wi: int, custom: Dictionary) -> Dictionary:
	var w: Dictionary = WEAPONS[wi].duplicate()
	var att: Array = custom.get("att", [])
	if att.has("silencer"):
		w["damage"] = int(round(float(w.damage) * 0.9))
	if att.has("mag"):
		w["mag"] = int(ceil(float(w.mag) * 1.5))
		w["reload"] = float(w.reload) * 1.15
	if att.has("grip"):
		w["recoil"] = float(w.recoil) * 0.65
		w["spread"] = float(w.spread) * 0.8
	if att.has("optic"):
		w["zoom"] = 55
		w["optic"] = true
	return w

# Familles d'armes : dans l'armurerie, on choisit l'arme utilisée pour chaque famille.
const CATS := {
	"ar": "Fusils d'assaut", "smg": "Mitraillettes", "pistol": "Pistolets", "revolver": "Revolvers",
	"shotgun": "Fusils à pompe", "sawed": "Canons courts", "sniper": "Snipers", "dmr": "Fusils de précision",
	"gl": "Lance-grenades", "rocket": "Lance-roquettes",
}
const CAT_ORDER := ["ar", "smg", "pistol", "revolver", "shotgun", "sawed", "sniper", "dmr", "gl", "rocket"]


## Arme réellement utilisée à la place de l'arme « wi » d'une classe : le choix du joueur pour cette famille.
static func resolve_weapon(wi: int, armory: Dictionary) -> int:
	var picks = armory.get("pick", {})
	if not (picks is Dictionary):
		return wi
	var cat: String = WEAPONS[wi].cat
	var p := int(picks.get(cat, wi))
	if p >= 0 and p < WEAPONS.size() and WEAPONS[p].cat == cat:
		return p
	return wi
