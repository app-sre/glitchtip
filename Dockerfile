#
# Upstream image (Glitchtip version)
#
ARG GLITCHTIP_VERSION=v4.2.5
ARG GLITCHTIP_IMAGE=registry.gitlab.com/glitchtip/glitchtip-frontend:${GLITCHTIP_VERSION}
FROM ${GLITCHTIP_IMAGE} AS upstream


#
# Base image
#
FROM registry.access.redhat.com/ubi9/python-312:9.6-1747333115@sha256:e80ff3673c95b91f0dafdbe97afb261eab8244d7fd8b47e20ffcbcfee27fb168 AS base
COPY --from=upstream /code/LICENSE /licenses/LICENSE

ARG GLITCHTIP_VERSION
ENV GLITCHTIP_VERSION=${GLITCHTIP_VERSION}
LABEL konflux.additional-tags="${GLITCHTIP_VERSION}"


#
# Build and patch Glitchtip
#
FROM base AS builder
ENV \
    # use venv from ubi image
    UV_PROJECT_ENVIRONMENT=$APP_ROOT \
    # compile bytecode for faster startup
    UV_COMPILE_BYTECODE="true" \
    # disable uv cache. it doesn't make sense in a container
    UV_NO_CACHE=true

COPY --from=ghcr.io/astral-sh/uv:0.7.9@sha256:563b73ab264117698521303e361fb781a0b421058661b4055750b6c822262d1e /uv /bin/uv
COPY --from=upstream --chown=1001:root /code ./

# Install the required packages
RUN uv sync --frozen --no-group dev

# Upgrade h11 CVE-2025-43859
RUN uv pip install --no-cache-dir "h11>=0.16.0"

# Our customizations
COPY bin/* ./bin/
COPY appsre ./appsre

# Apply our patches
COPY patches ./patches
# Do not send invitation emails
RUN cat patches/00-skip-user-invitation-process.patch | patch -p1
# add https:// to the s3 endpoint url
RUN cat patches/04-aws-s3-endpoint-url.patch | patch -p1
# WSGI prometheus
RUN cat patches/06-wsgi.patch | patch -p1
# Events counter - https://gitlab.com/glitchtip/glitchtip-backend/-/merge_requests/1528
RUN cat patches/07-events-counter.patch | patch -p1


#
# Final image
#
FROM base AS prod
ENV PORT=8080
EXPOSE ${PORT}

# get everything from the builder
COPY --from=builder $APP_ROOT/ $APP_ROOT/

# Collect static files
RUN SECRET_KEY=ci ./manage.py collectstatic --noinput

CMD ["./bin/start.sh"]


#
# Test image
#
FROM prod AS test
COPY --from=ghcr.io/astral-sh/uv:0.7.9@sha256:563b73ab264117698521303e361fb781a0b421058661b4055750b6c822262d1e /uv /bin/uv
ENV \
    # use venv from ubi image
    UV_PROJECT_ENVIRONMENT=$APP_ROOT \
    # disable uv cache. it doesn't make sense in a container
    UV_NO_CACHE=true

COPY Makefile pyproject.toml ./
COPY acceptance/ ./acceptance/
RUN make test
