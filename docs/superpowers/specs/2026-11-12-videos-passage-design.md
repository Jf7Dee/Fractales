# Vidéos : étapes de passage (trajets enchaînés)

## Intention

Aujourd'hui, chaque trajet entre deux étapes démarre à l'arrêt, accélère, puis ralentit jusqu'à l'arrêt complet
sur l'étape suivante. Sur une suite de favoris, ce rythme « démarre, file, freine » devient répétitif.

On veut pouvoir **traverser** une étape sans s'y arrêter : la caméra garde sa vitesse de croisière d'un trajet à
l'autre et ne ralentit que là où elle doit vraiment s'arrêter. Exemple : survol vers A, passage par B et C sans
freiner, survol vers D avec ralentissement seulement à l'arrivée sur D.

## Objectifs

- Une case **« Arrêt »** par étape, à côté du combo du mode, cochée par défaut.
  - Cochée : comportement actuel, la caméra freine et s'arrête sur l'étape.
  - Décochée : la caméra passe par l'étape sans freiner.
  - Toujours des arrêts, case cochée et désactivée : la première étape, la dernière, et toute étape dont la pause
    est non nulle.
- **Enchaînement** : les trajets compris entre deux arrêts forment un seul mouvement : accélération au départ,
  vitesse constante, ralentissement à l'arrivée. Survol et Latéral se combinent librement, deux survols de suite
  compris.
- **Durées** : la durée totale de l'enchaînement est la somme des durées de ses trajets, parcourue à vitesse
  constante (perçue à l'écran). Les durées de chaque étape restent modifiables ; le moment exact du passage par une
  étape intermédiaire en découle et ne tombe pas forcément à la seconde prévue.
- **Étapes de passage = repères** : la trajectoire s'en approche par une courbe douce, sans coin ni à-coup ; elle
  ne passe pas forcément exactement par le cadrage ni par le zoom de l'étape. Pour montrer une vue précise, on en
  fait un arrêt.
- **Affichage** : sur une étape enchaînée, la ligne d'information sous le mode (celle de l'avertissement de vitesse
  du latéral) indique l'enchaînement, par exemple : « Enchaîné avec les étapes 3 à 5 : 30 s en tout, passage ici
  vers 12,4 s ».
  - L'avertissement « trop rapide » du latéral est calculé, pour un trajet enchaîné, avec la vitesse de croisière de
    l'enchaînement (pas avec la durée propre du trajet) ; s'il s'applique, il s'affiche sous le texte
    d'enchaînement. *(choix de rédaction)*
  - Le champ durée d'une étape enchaînée reste tel quel, sans grisage ni annotation : sa valeur compte dans la
    somme, et la ligne d'information montre l'effet réel. *(choix de rédaction)*
- **Règles déjà implicites** : le trajet qui arrive à une étape suit le mode de cette étape (comme aujourd'hui) ;
  une clé `Arret=0` sur une étape à pause non nulle ou sur la dernière est lue puis ignorée.

## Non-objectifs

- Pas de réglage pour l'autre comportement (durées exactes, vitesse variable) : un seul comportement.
- Pas de nouveau mode à côté de Survol et Latéral : la case porte seule l'arrêt.
- Pas de confirmation ni d'indicateur « modifié » (sujet séparé).

## Anti-objectifs

- Un scénario existant ne doit **pas** changer : toutes les cases cochées donnent exactement les mêmes images
  qu'aujourd'hui (un enchaînement d'un seul trajet = le trajet actuel, `EaseInOut` compris).
- Pas d'à-coup visible au passage d'une étape (ni arrêt, ni saut de direction, ni saut de vitesse).
- Pas de perte de précision en zoom profond : tout mélange de poses doit respecter la façon dont `CenterFrom`
  garde la précision de chaque bout (nombres à précision étendue, `FracWords`).

## Contraintes

- Fichier scénario : clé `Arret=0` dans la section `[StepN]`, écrite seulement quand la case est décochée ;
  absente = arrêt. `Version=1` inchangée : les anciens fichiers se lisent tels quels.
- `SaveToText` inclut la clé : l'estampille de reprise (`scenario.txt`) et celle de l'aperçu changent donc quand
  on coche ou décoche, ce qui est voulu.
- `TVideoStep` reçoit un champ booléen (nom au choix, par ex. `IsStop`), défaut vrai dans `AddLocation`.
- Le profil de coût, la reprise par morceaux et l'aperçu passent par `PoseAtFrame` : rien d'autre à changer de ce
  côté.
- Compile sous D2010 et CE 13.

## Laissé au constructeur

- **Profil de vitesse d'un enchaînement de plusieurs trajets** : rampe d'accélération, palier constant, rampe de
  décélération. Durée des rampes à choisir (ordre de grandeur : celle d'un `EaseInOut` sur un trajet seul, bornée
  par une fraction de l'enchaînement). Contrainte : un enchaînement d'un seul trajet reste identique à aujourd'hui.
- **Mesure commune de longueur perçue** pour Survol et Latéral, nécessaire pour une vitesse constante d'un mode à
  l'autre (la métrique du survol, `FlyoverLength`, est la référence).
- **Arrondi autour des repères** : méthode libre (fondu entre les deux trajets sur une fenêtre de temps autour de
  l'étape, courbe en log(largeur) et centre, …), à choisir en comparant des images extraites des vidéos.
- Disposition exacte de la case et texte précis de la ligne d'information.

## Vérification attendue

- Tous arrêts : images identiques à la version actuelle (test sur `PoseAtFrame`).
- Enchaînement A→B→C, B en passage : aucun quasi-arrêt autour de B (l'écart de pose entre images consécutives
  reste proche de la vitesse de croisière), pas de saut de direction.
- Pause non nulle ou dernière étape : arrêt forcé même si la clé dit le contraire.
- Aller-retour fichier : `Arret=0` relu ; ancien fichier sans la clé = tous arrêts.
- Durée totale du scénario inchangée par le passage d'une étape en mode passage.
