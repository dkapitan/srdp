#!/bin/sh

# Configuration
REGISTRY="rg.fr-par.scw.cloud/srdp-registry" # REPLACE THIS with your actual Registry Endpoint from the previous step
VERSION="v1.0"

echo "Logging into Scaleway Registry"
echo $SCW_SECRET_KEY | docker login rg.fr-par.scw.cloud -u nologin --password-stdin

echo "Building and Pushing SRDP Images"
echo "Target Registry: $REGISTRY"
echo "Version: $VERSION"

# Build Marimo
echo "Building Marimo..."
docker build --platform linux/amd64 -t $REGISTRY/marimo:$VERSION ../local/apps/marimo
docker push $REGISTRY/marimo:$VERSION

# 2Build Quarto
echo "Building Quarto..."
docker build --platform linux/amd64 -t $REGISTRY/quarto:$VERSION ../local/apps/quarto
docker push $REGISTRY/quarto:$VERSION

echo "Done! Images pushed."