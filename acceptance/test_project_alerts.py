import pytest
from reconcile.utils.glitchtip import GlitchtipClient
from reconcile.utils.glitchtip.models import (
    ProjectAlert,
    ProjectAlertRecipient,
    RecipientType,
)


@pytest.fixture
def test_alert(
    glitchtip_client: GlitchtipClient,
    test_org: str,
    test_project: str,
) -> ProjectAlert:
    """Fetch our test alert from Glitchtip."""
    project_alerts = glitchtip_client.project_alerts(test_org, test_project)
    assert len(project_alerts) == 1
    return project_alerts[0]


@pytest.mark.order(
    after=["test_projects.py::test_project_create"],
    before=["test_projects.py::test_project_delete"],
)
def test_project_alert_create(
    glitchtip_client: GlitchtipClient,
    test_org: str,
    test_project: str,
) -> None:
    """Create a new project alert."""
    glitchtip_client.create_project_alert(
        test_org,
        test_project,
        ProjectAlert(
            name="glitchtip-acceptance-alert-12-34-56-78-90",
            timespan_minutes=1,
            quantity=1,
            recipients=[
                ProjectAlertRecipient(
                    recipient_type=RecipientType.WEBHOOK,
                    url="http://example.com/foobar/test",
                )
            ],
        ),
    )


@pytest.mark.order(
    after=["test_project_alert_create"],
    before=["test_project_alert_delete"],
)
def test_project_alert_get(test_alert: ProjectAlert) -> None:
    """Get a project alert."""
    assert test_alert.name is not None
    assert test_alert.pk is not None


@pytest.mark.order(
    after=["test_project_alert_create"],
    before=["test_project_alert_delete"],
)
def test_project_alert_update(
    glitchtip_client: GlitchtipClient,
    test_org: str,
    test_project: str,
    test_alert: ProjectAlert,
) -> None:
    """Update a project alert."""
    test_alert.timespan_minutes = 2000
    test_alert.name = "Updated alert"

    # update the alert
    glitchtip_client.update_project_alert(test_org, test_project, test_alert)

    # fetch the alert again
    project_alerts = glitchtip_client.project_alerts(test_org, test_project)
    assert len(project_alerts) == 1
    assert project_alerts[0].timespan_minutes == test_alert.timespan_minutes
    assert project_alerts[0].name == test_alert.name


@pytest.mark.order(
    after=["test_project_alert_create"],
    before=["test_projects.py::test_project_delete"],
)
def test_project_alert_delete(
    glitchtip_client: GlitchtipClient,
    test_org: str,
    test_project: str,
    test_alert: ProjectAlert,
) -> None:
    """Delete a project alert."""
    assert test_alert.pk is not None
    glitchtip_client.delete_project_alert(test_org, test_project, test_alert.pk)
