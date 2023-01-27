# Red Hat AppSRE glitchtip deployment

<img src="https://glitchtip.com/assets/home/issues-page@2x.webp">

## What is Glitchtip?

[Glitchtip](https://glitchtip.com) is a Sentry-compatible error-tracking service that helps you to find and fix bugs faster. It is a self-hosted alternative to Sentry.

## Release Process

* See [glitchtip-frontend images](https://gitlab.com/glitchtip/glitchtip-frontend/container_registry/812701?orderBy=NAME&sort=desc&search[]=v&search[]=) for the latest version available.
* Change the image tag in the [Dockerfile](Dockerfile)
* Changes are deployed automatically to the staging environment
* CI/CD acceptance tests are run automatically in [glitchtip-stage](https://console-openshift-console.apps.app-sre-stage-0.k3s7.p1.openshiftapps.com/k8s/ns/glitchtip-stage/core~v1~Pod?name=accept) namespace
* After the acceptance tests pass, the image is promoted to the production environment automatically
