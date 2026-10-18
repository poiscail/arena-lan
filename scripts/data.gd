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

# Apparence de l'arme en vue à la première personne : [taille, couleur]
const GUN_LOOKS := [
	[Vector3(0.045, 0.065, 0.4), Color(0.15, 0.15, 0.17)],
	[Vector3(0.06, 0.07, 0.34), Color(0.4, 0.25, 0.12)],
	[Vector3(0.04, 0.06, 0.55), Color(0.25, 0.3, 0.18)],
]

# Recul vertical de la caméra (radians) par tir
const RECOIL := [0.012, 0.05, 0.09]


static func esc(text: String) -> String:
	return text.replace("[", "[lb]")
