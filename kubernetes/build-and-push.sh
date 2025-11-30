#!/bin/bash

# Configuration
REGISTRY="rg.fr-par.scw.cloud/srdp-registry" # REPLACE THIS with your actual Registry Endpoint from the previous step
VERSION="v1.0"

echo "Building and Pushing SRDP Images"
echo "Target Registry: $REGISTRY"
echo "Version: $VERSION"

# Build Marimo
echo "Building Marimo..."
docker build --platform linux/amd64 -t $REGISTRY/marimo:$VERSION ./marimo # Assuming your Dockerfile is in a folder named 'marimo'
docker push $REGISTRY/marimo:$VERSION

# 2Build Quarto
echo "Building Quarto..."
docker build --platform linux/amd64 -t $REGISTRY/quarto:$VERSION ./quarto # Assuming your Dockerfile is in a folder named 'quarto'
docker push $REGISTRY/quarto:$VERSION

echo "Done! Images pushed."