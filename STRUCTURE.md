# Organisation du code — Thiossane Deploy v1.9.40

## Structure

```
addons/thiossane_deploy/
├── plugin.cfg / plugin.gd
├── thiossane_dock.gd          # Orchestrateur UI + logique
├── i18n/strings.gd            # FR / EN / 中文
├── core/
│   ├── constants.gd
│   └── config.gd              # ConfigFile + tokens chiffrés
├── features/
│   ├── api_client.gd          # HTTP helpers, erreurs humaines
│   ├── deploy.gd              # Export CLI, ZIP, SHA-256, état upload
│   ├── profiles.gd            # Profils plateformes + presets
│   └── share.gd               # Share-links + Ambassadeurs (API helpers)
├── ui/styles.gd
└── wellbeing/                 # (prévu) musique, mascotte…
```

## v1.9.40 — Ambassadeurs

1. Module `features/share.gd` (`ThiossaneShareApi`) — chemins & bodies share + ambassador.
2. Section UI **Ambassadeurs** dans Marketing (email, libellé, invitation, génération, copie, stats).
3. `ReqKind` : `AMBASSADOR_CREATE`, `AMBASSADOR_LIST`, `AMBASSADOR_STATS`, `AMBASSADOR_REVOKE`.
4. i18n FR / EN / 中文.

## v1.9.38 — valeur développeur

1. **Validation pré-export** — messages actionnables.
2. **Reprise upload après crash** — état JSON disque + SHA-256 local.
3. **Profils de déploiement** — sauver/charger plateformes + presets.
4. **File multi-plateformes visible**.
5. **Extraction** — `api_client.gd`, `deploy.gd`, `profiles.gd`.
