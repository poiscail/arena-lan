# Arena LAN

FPS à la première personne en réseau local, fait avec Godot 4.7.
- **1 à 12 joueurs humains.**
- **Modes** : *Équipes* (de 1 contre 1 jusqu'à 6 contre 6) ou *Chacun pour soi* (2 à 12 combattants).
- **Bots** : ils complètent les places vides, en 3 niveaux de difficulté.

## Télécharger (Windows, rien à installer)
1. Va dans **[Releases](https://github.com/poiscail/arena-lan/releases/latest)** et télécharge **`ArenaLAN.exe`**.
2. Double-clique dessus.
   - Si Windows affiche « Windows a protégé votre ordinateur » : clique sur **Informations complémentaires**, puis sur **Exécuter quand même**. Le message apparaît parce que l'exécutable n'est pas signé.

Tout le monde doit avoir **la même version** du jeu.

## Lancer depuis le code source
- Double-clique sur **`Lancer.bat`** (Godot 4.7 doit être installé).
- Ou bien ouvre `project.godot` dans Godot, puis appuie sur **F5**.
- Pour refaire le `.exe` : dans Godot, menu **Projet > Exporter…**, choisis le préréglage *Windows Desktop*. Les modèles d'export de Godot 4.7.2 doivent être installés.

## Jouer en LAN
1. **L'hôte** clique sur *Héberger une partie*. Le salon affiche son adresse IP (par ex. `192.168.1.20`).
2. **Les autres** tapent cette IP, puis cliquent sur *Rejoindre*. Tout le monde doit utiliser le même port (7777 par défaut).
3. **L'hôte règle la partie** : mode, nombre de joueurs, bots, difficulté, score à atteindre, durée.
4. **L'hôte lance** avec *Lancer la partie*.

Quelqu'un peut rejoindre en cours de partie. Il remplace alors un bot.

**Pare-feu Windows** : au premier lancement, Windows demande s'il faut autoriser Godot. Coche **Réseaux privés**, puis *Autoriser*. Fais-le sur le PC de l'hôte en priorité.

**Jouer seul contre des bots** : héberge une partie, puis lance-la directement.

## Commandes (positions des touches : ZQSD sur AZERTY)
| Touche | Action |
|---|---|
| ZQSD / flèches | Se déplacer |
| Souris | Viser |
| Clic gauche | Tirer |
| Clic droit | Zoom (sniper) |
| Espace | Sauter |
| Maj | Sprinter |
| R | Recharger |
| 1 / 2 / 3 ou molette | Fusil / Pompe / Sniper |
| Tab | Tableau des scores |
| Échap | Pause (sensibilité, quitter) |

## Armes
- **Fusil** : automatique, 20 dégâts, 30 balles.
- **Pompe** : 9 plombs de 12 dégâts, 6 cartouches. Dévastateur de près.
- **Sniper** : 80 dégâts, 5 balles. Précis seulement avec le zoom.
- **Tir à la tête** : les dégâts sont multipliés (×1,3 à ×2 selon l'arme).

## Organisation du code (`scripts/`)
| Fichier | Rôle |
|---|---|
| `net.gd` | Connexion, salon, paramètres (chargé en permanence sous le nom `Net`) |
| `main.gd` | Menu et salon |
| `game.gd` | Règles de la partie, réseau en jeu, tirs, scores, effets |
| `character.gd` | Joueur et bot : déplacement, armes, caméra |
| `bot.gd` | Intelligence des bots (vision, combat, déplacement sur la carte) |
| `map.gd` | Construction de l'arène, points d'apparition, chemins des bots |
| `hud.gd` | Interface en jeu |
| `data.gd` | Réglages des armes et des équipes |

Toute la partie est décidée par l'hôte : dégâts, morts, scores et bots. Chaque joueur envoie seulement sa position et ses tirs.
