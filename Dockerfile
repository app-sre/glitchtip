#
# Upstream image (Glitchtip version)
#
ARG GLITCHTIP_VERSION=v4.1.5
ARG GLITCHTIP_IMAGE=registry.gitlab.com/glitchtip/glitchtip-frontend:${GLITCHTIP_VERSION}
FROM ${GLITCHTIP_IMAGE} AS upstream


#
# Base image
#
FROM registry.access.redhat.com/ubi9/python-312:9.5-1739191330@sha256:4b4a9f1208c49ecb274647e65f1e4544621f13ebbce31a743775bbd57f583529 AS base
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

COPY --from=ghcr.io/astral-sh/uv:0.6.0@sha256:63b7453435641145dc3afab79a6bc2b6df6f77107bec2d0df39fd27b1c791c0a /uv /bin/uv
COPY --from=upstream --chown=1001:root /code ./

# Install the required packages
RUN uv sync --frozen --no-group dev

# Our customizations
COPY bin/* ./bin/
COPY appsre ./appsre

# Apply our patches
COPY patches ./patches
# Do not send invitation emails
RUN cat patches/00-skip-user-invitation-process.patch | patch -p1
# add https:// to the s3 endpoint url
RUN cat patches/04-aws-s3-endpoint-url.patch | patch -p1


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
COPY --from=ghcr.io/astral-sh/uv:0.6.0@sha256:63b7453435641145dc3afab79a6bc2b6df6f77107bec2d0df39fd27b1c791c0a /uv /bin/uv
ENV \
    # use venv from ubi image
    UV_PROJECT_ENVIRONMENT=$APP_ROOT \
    # disable uv cache. it doesn't make sense in a container
    UV_NO_CACHE=true

COPY Makefile pyproject.toml ./
COPY acceptance/ ./acceptance/
RUN make test
