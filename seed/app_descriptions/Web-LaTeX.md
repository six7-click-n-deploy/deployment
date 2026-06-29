# Web-LaTeX Editor

Ein browserbasierter LaTeX-Editor, der pro Team eine dedizierte VM mit vollständiger
LaTeX-Umgebung, Syntax-Highlighting und Live-PDF-Preview bereitstellt. Nutzer melden
sich mit ihren persönlichen Zugangsdaten an und arbeiten in einem isolierten Workspace.

## User-Management

Jeder Nutzer erhält einen individuellen Account mit E-Mail-Adresse als Benutzername
und einem automatisch generierten Passwort. Die Zugangsdaten werden nach dem Deployment
per Mail versendet. Innerhalb eines Teams teilen sich alle Nutzer dieselbe VM, arbeiten
aber in voneinander getrennten Workspaces — jeder Nutzer hat sein eigenes Projektverzeichnis.

## VM-Deployment

Es wird **eine VM pro Team** deployed. Bei zwei Teams entstehen zwei VMs.
Alle Nutzer eines Teams greifen auf dieselbe VM zu, erreichen den Editor jedoch
auf individuellen Ports (ab Port 8080, aufsteigend pro Nutzer).

## Deployment-Dauer

| Phase | Dauer |
|---|---|
| Packer Image Build | ca. 15–20 Minuten (einmalig) |
| Terraform Apply (pro Team) | ca. 3–5 Minuten |
| VM-Boot + cloud-init | ca. 2–3 Minuten |
| **Gesamt (erstmalig)** | **ca. 20–30 Minuten** |

Bei Deployments mit einem bereits vorhandenen Image entfällt der Packer-Build —
dann ca. 5–8 Minuten gesamt.

## Konfigurierbare Variablen

| Variable | Beschreibung | Pflicht |
|---|---|---|
| `assignment_files` | ZIP-Datei pro Team mit dem Startprojekt (LaTeX-Dateien) | **Ja** |
| `network_uuid` | UUID des internen Netzwerks | Ja (Default vorhanden) |
| `floating_ip_pool` | Name des External Networks für öffentliche IPs | Ja (Default vorhanden) |
| `shared_secgroup_id` | ID der Security Group | Ja (Default vorhanden) |

### Wichtig: Aufgabendateien (`assignment_files`)

Für jedes Team **muss** eine ZIP-Datei hochgeladen werden. Die ZIP wird beim
VM-Start entpackt und bildet den initialen LaTeX-Workspace des Teams. Die ZIP muss mindestens
eine `master.tex` im Root enthalten.

## Features

- Live-PDF-Preview nach dem Kompilieren
- Datei-Explorer mit Unterstützung für mehrere `.tex`-Dateien und Unterverzeichnisse
- Neue `.tex`-Dateien direkt im Browser anlegen
- Bilder (PNG, JPG, JPEG, GIF) hochladen und per `\includegraphics{}` einbinden
- Auto-Save (500ms Debounce)
- Kompilierung via `pdflatex` (zweifacher Lauf für TOC/Referenzen)
