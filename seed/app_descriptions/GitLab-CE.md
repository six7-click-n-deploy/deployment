# GitLab CE – Individuelle Git-Umgebung pro Student

Deployt für jedes Team eine eigene GitLab CE Instanz. Jeder Student erhält einen
persönlichen Account mit individuellem Passwort und ein vorbereitetes Starter-Repository.

## User-Management

Ein Account pro Student, isoliert innerhalb der Team-VM. Alle Studenten eines Teams
teilen dieselbe GitLab-Instanz, haben aber getrennte Namespaces und Repositories.
Zugangsdaten (URL, Benutzername, Passwort) werden automatisch per Mail zugestellt.

## VM-Deployment

Es wird **eine VM pro Team** deployed. Bei 3 Teams entstehen 3 VMs, jede mit eigenem
GitLab CE und eigener Floating IP.

## Deployment-Dauer

| Phase | Dauer |
|---|---|
| VM-Start + cloud-init | 2–3 Min |
| GitLab-Dienste hochfahren | 8–12 Min |
| User- und Repository-Anlage | 1–3 Min |
| **Gesamt** | **11–18 Min** |

> Nach `terraform apply` ist die Instanz erst erreichbar wenn alle Schritte abgeschlossen
> sind — ein sofortiger Aufruf der URL zeigt noch einen 502-Fehler.

## Konfigurierbare Variablen

| Variable | Beschreibung | Pflicht |
|---|---|---|
| `flavor_name` | VM-Größe — Standard: `gp1.large` mit 4 GB RAM (nicht unterschreiten) | Nein |
| `assignment_files` | ZIP-Datei mit Starter-Repository | Ja |

### Starter-Repository (`assignment_files`)

Über `assignment_files` muss ein ZIP hochgeladen werden, das beim Deployment als
Starter-Projekt für jeden Studenten in GitLab importiert wird.

**Anforderungen an das ZIP:**
- Format: `.zip` (kein `.tar.gz`, kein `.rar`)
- Struktur: Das ZIP muss genau ein Oberverzeichnis enthalten (z.B. `mein-projekt/`),
  dessen Inhalt als Repository-Root verwendet wird
- Empfohlene Maximalgröße: < 10 MB
- Enthält das ZIP kein gültiges Verzeichnis, wird ein eingebautes Fallback-Projekt verwendet

## Wichtige Hinweise

- Studenten loggen sich mit ihrer **E-Mail-Adresse** als Benutzername ein
- Signup ist deaktiviert — nur vorab angelegte Accounts können sich einloggen
- Das Deployment ist sehr ressourcenintensiv. Der Flavor sollte daher gp1.medium nicht unterschreiten
