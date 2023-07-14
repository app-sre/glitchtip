#!/bin/bash
set -e

export NO_PUSH=1
exec ./build_deploy.sh
