# Installation — Thiossane Deploy (Godot 4.2+)

## Structure OBLIGATOIRE

Dans le projet Godot ouvert :

```
TonProjet/
└── addons/
    └── thiossane_deploy/
        ├── plugin.cfg
        ├── plugin.gd
        ├── thiossane_dock.gd
        └── LICENSE
```

⚠️ Ne pas laisser un dossier en trop (ex. `addons/thiossane_deploy/thiossane_deploy/`).

## Étapes

1. **Fermez Godot** (recommandé).
2. Copiez le dossier `thiossane_deploy` dans `addons/` de votre projet.
3. Ouvrez le projet dans Godot 4.2+.
4. Menu **Projet → Paramètres du projet → Plugins**.
5. Trouvez **Thiossane Deploy** et cliquez **Activer** (Enable).
6. Regardez le **dock de droite** (à côté de *Inspecteur*) : onglet **Thiossane Deploy**.

### Si l’onglet n’apparaît pas

- **Projet → Outils → Thiossane Deploy : afficher le dock**
- Ou désactivez / réactivez le plugin dans les paramètres.
- Ouvrez **Débogage → Erreurs** (ou la console éditeur) : un message rouge `[Thiossane Deploy]` indique un problème de chemin ou de syntaxe.

### Checklist rapide

| Vérification | OK ? |
|--------------|------|
| Godot **4.2 ou plus** | |
| Fichier `res://addons/thiossane_deploy/plugin.cfg` visible dans le FileSystem | |
| Plugin **Activé** dans Projet → Paramètres → Plugins | |
| Onglet à **droite** (pas en bas) | |
| Menu Projet → Outils contient l’entrée Thiossane | |
