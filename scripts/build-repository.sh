#!/usr/bin/env bash

set -euo pipefail

deb_directory=${1:-release-files}
repository_directory=${2:-repository}
suite=${APT_SUITE:-stable}
component=${APT_COMPONENT:-main}
origin=${APT_ORIGIN:-OpenTubeX}
label=${APT_LABEL:-OpenTubeX}
description=${APT_DESCRIPTION:-Official OpenTubeX packages}

if [[ ! -d "$deb_directory" ]]; then
  printf 'Package directory does not exist: %s\n' "$deb_directory" >&2
  exit 1
fi

mapfile -t packages < <(find "$deb_directory" -maxdepth 1 -type f -name '*.deb' -print | sort)

if (( ${#packages[@]} == 0 )); then
  printf 'No Debian packages found in %s\n' "$deb_directory" >&2
  exit 1
fi

rm -rf "$repository_directory"
pool_directory="$repository_directory/pool/main/o/opentubex"
mkdir -p "$pool_directory"

architectures=()
for package in "${packages[@]}"; do
  package_name=$(dpkg-deb --field "$package" Package)
  architecture=$(dpkg-deb --field "$package" Architecture)

  if [[ "$package_name" != 'opentubex' ]]; then
    printf 'Unexpected package name %s in %s\n' "$package_name" "$package" >&2
    exit 1
  fi

  case "$architecture" in
    amd64|arm64|armhf)
      ;;
    *)
      printf 'Unsupported Debian architecture %s in %s\n' "$architecture" "$package" >&2
      exit 1
      ;;
  esac

  architectures+=("$architecture")
  cp "$package" "$pool_directory/"
done

mapfile -t architectures < <(printf '%s\n' "${architectures[@]}" | sort -u)

pushd "$repository_directory" >/dev/null
for architecture in "${architectures[@]}"; do
  package_index="dists/$suite/$component/binary-$architecture"
  mkdir -p "$package_index"
  apt-ftparchive --arch "$architecture" packages pool > "$package_index/Packages"
  gzip --keep --no-name --best "$package_index/Packages"
done

architectures_list=$(printf '%s ' "${architectures[@]}")
architectures_list=${architectures_list% }

apt-ftparchive \
  -o "APT::FTPArchive::Release::Origin=$origin" \
  -o "APT::FTPArchive::Release::Label=$label" \
  -o "APT::FTPArchive::Release::Suite=$suite" \
  -o "APT::FTPArchive::Release::Codename=$suite" \
  -o "APT::FTPArchive::Release::Architectures=$architectures_list" \
  -o "APT::FTPArchive::Release::Components=$component" \
  -o "APT::FTPArchive::Release::Description=$description" \
  release "dists/$suite" > "dists/$suite/Release"

: "${APT_GPG_KEY_ID:?APT_GPG_KEY_ID is required to sign the repository}"
: "${APT_GPG_PASSPHRASE:?APT_GPG_PASSPHRASE is required to sign the repository}"

gpg --batch --yes --pinentry-mode loopback \
  --passphrase "$APT_GPG_PASSPHRASE" \
  --local-user "$APT_GPG_KEY_ID" \
  --clearsign --output "dists/$suite/InRelease" "dists/$suite/Release"
gpg --batch --yes --pinentry-mode loopback \
  --passphrase "$APT_GPG_PASSPHRASE" \
  --local-user "$APT_GPG_KEY_ID" \
  --armor --detach-sign --output "dists/$suite/Release.gpg" "dists/$suite/Release"
gpg --batch --export "$APT_GPG_KEY_ID" > opentubex-archive-keyring.gpg

cp ../static/CNAME ../static/index.html ../static/style.css .
touch .nojekyll
popd >/dev/null
