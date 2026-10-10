#!/usr/bin/env bash
# Installs the terminal configuration. mirror() overwrites on every run; seed()
# copies once and never overwrites; gdb_presets() keeps one managed block at the
# top of the gdb init file. Re-run after editing a file here.
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
mirror "$SRC/bin/el"                 "$HOME/.local/bin/el"
mirror "$SRC/npm/npmrc"              "$HOME/.npmrc"
mirror "$SRC/iex/iex.exs"            "$HOME/.iex.exs"
# zshrc sources a literal ~/.config/zsh, so this ignores XDG_CONFIG_HOME.
mirror "$SRC/zsh/config"             "$HOME/.config/zsh"
mirror "$SRC/shell"                  "$CONFIG/shell"
mirror "$SRC/kitty"                  "$CONFIG/kitty"
mirror "$SRC/tmux/tmux.conf"         "$CONFIG/tmux/tmux.conf"
mirror "$SRC/fastfetch"              "$CONFIG/fastfetch"
# File by file: mirroring the directory would delete a gdbinit or gdbearlyinit
# that gdb reads from there.
mirror "$SRC/gdb/presets.py"         "$CONFIG/gdb/presets.py"
mirror "$SRC/gdb/debug-max.gdb"      "$CONFIG/gdb/debug-max.gdb"

# gdb reads exactly one user init file, so gdb is asked which. The block records
# where pwndbg's gdbinit.py is and sources presets.py. A raw pwndbg `source`
# line, which pwndbg's setup.sh appends, moves into the block, and the inline
# debug-max block that predates gdb/debug-max.gdb is dropped. Other blocks stay;
# a symlinked file or unpaired markers are left alone.
gdb_presets() {
    local help init begin end raw recorded pwndbg="" candidate block tmp
    local -a candidates=()
    if ! command -v gdb >/dev/null 2>&1; then
        echo "gdb is not installed; no presets block written"
        return 0
    fi
    help="$(gdb --help 2>/dev/null)" || help=""
    init="$(sed -n 's/^ *\* user-specific init file: *//p' <<<"$help")"
    init="${init%%$'\n'*}"
    if [[ -z "$init" ]]; then
        init="$CONFIG/gdb/gdbinit"
        [[ -f "$init" ]] || init="$HOME/.gdbinit"
    fi
    begin="# >>> dotfiles-terminal gdb presets >>>"
    end="# <<< dotfiles-terminal gdb presets <<<"
    local dbg_begin='^# ===== debug-max [(]managed[)]'
    local dbg_end='^# ===== end debug-max =====$'
    local pw_line='^[[:space:]]*source[[:space:]]+.*pwndbg/gdbinit[.]py[[:space:]]*$'
    local dbg_ok=0 moved=0
    if [[ -f "$init" ]]; then
        if [[ "$(grep -cxF "$begin" "$init")" != "$(grep -cxF "$end" "$init")" ]]; then
            echo "$init has an unpaired presets marker; left it alone" >&2
            return 0
        fi
        if grep -qE "$dbg_begin" "$init"; then
            if grep -qE "$dbg_end" "$init"; then
                dbg_ok=1
            else
                echo "$init has a debug-max block without its end marker; left that block in place" >&2
            fi
        fi
        raw="$(grep -m 1 -E "$pw_line" "$init")" || raw=""
        if [[ -n "$raw" ]]; then
            moved=1
            raw="$(sed -E 's/^[[:space:]]*source[[:space:]]+//; s/[[:space:]]+$//' <<<"$raw")"
            candidates+=("${raw/#\~/$HOME}")
        fi
        recorded="$(sed -n 's/^python gdb_presets_pwndbg_source = "\(.*\)"$/\1/p' "$init")"
        recorded="${recorded%%$'\n'*}"
        [[ -n "$recorded" ]] && candidates+=("$recorded")
    fi
    candidates+=("$HOME/pwndbg/gdbinit.py" /usr/share/pwndbg/gdbinit.py)
    for candidate in "${candidates[@]}"; do
        if [[ -f "$candidate" ]]; then
            pwndbg="$candidate"
            break
        fi
    done
    if [[ -z "$pwndbg" && ${#candidates[@]} -gt 2 ]]; then
        pwndbg="${candidates[0]}"
    fi
    if [[ "$pwndbg" == *[\"\\]* ]]; then
        echo "pwndbg's path $pwndbg has a quote or backslash; not recorded, gdb runs without pwndbg" >&2
        pwndbg=""
    fi
    block="$begin"$'\n'
    if [[ -n "$pwndbg" ]]; then
        block+="python gdb_presets_pwndbg_source = \"$pwndbg\""$'\n'
    fi
    block+="source $CONFIG/gdb/presets.py"$'\n'"$end"
    if [[ -L "$init" ]]; then
        echo "$init is a symlink; left it alone. Put this block at its top by hand:" >&2
        printf '  %s\n' "${block//$'\n'/$'\n'  }" >&2
        return 0
    fi
    tmp="$(mktemp "$init.new-XXXXXX")"
    {
        printf '%s\n' "$block"
        if [[ -f "$init" ]]; then
            awk -v begin="$begin" -v end="$end" -v dbg_ok="$dbg_ok" \
                -v dbg_begin="$dbg_begin" -v dbg_end="$dbg_end" -v pw_line="$pw_line" '
                $0 == begin { ours = 1; next }
                ours { if ($0 == end) ours = 0; next }
                dbg_ok && $0 ~ dbg_begin { dbg = 1; next }
                dbg { if ($0 ~ dbg_end) dbg = 0; next }
                $0 ~ pw_line { next }
                !started && /^[[:space:]]*$/ { next }
                { if (!started) { print ""; started = 1 } print }
            ' "$init"
        fi
    } > "$tmp"
    if [[ -f "$init" ]] && cmp -s "$tmp" "$init"; then
        rm -f "$tmp"
        echo "already configured $init"
        return 0
    fi
    if [[ -f "$init" ]]; then
        chmod --reference="$init" "$tmp"
        cp -p "$init" "$init.bak-$STAMP"
        echo "kept the previous $init at $init.bak-$STAMP"
    fi
    mv -T "$tmp" "$init"
    echo "configured $init: presets block on top${pwndbg:+, pwndbg at $pwndbg}"
    (( moved )) && echo "  moved its own pwndbg source line into the block"
    (( dbg_ok )) && echo "  dropped the inline debug-max block; it is now $CONFIG/gdb/debug-max.gdb"
    return 0
}
gdb_presets

# sudo searches only its secure_path, so `sudo el` needs a root-owned copy
# there. The command is printed, never run: this script does not use sudo.
if [[ -f /usr/local/bin/el ]] && cmp -s "$SRC/bin/el" /usr/local/bin/el; then
    echo "sudo el: /usr/local/bin/el matches bin/el"
else
    echo "sudo el needs a root-owned copy where sudo looks for commands; run:"
    echo "  sudo install -m 0755 -o root -g root '$SRC/bin/el' /usr/local/bin/el"
fi

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
