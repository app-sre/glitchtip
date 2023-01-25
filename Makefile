
build-acceptance-tests:
	NO_PUSH=1 ./build_deploy.sh

run-glitchtip:
	docker-compose -f docker-compose.yml up

run-acceptance-tests-locally: build-acceptance-tests
	docker run --rm -it --network qontract-development glitchtip-acceptance
