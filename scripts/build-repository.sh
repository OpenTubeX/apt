#!/usr/bin/env bash

set -euo pipefail

stable_directory=${1:-release-files}
repository_directory=${2:-repository}
nightly_directory=${3:-}
component=${APT_COMPONENT:-main}
origin=${APT_ORIGIN:-OpenTubeX}
label=${APT_LABEL:-OpenTubeX}
description=${APT_DESCRIPTION:-Official OpenTubeX packages}

if [[ ! -d "$stable_directory" ]]; then
  printf 'Package directory does not exist: %s\n' "$stable_directory" >&2
  exit 1
fi

if [[ -z "$repository_directory" || "$repository_directory" == '/' || "$repository_directory" == '.' ]]; then
  printf 'Unsafe repository directory: %s\n' "$repository_directory" >&2
  exit 1
fi

: "${APT_GPG_KEY_ID:?APT_GPG_KEY_ID is required to sign the repository}"
: "${APT_GPG_PASSPHRASE:?APT_GPG_PASSPHRASE is required to sign the repository}"

rm -rf -- "$repository_directory"
mkdir -p "$repository_directory"

# Replaces only the control archive, so the package contents stay unchanged.
set_package_version() {
  local package destination version=$2 work control_member data_member
  package=$(realpath "$1")
  destination=$(realpath -m "$3")
  work=$(mktemp -d)
  control_member=$(ar t "$package" | grep '^control\.tar')
  data_member=$(ar t "$package" | grep '^data\.tar')
  (
    cd "$work"
    ar x "$package"
    mkdir control
    tar -xf "$control_member" -C control
    sed -i "s/^Version: .*/Version: $version/" control/control
    tar --create --xz --file=control.tar.xz --owner=0 --group=0 --numeric-owner --sort=name -C control .
    ar rcD "$destination" debian-binary control.tar.xz "$data_member"
  )
  rm -rf -- "$work"
}

publish_suite() {
  local source_directory=$1
  local suite=$2
  local pool_directory="$repository_directory/pool/$suite/main/o/opentubex"
  local package package_name architecture version package_index architectures_list
  local -a packages architectures

  mapfile -t packages < <(find "$source_directory" -maxdepth 1 -type f -name '*.deb' -print | sort)
  if (( ${#packages[@]} == 0 )); then
    printf 'No Debian packages found in %s\n' "$source_directory" >&2
    exit 1
  fi

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
      amd64|arm64|armhf) ;;
      *)
        printf 'Unsupported Debian architecture %s in %s\n' "$architecture" "$package" >&2
        exit 1
        ;;
    esac

    architectures+=("$architecture")
    version=$(dpkg-deb --field "$package" Version)
    # Nightlies are built after the release they are numbered after, so
    # 0.37.0.nightly.2527 must sort between the 0.37.0 and 0.37.1 releases.
    if [[ "$version" =~ ^([0-9]+\.[0-9]+\.[0-9]+)~nightly~([0-9]+)$ ]]; then
      version="${BASH_REMATCH[1]}.nightly.${BASH_REMATCH[2]}"
      set_package_version "$package" "$version" "$pool_directory/opentubex_${version}_${architecture}.deb"
    else
      cp "$package" "$pool_directory/"
    fi
  done

  mapfile -t architectures < <(printf '%s\n' "${architectures[@]}" | sort -u)

  pushd "$repository_directory" >/dev/null
  for architecture in "${architectures[@]}"; do
    package_index="dists/$suite/$component/binary-$architecture"
    mkdir -p "$package_index"
    apt-ftparchive --arch "$architecture" packages "pool/$suite" > "$package_index/Packages"
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
    -o "APT::FTPArchive::Release::Description=$description ($suite)" \
    release "dists/$suite" > "dists/$suite/Release"

  gpg --batch --yes --pinentry-mode loopback \
    --passphrase "$APT_GPG_PASSPHRASE" \
    --local-user "$APT_GPG_KEY_ID" \
    --clearsign --output "dists/$suite/InRelease" "dists/$suite/Release"
  gpg --batch --yes --pinentry-mode loopback \
    --passphrase "$APT_GPG_PASSPHRASE" \
    --local-user "$APT_GPG_KEY_ID" \
    --armor --detach-sign --output "dists/$suite/Release.gpg" "dists/$suite/Release"
  popd >/dev/null
}

publish_suite "$stable_directory" stable
if [[ -n "$nightly_directory" && -d "$nightly_directory" ]]; then
  publish_suite "$nightly_directory" nightly
fi

pushd "$repository_directory" >/dev/null
gpg --batch --export "$APT_GPG_KEY_ID" > opentubex-archive-keyring.gpg
cp ../static/CNAME ../static/code-blocks.js ../static/favicon.ico \
  ../static/favicon.svg ../static/index.html ../static/og.png \
  ../static/style.css .
touch .nojekyll
popd >/dev/null
