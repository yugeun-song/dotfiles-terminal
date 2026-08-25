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
# zshrc sources the drop-in from a literal ~/.config/zsh, so this one link
# cannot follow XDG_CONFIG_HOME.
link "$SRC/zsh/config"             "$HOME/.config/zsh"
link "$SRC/kitty"                  "$CONFIG/kitty"
link "$SRC/tmux/tmux.conf"         "$CONFIG/tmux/tmux.conf"

echo
echo "done. start a new shell to pick up the changes."
