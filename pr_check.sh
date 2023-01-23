#!/bin/bash
set -exv

# Build Image
docker build . -t glitchtip:latest
