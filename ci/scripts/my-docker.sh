#!/bin/bash
set -euo pipefail

# Default values if not set in environment
CARGO_PROFILE=${CARGO_PROFILE:-release}
ALWAYS_PULL=${ALWAYS_PULL:-false}
BUILDKITE_COMMIT=${BUILDKITE_COMMIT:-$(git rev-parse HEAD)}
arch=amd64
ghcraddr=${GHCR_ADDR:-"gladium08/streamer"}

echo "--- docker build and tag"
echo "CARGO_PROFILE is set to ${CARGO_PROFILE}"

echo "--- authenticating with docker"
if [ -z "${DOCKER_USERNAME:-}" ] || [ -z "${DOCKER_PASSWORD:-}" ]; then
    echo "Error: DOCKER_USERNAME and DOCKER_PASSWORD must be set"
    exit 1
fi

# Login to Docker
echo "${DOCKER_PASSWORD}" | docker login --username "${DOCKER_USERNAME}" --password-stdin

# Create buildx builder instance
docker buildx create \
  --name container \
  --driver=docker-container

# Set pull parameter based on ALWAYS_PULL env var
PULL_PARAM=""
if [[ "${ALWAYS_PULL}" = "true" ]]; then
  PULL_PARAM="--pull"
fi

# Build the image
docker buildx build -f docker/Dockerfile \
  --build-arg "GIT_SHA=${BUILDKITE_COMMIT}" \
  --build-arg "CARGO_PROFILE=${CARGO_PROFILE}" \
  -t "${ghcraddr}:${BUILDKITE_COMMIT}-${arch}" \
  --progress plain \
  --builder=container \
  --load \
  ${PULL_PARAM} \
  .

echo "--- check the image can start correctly"
container_id=$(docker run -d "${ghcraddr}:${BUILDKITE_COMMIT}-${arch}" playground)
sleep 10
container_status=$(docker inspect --format='{{.State.Status}}' "$container_id")

if [ "$container_status" != "running" ]; then
  echo "docker run failed with status $container_status"
  docker inspect "$container_id"
  docker logs "$container_id"
  exit 1
fi

# Clean up test container
echo "--- cleaning up test container"
docker stop "$container_id"
docker rm "$container_id"

# Push to registry
echo "--- pushing image to registry"
docker push "${ghcraddr}:${BUILDKITE_COMMIT}-${arch}"

echo "--- Build and push completed successfully"