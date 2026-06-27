"""
Seed script for the Click-n-Deploy app store.

Was es macht
------------
1. Legt Keycloak-User im Realm ``dhbw`` an (Profs, Studenten, ein
   Admin). Setzt jedem ein festes Initialpasswort und mappt die
   passende Realm-Rolle (admin / teacher / student).
2. Spiegelt die User in die Backend-Datenbank, baut die Kurse, hängt
   die Studenten an ihre Kurse und verlinkt die Profs als
   Course-Teacher (Many-to-Many via ``course_teachers``).
3. Erstellt Beispiel-Apps (Online-IDE, Web-LaTeX, …) deren Repos in
   der Org ``six7-click-n-deploy`` liegen, plus ein paar private
   Bastel-Apps.
4. Erzeugt für die öffentlichen Apps ein realistisches Gemisch aus
   ``APPROVED`` / ``PENDING`` / ``REJECTED`` Version-Approvals mit
   Notes und Rejection-Reasons.

Das Skript ist idempotent: Findet es einen User mit derselben Email,
einen Kurs mit demselben Namen oder eine App mit demselben Namen,
benutzt es den existierenden Datensatz statt einen Duplikat anzulegen.
Erneutes Ausführen aktualisiert lediglich Felder, die sich geändert
haben.

Aufruf
------
Aus dem Backend-Container (hat python-keycloak + SQLAlchemy + Modelle):

    docker compose -f docker-compose.dev.yml exec backend \
        python /seed/seed_data.py

Oder einfacher via Makefile: ``make seed-data``.
"""
from __future__ import annotations

import json
import logging
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

from keycloak import KeycloakAdmin
from keycloak.exceptions import KeycloakGetError
from sqlalchemy.orm import Session

from app.database import SessionLocal
from app.models import (
    App,
    AppVersionApproval,
    AppVersionApprovalStatus,
    Course,
    CourseTeacher,
    User,
    UserRole,
)

logger = logging.getLogger("seed")
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

# ----------------------------------------------------------------
# Konfiguration
# ----------------------------------------------------------------
KEYCLOAK_URL = os.environ.get("KEYCLOAK_SERVER_URL", "http://keycloak:8080")
KEYCLOAK_REALM = os.environ.get("KEYCLOAK_REALM", "dhbw")
KEYCLOAK_ADMIN_USER = os.environ.get("KEYCLOAK_ADMIN_USER", "admin")
KEYCLOAK_ADMIN_PASSWORD = os.environ.get("KEYCLOAK_ADMIN_PASSWORD", "admin")

DEFAULT_PASSWORD = "1234"
EMAIL_DOMAIN = "dhbw.de"

# Optionaler Pfad zur Realm-Export-Datei. Wenn der Realm noch nicht
# existiert, importieren wir ihn von hier; danach läuft das normale
# Seeding. In den Backend-Container reicht der Default-Pfad via
# Bind-Mount des deployment-Verzeichnisses meist nicht, deshalb kann
# das Makefile die Datei zusätzlich nach ``/tmp/realm-export.json``
# kopieren — wir suchen an beiden Stellen.
REALM_EXPORT_CANDIDATES = [
    Path(os.environ.get("REALM_EXPORT_PATH", "/tmp/realm-export.json")),
    Path("/deployment/keycloak/realm-export.json"),
    Path(__file__).parent.parent / "keycloak" / "realm-export.json",
]


# ----------------------------------------------------------------
# Datendefinitionen
# ----------------------------------------------------------------
@dataclass(frozen=True)
class SeedUser:
    first_name: str
    last_name: str
    role: UserRole
    course: str | None = None  # nur bei Studenten gesetzt
    teaches: tuple[str, ...] = field(default_factory=tuple)  # Kurse, in denen Prof Lehrender ist


@dataclass(frozen=True)
class SeedApp:
    name: str
    description: str
    git_link: str
    is_private: bool
    owner_email: str  # wer die App im Store eingestellt hat
    # Eine Liste aus (version_tag, status, notes, rejection_reason).
    # ``reviewed_by_email`` wird beim Anlegen auf den Admin-User
    # gesetzt. Notes erklären den Inhalt der Version; rejection_reason
    # ist nur bei REJECTED relevant.
    versions: tuple[tuple[str, AppVersionApprovalStatus, str | None, str | None], ...] = ()


def _email(first: str, last: str) -> str:
    """``Vorname Nachname`` → ``vorname.nachname@dhbw.de`` (ASCII-bereinigt)."""
    def _norm(s: str) -> str:
        # Umlaute & Sonderzeichen weg, alles klein
        repl = {"ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss", " ": "", "-": "", "'": ""}
        out = s.strip().lower()
        for k, v in repl.items():
            out = out.replace(k, v)
        return out
    return f"{_norm(first)}.{_norm(last)}@{EMAIL_DOMAIN}"


# Kurse (Name → Beschreibung im Klartext nur zur Doku hier)
COURSES = [
    "WI SE B 23",   # Standard-Kurs aus der Aufgabe
    "WI SE B 24",   # neuer Jahrgang
    "INF TI 23",    # zweites Studienprogramm
    "WI SE A 23",   # Parallelkurs
]


PROFESSORS: list[SeedUser] = [
    SeedUser("Henning",  "Pagnia",   UserRole.TEACHER, teaches=("WI SE B 23", "WI SE B 24")),
    SeedUser("Michael",  "Eichberg", UserRole.TEACHER, teaches=("WI SE B 23", "INF TI 23")),
    SeedUser("Sarah",    "Detzler",  UserRole.TEACHER, teaches=("WI SE B 23", "WI SE A 23")),
    SeedUser("Frank",    "Hubert",   UserRole.TEACHER, teaches=("WI SE B 23",)),
    # Erfundene Profs für die zusätzlichen Kurse
    SeedUser("Andrea",   "Bauer",    UserRole.TEACHER, teaches=("WI SE B 24",)),
    SeedUser("Thomas",   "Wagner",   UserRole.TEACHER, teaches=("INF TI 23", "WI SE A 23")),
]


STUDENTS_WI_SE_B_23: list[SeedUser] = [
    SeedUser("Luca",    "Bäck",    UserRole.STUDENT, course="WI SE B 23"),
    SeedUser("Felix",   "Erhard",  UserRole.STUDENT, course="WI SE B 23"),
    SeedUser("Raphael", "Plett",   UserRole.STUDENT, course="WI SE B 23"),
    SeedUser("Mika",    "Jun",     UserRole.STUDENT, course="WI SE B 23"),
    SeedUser("Okan",    "Sömnez",  UserRole.STUDENT, course="WI SE B 23"),
    SeedUser("Leon",    "Priemer", UserRole.STUDENT, course="WI SE B 23"),
    SeedUser("Tom",     "Weber",   UserRole.STUDENT, course="WI SE B 23"),
    SeedUser("Monika",  "Piano",   UserRole.STUDENT, course="WI SE B 23"),
    SeedUser("Iven",    "Stahl",   UserRole.STUDENT, course="WI SE B 23"),
]


STUDENTS_OTHER: list[SeedUser] = [
    # WI SE B 24
    SeedUser("Anna",     "Schulz",     UserRole.STUDENT, course="WI SE B 24"),
    SeedUser("Jonas",    "Becker",     UserRole.STUDENT, course="WI SE B 24"),
    SeedUser("Lisa",     "Hoffmann",   UserRole.STUDENT, course="WI SE B 24"),
    SeedUser("Paul",     "Schmidt",    UserRole.STUDENT, course="WI SE B 24"),
    # INF TI 23
    SeedUser("Jan",      "Krüger",     UserRole.STUDENT, course="INF TI 23"),
    SeedUser("Maria",    "Lehmann",    UserRole.STUDENT, course="INF TI 23"),
    SeedUser("Niklas",   "Vogel",      UserRole.STUDENT, course="INF TI 23"),
    # WI SE A 23
    SeedUser("Hannah",   "Roth",       UserRole.STUDENT, course="WI SE A 23"),
    SeedUser("Sebastian","Friedrich",  UserRole.STUDENT, course="WI SE A 23"),
    SeedUser("Lea",      "Neumann",    UserRole.STUDENT, course="WI SE A 23"),
]


ADMIN: SeedUser = SeedUser("Tobias", "Admin", UserRole.ADMIN)


ALL_USERS: list[SeedUser] = (
    PROFESSORS + STUDENTS_WI_SE_B_23 + STUDENTS_OTHER + [ADMIN]
)


# ----------------------------------------------------------------
# Beispiel-Apps. Die Git-Repos existieren wirklich in der Org
# six7-click-n-deploy; die Tag-Namen sind die aktuell dort vorhandenen
# (Stand Juni 2026). Für Profs sind Apps "eingestellt von"; das passt
# zur Berechtigungslogik (Teacher dürfen Apps in den Store legen).
# ----------------------------------------------------------------
APPROVED = AppVersionApprovalStatus.APPROVED
PENDING = AppVersionApprovalStatus.PENDING
REJECTED = AppVersionApprovalStatus.REJECTED


APPS: list[SeedApp] = [
    # ----------------------------------------------------------------
    # Prof-eingestellte Apps (Lehrveranstaltungs-Sandboxes).
    # ----------------------------------------------------------------
    SeedApp(
        name="Online IDE",
        description=(
            "Browser-basierte VS-Code-Instanz (code-server) als Lehr-Sandbox. "
            "Bring-Your-Own-Repo: Studierende klonen ihr Git-Repo direkt in den "
            "deploybaren Workspace, kein lokales Setup nötig."
        ),
        git_link="https://github.com/six7-click-n-deploy/Online-IDE.git",
        is_private=False,
        owner_email=_email("Michael", "Eichberg"),
        versions=(
            ("v1.0.7",  APPROVED, "Initialer Rollout für die Vorlesung 'Software Engineering'.", None),
            ("v1.0.8",  APPROVED, "Default-SecGroup auf den Build-VM-Pfad korrigiert.", None),
            ("v1.0.9",  REJECTED, "Hotfix – sollte v1.0.10 zuvorkommen.",
             "Commit-Nachricht 'Fix' ist nicht aussagekräftig genug; bitte Changelog nachreichen."),
            ("v1.0.10", APPROVED, "Variable für Notebook-URL nachgereicht.", None),
            ("v1.0.11", APPROVED, "Konfigurationsbeschreibungen für Studierende klarer formuliert.", None),
            ("v1.0.12", APPROVED, "Cloud-Init-Dateien gebündelt.", None),
            ("v1.0.13", PENDING,  "Variable-Scopes (Team vs. Deployment) eingeführt – Review angefragt.", None),
            ("v1.0.14", PENDING,  "Pro-Team Flavor-Auswahl – braucht Sicherheits-Review wegen quotas.", None),
        ),
    ),
    SeedApp(
        name="Web-LaTeX",
        description=(
            "Self-hosted Overleaf-Alternative (TexLive-Full). Pro Studierender "
            "ein persistenter Workspace; nützlich für Abschlussarbeiten und "
            "Übungsblätter."
        ),
        git_link="https://github.com/six7-click-n-deploy/Web-LaTeX.git",
        is_private=False,
        owner_email=_email("Sarah", "Detzler"),
        versions=(
            ("v1.0.0", APPROVED,
             "Erst-Veröffentlichung im Rahmen der DHBW-eigenen App-Store-Migration.",
             None),
            ("v1.0.1", REJECTED,
             "Kleiner Hotfix kurz nach v1.0.0.",
             "Tag enthält keinen relevanten Diff gegenüber v1.0.0 – bitte v1.0.2 verwenden."),
            ("v1.0.2", APPROVED,
             "Build-Image-Pinning korrigiert (TexLive 2025 → 2024 LTS).", None),
        ),
    ),
    SeedApp(
        name="Jupyter Notebook",
        description=(
            "Single-User JupyterLab mit vorinstallierten Data-Science-"
            "Bibliotheken (numpy, pandas, scikit-learn). Geeignet für die "
            "Lehrveranstaltung 'Maschinelles Lernen'."
        ),
        git_link="https://github.com/six7-click-n-deploy/Jupyter-Notebook.git",
        is_private=False,
        owner_email=_email("Henning", "Pagnia"),
        versions=(
            ("v1.0.0", PENDING,
             "Erstveröffentlichung. Bitte vor Vorlesungsbeginn prüfen.", None),
        ),
    ),
    SeedApp(
        name="pgAdmin",
        description=(
            "pgAdmin 4 als Web-UI, vorkonfiguriert mit Demo-Datenbank. "
            "Wird in der Vorlesung 'Datenbanken I' für die SQL-Übungen "
            "ausgerollt."
        ),
        git_link="https://github.com/six7-click-n-deploy/pgAdmin.git",
        is_private=False,
        owner_email=_email("Frank", "Hubert"),
        versions=(
            ("v1.0.0", APPROVED,
             "Initialer Rollout für DB-I-Vorlesung.", None),
        ),
    ),
    SeedApp(
        name="Ubuntu Sandbox",
        description=(
            "Generische Ubuntu-22.04-VM mit SSH-Zugang. Catch-all für "
            "Studierende, die ihren eigenen Stack mitbringen wollen."
        ),
        git_link="https://github.com/six7-click-n-deploy/Ubuntu-App.git",
        is_private=False,
        owner_email=_email("Andrea", "Bauer"),
        versions=(
            ("v1.0.10", APPROVED,
             "Cloud-Init-SSH-Konfiguration stabilisiert.", None),
            ("v1.0.11", REJECTED,
             "Schnelles Re-Tag wegen Doku-Tippfehler.",
             "Inhaltlich identisch zu v1.0.10 – kein Mehrwert für End-User."),
            ("v1.0.12", APPROVED,
             "Erweiterte Konfigurationsbeschreibungen.", None),
        ),
    ),
    # ----------------------------------------------------------------
    # Private Bastel-Apps (kein Approval-Prozess, nicht im Store).
    # Wichtig, weil die Visibility-Logik (``get_visible_apps``) und die
    # Approval-Liste explizit zwischen public+approved und privaten
    # Apps unterscheidet — wir brauchen beide Sorten zum Testen.
    # ----------------------------------------------------------------
    SeedApp(
        name="Test-App (Template-Spielwiese)",
        description=(
            "Private Test-App zum Ausprobieren neuer Packer-/Terraform-"
            "Templates. Nicht für Studierende gedacht."
        ),
        git_link="https://github.com/six7-click-n-deploy/Test-App.git",
        is_private=True,
        owner_email=_email("Tobias", "Admin"),
        versions=(),  # private Apps brauchen keine Approval-Records
    ),
    SeedApp(
        name="My Custom Stack (WIP)",
        description=(
            "Persönliche Spiel-App von Eichberg – kombiniert pgAdmin + "
            "Online-IDE in einem Deployment. Noch nicht reif für den Store."
        ),
        git_link="https://github.com/six7-click-n-deploy/Online-IDE.git",
        is_private=True,
        owner_email=_email("Michael", "Eichberg"),
        versions=(),
    ),
    # ----------------------------------------------------------------
    # Studenten-Apps. Studierende dürfen ebenfalls Apps in den Store
    # stellen — typischerweise private Fork/Forschungsprojekte; manche
    # haben aber auch öffentliche Versionen eingereicht, weil sie ihre
    # Arbeit teilen wollen. Wir mischen deshalb private, öffentliche
    # mit PENDING-Submission und öffentliche mit bereits APPROVED
    # Versionen — damit der Approval-Workflow auch aus Studi-Sicht
    # testbar wird.
    # ----------------------------------------------------------------
    SeedApp(
        name="Luca's IDE Fork",
        description=(
            "Eigener Fork der Online-IDE mit vorinstallierten Rust-Toolchain "
            "und probe-rs. Ursprünglich für die IoT-Übungen im 5. Semester "
            "entstanden; öffentlich gemacht, weil ein paar Kommilitonen die "
            "Konfiguration nachnutzen wollten."
        ),
        git_link="https://github.com/six7-click-n-deploy/Online-IDE.git",
        is_private=False,
        owner_email=_email("Luca", "Bäck"),
        versions=(
            ("v1.0.12", APPROVED,
             "Cloud-Init-Modul für probe-rs ergänzt; lokal getestet auf 4 VMs.", None),
            ("v1.0.13", PENDING,
             "Variable-Scopes übernommen — wartet auf Review, damit die "
             "Kommilitonen aus WI SE B 23 darauf zugreifen können.", None),
        ),
    ),
    SeedApp(
        name="Felix's LaTeX Vorlage",
        description=(
            "Web-LaTeX mit DHBW-Bachelorarbeit-Template vorgeladen. Spart "
            "den Initial-Klon-Aufwand und enthält die korrekte BibTeX-Konfig."
        ),
        git_link="https://github.com/six7-click-n-deploy/Web-LaTeX.git",
        is_private=False,
        owner_email=_email("Felix", "Erhard"),
        versions=(
            ("v1.0.2", PENDING,
             "Erste öffentliche Version. Bitte vor dem WiSe-Start reviewen, "
             "damit der Jahrgang sie nutzen kann.", None),
        ),
    ),
    SeedApp(
        name="Raphael's Notebook-Stack",
        description=(
            "Forks des Jupyter-Notebook-Apps mit zusätzlich vorinstalliertem "
            "PyTorch + CUDA-Treibern. Privater Spielplatz für die "
            "Studienarbeit."
        ),
        git_link="https://github.com/six7-click-n-deploy/Jupyter-Notebook.git",
        is_private=True,
        owner_email=_email("Raphael", "Plett"),
        versions=(),
    ),
    SeedApp(
        name="Tom's Ubuntu mit Docker",
        description=(
            "Ubuntu-Sandbox mit vor-installiertem Docker-Engine. Gut für "
            "die DevOps-Übung im 6. Semester. Eingereicht zum Approval, "
            "wurde aber zunächst abgelehnt."
        ),
        git_link="https://github.com/six7-click-n-deploy/Ubuntu-App.git",
        is_private=False,
        owner_email=_email("Tom", "Weber"),
        versions=(
            ("v1.0.12", REJECTED,
             "Erste Submission. Hatte Docker via cloud-init nachinstalliert.",
             "Image enthält Klartext-API-Key in /etc/docker/daemon.json — "
             "bitte nachreichen ohne Credentials im Image."),
        ),
    ),
    SeedApp(
        name="Monika's Test-Sandbox",
        description=(
            "Privater Testplatz für Packer-/Terraform-Experimente. Wird "
            "irgendwann aufgeräumt, ist momentan reines Bastel-Setup."
        ),
        git_link="https://github.com/six7-click-n-deploy/Test-App.git",
        is_private=True,
        owner_email=_email("Monika", "Piano"),
        versions=(),
    ),
    SeedApp(
        name="Iven's PostgreSQL Lab",
        description=(
            "pgAdmin + vorgeladene Demo-DB für die DB-II-Übung. Open-Source "
            "geteilt mit dem Jahrgang."
        ),
        git_link="https://github.com/six7-click-n-deploy/pgAdmin.git",
        is_private=False,
        owner_email=_email("Iven", "Stahl"),
        versions=(
            ("v1.0.0", APPROVED,
             "Inhaltlich identisch zur offiziellen pgAdmin-App, aber mit "
             "vorgeladenem Northwind-Sample.", None),
        ),
    ),
    SeedApp(
        name="Anna's Web-LaTeX",
        description=(
            "Web-LaTeX mit Beamer-Klasse + DHBW-Folien-Template. Nützlich "
            "für Präsentationen in den Seminaren."
        ),
        git_link="https://github.com/six7-click-n-deploy/Web-LaTeX.git",
        is_private=False,
        owner_email=_email("Anna", "Schulz"),
        versions=(
            ("v1.0.2", PENDING,
             "Folien-Template eingebunden; warte auf Approval, damit ich "
             "es für die WI-Studierendenkonferenz freischalten kann.", None),
        ),
    ),
]


# ----------------------------------------------------------------
# Keycloak-Helpers
# ----------------------------------------------------------------
def _kc_master_admin() -> KeycloakAdmin:
    """Login als Master-Realm Admin, Working-Realm = master.

    Wird gebraucht, um *neue* Realms anzulegen — das geht nur von der
    master-Realm aus. Für das eigentliche User-Seeding verwenden wir
    ``_kc_admin()``, der auf den Ziel-Realm umschaltet.
    """
    return KeycloakAdmin(
        server_url=KEYCLOAK_URL,
        username=KEYCLOAK_ADMIN_USER,
        password=KEYCLOAK_ADMIN_PASSWORD,
        realm_name="master",
        user_realm_name="master",
        verify=True,
    )


def _ensure_realm_exists() -> None:
    """Importiert den ``dhbw``-Realm, falls er noch nicht existiert.

    Das Keycloak-Setup in der Compose-Datei macht *keinen* Auto-Import
    (kein ``--import-realm`` und kein Bind-Mount auf
    ``/opt/keycloak/data/import``). Damit ein frisches Volume direkt
    nutzbar ist, lädt das Skript hier den Realm-Export selber rein.

    Die Datei wird in dieser Reihenfolge gesucht:

    * ``$REALM_EXPORT_PATH`` (von außen settbar)
    * ``/tmp/realm-export.json`` (vom Makefile dahin kopiert)
    * ``/deployment/keycloak/realm-export.json`` (Bind-Mount)
    * Pfad relativ zu diesem Skript (falls lokal ausgeführt)
    """
    master = _kc_master_admin()
    try:
        master.get_realm(KEYCLOAK_REALM)
        logger.info("Realm '%s' existiert bereits.", KEYCLOAK_REALM)
        return
    except KeycloakGetError as exc:
        if "404" not in str(exc) and "not found" not in str(exc).lower():
            raise
        logger.info("Realm '%s' fehlt — importiere aus Export-Datei.", KEYCLOAK_REALM)

    export_path = next((p for p in REALM_EXPORT_CANDIDATES if p.is_file()), None)
    if export_path is None:
        searched = "\n  ".join(str(p) for p in REALM_EXPORT_CANDIDATES)
        raise FileNotFoundError(
            f"Realm '{KEYCLOAK_REALM}' fehlt in Keycloak und keine Export-Datei "
            f"gefunden. Gesucht in:\n  {searched}\n"
            f"Lege den Export an einer dieser Stellen ab oder setze "
            f"REALM_EXPORT_PATH."
        )

    payload = json.loads(export_path.read_text())
    # Sicherheitshalber den Realm-Namen erzwingen — falls jemand die
    # Datei umbenannt hat, würde python-keycloak sonst kommentarlos
    # einen anderen Realm importieren.
    payload["realm"] = KEYCLOAK_REALM
    master.create_realm(payload=payload, skip_exists=True)
    logger.info("Realm '%s' importiert (Quelle: %s).", KEYCLOAK_REALM, export_path)


def _kc_admin() -> KeycloakAdmin:
    """Login als Master-Realm Admin, dann auf den Ziel-Realm wechseln.

    python-keycloak benutzt zwei verschiedene Attribute:
    * ``user_realm_name`` — wohin geloggt wird (hier: ``master``)
    * ``realm_name`` — auf welchem Realm die Admin-Operationen laufen
      (hier: ``dhbw``)
    Wenn man nur ``connection.realm_name`` schreibt, hängen die Calls
    am falschen Realm und Keycloak antwortet mit 404.
    """
    kc = KeycloakAdmin(
        server_url=KEYCLOAK_URL,
        username=KEYCLOAK_ADMIN_USER,
        password=KEYCLOAK_ADMIN_PASSWORD,
        realm_name=KEYCLOAK_REALM,
        user_realm_name="master",
        verify=True,
    )
    # Defensive — falls eine neuere python-keycloak-Version den
    # Konstruktor anders interpretiert, setzen wir den Working-Realm
    # explizit nochmal.
    try:
        kc.change_current_realm(KEYCLOAK_REALM)
    except AttributeError:
        kc.realm_name = KEYCLOAK_REALM
    return kc


def _ensure_kc_user(kc: KeycloakAdmin, user: SeedUser) -> str:
    """Lege ``user`` in Keycloak an (oder finde den vorhandenen) und gib die KC-ID zurück."""
    email = _email(user.first_name, user.last_name)
    username = email.split("@")[0]  # Login-Name = lokaler Teil

    existing = kc.get_users({"email": email, "exact": True})
    if existing:
        kc_id = existing[0]["id"]
        # Stammdaten ggf. nachziehen (falls jemand den User manuell verändert hat).
        kc.update_user(
            user_id=kc_id,
            payload={
                "firstName": user.first_name,
                "lastName": user.last_name,
                "email": email,
                "emailVerified": True,
                "enabled": True,
            },
        )
        logger.info("KC user existiert bereits: %s", email)
    else:
        kc_id = kc.create_user(
            payload={
                "username": username,
                "email": email,
                "firstName": user.first_name,
                "lastName": user.last_name,
                "enabled": True,
                "emailVerified": True,
                "credentials": [
                    {"type": "password", "value": DEFAULT_PASSWORD, "temporary": False},
                ],
            },
            exist_ok=False,
        )
        logger.info("KC user angelegt: %s (id=%s)", email, kc_id)

    # Passwort immer auf den Default zurücksetzen — macht den Seed-Lauf
    # vorhersagbar, auch wenn ein vorhandener User andere Credentials hatte.
    kc.set_user_password(user_id=kc_id, password=DEFAULT_PASSWORD, temporary=False)

    # Realm-Rollen-Mapping: admin → ``admin``, teacher → ``teacher``,
    # student bekommt keine extra Rolle (Default).
    if user.role in (UserRole.ADMIN, UserRole.TEACHER):
        role_name = "admin" if user.role == UserRole.ADMIN else "teacher"
        role = kc.get_realm_role(role_name)
        kc.assign_realm_roles(user_id=kc_id, roles=[role])
    return kc_id


# ----------------------------------------------------------------
# DB-Helpers
# ----------------------------------------------------------------
def _ensure_course(db: Session, name: str) -> Course:
    course = db.query(Course).filter(Course.name == name).first()
    if course:
        return course
    course = Course(name=name)
    db.add(course)
    db.flush()
    logger.info("Kurs angelegt: %s (%s)", name, course.courseId)
    return course


def _ensure_user(
    db: Session,
    user: SeedUser,
    kc_id: str,
    courses_by_name: dict[str, Course],
) -> User:
    email = _email(user.first_name, user.last_name)
    username = email.split("@")[0]

    db_user = db.query(User).filter(User.email == email).first()
    course_id = courses_by_name[user.course].courseId if user.course else None

    if db_user is None:
        db_user = User(
            keycloak_id=kc_id,
            email=email,
            username=username,
            firstName=user.first_name,
            lastName=user.last_name,
            role=user.role,
            courseId=course_id,
        )
        db.add(db_user)
        db.flush()
        logger.info("DB user angelegt: %s [%s]", email, user.role.value)
    else:
        # Felder synchronisieren – Keycloak-ID ist die anker­identität.
        db_user.keycloak_id = kc_id
        db_user.username = username
        db_user.firstName = user.first_name
        db_user.lastName = user.last_name
        db_user.role = user.role
        db_user.courseId = course_id
    return db_user


def _ensure_course_teacher(db: Session, course: Course, teacher: User) -> None:
    link = (
        db.query(CourseTeacher)
        .filter(
            CourseTeacher.courseId == course.courseId,
            CourseTeacher.userId == teacher.userId,
        )
        .first()
    )
    if link:
        return
    db.add(CourseTeacher(courseId=course.courseId, userId=teacher.userId))
    logger.info("Course-Teacher: %s → %s", teacher.email, course.name)


def _ensure_app(db: Session, app_def: SeedApp, owner: User) -> App:
    app = db.query(App).filter(App.name == app_def.name).first()
    if app is None:
        app = App(
            name=app_def.name,
            description=app_def.description,
            git_link=app_def.git_link,
            is_private=app_def.is_private,
            userId=owner.userId,
        )
        db.add(app)
        db.flush()
        logger.info("App angelegt: %s (private=%s)", app_def.name, app_def.is_private)
    else:
        # Description / Visibility nachziehen.
        app.description = app_def.description
        app.is_private = app_def.is_private
        app.userId = owner.userId
    return app


def _ensure_version(
    db: Session,
    app: App,
    admin: User,
    version_tag: str,
    status: AppVersionApprovalStatus,
    notes: str | None,
    rejection_reason: str | None,
) -> None:
    from datetime import datetime

    row = (
        db.query(AppVersionApproval)
        .filter(
            AppVersionApproval.appId == app.appId,
            AppVersionApproval.version_tag == version_tag,
        )
        .first()
    )
    if row is None:
        row = AppVersionApproval(
            appId=app.appId,
            version_tag=version_tag,
            status=status,
            notes=notes,
        )
        db.add(row)
    else:
        row.status = status
        row.notes = notes

    if status == AppVersionApprovalStatus.PENDING:
        row.reviewed_by = None
        row.reviewed_at = None
        row.rejection_reason = None
    else:
        row.reviewed_by = admin.userId
        row.reviewed_at = datetime.utcnow()
        row.rejection_reason = rejection_reason if status == AppVersionApprovalStatus.REJECTED else None


# ----------------------------------------------------------------
# Orchestrierung
# ----------------------------------------------------------------
def seed() -> None:
    logger.info("→ Keycloak: %s, Realm: %s", KEYCLOAK_URL, KEYCLOAK_REALM)
    _ensure_realm_exists()
    kc = _kc_admin()

    # 1) Keycloak-User
    kc_ids: dict[str, str] = {}
    for user in ALL_USERS:
        kc_ids[_email(user.first_name, user.last_name)] = _ensure_kc_user(kc, user)

    # 2) DB-Seeding in einer Transaktion
    db: Session = SessionLocal()
    try:
        # Kurse
        courses_by_name: dict[str, Course] = {
            name: _ensure_course(db, name) for name in COURSES
        }

        # User
        db_users: dict[str, User] = {}
        for user in ALL_USERS:
            email = _email(user.first_name, user.last_name)
            db_users[email] = _ensure_user(db, user, kc_ids[email], courses_by_name)

        db.flush()

        # Course-Teacher-Verknüpfungen (nur Profs)
        for prof in PROFESSORS:
            db_prof = db_users[_email(prof.first_name, prof.last_name)]
            for course_name in prof.teaches:
                _ensure_course_teacher(db, courses_by_name[course_name], db_prof)

        # Admin für die Approval-Review-Spalte
        admin_user = db_users[_email(ADMIN.first_name, ADMIN.last_name)]

        # Apps + Approvals
        for app_def in APPS:
            owner = db_users.get(app_def.owner_email)
            if owner is None:
                logger.warning("Owner %s nicht gefunden – App %s wird übersprungen.",
                               app_def.owner_email, app_def.name)
                continue
            db_app = _ensure_app(db, app_def, owner)
            for version_tag, status, notes, reason in app_def.versions:
                _ensure_version(db, db_app, admin_user, version_tag, status, notes, reason)

        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()

    _print_summary()


def _print_summary() -> None:
    print()
    print("=" * 72)
    print("✓ Seed erfolgreich abgeschlossen.")
    print("=" * 72)
    print(f"Standardpasswort für alle User: {DEFAULT_PASSWORD!r}")
    print(f"Login-Format:                   <vorname>.<nachname>@{EMAIL_DOMAIN}")
    print()
    print("Profs (Teacher):")
    for u in PROFESSORS:
        print(f"  - {u.first_name} {u.last_name:10s}  {_email(u.first_name, u.last_name)}"
              f"   lehrt: {', '.join(u.teaches)}")
    print()
    print("Admin:")
    print(f"  - {ADMIN.first_name} {ADMIN.last_name}  {_email(ADMIN.first_name, ADMIN.last_name)}")
    print()
    print("Kurse:")
    for c in COURSES:
        members = [u for u in (STUDENTS_WI_SE_B_23 + STUDENTS_OTHER) if u.course == c]
        print(f"  - {c:14s}  {len(members)} Studierende")
    print()
    print("Apps:")
    for a in APPS:
        flavor = "private" if a.is_private else "public"
        print(f"  - [{flavor:7s}] {a.name:30s}  {len(a.versions)} Version(en)")
    print()
    print("=" * 72)


if __name__ == "__main__":
    try:
        seed()
    except Exception as exc:
        logger.exception("Seed fehlgeschlagen: %s", exc)
        sys.exit(1)
