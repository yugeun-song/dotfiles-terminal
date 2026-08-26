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

# Copy, every run, over whatever is there.
#
# For what this repository authors and nothing else writes: the Hyprland
# configuration, the scripts, the quickshell tree, the two commands in bin/.
# These used to be symlinked, because a link makes an edit live without running
# anything. What a link also does is make the installed path resolve back into
# the working tree, so anything that finds a sibling by walking up from its own
# location finds it in the repository rather than beside itself.
# hypr/scripts/auto_monitors.sh read ../monitors.preset that way and the preset
# was never installed at all; nothing reported it, the panel would simply have
# come up at scale 1.
#
# Unlike seed() this overwrites. The repository is the source of truth here, so
# a difference at the destination is something to lose rather than to keep. The
# copy goes in place rather than being swapped in, because quickshell watches
# these files and reloads on a write: a directory replaced underneath it is a
# crash instead of a reload.
mirror() {
    local from="$1" to="$2" rel
    if [[ ! -e "$from" ]]; then
        echo "missing source: $from" >&2
        exit 1
    fi
    # A link left by an older version of this script. Removing it is the whole
    # conversion; what replaces it is the same content as a real file.
    [[ -L "$to" ]] && rm -f "$to"
    mkdir -p "$(dirname "$to")"
    if [[ -d "$from" ]]; then
        [[ -e "$to" && ! -d "$to" ]] && rm -f "$to"
        mkdir -p "$to"
        cp -a -- "$from/." "$to/"
        # A file the repository no longer has is one a stale binding can still
        # reach, so it goes. Only inside this directory: local.lua and
        # local.monitors live a level up and are not ours to delete.
        while IFS= read -r -d '' rel; do
            rel="${rel#./}"
            if [[ ! -e "$from/$rel" ]]; then
                rm -rf -- "${to:?}/$rel"
                echo "removed stale $to/$rel"
            fi
        done < <(cd -- "$to" && find . -mindepth 1 -print0)
    else
        # Written beside the target and moved onto it, so there is never a
        # moment when the path does not exist. Hyprland watches its config and
        # reads it the instant it changes: an rm followed by a cp gave it a
        # window in which the file was gone, and it put "cannot open
        # hyprland.lua: No such file or directory" on the screen.
        local tmp="$to.new-$$"
        cp -a -- "$from" "$tmp"
        mv -T -- "$tmp" "$to"
    fi
    echo "installed $to"
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

mirror "$SRC/zsh/zshrc"              "$HOME/.zshrc"
mirror "$SRC/zsh/zshenv"             "$HOME/.zshenv"
# Seeded rather than linked. `p10k configure` rewrites this file with a plain
# shell redirect, which follows a symlink instead of replacing it, so running
# the wizard would edit the repository in place without saying so. A copy keeps
# the wizard's output where it belongs; copy it back here to keep a change.
seed "$SRC/zsh/p10k.zsh"           "$HOME/.p10k.zsh"
mirror "$SRC/zsh/zprofile"           "$HOME/.zprofile"
# bash is not the login shell, but a rescue shell or a container gets one, and
# without this it keeps 500 lines of history and overwrites them on exit.
mirror "$SRC/bash/bashrc"            "$HOME/.bashrc"
# zshrc sources the drop-in from a literal ~/.config/zsh, so this one link
# cannot follow XDG_CONFIG_HOME.
mirror "$SRC/zsh/config"             "$HOME/.config/zsh"
mirror "$SRC/kitty"                  "$CONFIG/kitty"
mirror "$SRC/tmux/tmux.conf"         "$CONFIG/tmux/tmux.conf"

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
