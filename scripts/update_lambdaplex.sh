#!/usr/bin/env bash
set -euo pipefail

# Update local tracking branch from petioptrv and fast-forward master.

git fetch petioptrv

git checkout feat/lambdaplex-connector
git pull --ff-only

git checkout master
git merge --ff-only feat/lambdaplex-connector

cat <<'MSG'
Done. If you want to publish to origin, run:
  git push origin master
MSG
