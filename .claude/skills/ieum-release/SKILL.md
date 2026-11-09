---
name: ieum-release
description: Cut an Ieum release: bump version, build, sign, notarize app and DMG, tag, push, GitHub Release with the DMG, verify the public download, deploy the site. Use when the owner asks to deploy / release / push with a tag and a binary.
---

# Ieum release runbook

Preconditions: clean `main`, `swift test` green, the owner has asked for a release (it publishes a binary and uploads to Apple).
Needs: Xcode 26, a *Developer ID Application* identity in the keychain, a `notarytool` keychain profile (`stt-notary` on the owner's Mac), `gh` logged in as `stoneidev`, `wrangler` logged in.

```sh
cd <repo>
export SIGN_IDENTITY="Developer ID Application: <name> (<team id>)"   # security find-identity -v -p codesigning
export NOTARY_PROFILE=stt-notary
```

1. **Version.** Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/App/Info.plist` (build number +1), the version badge and the
   "Version x.y.z." line in `README.md`. Pick the next patch (0.2.6 → 0.2.7) unless told otherwise.
2. **Tests.** `swift test` (143+ pass).
3. **App.** `make app-release SIGN_IDENTITY="$SIGN_IDENTITY" NOTARY_PROFILE=$NOTARY_PROFILE`. It signs with the hardened runtime, notarizes, staples and
   runs `spctl`. Expect "accepted / Notarized Developer ID". Takes about a minute.
4. **DMG.** `make dmg SIGN_IDENTITY=… NOTARY_PROFILE=…` (does not rebuild the app, so the stapled ticket is kept).
   If it hangs for minutes with no network connection and `xcrun notarytool history --keychain-profile $NOTARY_PROFILE` shows no new `Ieum.dmg`,
   kill `notarytool submit` and rerun `make dmg` only.
5. **Commit and tag.** `git add -A; git commit` (message "Release x.y.z" + one-paragraph summary + trailer), `git tag -a vx.y.z -m "Ieum x.y.z"`,
   `git push origin main --tags`. Never move an existing tag.
6. **GitHub Release.** `gh release create vx.y.z .build/app/Ieum.dmg --title "Ieum x.y.z" --notes "<English bullets>"`. If `gh` answers 504 the release may exist
   as a draft with no asset: `gh release upload vx.y.z .build/app/Ieum.dmg --clobber` then `gh release edit vx.y.z --draft=false`.
7. **Verify the public download** (no login):
   ```sh
   curl -sL -o /tmp/dl.dmg -w "%{http_code} %{size_download}\n" https://github.com/stoneidev/ieum/releases/latest/download/Ieum.dmg
   shasum -a 256 /tmp/dl.dmg .build/app/Ieum.dmg     # the two hashes must be equal
   xcrun stapler validate /tmp/dl.dmg
   ```
8. **Site.** `Scripts/deploy-site.sh` (only if `site/` changed or the owner said "배포"). The download button points at `releases/latest/download/Ieum.dmg`, so it
   needs no edit per release. Check `curl -s -o /dev/null -w "%{http_code}" https://ieum.calmwork.today/`.
9. **Report** in Korean: version, release URL, what is in it, what was verified, what was not (for example first launch on another Mac).

Notes: the bundle id `today.calmwork.ieum` and the signing identity must not change between releases or users lose their permission grants.
The site must never be deployed straight from `site/` (hook state in `site/.omc`): use the script.
