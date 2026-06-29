"""
Patcht die Redirect-/Origin-URLs der Realm-Clients ``appstore-frontend``
und ``appstore-backend`` auf ``APP_BASE_URL``.

Hintergrund
-----------
Der Realm-Export (``deployment/keycloak/realm-export.json``) stammt aus
einer Dev-Umgebung und enthält hartcodierte ``http://localhost:*`` URLs
für Redirect-URIs, Web-Origins und Post-Logout-URIs. Direkt nach
``make prod-seed`` lehnt Keycloak deshalb jeden Login/Logout mit
``Invalid redirect uri`` ab.

Statt den Export selbst zu pflegen (kollidiert mit Keycloaks eigenen
``${authBaseUrl}``-Platzhaltern), patcht dieses Skript die beiden
Clients programmatisch — idempotent. Wer in Keycloak manuell weitere
Redirect-URIs hinzugefügt hat, sollte das also wissen: jeder Lauf
*überschreibt* die Listen mit dem Standard-Set für ``APP_BASE_URL``.
Bewusst kein Teil von ``prod-seed`` — der soll nicht versteckt
manuelle UI-Konfiguration plattmachen.

Aufruf via Makefile-Target: ``make prod-set-keycloak-urls``.
"""
from __future__ import annotations

import logging
import os
import sys

from keycloak import KeycloakAdmin

logger = logging.getLogger("set-keycloak-urls")
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

KEYCLOAK_URL = os.environ.get("KEYCLOAK_SERVER_URL", "http://keycloak:8080")
KEYCLOAK_REALM = os.environ.get("KEYCLOAK_REALM", "dhbw")
KEYCLOAK_ADMIN_USER = os.environ.get("KEYCLOAK_ADMIN_USER", "admin")
KEYCLOAK_ADMIN_PASSWORD = os.environ.get("KEYCLOAK_ADMIN_PASSWORD")
APP_BASE_URL = os.environ.get("APP_BASE_URL")


def _require(name: str, value: str | None) -> str:
    if not value:
        logger.error("❌ %s ist nicht gesetzt.", name)
        sys.exit(1)
    return value


def _patch_client(admin: KeycloakAdmin, client_id: str, payload: dict) -> None:
    """Suche Client per ``clientId`` und update ihn mit ``payload``."""
    kc_id = admin.get_client_id(client_id)
    if not kc_id:
        logger.error("❌ Client '%s' nicht im Realm '%s' gefunden.", client_id, KEYCLOAK_REALM)
        sys.exit(1)
    admin.update_client(kc_id, payload)
    changed = ", ".join(payload.keys())
    logger.info("  ✔ %s: %s", client_id, changed)


def main() -> None:
    base = _require("APP_BASE_URL", APP_BASE_URL).rstrip("/")
    admin_user = _require("KEYCLOAK_ADMIN_USER", KEYCLOAK_ADMIN_USER)
    admin_pass = _require("KEYCLOAK_ADMIN_PASSWORD", KEYCLOAK_ADMIN_PASSWORD)

    logger.info("🔧 Patche Keycloak-Client-URLs auf APP_BASE_URL=%s ...", base)

    admin = KeycloakAdmin(
        server_url=KEYCLOAK_URL,
        username=admin_user,
        password=admin_pass,
        realm_name=KEYCLOAK_REALM,
        user_realm_name="master",
        verify=True,
    )

    # Frontend-Client: public client, redirect+webOrigins+post-logout
    _patch_client(
        admin,
        "appstore-frontend",
        {
            "redirectUris": [f"{base}/*"],
            "webOrigins": [base],
            "attributes": {
                # Keycloak speichert mehrere Post-Logout-URIs als
                # ``##``-separierten String — hier reicht ein Eintrag.
                "post.logout.redirect.uris": f"{base}/*",
            },
        },
    )

    # Backend-Client: confidential, eigene rootUrl/adminUrl + Redirect
    _patch_client(
        admin,
        "appstore-backend",
        {
            "rootUrl": base,
            "adminUrl": base,
            "redirectUris": [f"{base}/*"],
            "webOrigins": [base],
        },
    )

    logger.info("✅ Fertig. Login + Logout sollten jetzt funktionieren.")


if __name__ == "__main__":
    main()
