# glitchtip
AppSRE glitchtip deployment


## Release Process

* See [glitchtip-frontend images](https://gitlab.com/glitchtip/glitchtip-frontend/container_registry/812701?orderBy=NAME&sort=desc&search[]=v&search[]=) for the latest version available.
* Change the image tag in the [Dockerfile](Dockerfile)
* Changes are deployed automatically to the staging environment
* Manual testing in the staging environment
* For the production enviroment update `$ref` in [saas file](https://gitlab.cee.redhat.com/service/app-interface/-/blob/master/data/services/glitchtip/cicd/saas.yaml)
