import pytest
from reconcile.utils.glitchtip import GlitchtipClient


@pytest.fixture
def user_pk(glitchtip_client: GlitchtipClient, test_org: str, test_user: str) -> int:
    """Get a user pk."""
    users = glitchtip_client.organization_users(test_org)
    for user in users:
        if user.email == test_user:
            assert user.pk is not None
            return user.pk
    raise Exception(f"User {test_user} not found in {test_org}")


@pytest.mark.order(
    after=[
        "test_organizations.py::test_organsiation_create",
        "test_teams.py::test_team_create",
    ],
    before=[
        "test_organizations.py::test_organsiation_delete",
        "test_teams.py::test_team_delete",
    ],
)
def test_user_invite(
    glitchtip_client: GlitchtipClient,
    test_org: str,
    test_user: str,
) -> None:
    """Invite a new user."""
    glitchtip_client.invite_user(test_org, test_user, "member")


@pytest.mark.order(
    after=["test_user_invite"],
    before=["test_user_delete"],
)
def test_user_get(
    glitchtip_client: GlitchtipClient,
    test_org: str,
    test_user: str,
    api_user: str,
) -> None:
    """Get a user."""
    users = glitchtip_client.organization_users(test_org)
    assert {user.email for user in users} == {api_user, test_user}


@pytest.mark.order(
    after=["test_user_invite"],
    before=["test_user_delete"],
)
def test_user_update_role(
    glitchtip_client: GlitchtipClient, test_org: str, user_pk: int
) -> None:
    """Update user role."""
    user = glitchtip_client.update_user_role(test_org, "manager", user_pk)
    assert user.role == "manager"


@pytest.mark.order(
    after=["test_user_invite"],
    before=["test_user_delete"],
)
def test_user_add_to_team(
    glitchtip_client: GlitchtipClient,
    test_org: str,
    test_team2: str,
    user_pk: int,
    test_user: str,
    api_user: str,
) -> None:
    """Add user to a team."""
    team_users = glitchtip_client.team_users(test_org, test_team2)
    assert [u.email for u in team_users] == [api_user]

    team = glitchtip_client.add_user_to_team(test_org, test_team2, user_pk)
    assert {u.email for u in team.users} == {api_user, test_user}

    team_users = glitchtip_client.team_users(test_org, test_team2)
    assert {u.email for u in team_users} == {api_user, test_user}


@pytest.mark.order(
    after=["test_user_add_to_team"],
    before=["test_teams.py::test_team_delete", "test_user_delete"],
)
def test_user_remove_from_team(
    glitchtip_client: GlitchtipClient,
    test_org: str,
    test_team2: str,
    user_pk: int,
    api_user: str,
) -> None:
    """Add user to a team."""
    glitchtip_client.remove_user_from_team(test_org, test_team2, user_pk)
    team_users = glitchtip_client.team_users(test_org, test_team2)
    assert [u.email for u in team_users] == [api_user]


@pytest.mark.order(
    after=["test_user_invite"],
    before=["test_organizations.py::test_organsiation_delete"],
)
def test_user_delete(
    glitchtip_client: GlitchtipClient, test_org: str, user_pk: int
) -> None:
    """Delete a user."""
    glitchtip_client.delete_user(test_org, user_pk)
