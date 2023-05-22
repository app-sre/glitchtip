# glitchtip-frontend image includes the glitchtip backend and the frontend
FROM registry.gitlab.com/glitchtip/glitchtip-frontend:v3.2.0
USER root
RUN apt-get update && apt-get install -y patch && rm -rf /var/lib/apt/lists/*

USER app:app
COPY patches /code/patches
# Do not send invitation emails
RUN cat patches/00-do-not-send-invitation-emails.patch | patch -p1
# Accept all open invitations automatically
RUN cat patches/01-automatically-accept-open-inivitations-at-login.patch | patch -p1

# Our appsre custom scripts
COPY appsre /code/appsre
