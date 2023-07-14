import pytest
from reconcile.utils.glitchtip import GlitchtipClient


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
def test_project_create(
    glitchtip_client: GlitchtipClient,
    test_org: str,
    test_team: str,
    test_project: str,
) -> None:
    """Create a new project."""
    glitchtip_client.create_project(
        test_org, test_team, test_project, platform="python"
    )


@pytest.mark.order(
    after=["test_project_create"],
    before=["test_project_delete"],
)
def test_project_get(
    glitchtip_client: GlitchtipClient,
    test_org: str,
    test_project: str,
) -> None:
    """Get a project."""
    projects = glitchtip_client.projects(test_org)
    assert [test_project] == [project.name for project in projects]


@pytest.mark.order(
    after=["test_project_create"],
    before=["test_project_delete"],
)
def test_project_add_to_team(
    glitchtip_client: GlitchtipClient,
    test_org: str,
    test_project: str,
    test_team: str,
    test_team2: str,
) -> None:
    """Add a project to a team."""
    glitchtip_client.add_project_to_team(test_org, test_team2, test_project)
    projects = glitchtip_client.projects(test_org)
    assert [test_team, test_team2] == [
        team.name for project in projects for team in project.teams
    ]


@pytest.mark.order(
    after=["test_project_add_to_team"],
    before=["test_project_delete"],
)
def test_project_remove_from_team(
    glitchtip_client: GlitchtipClient,
    test_org: str,
    test_project: str,
    test_team: str,
    test_team2: str,
) -> None:
    """Remove a project from a team."""
    glitchtip_client.add_project_to_team(test_org, test_team2, test_project)
    projects = glitchtip_client.projects(test_org)
    assert [test_team, test_team2] == [
        team.name for project in projects for team in project.teams
    ]


@pytest.mark.order(
    after=["test_project_create"],
    before=[
        "test_organizations.py::test_organsiation_delete",
        "test_teams.py::test_team_delete",
    ],
)
def test_project_delete(
    glitchtip_client: GlitchtipClient,
    test_org: str,
    test_team: str,
    test_project: str,
) -> None:
    """Delete a project."""
    glitchtip_client.delete_project(test_org, test_project)
