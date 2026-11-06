#!/usr/bin/env bash
# Installs what packages.txt names and the system lacks, before install.sh
# checks its premise (zsh, kitty, nvim and git come from here). Arch only.
# Never a reinstall: pacman -T names what nothing installed satisfies, and
# only that goes to pacman -S --needed. Never -Sy, a partial upgrade. Silent
# when nothing is missing; without a terminal it only says what is.
#   packages.sh [--check]     exit 3: missing, and no terminal to install in
set -uo pipefail

HERE=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)
CHECK=0
case ${1:-} in "") ;; --check) CHECK=1 ;; *) echo "usage: packages.sh [--check]" >&2; exit 2 ;; esac

command -v pacman >/dev/null 2>&1 || exit 0
release=${DOTFILES_OS_RELEASE:-/etc/os-release}
ids=$(sed -nE 's/^(ID|ID_LIKE)="?([^"]*)"?$/\2/p' "$release" 2>/dev/null | tr '\n' ' ')
[[ " $ids " =~ \ (arch|manjaro|endeavouros|cachyos|garuda|artix)\  ]] || exit 0

mapfile -t want < <(sed -E 's/#.*//; s/[[:space:]]+//g; /^$/d' -- "$HERE/packages.txt" | LC_ALL=C sort -u)
mapfile -t need < <(pacman -T -- "${want[@]}" 2>/dev/null; true)
(( ${#need[@]} )) || exit 0

# Not in any enabled repository: said, and left.
mapfile -t absent < <(pacman -Si -- "${need[@]}" 2>&1 >/dev/null | sed -nE "s/^error: package '([^']+)' was not found$/\1/p")
get=()
for p in "${need[@]}"; do [[ " ${absent[*]} " == *" $p "* ]] || get+=("$p"); done
(( ${#absent[@]} )) && echo "packages: in no enabled repository: ${absent[*]}"
(( ${#get[@]} )) || exit 0
echo "packages: missing (${#get[@]}): ${get[*]}"
(( CHECK )) && exit 0
if ! { : </dev/tty; } 2>/dev/null; then
    echo "packages: none installed, with no terminal to confirm them in; run ./install.sh in one"
    exit 3
fi
# shellcheck disable=SC2024 # the terminal is read here, as pacman's answers
if ! sudo pacman -S --needed -- "${get[@]}" </dev/tty; then
    echo "packages: pacman installed none of them; if it could not fetch, run sudo pacman -Syu first" >&2
    exit 1
fi
