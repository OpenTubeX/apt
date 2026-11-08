# OpenTubeX APT repository

This repository publishes signed OpenTubeX packages for Debian and Ubuntu at
[apt.opentubex.org](https://apt.opentubex.org). It supports `amd64` and `arm64`
systems.

## Install OpenTubeX

```sh
sudo install -d -m 0755 /etc/apt/keyrings
wget -qO- https://apt.opentubex.org/opentubex-archive-keyring.gpg \
  | sudo tee /etc/apt/keyrings/opentubex-archive-keyring.gpg >/dev/null
sudo tee /etc/apt/sources.list.d/opentubex.sources >/dev/null <<'EOF'
Types: deb
URIs: https://apt.opentubex.org
Suites: stable
Components: main
Signed-By: /etc/apt/keyrings/opentubex-archive-keyring.gpg
EOF
sudo apt update
sudo apt install opentubex
```

If you set up the repository with the older one-line
`/etc/apt/sources.list.d/opentubex.list` entry, delete that file after adding
`opentubex.sources`.

Development snapshots are available through the opt-in `nightly` suite:

```sh
sudo sed -i 's/^Suites: stable$/Suites: nightly/' /etc/apt/sources.list.d/opentubex.sources
sudo apt update
sudo apt install opentubex
```

Stable and nightly packages are indexed separately. The nightly suite carries
the latest stable release while it is newer than the latest nightly.

## How publishing works

After an OpenTubeX stable or nightly release finishes uploading its packages,
the application repository sends a repository dispatch containing the exact
release tag. The publish workflow then:

1. resolves the latest stable release and the latest nightly; the nightly suite
   follows whichever of the two was published last;
2. downloads their `amd64` and `arm64` `.deb` assets;
3. validates their package names and Debian architectures;
4. creates isolated `stable` and `nightly` metadata;
5. deploys the signed static repository to GitHub Pages.

The workflow can also be run manually. It then publishes the latest stable
release and nightly.

## Maintainer setup

1. Create a dedicated, passphrase-protected GPG key for this repository.
2. Add its ASCII-armored private key as the `APT_GPG_PRIVATE_KEY` repository
   secret and its passphrase as `APT_GPG_PASSPHRASE`.
3. In **Settings → Pages**, select **GitHub Actions** as the source and configure
   `apt.opentubex.org` as the custom domain.
4. Add a DNS `CNAME` record from `apt.opentubex.org` to
   `opentubex.github.io`.
5. Run the **Publish APT repository** workflow once.

The OpenTubeX application repository uses its existing `PUSH_TOKEN` secret to
send the cross-repository dispatch. That token needs write access to this
repository.

To rotate the signing key, publish the new public key out-of-band before
replacing the secrets. Existing installations trust only the key they already
downloaded.
