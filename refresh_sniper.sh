#!/bin/bash

# Pull latest code
git pull

# Rebuild and restart containers
docker-compose up -d --build

# Prune old images to save space
docker image prune -f
