#!/usr/bin/env bash
# Online installer: download and verify the standalone platform binary.
set -euo pipefail

fail() { printf 'rekonkit: %s\n' "$*" >&2; exit 1; }

valid_version() {
    [[ "$1" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ ]] || return 1
    local part suffix="${1#*-}"
    if [[ "$1" == *-* ]]; then
        local parts
        IFS=. read -r -a parts <<< "$suffix"
        for part in "${parts[@]}"; do
            [[ ! "$part" =~ ^0[0-9]+$ ]] || return 1
        done
    fi
}

platform_asset() {
    case "$1/$2" in
        Linux/x86_64|Linux/amd64) printf '%s\n' rekonkit-linux-amd64 ;;
        Linux/aarch64|Linux/arm64) printf '%s\n' rekonkit-linux-arm64 ;;
        Darwin/x86_64) printf '%s\n' rekonkit-darwin-amd64 ;;
        Darwin/arm64) printf '%s\n' rekonkit-darwin-arm64 ;;
        *) fail "unsupported operating system/architecture: $1/$2" ;;
    esac
}

fetch() {
    # Never accept a caller-supplied host or metadata-provided executable URL.
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --connect-timeout 20 --max-time 300 --retry 2 \
        --header 'Accept: application/vnd.github+json' --user-agent 'rekonkit-installer' \
        --output "$2" "$1" || fail "download failed: $1 (check network/proxy access and GitHub rate limits)"
}

json_strings() {
    # Only consume unescaped scalar strings for these two GitHub API fields.
    # Tags/asset names are validated below; URLs and other metadata are never evaluated.
    grep -Eo '"'"$1"'"[[:space:]]*:[[:space:]]*"[^"\\]*"' "$2" |
        sed -E 's/^[^:]*:[[:space:]]*"(.*)"$/\1/'
}

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

configure_path() {
    local dir="$1" os="$2" profile shell="${SHELL:-}" line='export PATH="$HOME/.local/bin:$PATH"'
    case ":${PATH:-}:" in *":$dir:"*|*":$dir/:"*) return ;; esac
    case "${shell##*/}" in
        bash)
            profile="$HOME/.bashrc"
            if [[ "$os" == Darwin ]]; then
                profile="$HOME/.bash_profile"
                # Bash reads only the first existing login profile; don't mask one.
                local candidate
                for candidate in .bash_profile .bash_login .profile; do
                    if [[ -e "$HOME/$candidate" || -L "$HOME/$candidate" ]]; then profile="$HOME/$candidate"; break; fi
                done
            fi ;;
        zsh) profile="${ZDOTDIR:-$HOME}/.zshrc" ;;
        *) printf 'Add %s to your shell PATH, then reopen the terminal.\n' "$dir"; return ;;
    esac
    if [[ -L "$profile" || ( -e "$profile" && ! -f "$profile" ) ]]; then
        printf 'Profile is linked/nonregular; left unchanged: %s\nAdd this yourself, then reopen the terminal:\n  %s\n' "$profile" "$line"
        return
    fi
    if [[ ! -f "$profile" ]] || ! grep -Fxq "$line" "$profile"; then
        printf '\n# RekonKit user-local binaries\n%s\n' "$line" >> "$profile" || fail "cannot update $profile"
    fi
    printf 'PATH configured in %s. Reopen your terminal, or run:\n  %s\n' "$profile" "$line"
}

install_rekonkit() (
    set -euo pipefail
    local version='' os arch asset repo='redoyudis/rekonkit-release'
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version) [[ $# -ge 2 && -z "$version" ]] || fail 'usage: bash install.sh [--version vX.Y.Z]'; version="$2"; shift 2 ;;
            -h|--help) printf 'Usage: bash install.sh [--version vX.Y.Z]\n'; return ;;
            *) fail "unknown argument: $1" ;;
        esac
    done
    [[ -z "$version" ]] || valid_version "$version" || fail "invalid version: $version"
    os="$(uname -s)"; arch="$(uname -m)"
    asset="$(platform_asset "$os" "$arch")"
    for tool in curl grep sed awk mktemp; do command -v "$tool" >/dev/null || fail "required tool missing: $tool"; done
    command -v sha256sum >/dev/null || command -v shasum >/dev/null || fail 'sha256sum or shasum is required'
    [[ "${HOME:-}" == /* && -d "$HOME" ]] || fail 'HOME must be an existing absolute directory'
    local work stage='' backup='' target='' replaced=false success=false lock=''
    work="$(mktemp -d)"
    cleanup() {
        local status=$?
        trap - EXIT INT TERM
        if [[ "$replaced" == true && "$success" != true ]]; then
            if [[ -n "$backup" ]]; then
                mv -f "$backup" "$target" || { printf 'ROLLBACK FAILED: previous binary retained at %s\n' "$backup" >&2; backup=''; }
            else
                rm -f "$target"
            fi
        fi
        [[ -z "$stage" ]] || rm -f "$stage"
        [[ -z "$backup" ]] || rm -f "$backup"
        [[ -z "$lock" ]] || rmdir "$lock"
        rm -rf "$work"
        exit "$status"
    }
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    local endpoint=latest
    [[ -z "$version" ]] || endpoint="tags/$version"
    printf 'Looking up %s release (%s/%s)...\n' "${version:-latest stable}" "$os" "$arch"
    fetch "https://api.github.com/repos/$repo/releases/$endpoint" "$work/release.json"
    local released names
    released="$(json_strings tag_name "$work/release.json")" || fail 'release metadata has no usable tag_name'
    valid_version "$released" || fail 'invalid release tag in GitHub response'
    [[ -z "$version" || "$version" == "$released" ]] || fail 'GitHub returned a different release version'
    [[ "$endpoint" != latest || "$released" != *-* ]] || fail 'latest stable endpoint returned a prerelease'
    version="$released"
    names="$(json_strings name "$work/release.json")" || fail 'release metadata has no assets'
    printf '%s\n' "$names" | grep -Fx "$asset" > /dev/null || fail "release missing asset: $asset"
    printf '%s\n' "$names" | grep -Fx SHA256SUMS > /dev/null || fail 'release missing asset: SHA256SUMS'
    printf 'Downloading %s...\n' "$asset"
    fetch "https://github.com/$repo/releases/download/$version/$asset" "$work/binary"
    fetch "https://github.com/$repo/releases/download/$version/SHA256SUMS" "$work/SHA256SUMS"
    local expected actual
    expected="$(awk -v name="$asset" 'length($0)==66+length(name) && substr($0,65,2)=="  " && substr($0,67)==name {print substr($0,1,64)}' "$work/SHA256SUMS")"
    [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || fail 'missing, duplicate, or invalid binary checksum'
    actual="$(sha256 "$work/binary")"
    [[ "$(printf '%s' "$expected" | tr 'A-F' 'a-f')" == "$actual" ]] || fail 'checksum mismatch; existing installation unchanged'

    local dir="$HOME/.local/bin" path output
    for path in "$HOME/.local" "$dir"; do
        [[ ! -L "$path" && ( ! -e "$path" || -d "$path" ) ]] || fail "unsafe install directory: $path"
    done
    mkdir -p "$dir"
    mkdir "$dir/.rekonkit-install.lock" || fail 'another install is active (or a stale .rekonkit-install.lock needs review)'
    lock="$dir/.rekonkit-install.lock"
    target="$dir/rekonkit"
    [[ ! -L "$target" && ( ! -e "$target" || ( -f "$target" && -x "$target" ) ) ]] || fail "refusing to replace nonregular/nonexecutable file: $target"
    if [[ -e "$target" ]]; then
        output="$("$target" --version)" || fail 'existing binary does not work; refusing to overwrite'
        [[ "$output" == 'rekonkit '* ]] || fail 'existing file is not RekonKit; refusing to overwrite'
    fi
    stage="$(mktemp "$dir/.rekonkit-new.XXXXXX")"
    cp "$work/binary" "$stage"
    chmod 755 "$stage"
    output="$("$stage" --version)" || fail 'downloaded binary cannot run; existing installation unchanged'
    [[ "$output" == "rekonkit $version" || "$output" == "rekonkit $version"$'\n'* ]] || fail 'downloaded binary reports an unexpected version'
    configure_path "$dir" "$os"
    if [[ -e "$target" ]]; then
        backup="$(mktemp "$dir/.rekonkit-old.XXXXXX")"
        cp -p "$target" "$backup"
    fi
    # Arm rollback before mv: a signal can arrive immediately after its atomic rename.
    replaced=true
    mv -f "$stage" "$target" || fail 'cannot replace installed binary; existing installation unchanged'
    stage=''
    "$target" --version || fail 'installed version check failed; restoring previous binary'
    success=true
    printf 'Installed %s to %s. Run rekonkit --help in a new terminal.\n' "$version" "$target"
)

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]:-}" == "$0" ]]; then
    install_rekonkit "$@"
fi
