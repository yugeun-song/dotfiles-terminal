#!/usr/bin/env bash
# Installs the terminal configuration. mirror() overwrites on every run; seed()
# copies once and never overwrites. Re-run after editing a file here.
set -euo pipefail

SRC="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
STAMP="$(date +%Y%m%d-%H%M%S)"

# Symlink with a timestamped backup. Unused at present.
link() {
    local from="$1" to="$2"
    if [[ ! -e "$from" ]]; then
        echo "missing source: $from" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$to")"
    if [[ -L "$to" && "$(readlink "$to")" == "$from" ]]; then
        echo "already linked $to"
        return 0
    fi
    # Built under a temporary name so a failure leaves the old config intact.
    local tmp="$to.new-$STAMP"
    ln -s "$from" "$tmp"
    if [[ -e "$to" || -L "$to" ]]; then
        mv "$to" "$to.bak-$STAMP"
        echo "kept existing config at $to.bak-$STAMP"
    fi
    mv -T "$tmp" "$to"
    echo "linked $to"
}

# Copy over whatever is there: for files this repository owns and nothing else
# writes. A copy, not a link, so an installed path never resolves back into the
# working tree. Directories are updated in place rather than swapped, so a
# program watching them sees writes, not a vanished directory.
mirror() {
    local from="$1" to="$2" rel
    if [[ ! -e "$from" ]]; then
        echo "missing source: $from" >&2
        exit 1
    fi
    # Replace a symlink left by an older install.
    [[ -L "$to" ]] && rm -f "$to"
    mkdir -p "$(dirname "$to")"
    if [[ -d "$from" ]]; then
        [[ -e "$to" && ! -d "$to" ]] && rm -f "$to"
        mkdir -p "$to"
        cp -a -- "$from/." "$to/"
        # Delete what the repository no longer has, only inside this directory.
        while IFS= read -r -d '' rel; do
            rel="${rel#./}"
            if [[ ! -e "$from/$rel" ]]; then
                rm -rf -- "${to:?}/$rel"
                echo "removed stale $to/$rel"
            fi
        done < <(cd -- "$to" && find . -mindepth 1 -print0)
    else
        # Rename over the target so the path never disappears for a watcher.
        local tmp="$to.new-$$"
        cp -a -- "$from" "$tmp"
        mv -T -- "$tmp" "$to"
    fi
    echo "installed $to"
}

# Copy once, then leave alone: for files a program rewrites itself, where a
# link would be replaced by its atomic save or written through. A diverged
# copy is reported, never overwritten.
seed() {
    local from="$1" to="$2"
    if [[ ! -e "$from" ]]; then
        echo "missing source: $from" >&2
        exit 1
    fi
    if [[ -L "$to" ]]; then
        rm -f "$to"; mkdir -p "$(dirname "$to")"; cp -a "$from" "$to"
        echo "unlinked and seeded $to"
        return 0
    fi
    if [[ -e "$to" ]]; then
        if diff -rq "$from" "$to" >/dev/null 2>&1; then
            echo "already seeded $to"
        else
            echo "left $to alone: it exists and differs from $from"
            echo "  copy it back into $from to keep the change"
        fi
        return 0
    fi
    mkdir -p "$(dirname "$to")"
    cp -a "$from" "$to"
    echo "seeded $to"
}

mirror "$SRC/zsh/zshrc"              "$HOME/.zshrc"
mirror "$SRC/zsh/zshenv"             "$HOME/.zshenv"
# `p10k configure` rewrites this through a redirect, which would write through
# a link into the repository. Copy the result back here to keep a change.
seed "$SRC/zsh/p10k.zsh"           "$HOME/.p10k.zsh"
mirror "$SRC/zsh/zprofile"           "$HOME/.zprofile"
mirror "$SRC/bash/bashrc"            "$HOME/.bashrc"
mirror "$SRC/npm/npmrc"              "$HOME/.npmrc"
# zshrc sources a literal ~/.config/zsh, so this ignores XDG_CONFIG_HOME.
mirror "$SRC/zsh/config"             "$HOME/.config/zsh"
mirror "$SRC/shell"                  "$CONFIG/shell"
mirror "$SRC/kitty"                  "$CONFIG/kitty"
mirror "$SRC/tmux/tmux.conf"         "$CONFIG/tmux/tmux.conf"
mirror "$SRC/fastfetch"              "$CONFIG/fastfetch"

# Included, not linked, so ~/.gitconfig keeps the identity and its own entries
# still override. The include is an absolute path into this checkout.
if git config --global --get-all include.path 2>/dev/null | grep -qxF "$SRC/git/gitconfig"; then
    echo "already including $SRC/git/gitconfig"
else
    git config --global --add include.path "$SRC/git/gitconfig"
    echo "included $SRC/git/gitconfig from ~/.gitconfig"
fi

echo
echo "done. start a new shell to pick up the changes."
