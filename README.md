# Signet

Application de suivi de lecture pour iPhone (livres lus, en cours, envies), en un seul fichier HTML. En français et en anglais.

**Ouvrir l'app :** https://laurentureta.github.io/Ex-Libris/ (dans Safari, puis Partager → « Sur l'écran d'accueil »)

- Chargement : un livre en 3D qui s'effeuille, avec barre de progression
- La Galerie : carrousel 3D de couvertures, reflets, profondeur de champ
- Le Feuilletage : page tournée en WebGL avec ombres et papier
- L'Étagère : dos de livres sur étagères en bois, recherche, extraction en 3D
- Scan des livres par code-barres ISBN ou QR code, recherche Google Books / Open Library
- Carnet : note en demi-étoiles, avis, dates, citations
- Sessions de lecture chronométrées, vitesse de lecture, série de jours
- Bilan : objectif annuel, carte de chaleur, livres par mois, auteurs favoris, image « Mon année » à partager
- Suppression en poussière avec annulation, sauvegarde / restauration en fichier
- Cartes holographiques à collectionner (bronze, argent, or, légendaire) : reflets qui suivent l'inclinaison, verso, partage
- Packs du grimoire : 476 livres à collectionner en cartes communes, rares, épiques, légendaires et mythiques, parfois brillantes. On déchire le paquet au doigt, puis chaque carte se retourne avec sa mise en scène (éclairs pour les épiques, rayons d'or pour les légendaires, arc-en-ciel pour les mythiques). Un pack par jour, un par livre terminé, un par sceau de quête, un pack doré par niveau ; les doublons deviennent des éclats d'encre qui révèlent les livres manquants
- Salle de lecture en 3D (WebGL) : une grande bibliothèque à galerie (on peut y monter), colonnes de marbre, voûte à caissons, cheminée, des milliers de livres, lustres et bougies flottantes. On regarde au doigt, on touche le sol pour avancer, on touche un de ses livres pour l'ouvrir
- Édimbourg en vrai derrière la vitre : la vue depuis Princes Street sur Castle Rock et le château, avec les vrais bâtiments d'OpenStreetMap (18 000 contours) et le relief réel ; le ciel suit l'heure et la météo réelles d'Édimbourg (pluie, neige, brume), château illuminé la nuit
- Quêtes du grimoire : 20 sceaux à gagner, des niveaux de lecteur, et des objets qui apparaissent dans la salle (globe, horloge, chat près du feu, lucioles, aurore boréale…)
- Rappels de lecture : une notification à l'heure choisie, seulement les jours où l'on n'a pas encore lu (Signet doit être ajouté à l'écran d'accueil)
- Ma bibliothèque publique : un lien à partager, que vos amis ouvrent sans compte
- Scanner une étagère entière (expérimental) : une photo des dos de livres, puis on coche ceux à ajouter
- Globe des voyages : les lieux des histoires sur un globe doré, avec les routes entre vos lectures
- Story « Mon année » : récap animé façon grimoire, prêt à partager
- Mes goûts de lecture : à la première ouverture, comme sur une plateforme de films, on choisit ses genres et ses livres préférés (modifiable dans Réglages)
- Le secret du grimoire : secouez l'iPhone n'importe où, le sceau se brise et révèle un livre choisi d'après vos goûts (catalogue de 476 livres, 18 genres)
- L'oracle : le grimoire choisit votre prochaine lecture parmi vos envies
- Ex-libris : sceau de cire personnel (initiales, emblème, couleur de cire)
- Saisons (neige, pétales, lucioles, feuilles) et bougie du soir qui suit le doigt
- Fonctionne hors ligne : l'app s'ouvre instantanément depuis le téléphone et se met à jour en arrière-plan
- Compte Signet (clé secrète) : sauvegarde en ligne et synchronisation entre appareils, couvertures comprises
- Club de lecture : code ami, lectures des amis, défis communs avec classement (dans Bilan → Club)
- Import Goodreads / Babelio (export CSV), recherche automatique des couvertures
- Citation en photo : on photographie une page et on surligne la phrase au doigt
- Séance d'ambiance : minuteur plein écran, pluie, cheminée, café ou forêt, lumière qui se réchauffe le soir
- Le grimoire te conseille : suggestions de livres d'après vos coups de cœur
- Rangement : sagas et tomes, étiquettes, livres prêtés, filtres sur l'étagère

Le serveur de synchronisation (Supabase) se crée avec le script `supabase/signet.sql`.

La salle 3D utilise [three.js](https://threejs.org) r170 (licence MIT), fourni dans `three-r170.module.min.js`.
Les bâtiments d'Édimbourg (`edinburgh3d.json`) viennent d'OpenStreetMap : © OpenStreetMap contributors (ODbL), © OpenMapTiles.
