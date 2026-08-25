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
    [[ -e "$from" ]] || return 0
    mkdir -p "$(dirname "$to")"
    if [[ -e "$to" || -L "$to" ]]; then
        mv "$to" "$to.bak-$STAMP"
        echo "kept existing config at $to.bak-$STAMP"
    fi
    ln -s "$from" "$to"
    echo "linked $to"
}

link "$SRC/zsh/zshrc"              "$HOME/.zshrc"
link "$SRC/zsh/zshenv"             "$HOME/.zshenv"
link "$SRC/zsh/p10k.zsh"           "$HOME/.p10k.zsh"
link "$SRC/zsh/config"             "$CONFIG/zsh"
link "$SRC/kitty"                  "$CONFIG/kitty"
link "$SRC/tmux/tmux.conf"         "$CONFIG/tmux/tmux.conf"
link "$SRC/starship/starship.toml" "$CONFIG/starship.toml"

echo
echo "done. start a new shell to pick up the changes."
