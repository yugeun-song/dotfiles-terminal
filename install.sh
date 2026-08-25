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

link "$SRC/zsh/zshrc"              "$HOME/.zshrc"
link "$SRC/zsh/zshenv"             "$HOME/.zshenv"
link "$SRC/zsh/p10k.zsh"           "$HOME/.p10k.zsh"
link "$SRC/zsh/zprofile"           "$HOME/.zprofile"
# bash is not the login shell, but a rescue shell or a container gets one, and
# without this it keeps 500 lines of history and overwrites them on exit.
link "$SRC/bash/bashrc"            "$HOME/.bashrc"
# zshrc sources the drop-in from a literal ~/.config/zsh, so this one link
# cannot follow XDG_CONFIG_HOME.
link "$SRC/zsh/config"             "$HOME/.config/zsh"
link "$SRC/kitty"                  "$CONFIG/kitty"
link "$SRC/tmux/tmux.conf"         "$CONFIG/tmux/tmux.conf"

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
