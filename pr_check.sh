#!/bin/bash
set -e

# Build Image
docker build . -t glitchtip:latest
