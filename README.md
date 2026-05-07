# Red Hat AppSRE GlitchTip Deployment

<img src="https://glitchtip.com/assets/home/issues-page@2x.webp">

## What is GlitchTip?

[GlitchTip](https://glitchtip.com) is a Sentry-compatible error-tracking service that helps you find and fix bugs faster. It is a self-hosted alternative to Sentry.

**Upstream repositories:**

- Backend: <https://gitlab.com/glitchtip/glitchtip-backend>
- Frontend: <https://gitlab.com/glitchtip/glitchtip-frontend>
- Changelog: see `CHANGELOG` in the backend repo

## Architecture

The deployment consists of the following components in OpenShift (defined in `openshift/template.autoscaler.yaml`):

| Component                          | Type       | Purpose                                                          |
| ---------------------------------- | ---------- | ---------------------------------------------------------------- |
| **glitchtip-web**                  | Deployment | Serves the API and frontend (granian ASGI server)                |
| **glitchtip-worker**               | Deployment | Processes async tasks via django-tasks (`runworker --scheduler`) |
| **glitchtip-notification-cleaner** | CronJob    | Cleans the notification table daily (04:32 UTC)                  |
| **KEDA ScaledObject**              | Autoscaler | Scales workers based on event ingest rate (prometheus query)     |

### Web

- 3 replicas (default), rolling update (maxUnavailable: 0)
- Port 8000 (granian), metrics on port 9090
- Init containers: DB migration (`bin/run-migrate.sh`), API user creation (`appsre/create-api-users.py`)
- TCP-based readiness, startup, and liveness probes

### Worker

- 3-15 replicas, auto-scaled by KEDA based on event ingest rate
- Runs `./manage.py runworker --scheduler --health-check-file /tmp/worker_health`
- `--scheduler` replaces celery-beat (runs on every worker, coordinated via DB backend)
- File-based liveness/readiness probes: checks `/tmp/worker_health` was modified within last 15 seconds

### Secrets

| Secret          | Keys                                                                          |
| --------------- | ----------------------------------------------------------------------------- |
| `glitchtip-rds` | `db.host`, `db.password`, `db.name`, `db.user`                                |
| `redis-url`     | `redis.url`                                                                   |
| `smtp`          | `server`, `password`, `username`, `port`, `require_tls`                       |
| `glitchtip-s3`  | `aws_access_key_id`, `aws_secret_access_key`, `bucket`, `endpoint` (optional) |

## Customizations

We apply patches and ship custom scripts on top of the upstream GlitchTip image.

### Patches

Applied during the Docker build (`Dockerfile`):

| Patch                             | File                            | Purpose                                                                                                                        |
| --------------------------------- | ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `00-skip-user-invitation-process` | `apps/organizations_ext/api.py` | Skips invitation emails and auto-creates Django users when adding members to an organization                                   |
| `04-aws-s3-endpoint-url`          | `glitchtip/settings.py`         | Prepends `https://` to `AWS_S3_ENDPOINT_URL`                                                                                   |
| `07-events-counter`               | `apps/observability/metrics.py` | Adds `glitchtip_events` prometheus gauge with `project` and `organization` labels                                              |
| `08-ingest-prometheus-middleware` | `glitchtip/ingest_asgi.py`      | Restores `PrometheusBeforeMiddleware` / `PrometheusAfterMiddleware` on ingest endpoints (stripped by upstream for performance) |

### Custom Scripts

| Script                            | Used by           | Purpose                                                                           |
| --------------------------------- | ----------------- | --------------------------------------------------------------------------------- |
| `bin/run-worker.sh`               | Worker deployment | Overrides upstream to add `--health-check-file /tmp/worker_health` for k8s probes |
| `appsre/create-api-users.py`      | Init container    | Creates superusers and API tokens from `APPSRE_API_USER_*` env vars               |
| `appsre/cleanup-notifications.py` | CronJob           | Deletes all notification records to prevent unbounded table growth                |

## Prometheus Metrics

### Custom Metrics (via patches)

| Metric                    | Type  | Labels                    | Source     |
| ------------------------- | ----- | ------------------------- | ---------- |
| `glitchtip_organizations` | Gauge | —                         | upstream   |
| `glitchtip_projects`      | Gauge | `organization`            | patch `09` |
| `glitchtip_events`        | Gauge | `project`, `organization` | patch `09` |

### Django Prometheus Metrics (via middleware)

These are provided by `django-prometheus` and require the middleware to be active (patch `08` restores this for ingest endpoints):

- `django_http_requests_total_by_view_transport_method_total` — request count per view (used by KEDA autoscaler)
- `django_http_requests_latency_seconds_by_view_method_bucket` — latency histogram per view
- `django_http_responses_total_by_status_total` — response count per HTTP status
- `django_http_requests_total_by_transport_total` — request count by transport

### Granian Server Metrics

Exposed on port 9090 (configured via `GRANIAN_METRICS_ENABLED=1`, `GRANIAN_METRICS_PORT=9090`).

## Grafana Dashboards

All dashboards are in `grafana/`:

| Dashboard    | File                    | What it monitors                                                                                                    |
| ------------ | ----------------------- | ------------------------------------------------------------------------------------------------------------------- |
| **Main**     | `grafana-dashboard.yml` | HAProxy availability, events/min, RDS connections/IOPS/latency, ElastiCache, pod resources, API latency percentiles |
| **Django**   | `grafana-django.yml`    | HTTP request/response rates, latency percentiles, top 10 endpoints, response body sizes                             |
| **Projects** | `grafana-project.yml`   | Per-project event counts and rates (uses `glitchtip_events` from patch `07`)                                        |
| **SLO**      | `grafana-slo.yml`       | Service level objective tracking                                                                                    |

## Release / Upgrade Process

1. Check available versions at [glitchtip-frontend images](https://gitlab.com/glitchtip/glitchtip-frontend/container_registry/812701?orderBy=NAME&sort=desc&search[]=v&search[]=)
2. Read the upstream `CHANGELOG` for breaking changes between current and target version
3. Update `GLITCHTIP_VERSION` in `Dockerfile`
4. Verify all patches still apply — build locally with `make build`
5. Update patches if they fail to apply (upstream code changed)
6. Push to branch, create PR
7. Changes deploy automatically to **staging**
8. CI/CD acceptance tests run automatically in [`glitchtip-stage`](https://console-openshift-console.apps.app-sre-stage-0.k3s7.p1.openshiftapps.com/k8s/ns/glitchtip-stage/core~v1~Pod?name=accept)
9. After acceptance tests pass, promoted to **production** manually via MR in app-interface.

## Post-Upgrade Checklist

After every upgrade, manually verify:

- [ ] **Build succeeds** — all patches apply cleanly
- [ ] **OIDC / SSO login works** — log in via the web UI
- [ ] **API user creation works** — `init-api-users` init container completes successfully
- [ ] **Event ingestion works** — send a test event via Sentry SDK and verify it appears in the UI
- [ ] **Worker pods become ready** — health check file `/tmp/worker_health` is being written
- [ ] **Web pod access logs** — verify web POD writes access logs
- [ ] **Prometheus metrics present**:
  - `glitchtip_events` (per project/org)
  - `glitchtip_organizations`
  - `glitchtip_projects`
  - `django_http_requests_total_by_view_transport_method_total` for `events` views (used by KEDA autoscaler)
- [ ] **KEDA autoscaler** — check `ScaledObject` status, verify worker scaling on load
- [ ] **Grafana dashboards** — all 4 dashboards load and show data
- [ ] **Notification cleaner CronJob** — runs successfully on schedule
- [ ] **Acceptance tests pass** — automated in CI, but verify in staging

## Acceptance Tests

Located in `acceptance/`, run with `pytest`. Tests cover:

- Organization CRUD
- Team CRUD
- Project CRUD (including team assignment)
- Project alerts (webhook type, create/update/delete)
- User invite, role update, team assignment

Tests run in order (via `pytest-order`) and clean up after themselves.

**Environment variables:**

| Variable                   | Default                            | Purpose                    |
| -------------------------- | ---------------------------------- | -------------------------- |
| `GLITCHTIP_URL`            | `http://web:8080`                  | GlitchTip instance URL     |
| `GLITCHTIP_API_USER_EMAIL` | `glitchtip@qontract-reconcile.org` | API user for test auth     |
| `GLITCHTIP_API_USER_TOKEN` | `token`                            | Bearer token for API calls |

## Local Development

```bash
# start all services (requires external network "qontract-development")
docker-compose up

# build images locally
make build

# run linters and type checks
make test
```

The `docker-compose.yml` starts postgres, redis, web, worker, and init-api-users. Web is available at `http://localhost:8000`.

Default local users:

| Email                              | Password              | Token   |
| ---------------------------------- | --------------------- | ------- |
| `admin@admin.org`                  | `rev9tbk!YUE.wfy8uku` | —       |
| `glitchtip@qontract-reconcile.org` | —                     | `token` |
