#!/usr/bin/env bash
# Runs zshrc's fzf block in zsh on a fake root, one distribution's layout at a
# time. The block is cut out of zsh/zshrc by its first and last lines and its
# /usr/share pointed into the fake root, so zshrc carries no test hook; a
# change to either line fails here instead of going untested.

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if ! ZSH_BIN=$(command -v zsh); then
    echo "SKIP  fzf block: zsh is not installed"
    exit 0
fi
WORK=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-terminal-fzf.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT

passed=0
failed=0
pass() { passed=$((passed + 1)); }
fail() { failed=$((failed + 1)); printf 'FAIL  fzf block: %s\n' "$*"; }
is() { if [[ $2 == "$3" ]]; then pass; else fail "$1: got [$2], want [$3]"; fi; }

block=$(awk '/^_fzf_dir=$/ { on = 1 } on { print } on && /^unset _fzf_dir _fzf_init _d$/ { exit }' "$REPO/zsh/zshrc")
if [[ $block != _fzf_dir=* || $block != *"unset _fzf_dir _fzf_init _d" || $block != */usr/share/* ]]; then
    echo "FAIL  fzf block: its first or last line changed in zsh/zshrc"
    exit 1
fi

# fzf 0.48 and later print their zsh setup; older ones reject the option.
cat >"$WORK/fzf-new" <<'STUB'
#!/bin/sh
[ "$1" = --zsh ] && echo 'FZF_MARK+=" fzf --zsh"'
STUB
cat >"$WORK/fzf-old" <<'STUB'
#!/bin/sh
echo "unknown option: $1" >&2
exit 2
STUB
chmod +x "$WORK/fzf-new" "$WORK/fzf-old"

# $1 the case, $2 the fzf on PATH (new, old or none), $3 what should be sourced,
# then the files to plant under the fake root. Each planted file appends its
# own path to FZF_MARK. After the |, any variable the block left behind.
check() {
    local name=$1 fzf=$2 want=$3 root f got
    shift 3
    root=$(mktemp -d "$WORK/root.XXXXXX")
    mkdir -p "$root/bin"
    for f in "$@"; do
        mkdir -p "$root/${f%/*}"
        printf 'FZF_MARK+=" %s"\n' "$f" >"$root/$f"
    done
    if [[ $fzf != none ]]; then cp "$WORK/fzf-$fzf" "$root/bin/fzf"; fi
    # shellcheck disable=SC2016 # zsh expands it
    got=$(env -i HOME="$root" PATH="$root/bin" "$ZSH_BIN" -f -c \
        '_before=(${(k)parameters})'$'\n'"${block//"/usr/share/"/"$root/usr/share/"}"$'\n''_after=(${(k)parameters}); _after=(${_after:|_before})
print -rn -- "${FZF_MARK# }|${(j: :)${(@)_after:#(_before|FZF_MARK)}}"' 2>&1)
    is "$name" "$got" "$want|"
}

check "Arch's and Void's layout" new "usr/share/fzf/key-bindings.zsh usr/share/fzf/completion.zsh" \
    usr/share/fzf/key-bindings.zsh usr/share/fzf/completion.zsh
check "openSUSE's layout" new "usr/share/fzf/shell/key-bindings.zsh usr/share/fzf/shell/completion.zsh" \
    usr/share/fzf/shell/key-bindings.zsh usr/share/fzf/shell/completion.zsh
check "Debian's layout, with an fzf before 0.48" old "usr/share/doc/fzf/examples/key-bindings.zsh usr/share/doc/fzf/examples/completion.zsh" \
    usr/share/doc/fzf/examples/key-bindings.zsh usr/share/doc/fzf/examples/completion.zsh
check "Fedora's layout, key bindings only: fzf --zsh" new "fzf --zsh" \
    usr/share/fzf/shell/key-bindings.zsh
check "Gentoo's layout, key bindings only: fzf --zsh" new "fzf --zsh" \
    usr/share/fzf/key-bindings.zsh
check "key bindings only, an fzf before 0.48" old "usr/share/fzf/shell/key-bindings.zsh" \
    usr/share/fzf/shell/key-bindings.zsh
check "key bindings only, no fzf" none "usr/share/fzf/key-bindings.zsh" \
    usr/share/fzf/key-bindings.zsh
check "the first directory found wins" new "usr/share/fzf/key-bindings.zsh usr/share/fzf/completion.zsh" \
    usr/share/fzf/key-bindings.zsh usr/share/fzf/completion.zsh \
    usr/share/doc/fzf/examples/key-bindings.zsh usr/share/doc/fzf/examples/completion.zsh
check "no files: fzf --zsh" new "fzf --zsh"
check "no files, an fzf before 0.48" old ""
check "no files, no fzf" none ""

if (( failed )); then
    echo "FAIL  fzf block: $failed of $((passed + failed)) checks"
    exit 1
fi
echo "PASS  fzf block: $passed checks"
