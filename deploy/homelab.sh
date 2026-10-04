#!/usr/bin/env bash
# Deploy a committed revision; no credentials or untracked files leave the Mac.
set -euo pipefail
cd "$(dirname "$0")/.."
release=$(git rev-parse --verify "${1:-HEAD}^{commit}")
[[ "$release" =~ ^[0-9a-f]{40}$ ]]
target="/home/irrssue/apps/poki/releases/$release"
git archive "$release" | ssh irrssue@homelab "mkdir -p '$target' && tar -xf - -C '$target'"
ssh irrssue@homelab "bash -s -- '$target' '$release'" <<'REMOTE'
set -euo pipefail
target=$1
export POKI_RELEASE=$2
cd "$target"
# A failed build/test leaves the current containers running.
docker compose -f deploy/compose.yml build
docker compose -f deploy/compose.yml up -d --wait --wait-timeout 120
curl --fail --silent --show-error http://127.0.0.1:3014/v1/health
ln -sfn "$target" /home/irrssue/apps/poki/current
printf '\nDeployed %s\n' "$POKI_RELEASE"
REMOTE
curl --fail --silent --show-error --retry 8 --retry-all-errors --retry-delay 5 \
  https://poki.irrssue.com/v1/health
printf '\n'
