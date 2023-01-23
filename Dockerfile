# glitchtip-frontend image includes the glitchtip backend and the frontend
FROM registry.gitlab.com/glitchtip/glitchtip-frontend:v3.0.4
USER root
RUN apt-get update && apt-get install -y patch && rm -rf /var/lib/apt/lists/*

USER app:app
COPY *.patch .
# Do not send invitation emails
RUN cat 00-do-not-send-invitation-emails.patch | patch -p1
# Accept all open invitations automatically
RUN cat 01-relate-users.patch | patch -p1
