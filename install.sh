#!/usr/bin/env bash
#
# Links the terminal configuration into place.
#
# An existing file is moved aside with a timestamp rather than replaced, so a
# bad run is always reversible.
#
set -euo pipefail

SRC="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
STAMP="$(date +%Y%m%d-%H%M%S)"

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
    # The new link is created under a temporary name first, so a failure here
    # leaves the existing config where it is instead of removing it and then
    # failing to put anything back.
    local tmp="$to.new-$STAMP"
    ln -s "$from" "$tmp"
    if [[ -e "$to" || -L "$to" ]]; then
        mv "$to" "$to.bak-$STAMP"
        echo "kept existing config at $to.bak-$STAMP"
    fi
    mv -T "$tmp" "$to"
    echo "linked $to"
}

# Copy once, then leave it alone. Some programs own their configuration file
# and rewrite it themselves; a link to the repository either gets replaced by
# their atomic save or, worse, gets written through. Seeding says what is true:
# this is where the settings start, and the program owns them from then on.
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

seed "$SRC/zsh/zshrc"              "$HOME/.zshrc"
seed "$SRC/zsh/zshenv"             "$HOME/.zshenv"
# Seeded rather than linked. `p10k configure` rewrites this file with a plain
# shell redirect, which follows a symlink instead of replacing it, so running
# the wizard would edit the repository in place without saying so. A copy keeps
# the wizard's output where it belongs; copy it back here to keep a change.
seed "$SRC/zsh/p10k.zsh"           "$HOME/.p10k.zsh"
seed "$SRC/zsh/zprofile"           "$HOME/.zprofile"
# bash is not the login shell, but a rescue shell or a container gets one, and
# without this it keeps 500 lines of history and overwrites them on exit.
seed "$SRC/bash/bashrc"            "$HOME/.bashrc"
# zshrc sources the drop-in from a literal ~/.config/zsh, so this one link
# cannot follow XDG_CONFIG_HOME.
seed "$SRC/zsh/config"             "$HOME/.config/zsh"
seed "$SRC/kitty"                  "$CONFIG/kitty"
seed "$SRC/tmux/tmux.conf"         "$CONFIG/tmux/tmux.conf"

# git/gitconfig is included rather than linked over ~/.gitconfig. Linking would
# replace the file that holds user.name and user.email, and an identity is not
# something to lose to an installer; including leaves it where it is and layers
# the shared settings underneath. Later entries win in git config, so anything
# set directly in ~/.gitconfig still overrides what is included here.
if git config --global --get-all include.path 2>/dev/null | grep -qxF "$SRC/git/gitconfig"; then
    echo "already including $SRC/git/gitconfig"
else
    git config --global --add include.path "$SRC/git/gitconfig"
    echo "included $SRC/git/gitconfig from ~/.gitconfig"
fi

echo
echo "done. start a new shell to pick up the changes."
