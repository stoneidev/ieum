#!/bin/zsh
# Deploys site/ to the Cloudflare Pages project "ieum" (https://ieum.calmwork.today).
# - Copies the folder first without .omc: tool state written there by hooks would otherwise be published.
# - Stamps the page with the version and size of the latest GitHub release ({{VERSION}}, {{SIZE}}), so the site shows exactly
#   what the download button gives. Needs `gh` (logged in).
set -e
cd "$(dirname "$0")/.."
info=$(gh release view --repo stoneidev/ieum --json tagName,assets -q '.tagName + " " + (.assets[0].size | tostring)')
tag=${info%% *}
bytes=${info##* }
version=${tag#v}
size=$(python3 -c "print(f'{$bytes / 1e6:.1f} MB')")
tmp=$(mktemp -d)
rsync -a --exclude '.omc' site/ "$tmp/"
sed -i '' "s/{{VERSION}}/$version/g; s/{{SIZE}}/$size/g" "$tmp/index.html"
if grep -q '{{' "$tmp/index.html"; then echo "unreplaced placeholder in index.html" >&2; exit 1; fi
echo "deploying version $version ($size)"
npx --yes wrangler pages deploy "$tmp" --project-name ieum --branch main
rm -rf "$tmp"
