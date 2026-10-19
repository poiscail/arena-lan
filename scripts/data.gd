extends RefCounted
## Données partagées : armes, équipes, règles.

const RESPAWN_TIME := 3.0

const TEAM_NAMES := ["BLEUS", "ROUGES"]
const TEAM_COLORS := [Color(0.25, 0.5, 1.0), Color(1.0, 0.32, 0.26)]
const TEAM_HEX := ["#6f9bff", "#ff6b5e"]

# Armes. "model"/"len" : modèle 3D (Quaternius Toon Shooter) et sa longueur en vue à la première personne.
# "zoom" : champ de vision en visée (0 = pas de lunette), "splash" : rayon d'explosion, "recoil" : recul (radians).
const WEAPONS := [
	{"name": "Fusil d'assaut", "model": "AK", "len": 0.62, "damage": 20, "rate": 0.1, "mag": 30, "reload": 1.8, "spread": 0.7, "pellets": 1, "range": 150.0, "auto": true, "head": 1.6, "zoom": 0, "splash": 0.0, "recoil": 0.012, "sound": 0},
	{"name": "Pompe", "model": "Shotgun", "len": 0.62, "damage": 12, "rate": 0.8, "mag": 6, "reload": 2.2, "spread": 5.5, "pellets": 9, "range": 35.0, "auto": false, "head": 1.3, "zoom": 0, "splash": 0.0, "recoil": 0.05, "sound": 1},
	{"name": "Sniper", "model": "Sniper", "len": 0.8, "damage": 80, "rate": 1.3, "mag": 5, "reload": 2.6, "spread": 0.0, "pellets": 1, "range": 300.0, "auto": false, "head": 2.0, "zoom": 25, "splash": 0.0, "recoil": 0.09, "sound": 2},
	{"name": "Mitraillette", "model": "SMG", "len": 0.5, "damage": 14, "rate": 0.065, "mag": 35, "reload": 1.5, "spread": 1.6, "pellets": 1, "range": 80.0, "auto": true, "head": 1.5, "zoom": 0, "splash": 0.0, "recoil": 0.008, "sound": 0},
	{"name": "Pistolet", "model": "Pistol", "len": 0.32, "damage": 26, "rate": 0.18, "mag": 12, "reload": 1.2, "spread": 0.9, "pellets": 1, "range": 90.0, "auto": false, "head": 1.8, "zoom": 0, "splash": 0.0, "recoil": 0.025, "sound": 0},
	{"name": "Revolver", "model": "Revolver", "len": 0.38, "damage": 48, "rate": 0.5, "mag": 6, "reload": 2.0, "spread": 0.4, "pellets": 1, "range": 120.0, "auto": false, "head": 2.0, "zoom": 0, "splash": 0.0, "recoil": 0.07, "sound": 1},
	{"name": "Fusil de précision", "model": "Sniper_2", "len": 0.75, "damage": 45, "rate": 0.35, "mag": 10, "reload": 2.2, "spread": 0.2, "pellets": 1, "range": 220.0, "auto": false, "head": 1.8, "zoom": 45, "splash": 0.0, "recoil": 0.04, "sound": 2},
	{"name": "Canon court", "model": "ShortCannon", "len": 0.5, "damage": 10, "rate": 0.3, "mag": 2, "reload": 1.9, "spread": 8.0, "pellets": 14, "range": 20.0, "auto": false, "head": 1.2, "zoom": 0, "splash": 0.0, "recoil": 0.1, "sound": 1},
	{"name": "Lance-grenades", "model": "GrenadeLauncher", "len": 0.52, "damage": 90, "rate": 0.9, "mag": 4, "reload": 2.6, "spread": 0.5, "pellets": 1, "range": 60.0, "auto": false, "head": 1.0, "zoom": 0, "splash": 4.0, "recoil": 0.06, "sound": 3},
	{"name": "Lance-roquettes", "model": "RocketLauncher", "len": 0.62, "damage": 120, "rate": 1.0, "mag": 1, "reload": 2.8, "spread": 0.0, "pellets": 1, "range": 150.0, "auto": false, "head": 1.0, "zoom": 0, "splash": 5.0, "recoil": 0.08, "sound": 3},
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
const MAPS := ["Base militaire", "Ville"]
