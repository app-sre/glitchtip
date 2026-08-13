"""Regression test pinning the real JSON shape GlitchTip sends for a generic webhook alert recipient.

Not part of the upstream glitchtip-backend source: this file is COPY'd into
the built image inside the Docker `test` stage (see ../Dockerfile) and run
via `make test`, which Konflux already builds on every PR
(.tekton/glitchtip-main-pull-request.yaml sets target-stage: test).

Why this exists: glitchtip-jira-bridge had every incoming webhook alert
silently rejected for months because this exact payload shape drifted
upstream twice, and nothing anywhere exercised the real serialization code
and inspected what it actually produces. This test does.

Deliberately NOT a Django TestCase / GlitchTipTestCase: those spin up a
real Postgres test database before running anything, and none is reachable
during a plain `docker build` step. Instead this builds unsaved, in-memory
model instances and mocks the one DB-touching call
(gather_issue_tags), so the whole test runs via plain `python -m unittest`
with no database and no network at all.

The consumer contract itself (GlitchtipAlert/Attachment) is imported from
`glitchtip_jira_bridge_models.py`, which is not written here -- it's the
real `glitchtip_jira_bridge/models.py`, copied verbatim out of the actual
deployed consumer image at Docker build time (see ../Dockerfile). So this
test validates the captured payload against glitchtip-jira-bridge's real,
currently-deployed pydantic model, not a hand-maintained guess at its shape.
"""

import os
import unittest
from unittest import mock

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "glitchtip.settings")
os.environ.setdefault("SECRET_KEY", "ci")

import django

django.setup()

from apps.alerts.tests.glitchtip_jira_bridge_models import GlitchtipAlert
from apps.alerts.webhooks import send_issue_as_webhook
from apps.issue_events.constants import IssueEventType, LogLevel
from apps.issue_events.models import Issue
from apps.organizations_ext.models import Organization
from apps.projects.models import Project

WEBHOOK_URL = "https://example.invalid/webhook"


def _mock_aiohttp_session() -> tuple[mock.MagicMock, mock.MagicMock]:
    """Build a mock aiohttp.ClientSession that captures session.post() calls."""
    mock_response = mock.AsyncMock()
    mock_response.status = 200
    mock_response.__aenter__ = mock.AsyncMock(return_value=mock_response)
    mock_response.__aexit__ = mock.AsyncMock(return_value=False)

    mock_post = mock.MagicMock(return_value=mock_response)

    mock_session = mock.AsyncMock()
    mock_session.post = mock_post
    mock_session.__aenter__ = mock.AsyncMock(return_value=mock_session)
    mock_session.__aexit__ = mock.AsyncMock(return_value=False)

    return mock.MagicMock(return_value=mock_session), mock_post


class WebhookPayloadContractTests(unittest.IsolatedAsyncioTestCase):
    """Pins the real dict `send_issue_as_webhook` posts as JSON.

    GlitchTip's raw-SQL fast path for issue creation
    (apps/event_ingest/process_event.py::_create_issue_and_hash) hardcodes
    `culprit` to NULL for every issue, unconditionally, as of v6.2.3. That
    makes WebhookAttachment.text (== issue.culprit) always None, and
    WebhookPayload.to_dict() (added in 39a9d4da, "fix: fix support for
    mattermost webhooks") drops any attachment key whose value is None or
    [] -- so "text" is always omitted from a real issue-based webhook
    attachment in this version. If GlitchTip ever starts populating a real
    culprit again, "text" showing up is a welcome, contract-compatible
    change for glitchtip-jira-bridge -- relax the assertion below rather
    than treat it as a failure.
    """

    def setUp(self) -> None:
        tags_patcher = mock.patch(
            "apps.alerts.webhooks.gather_issue_tags",
            new=mock.AsyncMock(return_value=[]),
        )
        tags_patcher.start()
        self.addCleanup(tags_patcher.stop)

        # Avoids a real DNS lookup for the SSRF guard -- matches the pattern
        # already used in apps/alerts/tests/test_webhooks.py.
        url_allowed_patcher = mock.patch(
            "apps.alerts.webhooks._is_url_allowed",
            new=mock.AsyncMock(return_value=True),
        )
        url_allowed_patcher.start()
        self.addCleanup(url_allowed_patcher.stop)

        # Issue.level is a read-only proxy onto a related, DB-backed
        # IssueIndex row (the "hot-split" leaf table) -- irrelevant to this
        # test's purpose, so it's patched directly rather than faking that
        # relationship too.
        level_patcher = mock.patch.object(
            Issue, "level", new_callable=mock.PropertyMock, return_value=LogLevel.ERROR
        )
        level_patcher.start()
        self.addCleanup(level_patcher.stop)

        organization = Organization(name="Acceptance Org", slug="acceptance-org")
        project = Project(
            organization=organization,
            name="Acceptance Project",
            slug="acceptance-project",
        )
        self.issue = Issue(
            project=project,
            title="ZeroDivisionError: division by zero",
            culprit=None,
            type=IssueEventType.ERROR,
            metadata={},
        )
        self.issue.pk = 1

    async def test_real_issue_webhook_payload_matches_jira_bridge_contract(
        self,
    ) -> None:
        mock_constructor, mock_post = _mock_aiohttp_session()
        with mock.patch("aiohttp.ClientSession", mock_constructor):
            await send_issue_as_webhook(WEBHOOK_URL, [self.issue], 1)

        mock_post.assert_called_once()
        payload = mock_post.call_args.kwargs["json"]

        # The actual proof this test exists for: does glitchtip-jira-bridge's
        # real, currently-deployed pydantic model accept this payload at all?
        # Raises pydantic.ValidationError (failing the test) if not.
        alert = GlitchtipAlert(**payload)
        assert alert.attachments[0].title, f"title must never be empty: {payload!r}"
        assert alert.attachments[0].title_link, (
            f"title_link must never be empty: {payload!r}"
        )

        # GlitchtipAlert(**payload) alone can't distinguish "text omitted"
        # from "text explicitly null" -- both parse to attachments[0].text is
        # None. Pinning current, always-true (as of v6.2.3) behavior -- see
        # class docstring -- needs the raw dict.
        assert "text" not in payload["attachments"][0], (
            f"expected 'text' to be omitted from a real issue-based "
            f"attachment (see class docstring), got: {payload['attachments'][0]!r}"
        )


if __name__ == "__main__":
    unittest.main()
