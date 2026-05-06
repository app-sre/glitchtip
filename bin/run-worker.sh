#!/usr/bin/env bash
# Custom override of upstream run-worker.sh to add --health-check-file
# for kubernetes liveness/readiness probes (django-vtasks file-based health check).
export IS_WORKER="true"
export LOG_LEVEL=${LOG_LEVEL:-INFO}
set -e

. "$(dirname "$0")/tune-malloc.sh"

exec ./manage.py runworker --scheduler --health-check-file /tmp/worker_health
