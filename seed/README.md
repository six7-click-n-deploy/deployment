# Seed Data

Lädt eine realistische Beispiel-Konfiguration in Keycloak und in die
Backend-Datenbank, damit die App-Store-UI nach dem ersten Hochfahren
nicht leer ist.

## Was angelegt wird

### Keycloak (Realm `dhbw`)

| Rolle    | User                                                                    |
| -------- | ----------------------------------------------------------------------- |
| Admin    | Tobias Admin                                                            |
| Teacher  | Henning Pagnia, Michael Eichberg, Sarah Detzler, Frank Hubert,          |
|          | Andrea Bauer, Thomas Wagner                                             |
| Student  | Luca Bäck, Felix Erhard, Raphael Plett, Mika Jun, Okan Sömnez,          |
|          | Leon Priemer, Tom Weber, Monika Piano, Iven Stahl (alle WI SE B 23)     |
|          | + 10 weitere Studierende verteilt auf WI SE B 24, INF TI 23, WI SE A 23 |

- **Login-Format:** `<vorname>.<nachname>@dhbw.de`
  (Umlaute → `ae/oe/ue/ss`, Bindestriche/Leerzeichen entfernt)
- **Passwort:** `1234` (nicht temporär)

### Backend-DB

- 4 Kurse: `WI SE B 23`, `WI SE B 24`, `INF TI 23`, `WI SE A 23`
- Professoren als Course-Teacher verlinkt (Many-to-Many)
- Studenten via `users.courseId` ihrem Kurs zugewiesen
- 14 Apps (Mischung aus Prof- und Studi-Ownership, public/private):
  - **Prof-Apps (Lehr-Sandboxes):**
    - **Online IDE** (Eichberg, public) — 8 Versionen, gemischt approved/pending/rejected
    - **Web-LaTeX** (Detzler, public) — 3 Versionen
    - **Jupyter Notebook** (Pagnia, public) — 1 Version pending
    - **pgAdmin** (Hubert, public) — 1 Version approved
    - **Ubuntu Sandbox** (Bauer, public) — 3 Versionen
    - **Test-App (Template-Spielwiese)** (Admin, private)
    - **My Custom Stack (WIP)** (Eichberg, private)
  - **Studenten-Apps:**
    - **Luca's IDE Fork** (Luca Bäck, public) — 1× APPROVED + 1× PENDING
    - **Felix's LaTeX Vorlage** (Felix Erhard, public) — PENDING
    - **Raphael's Notebook-Stack** (Raphael Plett, private)
    - **Tom's Ubuntu mit Docker** (Tom Weber, public) — REJECTED (Klartext-API-Key)
    - **Monika's Test-Sandbox** (Monika Piano, private)
    - **Iven's PostgreSQL Lab** (Iven Stahl, public) — APPROVED
    - **Anna's Web-LaTeX** (Anna Schulz, public) — PENDING
- Realistischer Mix aus `APPROVED`, `PENDING`, `REJECTED`
  Approvals mit Notes und Rejection-Reasons

## Aufruf

```bash
cd deployment
make dev-up           # Falls noch nicht gestartet
make seed-data
```

Das Makefile-Target kopiert das Skript in den Backend-Container und
führt es dort aus (so muss lokal kein Python-Setup vorhanden sein).

### Direktaufruf (alternativ)

```bash
docker compose -f docker-compose.dev.yml cp \
  ./seed/seed_data.py backend:/tmp/seed_data.py
docker compose -f docker-compose.dev.yml exec backend \
  python /tmp/seed_data.py
```

## Idempotenz

Mehrfaches Ausführen ist unkritisch:

- User werden über `email` (exakte Übereinstimmung) gefunden und nur
  ergänzt, nicht dupliziert.
- Kurse werden über `name` gefunden.
- Apps werden über `name` gefunden, Beschreibung/Visibility werden
  bei jedem Lauf neu gesetzt.
- Approval-Records werden über `(appId, version_tag)` upsert-artig
  aktualisiert.

Passwörter werden bei jedem Lauf auf den Default zurückgesetzt — so
ist nach dem Seed garantiert, dass `1234` funktioniert.

## Voraussetzungen

- `make dev-up` hat Keycloak und das Backend hochgefahren.
- Keycloak-Admin-Account `admin/admin` (Default) ist erreichbar.
  Davon abweichende Credentials per `KEYCLOAK_ADMIN_USER` /
  `KEYCLOAK_ADMIN_PASSWORD` setzen.
- Die `dhbw`-Realm-Konfiguration ist importiert (Realm-Rollen
  `admin`, `teacher` müssen existieren — beides aus
  `keycloak/realm-export.json`).
