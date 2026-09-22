import os
import sys
from pathlib import Path

import django

# add the parent directory to the path so we can import the glitchtip module(s)
sys.path.append(str(Path(__file__).resolve().parent.parent))
# Set up Django environment. Must be done before importing any Django DB models.
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "glitchtip.settings")
django.setup()


from allauth.socialaccount.models import SocialApp  # isort:skip


def create_or_update_social_app(
    provider_id: str, client_id: str, client_secret: str, issuer: str
) -> None:
    """Create/update the OIDC SocialApp from the managed-sso-client secret.

    GlitchTip doesn't install django.contrib.sites, so SocialApp has no
    `sites` field here to associate -- allauth falls back to matching by
    provider/provider_id alone.
    """
    SocialApp.objects.update_or_create(
        provider="openid_connect",
        provider_id=provider_id,
        defaults={
            "name": "RedHat",
            "client_id": client_id,
            "secret": client_secret,
            "key": "email",
            "settings": {
                "server_url": f"{issuer}/.well-known/openid-configuration",
                "verified_email": True,
                "email_authentication": True,
            },
        },
    )


def main() -> None:
    client_id = os.environ.get("SSO_CLIENT_ID")
    if not client_id:
        print("SSO_CLIENT_ID not set, skipping social app configuration.")
        return

    client_secret = os.environ["SSO_CLIENT_SECRET"]
    issuer = os.environ["SSO_ISSUER"]
    provider_id = os.environ.get("SSO_PROVIDER_ID", "redhat-sso")

    print(f"Creating/updating social app for provider_id={provider_id}")
    create_or_update_social_app(provider_id, client_id, client_secret, issuer)
    print("Done.")


if __name__ == "__main__":
    main()
