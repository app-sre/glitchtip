import pytest
from reconcile.utils.glitchtip import GlitchtipClient


def test_organsiation_create(
    glitchtip_client: GlitchtipClient,
    test_org: str,
    delete_test_org_before_start: None,
) -> None:
    """Create a new organization."""
    org = glitchtip_client.create_organization(test_org)
    assert org.name == test_org


@pytest.mark.order(after="test_organsiation_get")
def test_organsiation_delete(glitchtip_client: GlitchtipClient, test_org: str) -> None:
    """Delete an organization."""
    glitchtip_client.delete_organization(test_org)


@pytest.mark.order(after="test_organsiation_create")
def test_organsiation_get(glitchtip_client: GlitchtipClient, test_org: str) -> None:
    """Get an organization."""
    orgs = glitchtip_client.organizations()
    assert test_org in [org.name for org in orgs]
