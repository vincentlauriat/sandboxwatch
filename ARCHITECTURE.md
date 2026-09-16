# Architecture — SandboxWatch

Miroir français de `ARCHITECTURE_EN.md`, qui fait foi. Les deux s'éditent dans le même tour.

**Ce qui existe aujourd'hui : le lot 1** — `SandboxWatchKit` et la CLI `sbw` en lecture seule.
Les lignes marquées *(lot 3)* ou *(lot 4)* sont conçues, pas construites : elles figurent ici
parce que la forme du Kit les suppose, pas parce qu'on les trouvera dans `Sources/`.

## Place dans la famille

```
Groupe de ressources Azure
├── web apps, plans, budget, attributions de rôles
└── AzureSandboxManager        Node 20, sans dépendance, identité managée, rôle Reader
    │                          collecte toutes les 10 min, diffe contre le snapshot précédent
    └── GET /api/v1/snapshot | /apps | /changes, POST /api/v1/refresh, GET /healthz
                                  ▲
                                  │ HTTPS, en-tête X-Sandbox-Token (Keychain)
                                  │
                       ┌──────────┴──────────┐
                       │    SandboxWatch     │  ce dépôt, sur le Mac
                       │  SandboxWatchKit    │
                       │   ├── sbw (CLI)     │
                       │   └── App (SwiftUI) │
                       └──────────┬──────────┘
                                  │ CLI az, identifiants de Vincent, tableaux d'arguments exacts
                                  ▼
                       start / stop / restart d'une web app
```

Deux transports, deux identités, délibérément. La lecture passe par le token de la sandbox, que le
serveur a borné à un rôle Reader. L'écriture passe par la session `az` de Vincent. Le token ne peut
jamais rien modifier.

## Composants

| Composant | Responsabilité | Dépend de |
|---|---|---|
| `SandboxStore` | L'inventaire YAML (`~/.config/sbw/sandboxes.yaml`). Aucun secret. | Yams |
| `TokenStore` | Le `SANDBOX_TOKEN` par sandbox, dans le Keychain. Protocole ; mocké en test. | Security.framework |
| `SandboxAPIClient` | Appels typés sur `/api/v1`. Chaque code de statut documenté devient un état modélisé. | `HTTPClient` |
| `SandboxAPIContract` | La moitié exécutable du contrat d'API. | — |
| Modèle `Snapshot` | Des sections dont la charge utile est inatteignable sans passer par leur statut. | — |
| `ChangeCursor` | Curseur `(at, type, subject)` par sandbox, avec détection de débordement. | — |
| `Doctor` | Le diagnostic à cinq verdicts. | `SandboxAPIClient` |
| `AzRunner` *(lot 3)* | Invocation d'`az` avec les trois gardes. | `ProcessRunner`, `SandboxAPIClient` |
| `ActionJournal` *(lot 3)* | Journal local append-only des actions d'écriture. | — |
| `sbw` | CLI mince au-dessus du Kit. | ArgumentParser |
| `App` *(lots 2 et 4)* | Menu bar + control center, linke le Kit en local. | SwiftUI |

## Seams

Tout effet de bord passe par un protocole, mocké en test :

- `HTTPClient` → `URLSessionHTTPClient` (prod) / `MockHTTPClient` (test)
- `TokenStore` → `KeychainTokenStore` (prod) / `InMemoryTokenStore` (test)
- `ProcessRunner` → `SystemProcessRunner` (prod) / `MockProcessRunner` (test) — *lot 3, quand
  `az` arrivera ; rien dans le lot 1 ne lance de sous-processus*

`swift test` ne touche donc ni le réseau, ni le Keychain, ni `az`. Les deux conséquences à
énoncer franchement : `KeychainTokenStore` et `URLSessionHTTPClient` sont les seuls types
qu'aucun test n'exécute — ils sont prouvés par l'usage, pas par la suite. C'est le pattern de
HomePortManager (`ProcessRunner` mocké dans tout `HomePortKitTests`), appliqué aux deux formes de
monde extérieur qu'a ce projet.

## Deux décisions structurantes

**La charge utile d'une section est inatteignable sans son statut.** Le serveur ne compare deux
snapshots que si les deux ont collecté la section avec succès, parce qu'un diff naïf annoncerait la
disparition simultanée de toutes les attributions de rôles à l'instant où un rôle Reader est révoqué.
Un client qui affiche une section `denied` comme « 0 attribution » réintroduit cette fausse alerte de
l'extérieur. Le modèle n'a donc pas de propriété `data` stockée : la charge utile vit dans le cas
`.ok`.

**Les actions d'écriture ont trois gardes.** Divergence d'abonnement (`az` pointe là où
`az account set` l'a laissé), péremption du snapshot (jusqu'à 10 minutes), et non-interactivité
(`az` ouvre un device-code flow qui pend indéfiniment sans TTY). Chaque garde est un test, pas une
convention.

## État sur disque

| Chemin | Contenu | Secret |
|---|---|---|
| `~/.config/sbw/sandboxes.yaml` | Inventaire : nom, URL, notes | non |
| Keychain `fr.lauriat.sandboxwatch` | Un token par sandbox | **oui** |
| `~/.config/sbw/cursors/<nom>.json` | Dernier changement vu | non |
| `~/.config/sbw/actions.jsonl` *(lot 3)* | Journal des actions d'écriture | non |
