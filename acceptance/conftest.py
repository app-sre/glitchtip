import os

import pytest
from reconcile.utils.glitchtip import GlitchtipClient
from reconcile.utils.rest_api_base import BearerTokenAuth


@pytest.fixture
def test_org() -> str:
    return "glitchtip-acceptance-org-12-34-56-78-90"


@pytest.fixture
def test_team() -> str:
    return "glitchtip-acceptance-team-12-34-56-78-90"


@pytest.fixture
def test_team2() -> str:
    return "glitchtip-acceptance-team2-12-34-56-78-90"


@pytest.fixture
def test_project() -> str:
    return "glitchtip-acceptance-project-12-34-56-78-90"


@pytest.fixture
def test_user() -> str:
    return "glitchtip-acceptance-user-12-34-56-78-90@example.com"


@pytest.fixture
def api_user() -> str:
    return os.environ.get(
        "GLITCHTIP_API_USER_EMAIL", "glitchtip@qontract-reconcile.org"
    )


@pytest.fixture
def glitchtip_client() -> GlitchtipClient:
    return GlitchtipClient(
        host=os.environ.get("GLITCHTIP_URL", "http://web:8080"),
        auth=BearerTokenAuth(os.environ.get("GLITCHTIP_API_USER_TOKEN", "token")),
    )


@pytest.fixture
def delete_test_org_before_start(
    glitchtip_client: GlitchtipClient, test_org: str
) -> None:
    """Delete the test organization before starting the tests. Maybe it's left-over from a previous run."""
    for org in glitchtip_client.organizations():
        if org.name == test_org:
            glitchtip_client.delete_organization(org.slug)
