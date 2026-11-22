---
name: ieum-ship
description: One-shot ship for Ieum: pull, commit pending work, bump the version, build the signed + notarized binary, tag and push, publish the GitHub Release, update the website and the Homebrew cask. Use when the owner says "커밋/빌드/바이너리/배포", "ship it", or "홈페이지 업데이트" in one request.
---

# Ieum ship (commit → binary → release → site → tap)

The entry point for a full ship. The detailed steps, failure modes and verification commands live in
`.claude/skills/ieum-release/SKILL.md`; this skill adds what comes before them (pull, committing pending work, choosing the version)
and fixes the order. Answer the owner in Korean throughout.

Authorization: a message that says 배포 / 푸시 / tag / 바이너리 authorizes the whole sequence below (AGENTS.md). A message that only says
"홈페이지 업데이트" authorizes step 8 alone. Ask first for anything else outward-facing.

## 0. Environment

```sh
cd ~/Projects/stt
export SIGN_IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
export NOTARY_PROFILE=stt-notary
gh auth status && npx wrangler whoami    # both must be logged in
```

Never print or commit the identity string (it holds the legal name and team id).

## 1. Pull and look

`git pull --ff-only`, then `git log --oneline <last tag>..HEAD` and `git status`. Read what came in: someone else (another agent, a PR) may
have pushed. Decide from it whether the release has user-visible changes. Engine, timing or pipeline changes are benchmarked
before shipping (`ieum-benchmark`, old tag built in a `git worktree` vs HEAD, 2 runs each); a change that does not do what it claims is
switched off or held, after asking the owner. `say` sometimes hangs forever on long text: kill it and generate only the clips you need.

## 2. Commit pending work

If the tree has local changes that belong to the release, commit them first as their own commit(s) with a descriptive message
(not "Release x.y.z") and the trailer from AGENTS.md. Do not commit stray files (`.omc` state, `/tmp` output, `.build`).

## 3. Version

Patch bump (0.18.0 → 0.18.1) for fixes, refactors and small polish; minor (0.18 → 0.19) for a feature users should notice.
Build number +1. Edit `Resources/App/Info.plist`, the badge and the "Version x.y.z." line in `README.md`. A minor release gets a
What's new page (`Sources/OverlayApp/Updates/WhatsNewView.swift`, see AGENTS.md); a patch usually does not.
Update the test count in `README.md` / `AGENTS.md` if it changed, and the "State at hand-off" line in `AGENTS.md`.

## 4. Test and build

```sh
swift test                         # all green, otherwise stop
make app-release SIGN_IDENTITY="$SIGN_IDENTITY" NOTARY_PROFILE=$NOTARY_PROFILE   # expect "accepted / Notarized Developer ID"
make dmg         SIGN_IDENTITY="$SIGN_IDENTITY" NOTARY_PROFILE=$NOTARY_PROFILE
```

Build output must be warning-free. If notarization hangs, see ieum-release step 5.

## 5. Commit, tag, push

`git commit -am "Release x.y.z"` (+ one-paragraph summary + trailer), `git tag -a vx.y.z -m "Ieum x.y.z"`, `git push origin main --tags`.
Never move or re-create an existing tag; if one is wrong, ship the next patch.
Other agents merge PRs into `main` while a release builds. If the push of `main` is rejected, `git fetch` and **merge** `origin/main`
(do not rebase: the tag must stay on `main`), run `swift test`, push; check `git merge-base --is-ancestor vx.y.z origin/main`.
The binary is the one built from the tag; what came in ships next time.

## 6. GitHub Release

```sh
gh release create vx.y.z .build/app/Ieum.dmg --title "Ieum x.y.z" --notes "$(printf -- '- …\n- …\n---\n- …\n- …\n')"
```

At most 3 one-line bullets per language (≈52 English / 26 Korean characters), English, a `---` line, Korean.

## 7. Verify the public download

```sh
curl -sL -o /tmp/dl.dmg -w "%{http_code} %{size_download}\n" https://github.com/stoneidev/ieum/releases/latest/download/Ieum.dmg
shasum -a 256 /tmp/dl.dmg .build/app/Ieum.dmg   # equal
xcrun stapler validate /tmp/dl.dmg
```

## 8. Website

Edit text in `site-src/index.template.html` (all four languages side by side) if the release changes what the site says;
check locally with `python3 Scripts/build-site.py /tmp/out --allow-missing`. Then always run `Scripts/deploy-site.sh` **after** step 6:
it stamps version and size from the latest release and writes `latest.json`, which is what offers the update to installed apps.
Check `curl -s https://ieum.calmwork.today/latest.json` shows the new version. Never deploy `site/` directly.

## 9. Homebrew tap

In `~/Projects/homebrew-tap`: set `version` and `sha256` (of `/tmp/dl.dmg`) in `Casks/ieum.rb`,
commit "ieum x.y.z", push. Brew reads its own clone (`brew --repository stoneidev/tap`), so run
`git -C "$(brew --repository stoneidev/tap)" pull --ff-only` before `brew audit --cask --online stoneidev/tap/ieum`; otherwise it audits
the old version and complains that livecheck found the new one.

## 10. Report (Korean)

Version, release URL, what is in it, what was verified (tests, notarization, download hash, feed, audit) and what was not.
