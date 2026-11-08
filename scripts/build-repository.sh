#!/usr/bin/env bash
# Builds the signed stable and nightly APT repositories.
# Usage: build-repository.sh STABLE_DIRECTORY REPOSITORY_DIRECTORY NIGHTLY_DIRECTORY

set -euo pipefail

stable_directory=$1
repository_directory=$2
nightly_directory=$3
component=main

for directory in "$stable_directory" "$nightly_directory"; do
  if [[ ! -d "$directory" ]]; then
    printf 'Package directory does not exist: %s\n' "$directory" >&2
    exit 1
  fi
done

if [[ -z "$repository_directory" || "$repository_directory" == '/' || "$repository_directory" == '.' ]]; then
  printf 'Unsafe repository directory: %s\n' "$repository_directory" >&2
  exit 1
fi

: "${APT_GPG_KEY_ID:?APT_GPG_KEY_ID is required to sign the repository}"
: "${APT_GPG_PASSPHRASE:?APT_GPG_PASSPHRASE is required to sign the repository}"

rm -rf -- "$repository_directory"
mkdir -p "$repository_directory"

# Replaces only the control archive, so the package contents stay unchanged.
# Fixed metadata keeps the result identical when the same nightly is published
# again, so clients with cached indexes still match its checksum.
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
    tar --create --xz --file=control.tar.xz --owner=0 --group=0 --numeric-owner \
      --sort=name --mtime=@0 -C control .
    ar rcD "$destination" debian-binary control.tar.xz "$data_member"
  )
  rm -rf -- "$work"
}

sign() {
  gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 \
    --local-user "$APT_GPG_KEY_ID" "$@" 3<<< "$APT_GPG_PASSPHRASE"
}

publish_suite() {
  local source_directory=$1
  local suite=$2
  local pool_directory="$repository_directory/pool/$suite/main/o/opentubex"
  local package package_name architecture version package_index release
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
      amd64|arm64) ;;
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

  # Write Release outside the indexed directory so it does not list itself.
  release=$(mktemp)
  apt-ftparchive \
    -o "APT::FTPArchive::Release::Origin=OpenTubeX" \
    -o "APT::FTPArchive::Release::Label=OpenTubeX" \
    -o "APT::FTPArchive::Release::Suite=$suite" \
    -o "APT::FTPArchive::Release::Codename=$suite" \
    -o "APT::FTPArchive::Release::Architectures=${architectures[*]}" \
    -o "APT::FTPArchive::Release::Components=$component" \
    -o "APT::FTPArchive::Release::Description=Official OpenTubeX packages ($suite)" \
    release "dists/$suite" > "$release"
  mv "$release" "dists/$suite/Release"
  chmod 0644 "dists/$suite/Release"

  sign --clearsign --output "dists/$suite/InRelease" "dists/$suite/Release"
  sign --armor --detach-sign --output "dists/$suite/Release.gpg" "dists/$suite/Release"
  popd >/dev/null
}

publish_suite "$stable_directory" stable
publish_suite "$nightly_directory" nightly

pushd "$repository_directory" >/dev/null
gpg --batch --export "$APT_GPG_KEY_ID" > opentubex-archive-keyring.gpg
cp ../static/CNAME ../static/code-blocks.js ../static/favicon.ico \
  ../static/favicon.svg ../static/index.html ../static/og.png \
  ../static/style.css .
touch .nojekyll
popd >/dev/null
