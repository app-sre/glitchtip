# ---- Upstream Glitchtip image ----
# Attention: Update the GLITCHTIP_VERSION also below in the release-glitchtip stage!
ARG GLITCHTIP_VERSION=v4.1.5
# glitchtip-frontend image includes the glitchtip backend and the frontend
FROM registry.gitlab.com/glitchtip/glitchtip-frontend:${GLITCHTIP_VERSION} as upstream-glitchtip

FROM registry.access.redhat.com/ubi9/ubi-minimal:9.3 as base-python
ENV PYTHONUNBUFFERED=1
RUN microdnf upgrade -y && \
    microdnf install -y \
        procps \
        shadow-utils \
        python3.11 && \
    microdnf clean all && \
    update-alternatives --install /usr/bin/python3 python /usr/bin/python3.11 1 && \
    ln -snf /usr/bin/python3.11 /usr/bin/python && \
    python3 -m ensurepip

# ---- Interims image to get and build all the python dependencies ----
FROM base-python as build-python
ENV POETRY_HOME=/opt/poetry \
    POETRY_VIRTUALENVS_CREATE=false \
    PIP_DISABLE_PIP_VERSION_CHECK=on

WORKDIR /code
COPY --from=upstream-glitchtip /code/ /code/

RUN microdnf install -y \
        libxml2-devel \
        libpq-devel \
        gcc \
        pcre2-devel \
        python3.11-devel

RUN python3 - < <(curl -sSL https://install.python-poetry.org)
RUN $POETRY_HOME/bin/poetry install --no-interaction --no-ansi --only main
# install some additional python packages
RUN python3 -m pip install uwsgitop locust

# ---- Interims image to patch the upstream glitchtip code with our customizations ----
FROM upstream-glitchtip as patched-glitchtip
USER root
RUN apt-get update && apt-get install -y patch

COPY patches /code/patches
# Do not send invitation emails
RUN cat patches/00-skip-user-invitation-process.patch | patch -p1
# add https:// to the s3 endpoint url
RUN cat patches/04-aws-s3-endpoint-url.patch | patch -p1

# Our appsre custom scripts
COPY appsre /code/appsre
COPY bin/* /code/bin/

# ---- Bundle everything together in the final image ----
FROM base-python as release-glitchtip
ARG GLITCHTIP_VERSION=v4.1.4
ENV GLITCHTIP_VERSION ${GLITCHTIP_VERSION}
ENV PORT=8080
EXPOSE 8080

RUN microdnf install -y \
        libxml2 \
        pcre2 \
        libpq && \
    microdnf clean all

WORKDIR /code

# get all the python dependencies from the build-python stage
COPY --from=build-python /usr/local/lib/python3.11/site-packages/ /usr/local/lib/python3.11/site-packages/
COPY --from=build-python /usr/local/lib64/python3.11/site-packages/ /usr/local/lib64/python3.11/site-packages/
COPY --from=build-python /usr/local/bin/ /usr/local/bin/
# get the patched glitchtip code
COPY --from=patched-glitchtip /code/ /code/

RUN SECRET_KEY=ci ./manage.py collectstatic --noinput

RUN useradd -u 5000 app && chown app:app /code && chown app:app /code/uploads
USER app:app

CMD ["./bin/start.sh"]
