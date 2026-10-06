# features/ — modules métier (v1.9.40)

Extractions depuis `thiossane_dock.gd` :

| Module | Rôle |
|--------|------|
| `api_client.gd` | URL, headers auth, erreurs réseau/API humaines, parse JSON |
| `deploy.gd` | Export CLI, ZIP, SHA-256, état upload persistant (reprise crash), inspection presets |
| `profiles.gd` | Profils de déploiement nommés (plateformes + presets) |
| `share.gd` | **Share-links + Ambassadeurs** — chemins API, corps JSON, validation email, URL store |

## Contrats

- Modules `RefCounted` / `class_name` — **pas de nœuds scène**.
- Les `HTTPRequest` restent dans le dock (arbre éditeur).
- Chaque extraction reste rétro-compatible (même comportement utilisateur).

## Ambassadeurs (v1.9.40)

Endpoints backend branchés dans le dock (section Marketing) :

| Action | Méthode | Route |
|--------|---------|-------|
| Créer lien | POST | `/developer/games/{id}/ambassador-links` |
| Liste | GET | `/developer/ambassador-links` |
| Stats | GET | `/developer/ambassador-stats` |
| Révoquer | POST | `/developer/ambassador-links/{id}/revoke` |
| Clic public | POST | `/ambassador/{token}/click` |

Helpers : `ThiossaneShareApi.ambassador_*`

## Prochaines extractions

- `auth.gd` — login, refresh token, profil
- `support.gd` — tickets
- `notifications.gd` — badges & polling
