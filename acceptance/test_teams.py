import pytest
from reconcile.utils.glitchtip import GlitchtipClient


@pytest.mark.order(
    after=["test_organizations.py::test_organsiation_create"],
    before=["test_organizations.py::test_organsiation_delete"],
)
def test_team_create(
    glitchtip_client: GlitchtipClient,
    test_org: str,
    test_team: str,
    test_team2: str,
) -> None:
    """Create a new team."""
    # create two teams to have test add/rm team from project
    team = glitchtip_client.create_team(test_org, test_team)
    assert team.name == test_team
    glitchtip_client.create_team(test_org, test_team2)


@pytest.mark.order(
    after=["test_team_create"],
    before=["test_team_delete"],
)
def test_team_get(
    glitchtip_client: GlitchtipClient,
    test_org: str,
    test_team: str,
    test_team2: str,
) -> None:
    """Get a team."""
    teams = glitchtip_client.teams(test_org)
    assert {test_team, test_team2} == {team.name for team in teams}


@pytest.mark.order(
    after=["test_team_create"],
    before=["test_organizations.py::test_organsiation_delete"],
)
def test_team_delete(
    glitchtip_client: GlitchtipClient,
    test_org: str,
    test_team: str,
    test_team2: str,
) -> None:
    """Delete a team."""
    glitchtip_client.delete_team(test_org, test_team)
    glitchtip_client.delete_team(test_org, test_team2)
