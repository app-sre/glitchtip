# glitchtip-frontend image includes the glitchtip backend and the frontend
FROM registry.gitlab.com/glitchtip/glitchtip-frontend:v3.0.4
USER root
RUN apt-get update && apt-get install -y patch git && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir -U "git+https://github.com/chassing/django-allauth.git@abae97f319a15f987e4695564529c7c1bd9f017d"

USER app:app
COPY *.patch /code/
# Do not send invitation emails
RUN cat 00-do-not-send-invitation-emails.patch | patch -p1
# Accept all open invitations automatically
RUN cat 01-automatically-accept-open-inivitations-at-login.patch | patch -p1
