#!/bin/zsh
# Deploys site/ to the Cloudflare Pages project "ieum" (https://ieum.calmwork.today).
# - Copies the folder first without .omc: tool state written there by hooks would otherwise be published.
# - Stamps the page with the version and size of the latest GitHub release ({{VERSION}}, {{SIZE}}).
# - Writes latest.json, the update feed the app reads (version, download address, SHA-256, notes). Publishing it is what offers
#   a release to installed apps, so run this after the release exists.
# Usage: Scripts/deploy-site.sh [--dry-run]    (--dry-run prints latest.json and deploys nothing)
set -e
cd "$(dirname "$0")/.."
repo=stoneidev/ieum
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

tag=$(gh release view --repo $repo --json tagName -q .tagName)
version=${tag#v}
gh release download "$tag" --repo $repo --pattern Ieum.dmg --dir "$tmp/dl"
bytes=$(stat -f %z "$tmp/dl/Ieum.dmg")
sha=$(shasum -a 256 "$tmp/dl/Ieum.dmg" | awk '{print $1}')
size=$(python3 -c "print(f'{$bytes / 1e6:.1f} MB')")

rsync -a --exclude '.omc' site/ "$tmp/site/"
sed -i '' "s/{{VERSION}}/$version/g; s/{{SIZE}}/$size/g" "$tmp/site/index.html"
if grep -q '{{' "$tmp/site/index.html"; then echo "unreplaced placeholder in index.html" >&2; exit 1; fi

# Release notes: English bullets, then a line with --- , then the Korean bullets.
gh release view "$tag" --repo $repo --json body -q .body > "$tmp/body.md"
python3 -I - "$version" "$tag" "$bytes" "$sha" "$tmp/body.md" "$tmp/site/latest.json" <<'PY'
import json, sys
version, tag, size, sha, body_path, out = sys.argv[1:]
body = open(body_path, encoding="utf-8").read().replace("\r", "")
english, _, korean = body.partition("\n---")
bullets = lambda text: [line[2:].strip() for line in text.splitlines() if line.startswith("- ") and "notarized by Apple" not in line]
notes = {"en": bullets(english)}
if bullets(korean):
    notes["ko"] = bullets(korean)
feed = {
    "version": version,
    "url": f"https://github.com/stoneidev/ieum/releases/download/{tag}/Ieum.dmg",
    "sha256": sha,
    "size": int(size),
    "minimumMacOS": "14.0",
    "notes": notes,
}
json.dump(feed, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
if [ "$1" = "--dry-run" ]; then echo "version $version ($size)"; cat "$tmp/site/latest.json"; exit 0; fi
echo "deploying version $version ($size)"
npx --yes wrangler pages deploy "$tmp/site" --project-name ieum --branch main
