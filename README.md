# OpenTubeX APT repository

This repository publishes signed OpenTubeX packages for Debian and Ubuntu at
[apt.opentubex.org](https://apt.opentubex.org). It supports `amd64`, `arm64`,
and `armhf` systems.

## Install OpenTubeX

```sh
sudo install -d -m 0755 /etc/apt/keyrings
wget -qO- https://apt.opentubex.org/opentubex-archive-keyring.gpg \
  | sudo tee /etc/apt/keyrings/opentubex-archive-keyring.gpg >/dev/null
echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/opentubex-archive-keyring.gpg] https://apt.opentubex.org stable main" \
  | sudo tee /etc/apt/sources.list.d/opentubex.list >/dev/null
sudo apt update
sudo apt install opentubex
```

Development snapshots are available through the opt-in `nightly` suite. Use
the same signing key and replace `stable` with `nightly` in the source entry.
Stable and nightly packages are indexed separately.

## How publishing works

After an OpenTubeX stable or nightly release finishes uploading its packages,
the application repository sends a repository dispatch containing the exact
release tag. The publish workflow then:

1. downloads the latest stable and nightly `amd64`, `arm64`, and ARMv7 `.deb`
   assets;
2. validates their package names and Debian architectures;
3. creates isolated `stable` and `nightly` metadata;
4. deploys the signed static repository to GitHub Pages.

The workflow can also be run manually with a release tag. If no tag is given,
it publishes the latest release.

## Maintainer setup

1. Create a dedicated, passphrase-protected GPG key for this repository.
2. Add its ASCII-armored private key as the `APT_GPG_PRIVATE_KEY` repository
   secret and its passphrase as `APT_GPG_PASSPHRASE`.
3. In **Settings → Pages**, select **GitHub Actions** as the source and configure
   `apt.opentubex.org` as the custom domain.
4. Add a DNS `CNAME` record from `apt.opentubex.org` to
   `opentubex.github.io`.
5. Run the **Publish APT repository** workflow once with a stable release tag.

The OpenTubeX application repository uses its existing `PUSH_TOKEN` secret to
send the cross-repository dispatch. That token needs write access to this
repository.

To rotate the signing key, publish the new public key out-of-band before
replacing the secrets. Existing installations trust only the key they already
downloaded.
