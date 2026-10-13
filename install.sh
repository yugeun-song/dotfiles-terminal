#!/usr/bin/env bash
#
# Installs the terminal configuration into $HOME.
#
#   ./install.sh           install
#   ./install.sh --check   report what is behind or conflicting; writes nothing
#   ./install.sh --force   overwrite conflicts without asking
#
# Exit status: 0 everything applied and current; 1 stopped, or applied with a
# step left undone (named in the summary); 2 usage.
#
# Premise: Arch Linux or a derivative, zsh with Oh My Zsh, powerlevel10k and
# its two plugins (./bootstrap.sh), kitty, nvim and git. When one is missing,
# or the session would read these files from somewhere else, nothing is
# written: a half-applied shell setup is worse than none.
#
# Files are copied, never linked, so an installed path never resolves back
# into the checkout. A target holding content this repository did not install
# is a conflict: its diff is shown and the user decides.
#
# Test hooks: DOTFILES_OS_RELEASE replaces /etc/os-release, DOTFILES_ROOT_EL
# replaces /usr/local/bin/el.

set -Eeuo pipefail

usage() {
    cat <<'EOF'
usage: ./install.sh [--check | --force]
  (none)    install, asking before overwriting anything this repository did not install
  --check   report what is behind or conflicting; writes nothing, exit 1 if anything is
  --force   overwrite conflicts without asking
EOF
}

MODE=install
FORCE=0
for arg in "$@"; do
    case $arg in
        --check) MODE=check ;;
        --force) FORCE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
if [[ $MODE == check ]] && (( FORCE )); then
    echo "install: --check writes nothing, so --force has no meaning with it" >&2
    exit 2
fi

if [[ ${HOME:-} != /* || ! -d ${HOME:-} ]]; then
    echo "install: HOME is not an existing absolute directory; nothing was written" >&2
    exit 1
fi

SRC=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)
STAMP=$(date +%Y%m%d-%H%M%S)
ROOT_EL=${DOTFILES_ROOT_EL:-/usr/local/bin/el}

# The XDG spec says a relative value is invalid and must be ignored.
xdg_dir() {
    local value=${!1:-}
    if [[ $value == /* ]]; then printf '%s' "${value%/}"; else printf '%s' "$2"; fi
}
CONFIG=$(xdg_dir XDG_CONFIG_HOME "$HOME/.config")
STATE=$(xdg_dir XDG_STATE_HOME "$HOME/.local/state")/dotfiles-terminal
MANIFEST_FILE=$STATE/installed
# zshrc pins ZSH here, so bootstrap.sh clones here; ZSH_CUSTOM is honoured
# by Oh My Zsh itself.
OMZ=$HOME/.oh-my-zsh
OMZ_CUSTOM=${ZSH_CUSTOM:-$OMZ/custom}

if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    RED=$'\e[31m' GREEN=$'\e[32m' CYAN=$'\e[36m' BOLD=$'\e[1m' DIM=$'\e[2m' RESET=$'\e[0m'
else
    RED='' GREEN='' CYAN='' BOLD='' DIM='' RESET=''
fi

HAVE_GIT=0
IN_GIT=0
if command -v git >/dev/null 2>&1; then
    HAVE_GIT=1
    if git -C "$SRC" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        IN_GIT=1
    fi
fi

declare -A MANIFEST=()
MANIFEST_DIRTY=0
INSTALLED=0 UNCHANGED=0 REMOVED=0 FORCED=0
DRIFT=0
PROBLEMS=() UNDONE=() NOTES=()
STEP=0
FINISHING=0
NO_PWNDBG=0
WORK=""

# ---- premise -------------------------------------------------------------

os_release_field() {
    local key=$1 file=$2 line value=""
    while IFS= read -r line; do
        if [[ $line == "$key="* ]]; then
            value=${line#*=}
            value=${value#[\"\']}
            value=${value%[\"\']}
        fi
    done <"$file"
    printf '%s' "$value"
}

check_premise() {
    local os=${DOTFILES_OS_RELEASE:-} f id like name tool sys session session_env missing=""
    if [[ -z $os ]]; then
        for f in /etc/os-release /usr/lib/os-release; do
            if [[ -r $f ]]; then os=$f; break; fi
        done
    fi
    if [[ -z $os || ! -r $os ]]; then
        PROBLEMS+=("no readable os-release, so the distribution is unknown; this repository targets Arch Linux")
    else
        id=$(os_release_field ID "$os")
        like=$(os_release_field ID_LIKE "$os")
        name=$(os_release_field PRETTY_NAME "$os")
        if [[ $id != arch && " $like " != *" arch "* ]]; then
            PROBLEMS+=("this is ${name:-${id:-an unknown system}}, not Arch Linux or a derivative; the paths here are Arch's")
        fi
    fi

    for tool in "zsh:the shell this configures" "kitty:the terminal kitty.conf is for" \
                "nvim:the editor, man pager and scrollback pager" \
                "git:the git include, and telling this repository's files from others"; do
        if ! command -v "${tool%%:*}" >/dev/null 2>&1; then
            PROBLEMS+=("${tool%%:*} is not installed (${tool#*:}); install it with pacman")
        fi
    done

    if [[ ! -r $OMZ/oh-my-zsh.sh ]]; then missing+=", Oh My Zsh in $OMZ"; fi
    for f in themes/powerlevel10k plugins/zsh-autosuggestions plugins/zsh-syntax-highlighting; do
        if [[ ! -d $OMZ_CUSTOM/$f ]]; then missing+=", $OMZ_CUSTOM/$f"; fi
    done
    if [[ -n $missing ]]; then
        PROBLEMS+=("zshrc needs ${missing#, }; run ./bootstrap.sh first")
    fi

    # zsh reads every startup file from ZDOTDIR when it is set, so a ~/.zshrc
    # written here would be ignored. -f still reads the system zshenv.
    if [[ -n ${ZDOTDIR:-} && ${ZDOTDIR%/} != "${HOME%/}" ]]; then
        PROBLEMS+=("ZDOTDIR is $ZDOTDIR, so zsh would ignore ~/.zshrc; unset it or set it to \$HOME")
    elif command -v zsh >/dev/null 2>&1; then
        # shellcheck disable=SC2016 # zsh expands it, not this shell
        sys=$(env -i HOME="$HOME" PATH="$PATH" zsh -f -c 'print -r -- "${ZDOTDIR-}"' 2>/dev/null) || sys=""
        if [[ -n $sys && ${sys%/} != "${HOME%/}" ]]; then
            PROBLEMS+=("the system zshenv sets ZDOTDIR to $sys, so zsh would ignore ~/.zshrc")
        fi
    fi

    # Files go where this shell's XDG_CONFIG_HOME says; kitty, tmux and the
    # rest start from the session's environment, which the user manager holds.
    if command -v systemctl >/dev/null 2>&1 && session_env=$(systemctl --user show-environment 2>/dev/null); then
        session=$(awk '/^XDG_CONFIG_HOME=/ { sub(/^[^=]*=/, ""); print; exit }' <<<"$session_env")
        if [[ $session != /* ]]; then session=$HOME/.config; fi
        if [[ ${session%/} != "$CONFIG" ]]; then
            PROBLEMS+=("files would go to $CONFIG, but the session's programs read ${session%/}: XDG_CONFIG_HOME differs between this shell and the systemd user manager")
        fi
    fi
    if [[ -n ${KITTY_CONFIG_DIRECTORY:-} && ${KITTY_CONFIG_DIRECTORY%/} != "$CONFIG/kitty" ]]; then
        PROBLEMS+=("KITTY_CONFIG_DIRECTORY is $KITTY_CONFIG_DIRECTORY, so kitty would not read $CONFIG/kitty")
    fi
}

# ---- ownership -----------------------------------------------------------

blob_of() {
    git hash-object --no-filters -- "$1"
}

load_manifest() {
    local blob path
    [[ -r $MANIFEST_FILE ]] || return 0
    while IFS=$'\t' read -r blob path; do
        if [[ -n $blob && -n $path ]]; then MANIFEST[$path]=$blob; fi
    done <"$MANIFEST_FILE"
}

save_manifest() {
    local tmp path
    (( MANIFEST_DIRTY )) || return 0
    mkdir -p -- "$STATE" || return 1
    tmp=$MANIFEST_FILE.new-$$
    {
        for path in "${!MANIFEST[@]}"; do
            if [[ -n ${MANIFEST[$path]} ]]; then printf '%s\t%s\n' "${MANIFEST[$path]}" "$path"; fi
        done | LC_ALL=C sort -t $'\t' -k2
    } >"$tmp" && mv -f -- "$tmp" "$MANIFEST_FILE"
}

remember() {
    local blob
    (( HAVE_GIT )) || return 0
    blob=$(blob_of "$1") || return 0
    if [[ ${MANIFEST[$1]:-} != "$blob" ]]; then
        MANIFEST[$1]=$blob
        MANIFEST_DIRTY=1
    fi
}

# True when the content at $1 is something this repository installed: the
# source itself ($2), what an earlier run recorded, or a version committed
# here. The record covers uncommitted edits installed while working.
ours() {
    local target=$1 source=${2:-} blob
    if [[ -n $source ]] && cmp -s -- "$target" "$source"; then return 0; fi
    (( HAVE_GIT )) || return 1
    blob=$(blob_of "$target" 2>/dev/null) || return 1
    if [[ ${MANIFEST[$target]:-} == "$blob" ]]; then return 0; fi
    if (( IN_GIT )) && [[ $(git -C "$SRC" cat-file -t "$blob" 2>/dev/null) == blob ]]; then return 0; fi
    return 1
}

# ---- conflicts -----------------------------------------------------------

# diff -u with each line numbered on both sides.
show_diff() {
    { diff -u -- "$1" "$2" 2>&1 || :; } | awk -v red="$RED" -v green="$GREEN" -v cyan="$CYAN" \
        -v dim="$DIM" -v reset="$RESET" -v old_label="$3" -v new_label="$4" '
        NR == 1 && /^--- /   { printf "%s--- %s%s\n", red, old_label, reset; next }
        NR == 2 && /^\+\+\+ / { printf "%s+++ %s%s\n", green, new_label, reset; next }
        /^@@ / {
            split($2, o, ","); split($3, n, ",")
            old = substr(o[1], 2) + 0; new = substr(n[1], 2) + 0
            printf "%s%s%s\n", cyan, $0, reset; next
        }
        /^-/  { printf "%s%5s %5s │ %s%s\n", red, old, "", $0, reset; old++; next }
        /^\+/ { printf "%s%5s %5s │ %s%s\n", green, "", new, $0, reset; new++; next }
        /^ /  { printf "%5s %5s │ %s\n", old, new, $0; old++; new++; next }
        { printf "%s%s%s\n", dim, $0, reset }'
}

# 0 to go ahead, 1 to keep the file. Asked on the terminal, so a redirected
# stdout still gets an answer; without a terminal the answer is no.
ask() {
    local verb=$1 target=$2 answer
    if ! { exec 3<>/dev/tty; } 2>/dev/null; then
        echo "install: no terminal to ask on; rerun in a terminal to choose, or with --force" >&2
        return 1
    fi
    while :; do
        printf '%s %s? [y] yes  [n] no, keep it and stop  [a] all, this and every later conflict: ' \
            "$verb" "$target" >&3
        if ! IFS= read -r answer <&3; then
            printf '\n' >&3
            answer=n
        fi
        case ${answer,,} in
            y|yes) exec 3>&-; return 0 ;;
            n|no) exec 3>&-; return 1 ;;
            a|all) FORCE=1; exec 3>&-; return 0 ;;
        esac
    done
}

# $1 Overwrite or Remove, $2 target, $3 label of the repository side, $4 its
# content (/dev/null for a removal). Returns to go ahead; stops on a no.
conflict() {
    local verb=$1 target=$2
    if (( FORCE )); then
        echo "forced $target"
        FORCED=$((FORCED + 1))
        return 0
    fi
    printf '%sconflict%s  %s: not what this repository installed\n' "$BOLD" "$RESET" "$target"
    show_diff "$target" "$4" "$target (installed)" "$3"
    if ask "$verb" "$target"; then
        FORCED=$((FORCED + 1))
        return 0
    fi
    stop "kept $target as it is"
}

# ---- writes --------------------------------------------------------------

write_file() {
    local src=$1 dst=$2 dir tmp
    dir=$(dirname -- "$dst")
    mkdir -p -- "$dir" || stop "could not create $dir"
    tmp=$dst.new-$$
    if ! cp -a -- "$src" "$tmp"; then
        rm -f -- "$tmp"
        stop "could not write $dst"
    fi
    # rename(2): a watcher never sees the path missing, and a link left by
    # an older install is replaced, not written through.
    if ! mv -fT -- "$tmp" "$dst"; then
        rm -f -- "$tmp"
        stop "could not replace $dst"
    fi
    remember "$dst"
    INSTALLED=$((INSTALLED + 1))
    echo "installed $dst"
}

remove_file() {
    rm -f -- "$1" || stop "could not remove $1"
    if [[ -n ${MANIFEST[$1]:-} ]]; then MANIFEST[$1]=""; MANIFEST_DIRTY=1; fi
    REMOVED=$((REMOVED + 1))
    echo "removed $1"
}

# Older installs linked into the checkout; such a link is ours to replace.
old_link() {
    [[ -L $1 && $(readlink -f -- "$1" 2>/dev/null) == "$SRC"/* ]]
}

# ---- steps ---------------------------------------------------------------

# Overwritten on every run: files this repository authors and nothing else writes.
mirror_file() {
    local rel=$1 src=$SRC/$1 dst=$2
    [[ -f $src ]] || stop "the source $rel is missing from the checkout"
    if [[ -d $dst && ! -L $dst ]]; then stop "$dst is a directory where $rel should go"; fi
    if [[ -e $dst ]] && ! old_link "$dst" && cmp -s -- "$src" "$dst"; then
        if [[ $MODE == install ]]; then remember "$dst"; fi
        UNCHANGED=$((UNCHANGED + 1))
        return 0
    fi
    if [[ $MODE == check ]]; then
        DRIFT=1
        if [[ ! -e $dst && ! -L $dst ]]; then echo "missing   $dst"
        elif old_link "$dst" || ours "$dst" "$src"; then echo "behind    $dst"
        else echo "conflict  $dst (would ask before overwriting)"
        fi
        return 0
    fi
    if [[ -e $dst || -L $dst ]] && ! old_link "$dst" && ! ours "$dst" "$src"; then
        conflict Overwrite "$dst" "$rel (repository)" "$src"
    fi
    write_file "$src" "$dst"
}

# Every path the repository had under a directory, at any commit: a prune
# only touches files this repository put there.
history_paths() {
    local rel=$1
    (( IN_GIT )) || return 0
    {
        git -C "$SRC" log --all --format= --name-only --no-renames -- "$rel" 2>/dev/null || :
        git -C "$SRC" ls-files -- "$rel" 2>/dev/null || :
    } | awk -v prefix="$rel/" 'index($0, prefix) == 1 { print substr($0, length(prefix) + 1) }'
}

# File by file, never swapped whole, so a program watching the directory
# sees writes rather than a vanished directory. Files the repository dropped
# go; files it never installed (kitty's current-theme.conf) stay.
mirror_dir() {
    local rel=$1 src=$SRC/$1 dst=$2 r t
    local -A known=()
    [[ -d $src ]] || stop "the source $rel is missing from the checkout"
    if old_link "$dst"; then
        if [[ $MODE == check ]]; then echo "behind    $dst (still a link from an older install)"; DRIFT=1; return 0; fi
        rm -f -- "$dst" || stop "could not remove the old link $dst"
    elif [[ -e $dst && ! -d $dst ]]; then
        stop "$dst is not a directory; move it away and run this again"
    fi
    while IFS= read -r -d '' -u 4 r; do
        mirror_file "$rel/${r#./}" "$dst/${r#./}"
    done 4< <(cd -- "$src" && find . -mindepth 1 \( -type f -o -type l \) -print0 | LC_ALL=C sort -z)

    [[ -d $dst ]] || return 0
    while IFS= read -r r; do known[$r]=1; done < <(history_paths "$rel")
    while IFS= read -r -d '' -u 4 r; do
        r=${r#./}
        t=$dst/$r
        [[ -e $src/$r ]] && continue
        [[ -n ${known[$r]:-} || -n ${MANIFEST[$t]:-} ]] || continue
        if [[ $MODE == check ]]; then
            DRIFT=1
            if ours "$t"; then echo "stale     $t (gone from the repository)"
            else echo "conflict  $t (gone from the repository and changed since; would ask before removing)"
            fi
            continue
        fi
        if ! ours "$t"; then
            conflict Remove "$t" "/dev/null (removed from the repository)" /dev/null
        fi
        remove_file "$t"
    done 4< <(cd -- "$dst" && find . -mindepth 1 \( -type f -o -type l \) -print0 | LC_ALL=C sort -z)
}

# Copied once, then left alone: p10k configure rewrites the file, and a link
# would let it write through into the checkout. Copy a change back to keep it.
seed_file() {
    local rel=$1 src=$SRC/$1 dst=$2
    if old_link "$dst"; then
        if [[ $MODE == check ]]; then echo "behind    $dst (still a link from an older install)"; DRIFT=1; return 0; fi
        rm -f -- "$dst" || stop "could not remove the old link $dst"
    fi
    if [[ -e $dst ]]; then
        if ! cmp -s -- "$src" "$dst"; then
            NOTES+=("$dst differs from $rel and is left alone; copy it back into $rel to keep the change")
        fi
        UNCHANGED=$((UNCHANGED + 1))
        return 0
    fi
    if [[ $MODE == check ]]; then echo "missing   $dst (would be seeded)"; DRIFT=1; return 0; fi
    write_file "$src" "$dst"
}

# A checkout without the executable bit (core.fileMode=false, an archive)
# still gives an el that runs.
ensure_executable() {
    [[ -x $1 ]] && return 0
    if [[ $MODE == check ]]; then echo "behind    $1 (not executable)"; DRIFT=1; return 0; fi
    chmod 755 -- "$1" || stop "could not make $1 executable"
}

# gdb reads exactly one user init file, so gdb is asked which. The block at
# its top records where pwndbg's gdbinit.py is and sources presets.py. A raw
# pwndbg source line (pwndbg's setup.sh appends one) moves into the block and
# the inline debug-max block that predates gdb/debug-max.gdb is dropped.
# Other blocks stay; a symlinked init file or unpaired markers are left alone.
gdb_presets() {
    local help init raw recorded pwndbg="" candidate block new tmp
    local -a candidates=()
    local begin="# >>> dotfiles-terminal gdb presets >>>"
    local end="# <<< dotfiles-terminal gdb presets <<<"
    local dbg_begin='^# ===== debug-max [(]managed[)]'
    local dbg_end='^# ===== end debug-max =====$'
    local pw_line='^[[:space:]]*source[[:space:]]+.*pwndbg/gdbinit[.]py[[:space:]]*$'
    local dbg_ok=0 moved=0
    command -v gdb >/dev/null 2>&1 || return 0
    help=$(gdb --help 2>/dev/null) || help=""
    init=$(sed -n 's/^ *\* user-specific init file: *//p' <<<"$help")
    init=${init%%$'\n'*}
    if [[ -z $init ]]; then
        init=$CONFIG/gdb/gdbinit
        [[ -f $init ]] || init=$HOME/.gdbinit
    fi
    if [[ -f $init ]]; then
        if [[ $(grep -cxF -- "$begin" "$init" || :) != "$(grep -cxF -- "$end" "$init" || :)" ]]; then
            NOTES+=("$init has an unpaired gdb presets marker, so it was left alone")
            return 0
        fi
        if grep -qE -- "$dbg_begin" "$init"; then
            if grep -qE -- "$dbg_end" "$init"; then
                dbg_ok=1
            else
                NOTES+=("$init has a debug-max block without its end marker; that block stays")
            fi
        fi
        raw=$(grep -m 1 -E -- "$pw_line" "$init" || :)
        if [[ -n $raw ]]; then
            moved=1
            raw=$(sed -E 's/^[[:space:]]*source[[:space:]]+//; s/[[:space:]]+$//' <<<"$raw")
            candidates+=("${raw/#\~/$HOME}")
        fi
        recorded=$(sed -n 's/^python gdb_presets_pwndbg_source = "\(.*\)"$/\1/p' "$init")
        recorded=${recorded%%$'\n'*}
        if [[ -n $recorded ]]; then candidates+=("$recorded"); fi
    fi
    candidates+=("$HOME/pwndbg/gdbinit.py" /usr/share/pwndbg/gdbinit.py)
    for candidate in "${candidates[@]}"; do
        if [[ -f $candidate ]]; then pwndbg=$candidate; break; fi
    done
    # A path the init file named is kept while it is missing (pwndbg being
    # rebuilt); only the two defaults are dropped when absent.
    if [[ -z $pwndbg && ${#candidates[@]} -gt 2 ]]; then pwndbg=${candidates[0]}; fi
    if [[ $pwndbg == *[\"\\]* ]]; then
        NOTES+=("pwndbg's path $pwndbg has a quote or backslash, so it is not recorded and gdb runs without pwndbg")
        pwndbg=""
    fi
    if [[ -z $pwndbg ]]; then NO_PWNDBG=1; fi
    block=$begin$'\n'
    if [[ -n $pwndbg ]]; then block+="python gdb_presets_pwndbg_source = \"$pwndbg\""$'\n'; fi
    block+="source $CONFIG/gdb/presets.py"$'\n'$end
    if [[ -L $init ]]; then
        NOTES+=("$init is a symlink and was left alone; put this block at its top by hand: ${block//$'\n'/ | }")
        return 0
    fi
    new=$WORK/gdbinit
    {
        printf '%s\n' "$block"
        if [[ -f $init ]]; then
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
    } >"$new"
    if [[ -f $init ]] && cmp -s -- "$new" "$init"; then
        UNCHANGED=$((UNCHANGED + 1))
        return 0
    fi
    if [[ $MODE == check ]]; then echo "behind    $init (gdb presets block)"; DRIFT=1; return 0; fi
    mkdir -p -- "$(dirname -- "$init")" || stop "could not create the directory of $init"
    tmp=$(mktemp "$init.new-XXXXXX") || stop "could not write beside $init"
    cat -- "$new" >"$tmp" || stop "could not write $tmp"
    if [[ -f $init ]]; then
        chmod --reference="$init" -- "$tmp" || :
        cp -p -- "$init" "$init.bak-$STAMP" || stop "could not back up $init"
        echo "kept the previous $init at $init.bak-$STAMP"
    fi
    mv -fT -- "$tmp" "$init" || stop "could not replace $init"
    INSTALLED=$((INSTALLED + 1))
    echo "configured $init: presets block on top${pwndbg:+, pwndbg at $pwndbg}"
    if (( moved )); then echo "  moved its own pwndbg source line into the block"; fi
    if (( dbg_ok )); then echo "  dropped the inline debug-max block; it is now $CONFIG/gdb/debug-max.gdb"; fi
}

# Included, not linked, so ~/.gitconfig keeps the identity and its own
# entries still override. The path points into this checkout: run this again
# after moving it.
git_include() {
    local include=$SRC/git/gitconfig
    if git config --global --get-all include.path 2>/dev/null | grep -qxF -- "$include"; then
        UNCHANGED=$((UNCHANGED + 1))
        return 0
    fi
    if [[ $MODE == check ]]; then echo "missing   include.path $include in the global git config"; DRIFT=1; return 0; fi
    git config --global --add include.path "$include" || stop "could not add $include to the global git config"
    INSTALLED=$((INSTALLED + 1))
    echo "included $include from the global git config"
}

# sudo looks for commands only in its secure_path, so `sudo el` needs a
# root-owned copy there. Printed, never run: this script does not use sudo.
el_root_copy() {
    local why="is missing"
    if [[ -f $ROOT_EL ]] && cmp -s -- "$SRC/bin/el" "$ROOT_EL"; then return 0; fi
    if [[ -e $ROOT_EL ]]; then why="differs from bin/el"; fi
    UNDONE+=("sudo el: $ROOT_EL $why; run: sudo install -m 0755 -o root -g root '$SRC/bin/el' $ROOT_EL")
    if [[ $MODE == check ]]; then DRIFT=1; fi
}

# Each tool below powers one feature, and each feature does without it.
doctor() {
    local tool families
    local -a missing=()
    for tool in "eza:el" "fzf:Ctrl-R and Ctrl-T in zsh" "tmux:tmux.conf" "wl-copy:tmux and zsh vi-mode yanks" \
                "gdb:the gdb presets" "node:the node REPL helpers" "iex:the IEx helpers" \
                "fastfetch:fastfetch/config.jsonc" "gh:git credentials for GitHub"; do
        command -v "${tool%%:*}" >/dev/null 2>&1 || missing+=("${tool%%:*} (${tool#*:})")
    done
    if (( NO_PWNDBG )); then missing+=("pwndbg in ~/pwndbg or /usr/share/pwndbg (gdb runs plain)"); fi
    if command -v fc-list >/dev/null 2>&1; then
        families=$(fc-list : family 2>/dev/null || :)
        for tool in "CaskaydiaCove Nerd Font Mono" "Pretendard"; do
            grep -qiF -- "$tool" <<<"$families" || missing+=("font $tool (kitty)")
        done
    fi
    if (( ${#missing[@]} == 0 )); then
        echo "doctor: every optional tool is present"
    else
        printf 'doctor: missing %s\n' "${missing[@]}"
    fi
}

# ---- the run -------------------------------------------------------------

STEP_KIND=() STEP_SRC=() STEP_DST=()
step() { STEP_KIND+=("$1"); STEP_SRC+=("$2"); STEP_DST+=("$3"); }

# Files that others source come first, so a stopped run leaves no file
# pointing at one not installed yet.
step dir  zsh/config        "$CONFIG/zsh"
step dir  shell             "$CONFIG/shell"
step file node/repl.js      "$CONFIG/node/repl.js"
# NODE_OPTIONS reaches every node, scripts included; repl.js defines nothing
# outside an interactive REPL.
step file node/node.sh      "$CONFIG/profile.d/node.sh"
# File by file: mirroring the directory would prune a gdbinit kept there.
step file gdb/presets.py    "$CONFIG/gdb/presets.py"
step file gdb/debug-max.gdb "$CONFIG/gdb/debug-max.gdb"
step dir  kitty             "$CONFIG/kitty"
step file tmux/tmux.conf    "$CONFIG/tmux/tmux.conf"
step dir  fastfetch         "$CONFIG/fastfetch"
step exe  bin/el            "$HOME/.local/bin/el"
step file npm/npmrc         "$HOME/.npmrc"
step file iex/iex.exs       "$HOME/.iex.exs"
step file zsh/zshenv        "$HOME/.zshenv"
step file zsh/zprofile      "$HOME/.zprofile"
step file zsh/zshrc         "$HOME/.zshrc"
step file bash/bashrc       "$HOME/.bashrc"
step seed zsh/p10k.zsh      "$HOME/.p10k.zsh"
step gdb  ""                "the gdb presets block"
step git  git/gitconfig     "the global git include"
step el   bin/el            "the root copy of el in $ROOT_EL"

run_step() {
    local i=$1
    case ${STEP_KIND[i]} in
        file) mirror_file "${STEP_SRC[i]}" "${STEP_DST[i]}" ;;
        exe)  mirror_file "${STEP_SRC[i]}" "${STEP_DST[i]}"
              if [[ -e ${STEP_DST[i]} ]]; then ensure_executable "${STEP_DST[i]}"; fi ;;
        dir)  mirror_dir "${STEP_SRC[i]}" "${STEP_DST[i]}" ;;
        seed) seed_file "${STEP_SRC[i]}" "${STEP_DST[i]}" ;;
        gdb)  gdb_presets ;;
        git)  git_include ;;
        el)   el_root_copy ;;
    esac
}

finish() {
    local code=$1 i
    FINISHING=1
    trap - ERR INT TERM
    if [[ $MODE == install ]]; then
        save_manifest || echo "install: could not record what was installed in $MANIFEST_FILE" >&2
    fi
    echo
    if [[ $MODE == install ]]; then
        echo "installed $INSTALLED, unchanged $UNCHANGED, removed $REMOVED, overwritten after a conflict $FORCED"
        if (( code != 0 && STEP < ${#STEP_KIND[@]} )); then
            echo "not done:"
            for (( i = STEP; i < ${#STEP_KIND[@]}; i++ )); do echo "  ${STEP_DST[i]}"; done
        fi
    fi
    for i in "${NOTES[@]}"; do echo "note: $i"; done
    if (( ${#UNDONE[@]} )); then
        echo "left undone:"
        for i in "${UNDONE[@]}"; do echo "  $i"; done
        (( code )) || code=1
    fi
    if [[ $MODE == check ]]; then
        if (( DRIFT || ${#PROBLEMS[@]} )); then
            code=1
            echo "run ./install.sh to apply"
        else
            echo "everything installed is current"
        fi
    fi
    if (( STEP >= ${#STEP_KIND[@]} )); then doctor; fi
    if [[ -n $WORK ]]; then rm -rf -- "$WORK"; fi
    exit "$code"
}

stop() {
    echo "install: stopped: $1" >&2
    finish 1
}

# Inside a command substitution the caller sees the failure and decides;
# only the script's own shell stops the run.
# shellcheck disable=SC2329 # called from the ERR trap
on_error() {
    local code=$? line=$1 command=$2
    if (( BASH_SUBSHELL > 0 )); then exit "$code"; fi
    if (( FINISHING )); then exit 1; fi
    stop "'$command' failed with status $code (install.sh line $line)"
}

check_premise
if (( ${#PROBLEMS[@]} )); then
    if [[ $MODE == install ]]; then
        echo "install: nothing was written; the premise is not met:" >&2
        printf '  %s\n' "${PROBLEMS[@]}" >&2
        exit 1
    fi
    printf 'premise   %s\n' "${PROBLEMS[@]}"
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-terminal.XXXXXX")
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR
trap 'stop "interrupted"' INT TERM

load_manifest
if [[ $MODE == install ]]; then
    mkdir -p -- "$STATE" || stop "could not create $STATE"
    exec 9>"$STATE/lock"
    flock -n 9 || stop "another ./install.sh is running"
fi

for (( STEP = 0; STEP < ${#STEP_KIND[@]}; STEP++ )); do
    run_step "$STEP"
done
finish 0
