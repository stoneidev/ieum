#!/bin/zsh
# Deploys site/ to the Cloudflare Pages project "ieum" (https://ieum.calmwork.today).
# Copies the folder first without .omc: tool state written there by hooks would otherwise be published.
set -e
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
rsync -a --exclude '.omc' site/ "$tmp/"
npx --yes wrangler pages deploy "$tmp" --project-name ieum --branch main
rm -rf "$tmp"
