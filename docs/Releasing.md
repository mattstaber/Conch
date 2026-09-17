# Releases

## GitHub Actions

The **Build and release** workflow runs tests and builds an Apple silicon app for
pull requests, pushes to `main`, manual runs, and `v*` tags. It uses GitHub's
[`xcode-27` runner](https://github.blog/changelog/2026-09-10-xcode-27-runner-image-now-runs-on-macos-27/),
which provides the required macOS 27 test host and SDK. This runner is currently a
public preview; the workflow checks the host/SDK versions before building.

Every successful run uploads a `Conch-macOS-arm64` Actions artifact with a ZIP and
SHA-256 checksum. Actions artifacts expire after 14 days and generally require a
GitHub login. A version tag also publishes those files to a GitHub Release, where
users can download them without finding a workflow run.

After reviewing and pushing the desired commit, create a version tag, for example:

```sh
git tag v0.1.0
git push origin v0.1.0
```

Use a new `vMAJOR.MINOR.PATCH` tag for each release. The tag supplies the bundle
version; the workflow run number supplies its build number. The workflow never
changes the source plist. Do not move published tags. Re-running the same tag
replaces its binary assets, so prefer a new patch version for changed code.

No signing secrets are required for the default workflow. Build/PR jobs have
read-only repository permissions; only the tag-release job can write a release.
The ZIP is built with `ditto` so bundle structure and executable permissions survive
artifact upload/download. The app remains ad-hoc signed and **not notarized**.

## Local package

```sh
CONCH_VERSION=0.1.0 CONCH_BUILD_NUMBER=1 ./scripts/build.sh
./scripts/package.sh
```

Outputs are in `dist/`. Verify a downloaded pair from the same release with:

```sh
shasum -a 256 -c Conch-0.1.0-macOS-arm64.zip.sha256
```

A checksum detects a changed download; it does not replace trusting the publisher
or verifying a Developer ID signature.

## Developer ID signing and notarization

To remove the unsigned-developer first-launch hurdle, use an Apple Developer ID
Application certificate in your keychain and a configured `notarytool` profile:

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./scripts/build.sh
./scripts/package.sh
xcrun notarytool submit dist/Conch-0.1.0-macOS-arm64.zip \
  --keychain-profile ConchNotary --wait
# Continue only if notarization reports Accepted.
xcrun stapler staple build/Conch.app
xcrun stapler validate build/Conch.app
spctl --assess --type execute --verbose build/Conch.app
./scripts/package.sh
```

Use the actual version filename if different. Repackaging after stapling includes
the ticket and regenerates the checksum. These credentials are not configured by
the default workflow. Never commit certificates, private keys or passwords.

Before distributing a notarized build, test a downloaded copy on another Mac:
installation, audio permission, launch at login, playback, quit and relaunch.
Notarization does not validate audio behavior or guarantee acceptance of the
undocumented ownership lookup on future macOS versions.
