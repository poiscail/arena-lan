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
2. **Les autres** voient la partie apparaître toute seule dans « Parties trouvées sur le réseau » : clic sur *Rejoindre*. Sinon, tapez l'IP de l'hôte puis *Rejoindre*. Tout le monde doit utiliser le même port (7777 par défaut, et 7778 pour la découverte automatique).
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
| Clic droit | Zoom (armes à lunette) |
| Espace | Sauter |
| Maj | Sprinter |
| Ctrl (ou C) en courant | Glisser |
| R | Recharger |
| G | Lancer une grenade (2 par vie) |
| H | Lancer un fumigène (1 par vie) |
| V | Coup de couteau (élimine d'un coup dans le dos) |
| 1 / 2 / 3 ou molette | Changer d'arme |
| T | Chat |
| X ou clic molette | Signaler un endroit à ton équipe |
| L | Lampe torche (cartes de nuit) |
| Tab | Tableau des scores |
| Échap | Pause (classe, options, quitter) |

Toutes les touches se changent dans **Options > Touches**.

**Glissade** : en courant, appuie sur Ctrl. Tu glisses vite et bas pendant presque une seconde, et tu restes précis en tirant. Saute pendant la glissade pour garder l'élan.

## Après la mort : mode spectateur
Quand tu es éliminé, la caméra suit un coéquipier (n'importe quel joueur en chacun pour soi) :
- **clic gauche / droit** : joueur suivant / précédent ;
- **Espace** : caméra libre (ZQSD + souris, Maj pour aller plus vite), puis Espace pour revenir.

Très pratique en mode Élimination, où l'on attend la manche suivante.

## Cartes
- **Base militaire** et **Ville**, de jour.
- **Entrepôt** : un grand hangar fermé, éclairé par des lampes au plafond, avec des cloisons, des piliers et des caisses.
- **Base militaire (nuit)** et **Ville (nuit)** : ciel étoilé, lampadaires et lampe torche (L).

## Armurerie
Bouton **Armurerie** dans le menu. Pour chaque arme :
- un **skin** : couleurs (Désert, Forêt, Urbain, Nuit, Rouge, Or, Néon) et motifs (Arctique, Digital, Bois, Tigre, Carbone, Lave), débloqués en montant de niveau ;
- des **accessoires visibles sur l'arme** : silencieux (son étouffé, pas de flash, -10 % de dégâts), chargeur étendu (+50 % de munitions), poignée (moins de recul et de dispersion), viseur point rouge (visée au clic droit).

Un aperçu 3D montre l'arme, et les caractéristiques changent en vert ou en rouge. Les autres joueurs voient ta personnalisation.

## Progression et personnalisation
- Chaque match rapporte de l'**expérience** : participation, éliminations, objectifs et victoire. Elle est sauvegardée sur ton PC.
- Le menu affiche ton **niveau** et ta barre d'expérience.
- En montant de niveau, tu débloques des **camouflages d'armes** : Désert, Forêt, Urbain, Nuit, Rouge, Or et Néon. Les autres joueurs les voient sur ton arme.

## Bots
Ils se déplacent avec des chemins calculés, glissent, se mettent à l'abri quand ils sont blessés (parfois avec un fumigène), lancent des grenades, donnent des coups de couteau de près, contournent l'ennemi, ramassent les bonus et jouent les objectifs des modes.

## Modes de jeu
L'hôte choisit le jeu dans le salon :
- **Match à mort** : le plus d'éliminations gagne (en équipes ou chacun pour soi).
- **Capture du drapeau** (équipes) : prends le drapeau ennemi et ramène-le à ta base pendant que le tien y est. Premier à 3 captures.
- **Roi de la colline** : reste seul (ou avec ton équipe) dans la zone du centre, 1 point par seconde. Premier à 100.
- **Course aux armes** : chaque élimination donne l'arme suivante (10 niveaux). Un coup de couteau fait reculer la victime d'un niveau.
- **Élimination** (équipes) : une vie par manche, la dernière équipe debout gagne la manche. Premier à 5 manches.

À la fin du match, un tableau donne les **récompenses** (meilleur joueur, plus précis, plus longue série, plus de dégâts, tirs à la tête) et **tes statistiques**.

## Classes
Choisis ta classe dans le menu. En partie, tu peux la changer dans la pause (Échap) : elle s'applique à ta prochaine réapparition.

| Classe | Armes (1 / 2 / 3) | Bonus |
|---|---|---|
| Assaut | Fusil d'assaut, pistolet, lance-grenades | — |
| Commando | Mitraillette, canon court, revolver | +10 % de vitesse |
| Tireur d'élite | Sniper, fusil de précision, pistolet | — |
| Lourd | Pompe, lance-roquettes, revolver | −10 % de vitesse |
| Classique | Fusil d'assaut, pompe, sniper | — |

## Armes
- **Fusil d'assaut** : automatique, 20 dégâts, 30 balles.
- **Mitraillette** : très rapide, 14 dégâts, 35 balles.
- **Pistolet** : 26 dégâts, 12 balles.
- **Revolver** : 48 dégâts, 6 balles. Très précis.
- **Pompe** : 9 plombs de 12 dégâts, 6 cartouches. Dévastateur de près.
- **Canon court** : 14 plombs, 2 coups. Énorme à bout portant.
- **Sniper** : 80 dégâts, 5 balles. Précis seulement avec le zoom.
- **Fusil de précision** : 45 dégâts, 10 balles, petit zoom.
- **Lance-grenades** : explosion de 4 m, jusqu'à 90 dégâts.
- **Lance-roquettes** : explosion de 5 m, jusqu'à 120 dégâts, 1 roquette.
- **Chiffres de dégâts** : les dégâts que tu infliges s'affichent au-dessus de l'ennemi (jaune à la tête, rouge quand il est éliminé).
- **Tir à la tête** : les dégâts sont multipliés (×1,2 à ×2 selon l'arme).

## Sur la carte
- **Trousses de soin** (+50 PV), **armure** (+50, absorbe la moitié des dégâts), **munitions** (recharge tout, grenades comprises) et **dégâts ×2** pendant 15 s. Chaque objet réapparaît après un moment.
- **Barils explosifs** : tire dessus pour les faire sauter. Ils explosent en chaîne et réapparaissent après 30 s.
- **Fumigènes** : les bots ne voient pas à travers.

## Séries d'éliminations (sans mourir)
- **3** : Adrénaline, +30 % de vitesse pendant 20 s.
- **5** : Radar, les ennemis sont marqués à travers les murs pendant 12 s.
- **7** : Frappe aérienne, une explosion tombe sur chaque ennemi 2 secondes après une alerte au sol.

## Options
Bouton **Options** dans le menu ou dans la pause. Tous les réglages sont appliqués tout de suite et sauvegardés :
- préréglages Basse / Moyenne / Haute / Ultra ;
- ombres (désactivées à hautes), anticrénelage, résolution 3D, distance de vue, brouillard, luminosité ;
- champ de vision, plein écran, synchro verticale, limite d'images, compteur d'IPS ;
- sensibilité de la souris.

Si le jeu rame, choisis **Basse**.

## Organisation du code (`scripts/`)
| Fichier | Rôle |
|---|---|
| `net.gd` | Connexion, salon, paramètres (chargé en permanence sous le nom `Net`) |
| `main.gd` | Menu et salon |
| `menu_bg.gd` | Fond 3D animé du menu |
| `game.gd` | Règles de la partie, réseau en jeu, tirs, scores, effets |
| `character.gd` | Joueur et bot : déplacement, armes, caméra, animations |
| `bot.gd` | Intelligence des bots (vision, combat, déplacement sur la carte) |
| `map.gd` | Construction de l'arène, points d'apparition, chemins des bots |
| `hud.gd` | Interface en jeu |
| `sfx.gd` | Sons, flash du canon, douilles, impacts, tremblement de caméra |
| `spectator.gd` | Caméra spectateur après la mort (coéquipier ou caméra libre) |
| `modes.gd` | Modes de jeu : drapeau, colline, course aux armes, élimination |
| `armory.gd` | Écran Armurerie (skins, accessoires, aperçu 3D) |
| `items.gd` | Trousses, bonus, barils explosifs, grenades et fumigènes |
| `options.gd` | Fenêtre d'options (graphismes, souris) |
| `ui_theme.gd` | Thème visuel (polices, panneaux, boutons) |
| `models.gd` | Chargement des armes 3D |
| `people.gd` | Personnages, skins et arbre d'animation |
| `data.gd` | Armes, classes, équipes, skins et cartes |

Toute la partie est décidée par l'hôte : dégâts, morts, scores et bots. Chaque joueur envoie seulement sa position et ses tirs.

## Crédits
- **Personnages et animations** : [Universal Base Characters](https://quaternius.com/packs/universalbasecharacters.html), [Modular Character Outfits - Fantasy](https://quaternius.itch.io/modular-character-outfits-fantasy) et [Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html) de Quaternius, licence CC0.
- **Armes réalistes** : [Ultimate Gun Pack](https://opengameart.org/content/low-poly-guns-pack) de Quaternius, licence CC0.
- **Armes et décor** : [Toon Shooter Game Kit](https://quaternius.com/packs/toonshootergamekit.html) de Quaternius, licence CC0.
- **Carte Ville** : [City Kit Commercial](https://kenney.nl/assets/city-kit-commercial), [City Kit Roads](https://kenney.nl/assets/city-kit-roads) et [Car Kit](https://kenney.nl/assets/car-kit) de Kenney, licence CC0.
- **Ciel et textures** : [Kloofendal 48d Partly Cloudy (Pure Sky)](https://polyhaven.com/a/kloofendal_48d_partly_cloudy_puresky), [Asphalt 02](https://polyhaven.com/a/asphalt_02) et [Concrete Floor 02](https://polyhaven.com/a/concrete_floor_02) de Poly Haven, licence CC0.
- **Sons** : [The Free Firearm Sound Library](https://opengameart.org/content/the-free-firearm-sound-library) (tirs, CC0), et [Impact Sounds](https://kenney.nl/assets/impact-sounds), [RPG Audio](https://kenney.nl/assets/rpg-audio) et [Interface Sounds](https://kenney.nl/assets/interface-sounds) de Kenney (CC0).
- **Polices** : [Rajdhani](https://fonts.google.com/specimen/Rajdhani) et [Orbitron](https://fonts.google.com/specimen/Orbitron), licence SIL Open Font.
- **Moteur** : [Godot 4.7](https://godotengine.org).
