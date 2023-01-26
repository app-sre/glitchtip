import os
import sys
from dataclasses import dataclass
from typing import Optional

import django
from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import make_password

# add the parent directory to the path so we can import the glitchtip module(s)
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# Set up Django environment. Must be done before importing any Django DB models.
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "glitchtip.settings")
django.setup()

from django.contrib.auth.models import AbstractBaseUser  # isort:skip
from api_tokens.models import APIToken  # isort:skip


@dataclass
class User:
    """A user object parse from environment."""

    email: str
    password: Optional[str] = None
    token: Optional[str] = None


def parse_enviroment() -> list[User]:
    """Parse environment variables to create users."""
    users = []
    indexes = set()

    for key in os.environ:
        if key.startswith("APPSRE_API_USER_"):
            indexes.add(key.split("_")[3])

    for index in indexes:
        email = os.environ[f"APPSRE_API_USER_{index}_EMAIL"]
        password = os.environ.get(f"APPSRE_API_USER_{index}_PASSWORD", None)
        token = os.environ.get(f"APPSRE_API_USER_{index}_TOKEN", None)
        users.append(User(email=email, password=password, token=token))

    return users


def create_or_update_user(email: str, password: Optional[str]) -> AbstractBaseUser:
    """Create/update a django user."""
    User = get_user_model()
    user, _ = User.objects.update_or_create(
        email=email,
        defaults={
            "password": make_password(password or None),
            "is_superuser": True,
            "is_staff": True,
            "is_active": True,
        },
    )
    return user


def create_or_update_token(user: AbstractBaseUser, token: str) -> None:
    """Create/update an API token for a user."""
    user_scopes = 0

    # grant all scopes to the user
    for scope_name in APIToken.scopes.keys():
        user_scopes = user_scopes | getattr(APIToken.scopes, scope_name)

    APIToken.objects.update_or_create(
        user=user, defaults={"token": token, "scopes": user_scopes}
    )


def main() -> None:
    print("Creating API users...")
    for user in parse_enviroment():
        print(f"Creating/updating user {user.email}")
        django_user = create_or_update_user(user.email, user.password)
        if user.token:
            print(f"Creating/updating token for user {user.email}")
            create_or_update_token(django_user, user.token)
    print("Done.")


if __name__ == "__main__":
    main()
