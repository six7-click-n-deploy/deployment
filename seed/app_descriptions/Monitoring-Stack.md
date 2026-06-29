# Monitoring-Stack – Prometheus & Grafana

Deployt pro Team eine Prometheus-VM und eine Grafana-VM. Prometheus sammelt
Systemmetriken beider VMs über Node Exporter, Grafana visualisiert die Daten
in Echtzeit. Jeder Nutzer erhält einen eigenen Grafana-Account mit Admin-Rechten.

## User-Management

Ein Account pro Nutzer in Grafana. Benutzername ist die E-Mail-Adresse, das
Passwort wird automatisch generiert und nach dem Deployment per Mail versendet.
Alle Nutzer eines Teams greifen auf dieselbe Grafana-Instanz zu, haben aber
voneinander getrennte Sessions. Jeder Nutzer hat Admin-Rechte und kann eigene
Dashboards erstellen und importieren.

## VM-Deployment

Es werden **zwei VMs pro Team** deployed:

| VM | Zweck | Öffentliche IP |
|---|---|---|
| Prometheus-VM | Metriken sammeln (Port 9090) | Nein |
| Grafana-VM | Metriken visualisieren (Port 3000) | Ja |

Bei zwei Teams entstehen vier VMs. Studenten greifen ausschließlich auf die
Grafana-VM zu. Die Prometheus-VM ist intern erreichbar.

## Deployment-Dauer

| Phase | Dauer |
|---|---|
| Packer Build grafana + prometheus (parallel) | ca. 10–15 Min |
| Terraform Apply | ca. 3–5 Min |
| VM-Boot + cloud-init (Datasource, User-Anlage) | ca. 2–4 Min |
| **Gesamt erstmalig** | **ca. 15–25 Min** |

Bei vorhandenen Packer-Images entfällt der Build — dann ca. **5–10 Minuten**.

> Nach dem Deployment kann es noch 1–2 Minuten dauern bis Grafana vollständig
> hochgefahren ist. Ein sofortiger Aufruf kann noch einen 502-Fehler zeigen.

## Konfigurierbare Variablen

| Variable | Beschreibung | Pflicht |
|---|---|---|
| `network_uuid` | UUID des internen Netzwerks | Ja (Default vorhanden) |
| `floating_ip_pool` | Name des External Networks für die öffentliche IP | Ja (Default vorhanden) |
| `shared_secgroup_id` | ID der Security Group | Ja (Default vorhanden) |

## Erste Schritte nach dem Login

1. `http://<grafana-ip>:3000` aufrufen
2. Mit E-Mail und Passwort aus den Zugangsdaten einloggen
3. **Dashboards → New → Import → ID `1860`** für das Node Exporter Full Dashboard
