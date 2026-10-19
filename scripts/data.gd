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
const MAPS := ["Base militaire", "Ville", "Entrepôt", "Base militaire (nuit)", "Ville (nuit)", "Forêt", "Port industriel"]

# Autres causes d'élimination (en plus des armes)
const KILL_GRENADE := 100
const KILL_KNIFE := 101
const KILL_BARREL := 102
const KILL_AIRSTRIKE := 103
const KILL_BOMB := 104
const KILL_ZOMBIE := 105
const KILL_ZONE := 106
# Postes d'achat du mode Zombies
const ZOMBIE_SHOP := [
	{"name": "Munitions", "kind": "ammo", "price": 400},
	{"name": "Mitraillette", "kind": "weapon", "wi": 3, "price": 900},
	{"name": "Pompe", "kind": "weapon", "wi": 1, "price": 1200},
	{"name": "AK-47", "kind": "weapon", "wi": 0, "price": 1500},
	{"name": "Armure", "kind": "armor", "price": 750},
	{"name": "Fusil de précision", "kind": "weapon", "wi": 6, "price": 1800},
	{"name": "Lance-roquettes", "kind": "weapon", "wi": 9, "price": 4000},
]
const KILL_NAMES := {100: "Grenade", 101: "Couteau", 102: "Baril", 103: "Frappe aérienne", 104: "Bombe", 105: "Zombie", 106: "Zone"}

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
	"snd": {"name": "Recherche et destruction", "unit": "manches", "limit": 4, "teams": true,
		"desc": "Une vie par manche. L'attaque pose la bombe sur A ou B (touche F), la défense la désamorce. Changement de camp toutes les 2 manches."},
	"zombies": {"name": "Zombies (coopération)", "unit": "vagues", "limit": 999, "teams": true,
		"desc": "Tous ensemble contre des vagues de zombies. Gagne des points et achète des armes aux postes (touche F). Les morts reviennent à la vague suivante."},
	"br": {"name": "Battle Royale", "unit": "victoires", "limit": 999, "teams": false, "ffa": true,
		"desc": "Chacun pour soi, une seule vie. Ramasse des armes au sol (touche F) et reste dans la zone qui rétrécit : le dernier debout gagne."},
}
const RULE_ORDER := ["dm", "ctf", "koth", "gungame", "elim", "snd", "zombies", "br"]
# Course aux armes : ordre des armes (indices dans WEAPONS)
const GUNGAME_LADDER := [0, 3, 1, 6, 2, 7, 5, 8, 9, 4]

# Skins d'armes (shader assets/shaders/gun_skin.gdshader), débloqués pour chaque arme en faisant
# des éliminations avec elle (voir skin_kills).
# p : motif (0 standard, 1 uni, 2 dégradé, 3 tigre, 4 camouflage, 5 numérique, 6 hexagones,
# 7 carbone, 8 damas, 9 marbre, 10 écailles, 11 zèbre, 12 léopard, 13 bois, 14 métal brossé,
# 15 galaxie, 16 lave, 17 néon, 18 circuit, 19 éclaboussures, 20 bandes, 21 holographique,
# 22 cristal, 23 flammes, 24 matière noire). c1/c2/c3 : couleurs ; m/ro : métal/rugosité ;
# e : lumière émise ; s : taille du motif ; sp : vitesse d'animation ; d : contraste des pièces.
# r : rareté (0 commun, 1 rare, 2 épique, 3 légendaire, 4 mythique).
const RARITIES := [
	{"name": "Commun", "color": Color(0.75, 0.78, 0.82)},
	{"name": "Rare", "color": Color(0.35, 0.65, 1.0)},
	{"name": "Épique", "color": Color(0.72, 0.42, 1.0)},
	{"name": "Légendaire", "color": Color(1.0, 0.68, 0.2)},
	{"name": "Mythique", "color": Color(1.0, 0.3, 0.35)},
]
const CAMOS := [
	{"name": "Standard", "r": 0, "p": 0},
	{"name": "Désert", "r": 0, "p": 4, "c1": Color("c9a774"), "c2": Color("8d6b44"), "c3": Color("5a4630")},
	{"name": "Forêt", "r": 0, "p": 4, "c1": Color("5f7a3c"), "c2": Color("3d5228"), "c3": Color("2a2a1c")},
	{"name": "Urbain", "r": 0, "p": 5, "c1": Color("8e9399"), "c2": Color("5e6369"), "c3": Color("2f3236")},
	{"name": "Nuit", "r": 1, "p": 5, "c1": Color("2b3550"), "c2": Color("1b2236"), "c3": Color("3d4b70")},
	{"name": "Rouge", "r": 1, "p": 1, "c1": Color("b3221c"), "m": 0.4, "ro": 0.3},
	{"name": "Or", "r": 3, "p": 14, "c1": Color("e8b64a"), "m": 1.0, "ro": 0.25, "d": 0.15},
	{"name": "Néon", "r": 2, "p": 17, "c1": Color("0b0f1a"), "c2": Color("1ee8ff"), "e": 2.5, "sp": 1.0, "s": 10.0},
	{"name": "Arctique", "r": 0, "p": 5, "c1": Color("f2f5f8"), "c2": Color("c3cfdb"), "c3": Color("8798aa")},
	{"name": "Digital", "r": 0, "p": 5, "c1": Color("6b7a52"), "c2": Color("8d966c"), "c3": Color("3a4030")},
	{"name": "Bois", "r": 1, "p": 13, "c1": Color("8a5a32"), "c2": Color("5b3820"), "s": 6.0, "ro": 0.6},
	{"name": "Tigre", "r": 1, "p": 3, "c1": Color("f08a24"), "c2": Color("16110d"), "s": 7.0},
	{"name": "Carbone", "r": 2, "p": 7, "c1": Color("1a1c20"), "c2": Color("3c4048"), "s": 10.0, "d": 0.1},
	{"name": "Lave", "r": 4, "p": 16, "c1": Color("2a1a14"), "c2": Color("ff6a10"), "e": 3.0, "sp": 1.0, "s": 7.0},
	{"name": "Diamant", "r": 4, "p": 22, "c1": Color("dff6ff"), "c2": Color("9fd8f0"), "c3": Color("ffffff"), "m": 0.6, "e": 1.2, "s": 9.0, "d": 0.1},
	{"name": "Damas", "r": 3, "p": 8, "c1": Color("c9ccd1"), "c2": Color("4a4e55"), "m": 0.9, "ro": 0.3, "s": 6.0, "d": 0.1},
	{"name": "Damas doré", "r": 3, "p": 8, "c1": Color("f2c75c"), "c2": Color("7a5418"), "m": 1.0, "ro": 0.25, "s": 6.0, "d": 0.1},
	{"name": "Obsidienne", "r": 3, "p": 22, "c1": Color("140f1c"), "c2": Color("2e1f40"), "c3": Color("8a5cff"), "m": 0.5, "e": 0.8, "s": 8.0, "d": 0.1},
	{"name": "Matière noire", "r": 4, "p": 24, "c1": Color("07040d"), "c2": Color("3a0f6b"), "c3": Color("c056ff"), "e": 1.6, "sp": 0.6, "s": 5.0, "d": 0.05},
	{"name": "Galaxie", "r": 4, "p": 15, "c1": Color("0a0b2a"), "c2": Color("5a2a9a"), "c3": Color("ff6ad5"), "e": 1.0, "sp": 0.5, "s": 4.0, "d": 0.05},
	{"name": "Nébuleuse", "r": 4, "p": 15, "c1": Color("041a1c"), "c2": Color("0e7a6e"), "c3": Color("9dff6a"), "e": 1.0, "sp": 0.5, "s": 4.0, "d": 0.05},
	{"name": "Marbre blanc", "r": 2, "p": 9, "c1": Color("eceae6"), "c2": Color("6f6f74"), "s": 5.0, "d": 0.1},
	{"name": "Marbre noir", "r": 3, "p": 9, "c1": Color("17171a"), "c2": Color("e0b04a"), "s": 5.0, "m": 0.3, "d": 0.1},
	{"name": "Écailles de dragon", "r": 2, "p": 10, "c1": Color("2c8a3e"), "c2": Color("0e2a14"), "s": 9.0, "m": 0.3, "ro": 0.35},
	{"name": "Écailles de feu", "r": 3, "p": 10, "c1": Color("b0201a"), "c2": Color("ffb030"), "e": 1.2, "s": 9.0, "m": 0.4, "ro": 0.35},
	{"name": "Hexagone", "r": 1, "p": 6, "c1": Color("23272e"), "c2": Color("4fb0a8"), "s": 9.0},
	{"name": "Hexagone néon", "r": 2, "p": 6, "c1": Color("121418"), "c2": Color("ff8a1a"), "e": 2.5, "s": 9.0},
	{"name": "Zèbre", "r": 1, "p": 11, "c1": Color("f2f2f2"), "c2": Color("121212"), "s": 9.0},
	{"name": "Léopard", "r": 2, "p": 12, "c1": Color("d9a85b"), "c2": Color("1a120a"), "c3": Color("9a6a32"), "s": 8.0},
	{"name": "Jaguar", "r": 2, "p": 12, "c1": Color("3a3430"), "c2": Color("0c0a09"), "c3": Color("5c4a3a"), "s": 8.0},
	{"name": "Flammes", "r": 3, "p": 23, "c1": Color("141414"), "c2": Color("ffd23a"), "c3": Color("e0300e"), "e": 1.1, "sp": 1.0, "s": 7.0},
	{"name": "Flammes bleues", "r": 4, "p": 23, "c1": Color("0e0f16"), "c2": Color("bff4ff"), "c3": Color("1a5cff"), "e": 1.2, "sp": 1.0, "s": 7.0},
	{"name": "Circuit", "r": 2, "p": 18, "c1": Color("0f2a1a"), "c2": Color("3dff7a"), "e": 2.0, "s": 9.0},
	{"name": "Circuit rouge", "r": 2, "p": 18, "c1": Color("1e0b0b"), "c2": Color("ff3a3a"), "e": 2.0, "s": 9.0},
	{"name": "Holographique", "r": 3, "p": 21, "c1": Color("dadde8"), "m": 0.5, "e": 1.0, "s": 6.0, "d": 0.1},
	{"name": "Chrome", "r": 2, "p": 14, "c1": Color("dfe3e8"), "m": 1.0, "ro": 0.12, "d": 0.15},
	{"name": "Or rose", "r": 3, "p": 14, "c1": Color("e8a58c"), "m": 1.0, "ro": 0.22, "d": 0.15},
	{"name": "Cuivre", "r": 2, "p": 14, "c1": Color("c4703a"), "m": 1.0, "ro": 0.3, "d": 0.2},
	{"name": "Coucher de soleil", "r": 1, "p": 2, "c1": Color("ff8a2a"), "c2": Color("6a1f8a"), "ro": 0.3},
	{"name": "Océan", "r": 1, "p": 2, "c1": Color("3ae0e8"), "c2": Color("0c2a7a"), "ro": 0.3},
	{"name": "Toxique", "r": 2, "p": 2, "c1": Color("c8ff2a"), "c2": Color("0f5a1a"), "e": 0.4, "ro": 0.3},
	{"name": "Éclaboussures", "r": 1, "p": 19, "c1": Color("1c1d22"), "c2": Color("ff3a8a"), "c3": Color("2ad0ff"), "s": 7.0},
	{"name": "Bandes de course", "r": 0, "p": 20, "c1": Color("c41e1e"), "c2": Color("f5f5f5"), "ro": 0.25},
	{"name": "Bandes bleues", "r": 0, "p": 20, "c1": Color("1e4fc4"), "c2": Color("f5f5f5"), "ro": 0.25},
	{"name": "Camouflage océan", "r": 1, "p": 4, "c1": Color("4a7aa8"), "c2": Color("23466e"), "c3": Color("9cc2e0")},
	{"name": "Camouflage rose", "r": 1, "p": 4, "c1": Color("f2a0c4"), "c2": Color("c45a8c"), "c3": Color("5a2440")},
	{"name": "Kaki", "r": 0, "p": 1, "c1": Color("6b6a42"), "ro": 0.7},
	{"name": "Blanc glacier", "r": 0, "p": 1, "c1": Color("eef3f7"), "ro": 0.25},
	{"name": "Glace", "r": 3, "p": 22, "c1": Color("bfe8ff"), "c2": Color("6ab4e8"), "c3": Color("ffffff"), "m": 0.3, "e": 0.8, "s": 7.0, "d": 0.1},
	{"name": "Lave bleue", "r": 4, "p": 16, "c1": Color("10141e"), "c2": Color("2aa8ff"), "e": 3.0, "sp": 1.0, "s": 7.0},
	{"name": "Radioactif", "r": 4, "p": 16, "c1": Color("141a10"), "c2": Color("7aff2a"), "e": 3.0, "sp": 1.2, "s": 7.0},
	{"name": "Ébène", "r": 1, "p": 13, "c1": Color("2a1c14"), "c2": Color("0e0907"), "s": 6.0, "ro": 0.35},
]


# Éliminations à faire avec une arme pour débloquer ses skins, par rareté : [départ, pas].
# Dans une rareté, chaque skin demande un palier de plus que le précédent.
const SKIN_KILL_STEPS := [[0, 2], [25, 5], [90, 10], [225, 25], [500, 50]]
static var _skin_kills := []

## Nombre d'éliminations avec une arme pour débloquer le skin k.
static func skin_kills(k: int) -> int:
	if _skin_kills.is_empty():
		var count := [0, 0, 0, 0, 0]
		for cm in CAMOS:
			var r := int(cm.get("r", 0))
			_skin_kills.append(SKIN_KILL_STEPS[r][0] + SKIN_KILL_STEPS[r][1] * count[r])
			count[r] += 1
	return _skin_kills[clampi(k, 0, CAMOS.size() - 1)]


## Niveau du joueur à partir de son expérience : [niveau, XP dans le niveau, XP pour le suivant].
static func level_info(xp: int) -> Array:
	var lvl := 1
	var need := 150
	while xp >= need:
		xp -= need
		lvl += 1
		need = 150 + 50 * (lvl - 1)
	return [lvl, xp, need]

# Accessoires d'armes (armurerie). « slot » : un seul accessoire par emplacement.
# « cats » : familles d'armes autorisées (vide = toutes). Les lance-grenades / roquettes n'en ont pas.
const ATTACHMENTS := [
	{"id": "silencer", "slot": "bouche", "cats": [], "name": "Silencieux", "desc": "Tir discret : son faible, pas de flash · dégâts -10 %"},
	{"id": "bayonet", "slot": "dessous_avant", "cats": ["ar", "shotgun", "sniper", "dmr"], "name": "Baïonnette", "desc": "Coup de couteau +50 % de dégâts et plus long (sur l'arme principale)"},
	{"id": "mag", "slot": "chargeur", "cats": [], "name": "Chargeur étendu", "desc": "+50 % de munitions · rechargement +15 %"},
	{"id": "grip", "slot": "poignee", "cats": [], "name": "Poignée", "desc": "Recul -35 % · dispersion -20 %"},
	{"id": "bipod", "slot": "poignee", "cats": ["ar", "sniper", "dmr", "shotgun"], "name": "Bipied", "desc": "Immobile : recul et dispersion divisés par 2"},
	{"id": "flashlight", "slot": "cote", "cats": [], "name": "Lampe tactique", "desc": "Éclaire devant toi · dispersion sans viser -15 %"},
	{"id": "stock", "slot": "crosse", "cats": ["pistol", "smg", "sawed", "revolver"], "name": "Crosse", "desc": "Recul -20 % · rechargement -10 %"},
	{"id": "optic", "slot": "dessus", "cats": [], "name": "Viseur point rouge", "desc": "Visée précise au clic droit (zoom léger) · dispersion -25 % en visée"},
	{"id": "scope", "slot": "dessus", "cats": ["ar", "smg", "shotgun"], "name": "Lunette x4", "desc": "Vraie lunette au clic droit (zoom fort)"},
]


# Où se trouve le chargeur de chaque modèle (relevé à la main, en fraction de la boîte du modèle
# d'origine) : [x du chargeur depuis la crosse, hauteur du bas du boîtier, demi-largeur de recherche].
# Pour les pistolets, c'est la poignée (le chargeur est dedans). Pas de chargeur visible = pas d'accessoire.
const MAG_HINTS := {
	"q/AssaultRifle2_1": [0.47, 0.55, 0.06], "q/AssaultRifle2_2": [0.49, 0.55, 0.06],
	"q/AssaultRifle2_3": [0.27, 0.6, 0.07], "q/AssaultRifle2_4": [0.7, 0.45, 0.07],
	"q/AssaultRifle_1": [0.37, 0.6, 0.05], "q/AssaultRifle_2": [0.5, 0.65, 0.08],
	"q/AssaultRifle_3": [0.42, 0.7, 0.1], "q/AssaultRifle_4": [0.5, 0.65, 0.08],
	"q/AssaultRifle_5": [0.55, 0.65, 0.08],
	"q/Bullpup_1": [0.28, 0.6, 0.05], "q/Bullpup_2": [0.12, 0.6, 0.06], "q/Bullpup_3": [0.12, 0.6, 0.09],
	"q/SubmachineGun_1": [0.47, 0.45, 0.06], "q/SubmachineGun_2": [0.65, 0.45, 0.06],
	"q/SubmachineGun_3": [0.66, 0.45, 0.05], "q/SubmachineGun_4": [0.5, 0.55, 0.1],
	"q/SubmachineGun_5": [0.52, 0.45, 0.04],
	"q/Pistol_1": [0.2, 0.45, 0.12], "q/Pistol_2": [0.2, 0.45, 0.12], "q/Pistol_3": [0.2, 0.45, 0.12],
	"q/Pistol_4": [0.2, 0.55, 0.14], "q/Pistol_5": [0.22, 0.45, 0.12], "q/Pistol_6": [0.15, 0.5, 0.1],
	"q/SniperRifle_2": [0.45, 0.3, 0.04],
}


## Accessoires possibles pour une arme.
static func attachments_for(wi: int) -> Array:
	var w: Dictionary = WEAPONS[wi]
	if float(w.splash) > 0.0:
		return []
	var out := []
	for a in ATTACHMENTS:
		if a["id"] == "mag" and not MAG_HINTS.has(w.model):
			continue  # chargeur tubulaire ou caché : pas de chargeur étendu
		if a["slot"] == "dessus" and int(w.zoom) > 0:
			continue  # déjà une lunette
		if not a["cats"].is_empty() and not a["cats"].has(w.cat):
			continue
		out.append(a["id"])
	return out


static func attachment_slot(id: String) -> String:
	for a in ATTACHMENTS:
		if a["id"] == id:
			return a["slot"]
	return ""


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
	if att.has("stock"):
		w["recoil"] = float(w.recoil) * 0.8
		w["reload"] = float(w.reload) * 0.9
	if att.has("bipod"):
		w["bipod"] = true
	if att.has("flashlight"):
		w["hip_spread"] = 0.85
	if att.has("optic"):
		w["zoom"] = 55
		w["optic"] = true
	if att.has("scope"):
		w["zoom"] = 30
	return w

# Familles d'armes : dans l'armurerie, on choisit l'arme utilisée pour chaque famille.
const CATS := {
	"ar": "Fusils d'assaut", "smg": "Mitraillettes", "pistol": "Pistolets", "revolver": "Revolvers",
	"shotgun": "Fusils à pompe", "sawed": "Canons courts", "sniper": "Snipers", "dmr": "Fusils de précision",
	"gl": "Lance-grenades", "rocket": "Lance-roquettes",
}
const CAT_ORDER := ["ar", "smg", "pistol", "revolver", "shotgun", "sawed", "sniper", "dmr", "gl", "rocket"]


## Arme réellement utilisée à la place de l'arme « wi » d'une classe : le choix du joueur pour cette famille.
## Les 3 armes d'une classe pour un joueur : celles qu'il a choisies (armory["loadouts"][classe]),
## sinon celles de la classe (avec l'arme préférée de chaque famille).
static func class_weapons(cls: int, armory: Dictionary) -> Array:
	cls = clampi(cls, 0, CLASSES.size() - 1)
	var lo = armory.get("loadouts", {})
	if lo is Dictionary and lo.has(str(cls)):
		var arr = lo[str(cls)]
		if arr is Array and arr.size() == 3:
			var out := []
			for wi in arr:
				var i := int(wi)
				if i < 0 or i >= WEAPONS.size() or out.has(i):
					out = []
					break
				out.append(i)
			if out.size() == 3:
				return out
	var def := []
	for wi in CLASSES[cls]["weapons"]:
		def.append(resolve_weapon(wi, armory))
	return def


## Texte court des armes d'une classe (« AK-47 · Pistolet · Lance-grenades »).
static func class_text(cls: int, armory: Dictionary) -> String:
	var names := []
	for wi in class_weapons(cls, armory):
		names.append(WEAPONS[wi].name)
	return " · ".join(names)


static func resolve_weapon(wi: int, armory: Dictionary) -> int:
	var picks = armory.get("pick", {})
	if not (picks is Dictionary):
		return wi
	var cat: String = WEAPONS[wi].cat
	var p := int(picks.get(cat, wi))
	if p >= 0 and p < WEAPONS.size() and WEAPONS[p].cat == cat:
		return p
	return wi
