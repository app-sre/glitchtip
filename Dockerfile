ARG GLITCHTIP_VERSION=v5.0.9
ARG GLITCHTIP_IMAGE=registry.gitlab.com/glitchtip/glitchtip-frontend:${GLITCHTIP_VERSION}
#
# Base image
#
FROM registry.access.redhat.com/ubi9/python-312:9.6-1760372467@sha256:f17b0788b7eff1683ff8ba7c6a17b907648753d489e8d7d3975eaf6c41644287 AS base
ARG GLITCHTIP_IMAGE
COPY --from=${GLITCHTIP_IMAGE} /code/LICENSE /licenses/LICENSE

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

COPY --from=ghcr.io/astral-sh/uv:0.9.2@sha256:6dbd7c42a9088083fa79e41431a579196a189bcee3ae68ba904ac2bf77765867 /uv /bin/uv
ARG GLITCHTIP_IMAGE
COPY --from=${GLITCHTIP_IMAGE} --chown=1001:root /code ./

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

# Test GLITCHTIP_VERSION is set
RUN if [ -z "${GLITCHTIP_VERSION}" ]; then echo "Error: The environment variable GLITCHTIP_VERSION is not set or empty." >&2; false; fi

# get everything from the builder
COPY --from=builder $APP_ROOT/ $APP_ROOT/

# Collect static files
RUN SECRET_KEY=ci ./manage.py collectstatic --noinput

CMD ["./bin/start.sh"]


#
# Test image
#
FROM prod AS test
COPY --from=ghcr.io/astral-sh/uv:0.9.2@sha256:6dbd7c42a9088083fa79e41431a579196a189bcee3ae68ba904ac2bf77765867 /uv /bin/uv
ENV \
    # use venv from ubi image
    UV_PROJECT_ENVIRONMENT=$APP_ROOT \
    # disable uv cache. it doesn't make sense in a container
    UV_NO_CACHE=true

COPY Makefile pyproject.toml ./
COPY acceptance/ ./acceptance/
RUN make test
