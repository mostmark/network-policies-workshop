#!/bin/bash

# Fail if QUAY_USER is not set or empty
if [[ -z "${QUAY_USER}" ]]; then
  echo "Error: QUAY_USER is not set."
  echo "Please export QUAY_USER before running this script, e.g.:"
  echo "  export QUAY_USER=your-quay-username"
  exit 1
fi

IMAGE="quay.io/$QUAY_USER/network-policies-lab:latest"

podman manifest rm "$IMAGE" 2>/dev/null || true
podman manifest create "$IMAGE"
podman build --platform linux/amd64,linux/arm64 --manifest "$IMAGE" .
podman manifest push --all "$IMAGE"

echo ""
echo "=============================================="
echo "✅ Build and push successful!"
echo "Image pushed to: $IMAGE"
echo ""
echo "You can run the container using:"
echo "  podman run --rm -p 8080:8080 $IMAGE"
echo "=============================================="