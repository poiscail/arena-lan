extends RefCounted
## Données partagées : armes, équipes, règles.

const RESPAWN_TIME := 3.0

const TEAM_NAMES := ["BLEUS", "ROUGES"]
const TEAM_COLORS := [Color(0.25, 0.5, 1.0), Color(1.0, 0.32, 0.26)]
const TEAM_HEX := ["#6f9bff", "#ff6b5e"]

const WEAPONS := [
	{"name": "Fusil", "damage": 20, "rate": 0.1, "mag": 30, "reload": 1.8, "spread": 0.7, "pellets": 1, "range": 150.0, "auto": true, "head": 1.6},
	{"name": "Pompe", "damage": 12, "rate": 0.8, "mag": 6, "reload": 2.2, "spread": 5.5, "pellets": 9, "range": 35.0, "auto": false, "head": 1.3},
	{"name": "Sniper", "damage": 80, "rate": 1.3, "mag": 5, "reload": 2.6, "spread": 0.0, "pellets": 1, "range": 300.0, "auto": false, "head": 2.0},
]

# Modèle 3D de chaque arme (Quaternius Toon Shooter) et sa longueur en vue à la première personne
const WEAPON_MODELS := [["AK", 0.62], ["Shotgun", 0.62], ["Sniper", 0.8]]

# Skins (Quaternius Universal Base Characters + tenues), animés par la Universal Animation Library
const SKINS := [
	{"name": "Rôdeur", "parts": ["Superhero_Male_FullBody", "Male_Ranger"]},
	{"name": "Rôdeuse", "parts": ["Superhero_Female_FullBody", "Female_Ranger"]},
	{"name": "Agent", "parts": ["Superhero_Male_FullBody"]},
	{"name": "Agente", "parts": ["Superhero_Female_FullBody"]},
]

# Recul vertical de la caméra (radians) par tir
const RECOIL := [0.012, 0.05, 0.09]


static func esc(text: String) -> String:
	return text.replace("[", "[lb]")
