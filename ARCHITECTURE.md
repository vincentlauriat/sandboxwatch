# Architecture — SandboxWatch

Miroir français de `ARCHITECTURE_EN.md`, qui fait foi. Les deux s'éditent dans le même tour.

**Ce qui existe aujourd'hui : le lot 1** — `SandboxWatchKit` et la CLI `sbw` en lecture seule.
Les lignes marquées *(lot 4)* sont conçues, pas construites : elles figurent ici
parce que la forme du Kit les suppose, pas parce qu'on les trouvera dans `Sources/`.

## Diagrammes

Deux diagrammes interactifs accompagnent ce document. Ce sont des fichiers HTML autonomes — à
ouvrir dans un navigateur ; la spécification dont chacun est issu se trouve à côté de lui.

| Diagramme | Ce qu'il montre |
|---|---|
| [`docs/diagrams/architecture.html`](docs/diagrams/architecture.html) | Les deux transports et les deux identités : ce qui lit sous le token borné à Reader, ce qui écrit sous la session `az` de Vincent, et quelles boîtes sont conçues plutôt que construites. |
| [`docs/diagrams/change-cursor.html`](docs/diagrams/change-cursor.html) | Comment `sbw changes` décide ce qui est nouveau — la marque `(at, type, subject)`, l'élargissement après un débordement, et le signalement qui remplace une troncature silencieuse. |

Pour en régénérer un, éditer son `.json` et le repasser par la skill `archify`. Le HTML est
l'artefact livré, pas un fichier à modifier à la main.

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
| `AzRunner` | L'argv exact d'`az`, en un seul endroit. | `ProcessRunner` |
| `ActionGuards` | Les trois gardes, sous forme de valeurs. | `ProcessRunner`, `SandboxAPIClient` |
| `ActionJournal` | Journal local append-only des actions, refus compris. | — |
| `SandboxAction` | Une action d'écriture de bout en bout : gardes, texte de confirmation, journal. | `ActionGuards`, `AzRunner`, `ActionJournal` |
| `OverviewRow` | Une ligne de centre de contrôle par sandbox. Les compteurs sont optionnels exprès. | `WatchPresentation` |
| `sbw` | CLI mince au-dessus du Kit. | ArgumentParser |
| `App` *(lots 2 et 4)* | Menu bar + control center, linke le Kit en local. | SwiftUI |

## Seams

Tout effet de bord passe par un protocole, mocké en test :

- `HTTPClient` → `URLSessionHTTPClient` (prod) / `MockHTTPClient` (test)
- `TokenStore` → `KeychainTokenStore` (prod) / `InMemoryTokenStore` (test)
- `ProcessRunner` → `SystemProcessRunner` (prod) / `MockProcessRunner` (test)

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
| `~/.config/sbw/cursors/<nom>.json` | Dernier changement rapporté par `sbw changes` | non |
| `~/.config/sbw/cursors-watch/<nom>.json` | Dernier changement rapporté par `sbw watch` | non |
| `~/.config/sbw/cursors-app/<nom>.json` | Dernier changement rapporté par l'app | non |
| `~/.config/sbw/liaison/<nom>.json` | État de liaison confirmé de `sbw watch`, pour l'anti-rebond | non |
| `~/.config/sbw/liaison-app/<nom>.json` | État de liaison confirmé de l'app | non |
| `~/.config/sbw/actions.jsonl` | Journal des actions, refus compris — **un seul, partagé** | non |

Le journal n'est volontairement **pas** découpé par surface, contrairement aux curseurs et à l'état
de liaison. Un curseur se consomme : la surface qui l'avance prive les autres. Une entrée de
journal ne se consomme pas, et ce qu'on veut est justement une trace unique de tout ce qui a été
fait à la sandbox, quelle que soit la surface qui l'a fait.

### Les trois gardes, dans cet ordre

`ActionGuards.check` les exécute toutes les trois avant qu'un seul processus `az webapp` existe,
et rend un `ActionContext` ou un `ActionRefusal` — une valeur, parce qu'un refus est un état que
la CLI imprime et que l'app montre dans une feuille.

1. **Non-interactivité**, en premier. `az account show --query id --output tsv --only-show-errors`.
   C'est le refus le moins cher et le plus certain, et rien ne doit toucher le réseau tant qu'`az`
   n'a pas prouvé qu'il peut répondre. Mesuré le 2026-09-18 : déconnecté, cette commande sort en 1
   avec un stdout vide et n'ouvre aucun flux device-code.
2. **Fraîcheur.** `POST /api/v1/refresh`, puis lecture de *cette* réponse — pas du relevé
   d'avant. Quand le serveur limite la cadence et renvoie `X-Refresh-Skipped: true`, le drapeau
   remonte jusqu'à la confirmation. Une invite qui le cacherait laisserait croire à un état
   fraîchement vérifié, la seule chose que cette garde existe pour garantir.
3. **Abonnement.** L'`identity.subscriptionId` du relevé contre ce qu'`az` a répondu. `az` pointe
   là où `az account set` l'a laissé, ce qui n'a rien à voir avec la sandbox affichée.
   `--subscription` est ensuite passé explicitement à l'action, pour que la garde vérifie une
   valeur qu'elle utilise aussi.

Les gardes tournent **une seule fois** par action. Le contexte contre lequel on confirme est celui
contre lequel l'action part ; vérifier deux fois romprait la promesse de la deuxième garde.


Trois lecteurs, trois notions de « depuis la dernière fois que j'ai regardé ». Un curseur partagé
laisserait un watch en tâche de fond consommer ce qu'un `sbw changes` manuel était dû — la surface
qui lit le plus souvent ferait taire les autres. `SandboxWatcher.poll` reçoit donc son `CursorStore`
en paramètre et n'en choisit jamais un lui-même.

**L'état de liaison suit la même règle, un cran plus haut, et l'enjeu y est plus grand.** `poll`
persiste sa décision sans condition : un `liaison/` partagé laisserait la surface qui relève en
premier confirmer le nouvel état, et la seconde comparerait le même ensemble à lui-même, conclurait
que rien n'a changé, et se tairait. Un événement manqué est une gêne. Une transition manquée, c'est
l'incident fondateur du projet.
