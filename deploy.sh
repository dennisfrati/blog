#!/usr/bin/env bash

set -euo pipefail

source $HOME/.site-config

echo ">>> Building..."
hugo build

echo ">>> Uploading to S3..."
aws s3 sync public/ s3://${BUCKET} --delete --profile ${PROFILE}

echo ">>> Invalidating cache..."
aws cloudfront create-invalidation \
  --distribution-id ${CF_ID} \
  --paths "/*" \
  --profile ${PROFILE}

echo ">>> Done!"
