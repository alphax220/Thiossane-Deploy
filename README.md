# Thiossane Deploy — Plugin Godot 4.x

**© 2026 Teranga Game Studio — Tous droits réservés.**

Plugin d’éditeur Godot pour **créer la fiche jeu**, **exporter**, **compresser en ZIP** et **envoyer** le build sur la plateforme **Thiossane Store**, sans passer par le formulaire web.

Compatible **Godot 4.2+**.

## Licence

Ce plugin est la propriété exclusive de **Teranga Game Studio**.

- Vous pouvez l’utiliser pour déployer vos jeux sur **Thiossane Store**.
- Toute redistribution, modification ou usage commercial hors de ce cadre est **interdit** sans autorisation écrite préalable.

Voir le fichier [LICENSE](LICENSE) pour les conditions complètes.

## Avertissement ressources de test

Le fichier `addons/thiossane_deploy/theme_circe_ref.jpg` **n’est pas la propriété de Teranga Game Studio**.  
Il s’agit uniquement d’une **référence visuelle pour les tests** (thème Circe).  
Cette image est disponible publiquement (recherche Google : `theme_circe_ref.jpg`).  
Elle ne doit pas être redistribuée comme asset du plugin ni utilisée en production.

## Installation

Structure attendue dans le projet :

```
TonProjet/
└── addons/
    └── thiossane_deploy/
        ├── plugin.cfg
        ├── plugin.gd
        ├── thiossane_dock.gd
        └── LICENSE
```

1. Copiez le dossier `thiossane_deploy` dans `addons/` de votre projet.
2. **Projet → Paramètres du projet → Plugins** → activez **Thiossane Deploy**.
3. Redémarrez l’éditeur si besoin.

Le panneau apparaît :
- en **dock à droite** de l’éditeur (onglet **Thiossane Deploy**, à côté de l’Inspecteur)
- via **Projet → Outils → Thiossane Deploy : afficher le dock**

## Interface (dock droit)

Flux pensé pour le workflow développeur :

1. **Connexion** — statut visible en tête, API + identifiants  
2. **Jeu à déployer** — sélection d’un jeu existant ou « Nouveau »  
3. **Fiche** — titre + version, description, catégorie/prix, options, champs optionnels  
4. **Plateformes** — cases + presets d’export  
5. **Déploiement** — bouton Launch principal, puis soumission modération + journal

Responsive (seuil ~380 px) : empilement auto des lignes email/mdp, titre/version, catégorie/prix et plateformes.

## Prérequis

- Compte développeur Thiossane (`ROLE_DEVELOPER`)
- Backend accessible (défaut `https://api.thiossane.store/api`)
- Presets d’export configurés + templates installés

## Licence / copyright

Copyright (c) 2026 **Teranga Game Studio**. Tous droits réservés.  
Voir le fichier [LICENSE](LICENSE) pour le texte complet de la licence.


## Changelog

### 1.9.37
- **Backgrounds d’ambiance par univers** : calque procédural derrière le dock (grille synthwave, pluie cyberpunk, digital rain Matrix, vagues océan, poussière western/teranga, speed lines manga, halftone comic, béton brutaliste, checker pixel, grain horror…).
- Teinte surface + vignette adaptées à chaque thème. Léger, tuilé, sans assets externes.

### 1.9.36
- **5 nouveaux univers** :
  - **Manga** — shōnen (noir, rouge sang, contrastes forts)
  - **Océan** — bleu profond, turquoise, écume
  - **Brutaliste** — béton, gris, angles à 0
  - **Western** — ocre, poussière, soleil brûlant
  - **Comic Book** — primaires rouge/bleu/jaune, vibe super-héros
- Sélecteur, i18n FR/EN/中文, éditeur, néon et FX ship mis à jour.

### 1.9.35
- **8 nouveaux univers de thèmes** :
  - **Teranga** — afrofuturisme (or, terre, nuit dakaroise)
  - **Synthwave** — Outrun 80s (rose/cyan, chrome)
  - **Cyberpunk** — Neo-Tokyo (noir, cyan fluo, glitch)
  - **Steampunk** — laiton / cuivre / industriel
  - **Horror CRT** — vert malade, rouge sang, scanlines (CRT auto)
  - **Minimal** — pro / store (blanc cassé, accent bleu)
  - **Pixel 8-bit** — coins durs, palette limitée
  - **Vaporwave** — rose pastel / turquoise
- Sélecteur, labels i18n (FR/EN/中文), éditeur de thème, néon, FX de ship et `valid_themes` mis à jour.

### 1.9.34
- **Correctif parse fatal** : variables `_fx_toggle_btn`, `_fx_panel` et `_fx_panel_open` utilisées sans déclaration → erreur « Identifier not declared » qui empêchait le chargement du script (et donc `plugin.gd` / `new()`).
- **Correctif thèmes gangster** : la liste de labels i18n du sélecteur de thème dans `_apply_ui_texts()` n’incluait pas `chicago30` / `gangster90` / `gangsta00`. Au changement de langue, les libellés étaient décalés (ex. « Custom » sur Chicago 1930). Ordre des labels aligné sur les `add_item()`.
- **Avis propriété** : mention explicite que `theme_circe_ref.jpg` n’est pas notre propriété (référence de test uniquement, image trouvée sur Google). Fichier `NOTICE_theme_circe_ref.txt` ajouté.

### 1.9.20
- **Graffiti urbain / RenderWare era** :
  - Tags procéduraux (RENDERWARE, NO CLIP, 2004, NFS, THIOSSANE CREW…).
  - Sprays aérosol + traits marker sur thèmes PS2 / Underground / CRT.
  - Refresh tags toutes les ~14 s.
  - Burst graffiti à la célébration de ship (SHIPPED / ONLINE / RESPECT).

### 1.9.19
- **PS2 / Underground** :
  - Thèmes **PS2** (phosphor green) et **Underground** (blood CRT) : radius bas, bordures dures, sans ombre soft.
  - Overlay **CRT** (scanlines + grain), toggle header.
  - **CRT motion** : confettis → flash + glitch + shake.
  - Mode **ARCADE** : copy workflow type menu console (PRESS DEPLOY, SYSTEM NOMINAL…).
  - Toggle **SFX** : bips générés (clic / confirm / erreur / ship).

### 1.9.17
- **Preflight bloquant** : auth, jeu, titre, version (format), plateformes, presets — panneau d’erreurs avant Launch.
- **Historique des deploys** (local, 40 entrées) dans la section Déploiement.
- **Notification desktop** en fin de ship (Linux notify-send / Windows balloon / macOS).
- **Statuts store enrichis** : draft / pending / approved / rejected / suspended + note de modération.
- **Liens prêts à coller** : page store, blurb Discord, blurb WhatsApp.

### 1.9.16
- **FX intégrés au workflow** (plus besoin de cliquer Chaos) :
  - Login / fiche → pulse + étincelles.
  - Launch deploy → ignition 🚀, secousse, sparkles.
  - Export / upload → glow barre de progression + énergie.
  - Ship réussi → FX auto selon thème (Matrix rain, T-800, explode, burn) + titre « IMPACT DÉPLOYÉ ».
  - Jalons 1 / 5 / 10 / 25 / 50 / 100 → FX epic + 🏆.
  - Échec export → shake rouge.
  - Bouton célébration = « Rejouer l’impact » (pas un Chaos manuel).

### 1.9.15
- **Éditeur de thème avancé** (bouton 🎨) :
  - 14 couleurs éditables en live (primary, surface, card, border, text, ok, err…).
  - Formes : radius cartes / boutons / champs, largeur bordure, ombre, alpha ombre, delta police.
  - Actions rapides : inverser, éclaircir, assombrir, saturer, désaturer, aléatoire.
  - Presets nommés persistés, import/export JSON (presse-papiers).
  - Thème **Custom** dans le sélecteur + base depuis Circe/Sakura/Matrix/etc.

### 1.9.14
- **Predator / Terminator / Matrix** :
  - Thème **Matrix** : logs en langage Yautja (*click-click*, glyphes), statut busy style « TARGET ACQUIRED », mascotte en mode chasseur / T-800 / Neo.
  - Chaos FX **🟢 Matrix** : pluie digitale (01 + katakana + glyphes), glitch vert, « Wake up, Neo ».
  - Chaos FX **🤖 T-800** : HUD rouge, scanlines, barre de scan, « TARGET ACQUIRED / I'LL BE BACK ».
  - Succès deploy (thème Matrix) : « TERMINATED », « Hasta la vista, bugs ».

### 1.9.13
- **Thèmes Circe / Asereth** (inspirés de l’esthétique rouge profond, perles & sakura) :
  - Nouveau thème par défaut **Circe** : cramoisi profond, contrastes élégants rouge / blanc / noir.
  - Variantes : **Sakura** (rose poudré), **Onyx** (nuit noire), **Ivoire** (kimono clair), **Ember** (braises).
  - Conservés : Matrix, Forest.
  - Compatibilité des anciennes configs (default / sunrise / sepia mappés vers les nouveaux).

### 1.9.12
- **Responsive dock** :
  - Header : titre sur sa ligne + barre d’outils en `HFlowContainer` (wrap auto des boutons).
  - Empilement email/mdp, titre/version, catégorie/prix, cases options, plateformes sous ~340 px.
  - Marges, tailles de police et hauteurs de journal adaptées (narrow / compact).
  - `custom_minimum_size` du dock abaissé à 260 px ; scroll horizontal désactivé, contenu qui suit la largeur.
  - Champs (LineEdit, presets) sans largeur min forcée pour éviter le débordement.

### 1.9.11
- **Fix UI noire après Brûler 🔥** : les tweens en boucle (modulate charbon) continuaient après restore.
  - Tous les tweens Chaos sont trackés et tués dans `_chaos_restore`.
  - Restore force immédiatement `modulate` / position / scale / rotation sauvegardés.
  - Couleur « charred » adoucie (brun chaud, alpha 1.0) au lieu de noir transparent.
  - Même correction appliquée à Explode / Freeze / Urgence (alpha modulate toujours 1.0).

### 1.9.10
- **Chaos FX dans le workflow** :
  - Bouton **💥 Célébrer en Chaos** sur la carte de célébration après un deploy réussi (effet soft + auto-restore).
  - Option **Après deploy** dans le menu Chaos (persistée).
  - Suggestion discrète pendant les longs uploads (`busy_tip_chaos`).
  - Astuce Chaos à la fin de l’onboarding (premier upload réussi).
- Chaos soft (`_chaos_start_soft`) : intensité plafonnée, durée courte, auto-restore forcé pour ne pas bloquer le flow pro.

### 1.9.6
- **Chaos FX** : bouton 💥 FX — exploser, brûler ou geler l’interface avec fumée / braises / gel.
- Restauration auto après quelques secondes, ou clic ♻ Restaurer.


### 1.9.5
- **Onboarding première session** : panneau guidé 5 étapes (connexion → jeu → fiche → plateformes → deploy).
- Checklist cliquable, message « prochaine action », empty state jeux.
- Progressive disclosure : marketing, support et wellbeing masqués jusqu’à fin d’intro (ou « Passer »).
- Fin auto après le premier upload réussi ; préférence `onboarding_done` persistée.


### 1.9.4
- **Progression upload fine** : Mo envoyés / total, débit (Mo/s, moyenne EMA), temps restant estimé.
- Ligne de détail sous la barre de progression ; tag « ↩ Reprise » si chunks déjà reçus côté serveur.
- Feedback à l’init en cas de reprise + message d’interruption avec volume déjà envoyé.
- Correctif : après refresh token 401 pendant un chunk, **reprise automatique** de l’upload (au lieu de relancer tout le flux auth).

### 1.9.3
- Correctif signal `toggled` / `_on_section_toggled_for_notif` (ordre des arguments `.bind()`).


### 1.9.2
- **Tokens unifiés** : `core/config.gd` devient la source de vérité (format `open_encrypted` + `store_var`).
  - Migrations automatiques depuis l’ancien format JSON+passphrase et depuis les tokens en clair du `.cfg`.
  - Le dock délègue load/save/clear — plus de logique dupliquée.
- **ui/styles.gd** : helpers de style (carte, boutons primaire/secondaire/succès, champs) paramétrés par palette.
- **Structure** : dossiers `features/` et `wellbeing/` documentés pour les prochaines extractions.
- Correctif de cohérence entre le module core et le dock (sessions tokens préservées).

### 1.9.1
- Bugfix packaging / stabilisation.


### 1.7.5
- **Pause 3D multi-activités** : café, coca, pizza, cigarette, marijuana (animations dans le dock).
  - Menu de choix avant l’animation.
  - **Avertissements santé** pour cigarette et marijuana.
  - **Rappel légal** : dans de nombreux pays, la marijuana est illégale ; scènes purement fictives.
  - FR / EN / 中文.

### 1.7.4
- **Playlist musique** : liste de titres, ajout multi-fichiers, retirer / vider, précédent / suivant.
  - Double-clic (ou Entrée) sur un titre pour le lire.
  - Fin de piste → titre suivant ; option Boucle pour relancer la playlist.
  - Playlist persistée entre les sessions.
  - FR / EN / 中文.

### 1.7.3
- **Section Avancé · Vidéo** : lecteur vidéo dans le dock (wellbeing) pour un export long.
  - Lecture native **.ogv** (Ogg Theora) dans le panneau.
  - Bouton **Lecteur système** pour MP4 / WebM / MKV etc.
  - Contrôles : play/pause, stop, boucle, volume, seek, choix de fichier.
  - Textes FR / EN / 中文.

### 1.7.2
- **Chinois (中文)** : interface complète FR / EN / 中文 (bouton de langue en cycle).
- **Clarté du langage** : messages d’erreur orientés action (« Session expirée — reconnectez-vous », export/preset, réseau). Journal utilisateur sans codes HTTP bruts ; détails techniques en console uniquement.
- **Organisation du code** : i18n extrait dans `i18n/strings.gd`, socle `core/` (constants, config). Voir [STRUCTURE.md](STRUCTURE.md).



### 1.6.0
- **Support tickets** : nouvelle section « 8 · Support » dans le dock.
- Création de tickets avec nature du problème (plugin/déploiement, compte, paiement, versements, modération, téléchargement, contenu, API, suggestion, autre).
- Liste de vos tickets + fil de conversation + réponses.
- Contexte technique auto (version Godot, OS, game_id) joint au ticket.
- Côté store : onglet **Tickets support** pour admin & modérateurs (réponse, statut, réaffectation de catégorie).

### 1.5.0
- **Cartes par étape** : chaque section (connexion, jeu, fiche, plateformes, déploiement, marketing, journal) est une carte avec ombre et coins arrondis.
- **Sections repliables** : clic sur le titre ▾/▸. Marketing fermé par défaut ; journal et déploiement s’ouvrent pendant une opération.
- **Champs unifiés** : LineEdit, TextEdit, OptionButton et SpinBox stylés comme les boutons (surface, bordure, focus or, hauteur 42).
- **Pastille ronde** de connexion ; plus de doublon « Non connecté ».
- **Moins d’emojis** dans les labels (titres, boutons, journal).

### 1.4.6
- **Espacement aéré** : marges dock 12 px, séparation verticale 14 px, écarts entre boutons côte à côte 10–12 px.
- **Boutons plus confortables** : hauteur min 42–54 px, padding horizontal accru, Connect plus large que Logout.

### 1.4.5
- **Mascotte responsive** : largeur de bulle adaptée à la largeur du dock (min 120 → max 210 px), texte qui se réajuste au resize, position recalculée.
- **Animations mascotte** : entrée/sortie plus fluides (cubic), flottement idle en boucle, gags (wiggle, squash, hop, clin d’œil) plus polis.
- **Boutons raffinés** : ombres soft, radius plus généreux, hover lumineux avec glow or, états pressed/disabled plus nets — primaire, Launch et secondaires.

### 1.4.4
- **Mascotte corrigée** : layout VBox (bulle + sprite), ancrée en bas-droite, plus de positions aléatoires cassées ni de flip horizontal.
- **Célébration + Streak** : après un déploiement réussi, overlay confettis + lion, compteur de ships de la semaine et total (persisté). Bouton « Continuer » + copie rapide du lien store.

### 1.4.3
- **Scroll fluide** : au clic (feedback, sections), le dock glisse en douceur (cubic ease-out) au lieu de sauter.

### 1.4.2
- **Mascotte Thiossane** : le lion couronné apparaît de temps en temps dans le dock, sort une réplique (FR/EN), fait un hop bizarre, puis repart.
- Clic sur la mascotte = nouvelle phrase + prolongement de la visite.
- Sprites `mascot_lion.png` / `mascot_head.png` (fond transparent).

### 1.4.1
- **UI Thiossane Store** : palette terre / or africaine (`#e8b94a`, surfaces brunes) alignée sur le store.
- **Boutons unifiés** : primaire or + texte brun, secondaire surface + bordure, radius 10 px (comme `.confirm-btn` / `.btn-secondary`).
- Titres de section et journal restylés pour cohérence visuelle.

### 1.4.0
- **Upload résumable** : envoi par chunks (2 Mo), reprise après coupure, limite 512 Mo affichée.
- **Stockage sécurisé des tokens** : `access_token` / `refresh_token` chiffrés hors du `.cfg` (`user://thiossane_tokens.dat`, clé dérivée machine).
- **Marketing** : campagnes + canaux sur les ShareLinks, analytics clics → ventes attribuées (`/api/developer/marketing/analytics`).



### 1.3.9
- **ShareLink** : nouvelle section « Liens de partage » dans le dock.
- Génération / récupération du lien tracké via `POST /api/developer/games/{id}/share-link`.
- Affichage du lien public (URL store + `game.html?id=&ref=`), stats clics / uniques.
- Boutons copier : lien brut, message WhatsApp prêt, caption TikTok.
- Stats globales développeur via `GET /api/developer/share-stats`.
- Champ configurable **URL store** (persisté dans la config plugin).



### 1.3.1
- **UI feedback** : bannière d’état colorée (ok / erreur / warning / busy / idle) sous le header.
- **Indicateur connexion** : pastille + libellé (vert / rouge).
- **Boutons stylés** : primaire (bleu), succès Launch (vert), secondaire (gris).
- **Journal** : préfixes ✔ ✖ ⚠ • … + bouton Effacer.
- **Messages action** : chaque validation et chaque étape du pipeline a un feedback précis et coloré.
- Section « Progression & journal » plus lisible.

### 1.3.0
- **Sécurité upload** : le JWT n’est plus passé en query string (`?bearer=…`) — uniquement via `Authorization` / `X-Access-Token`.
- **Refresh token** : en cas de HTTP 401, tentative automatique de `POST /api/token/refresh` puis reprise du flux.
- **Messages d’erreur** : extraction de `message` / `detail` / `hydra:description` / violations API Platform.
- **Login** : affichage immédiat du profil renvoyé par `/api/login` + alerte si le rôle n’est pas développeur.
- **Catégories** : en cas d’échec HTTP, le flux continue vers le chargement des jeux.
- **Upload** : avertissement si le build dépasse ~200 Mo ; nettoyage du ZIP temporaire après succès.
- **Export CLI** : logs plus clairs en cas d’échec (templates / nom de preset).
- Correction d’indentation dans le parsing des presets d’export.
