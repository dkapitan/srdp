#!/bin/sh

SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# Configuration
REGISTRY="rg.nl-ams.scw.cloud/srdp-registry"
VERSION="v1.0"

echo "Logging into Scaleway Registry"
echo "$SCW_SECRET_KEY" | docker login rg.nl-ams.scw.cloud -u nologin --password-stdin

echo "Building and Pushing SRDP Images"
echo "Target Registry: $REGISTRY"
echo "Version: $VERSION"

echo "Building Marimo..."
docker build --platform linux/amd64 -t "$REGISTRY/marimo:$VERSION" "$REPO_ROOT/local/apps/marimo"
docker push "$REGISTRY/marimo:$VERSION"

echo "Building Quarto..."
docker build --platform linux/amd64 -t "$REGISTRY/quarto:$VERSION" "$REPO_ROOT/local/apps/quarto"
docker push "$REGISTRY/quarto:$VERSION"

echo "Building SRDP ETL (Dagster user code)..."
docker build --platform linux/amd64 -t "$REGISTRY/srdp-etl:$VERSION" "$REPO_ROOT/kubernetes/apps/srdp-etl"
docker push "$REGISTRY/srdp-etl:$VERSION"

echo "Done! Images pushed."
