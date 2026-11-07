# Vidéos de voyage — conception

## Intention

Fabriquer, depuis Fractales, une vidéo `.mp4` prête à publier qui montre un **voyage** dans une fractale : un
voyageur passe d'une zone à une autre, s'approche, recule, se déplace. Le cas type est le Burning Ship et ses
nombreuses régions ; la descente continue d'un Julia n'en est qu'un cas particulier (deux étapes, la seconde
très profonde). Public : JF d'abord, puis Facebook et Instagram.

## Objectifs

- Un **scénario** : liste ordonnée d'**étapes**, enregistrable dans un fichier, rouvrable, modifiable, relançable.
- Les étapes viennent des **favoris** existants (`TFavoriteStore`, un `.frac` par favori), sans avoir à
  enregistrer une navigation.
- Entre deux étapes, des **indicateurs** réglables : durée du trajet, pause à l'arrivée (0 = pas de pause).
- Le programme calcule seul un mouvement fluide entre les étapes (voir « Mouvement »).
- Sortie : fichier `.mp4` (H.264) prêt à publier, au format choisi à la création :
  carré 1:1 (1080×1080), 4:5 (1080×1350), Reel 9:16 (1080×1920), 16:9 (1920×1080).
- Rendu long : estimation de durée, progression, annulation possible.

## Non-objectifs

- Enregistrer une navigation en direct (« caméra qui tourne ») : écarté par JF, trop laborieux.
- Changer de palette ou d'effets au fil de la vidéo : écarté par JF (« trop facile comme effet »).
- Mélanger plusieurs formules dans une vidéo.
- Musique, titres, montage : hors programme (un logiciel de montage s'en charge si besoin).
- Rotation de l'image (angle de vue) : retenue par JF pour **plus tard**, comme projet à part qui servira aussi
  à l'exploration (angle dans la position, les favoris, les `.frac` ; question de la lumière du relief).

## Anti-objectifs

- Un mouvement saccadé ou un zoom à vitesse apparente variable : la vidéo doit être agréable à regarder,
  c'est tout son intérêt.
- Des images qui « sautent » entre deux étapes (changement brutal du nombre d'itérations, de la palette…).
- Bloquer l'interface pendant le rendu.

## Décisions de JF

- Étapes marquées, via les favoris.
- Sortie `.mp4` prête à publier ; format choisi parmi plusieurs.
- Pause par étape, de x secondes ou zéro.
- Une seule palette pour toute la vidéo.
- Le parcours s'enregistre : c'est un scénario.
- Deux modes de trajet, choisis par passage : **survol** (reculer, glisser, replonger) et **latéral**
  (glissement à profondeur constante).
- Le rendu long doit pouvoir se faire sur une autre machine (la tablette) : on y copie le scénario, on l'ouvre,
  on lance le rendu.

## Choix de Claude (à vérifier par JF)

- **Couleurs** : celles affichées (palette + effets) au moment où l'on lance le rendu ; les couleurs
  enregistrées dans chaque favori sont ignorées, seule sa position compte.
- **Une formule par scénario** : toutes les étapes doivent avoir la même formule (et les mêmes paramètres,
  pour Julia) ; une étape différente est refusée à l'ajout, avec un message.
- **Cadence** : 30 images/s.
- **Encodage** : FFmpeg (`ffmpeg.exe`), cherché à côté de l'exe puis dans le chemin indiqué par
  `Fractales.ini` ; s'il manque, un message explique où l'obtenir. Les images passent à FFmpeg par un tube
  (pas de milliers de fichiers temporaires). Qualité visée : H.264, `yuv420p` (lecture partout), débit
  élevé — les fractales compressent mal.
- **Rendu** : même moteur que le rendu HD (Rust si disponible, perturbation pour les zooms profonds),
  dans un fil, sans suréchantillonnage par défaut (option).
- **Aperçu** : un bouton « Aperçu » rend le trajet en petite taille (par exemple 1/4 de la résolution, sans
  pause) pour vérifier le parcours avant un rendu long.
- **Fichier de scénario** : texte INI comme les `.frac` (extension `.fscn`, à confirmer), qui contient le
  format, la cadence, et pour chaque étape la position complète (centre en haute précision, largeur, formule)
  copiée du favori au moment de l'ajout — un favori renommé ou supprimé ne casse pas le scénario.
- **Itérations** : le nombre maximum d'itérations varie progressivement avec la profondeur (même règle que
  l'itération automatique), jamais par sauts.

## Mouvement

Entre deux étapes A et B (centres cA, cB ; largeurs wA, wB), selon le mode du passage :

- Le zoom se fait sur une échelle **logarithmique** (vitesse apparente constante), pas linéaire.
- **Survol** (par défaut) : si B n'est pas visible depuis A, le voyageur **recule** d'abord jusqu'à voir les
  deux, **glisse**, puis **replonge** — c'est le « zoom out, move, zoom in » de JF. Le chemin « zoom optimal »
  de van Wijk et Nuij (2003) fait exactement cela en une seule courbe douce ; c'est la piste proposée.
- **Latéral** : glissement direct de cA vers cB, sans recul ; si wA et wB diffèrent, la largeur passe de l'une à
  l'autre (en logarithmique) pendant le glissement. Un travelling trop rapide est illisible : la fenêtre
  affiche la vitesse en largeurs d'écran par seconde et avertit au-delà d'un seuil (à régler à l'essai).
- Départ et arrivée **adoucis** (accélération, décélération), surtout quand une pause suit.
- La durée du trajet est réglée par étape ; une valeur par défaut est proposée selon la distance parcourue
  (en largeurs d'écran et en facteur de zoom).

## Interface (proposition, à affiner)

Une fenêtre « Vidéo » (menu Fichier ou panneau latéral) :

- liste des étapes avec, pour chacune, mode du trajet (survol ou latéral), durée du trajet et pause ;
- ajouter depuis les favoris, ajouter la vue courante, retirer, monter, descendre ;
- format, nom du fichier de sortie, estimation de durée de vidéo et de calcul ;
- Ouvrir / Enregistrer le scénario, Aperçu, Rendre, Annuler ; barre de progression.

## Contraintes

- Delphi : code compilable sous D2010 (`./build.sh`) et CE 13 ; sources UTF-8 BOM, CRLF ; `.dfm` ASCII.
- Tests unitaires pour tout ce qui ne dépend pas de l'écran : calcul du trajet, lecture/écriture du scénario,
  estimation, contrôle des formules.
- Test de fumée : ouverture de la fenêtre et rendu d'une vidéo minuscule (si FFmpeg est présent ;
  sinon l'étape est signalée et sautée).
- Les specs et plans ne sont pas commités.

## Laissé au constructeur

- Le détail de l'algorithme de trajet et de l'adoucissement.
- La manière de piloter FFmpeg (arguments exacts) et la gestion de ses erreurs.
- Le découpage en unités (par exemple `Fractal.Video.Path`, `Fractal.Video.Scenario`, `VideoFrm`).
