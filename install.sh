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
# Premise: a distribution this script recognises (Arch is the one tested;
# Debian/Ubuntu, Fedora/RHEL, openSUSE, Void, Gentoo and Alpine are known by
# their package managers), GNU coreutils, zsh with Oh My Zsh, powerlevel10k
# and its two plugins (./bootstrap.sh), kitty, nvim and git. When one is
# missing, or the session would read these files from somewhere else, nothing
# is written: a half-applied shell setup is worse than none.
#
# Files are copied, never linked, so an installed path never resolves back
# into the checkout. A target holding content this repository did not install
# is a conflict: its diff is shown and the user decides.
#
# Test hooks: DOTFILES_OS_RELEASE replaces /etc/os-release, DOTFILES_ROOT_EL
# replaces /usr/local/bin/el.

set -Eeuo pipefail
# Under a umask of 002 (Fedora's and Ubuntu's, for user private groups) the
# directories made here would be group-writable; nothing here should be.
umask 022

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

# Colour only for a terminal, and never when NO_COLOR asks for none. The
# glyphs (a check, a cross, tree lines) stay either way: they carry meaning.
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    RED=$'\e[31m' GREEN=$'\e[32m' YELLOW=$'\e[33m' CYAN=$'\e[36m' BOLD=$'\e[1m' DIM=$'\e[2m' RESET=$'\e[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' DIM='' RESET=''
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
FAMILY="" PRETTY=""
CONFLICTED=0

# ---- output --------------------------------------------------------------

# $HOME as ~, so a line names the path a user would type.
tilde() {
    if [[ $1 == "$HOME" || $1 == "$HOME"/* ]]; then printf '~%s' "${1#"$HOME"}"; else printf '%s' "$1"; fi
}

# Each step is a tree: its label once there is something to say, one branch
# per change, and a last branch with the count. A step with nothing to say is
# one dim line.
GROUP_LABEL="" GROUP_SHOWN=0 GROUP_WROTE=0 GROUP_SAME=0 GROUP_TODO=0
group_open() {
    GROUP_LABEL=$1 GROUP_SHOWN=0 GROUP_WROTE=0 GROUP_SAME=0 GROUP_TODO=0
}
group_label() {
    (( GROUP_SHOWN )) && return 0
    printf '%s%s%s\n' "$BOLD" "$GROUP_LABEL" "$RESET"
    GROUP_SHOWN=1
}
branch() {
    group_label
    printf '%s├──%s %s\n' "$DIM" "$RESET" "$1"
}
group_close() {
    local tally
    if [[ $MODE == check ]]; then
        if (( GROUP_TODO )); then tally="$GROUP_TODO to apply"; else tally=current; fi
    elif (( GROUP_WROTE )); then
        tally="$GROUP_WROTE written, $GROUP_SAME unchanged"
    else
        tally="$GROUP_SAME unchanged"
    fi
    if (( GROUP_SHOWN )); then
        printf '%s└── %s%s\n' "$DIM" "$tally" "$RESET"
    else
        printf '%s%s  %s%s\n' "$DIM" "$GROUP_LABEL" "$tally" "$RESET"
    fi
}
# A plain list as a tree under a heading already printed.
tree_lines() {
    local colour=$1 i n
    shift
    n=$#
    for (( i = 1; i <= n; i++ )); do
        if (( i < n )); then
            printf '%s├──%s %s%s%s\n' "$DIM" "$RESET" "$colour" "${!i}" "$RESET"
        else
            printf '%s└──%s %s%s%s\n' "$DIM" "$RESET" "$colour" "${!i}" "$RESET"
        fi
    done
}

# ---- premise -------------------------------------------------------------

os_release_field() {
    local key=$1 file=$2 line value=""
    # A last line without a newline still counts.
    while IFS= read -r line || [[ -n $line ]]; do
        if [[ $line == "$key="* ]]; then
            value=${line#*=}
            value=${value#[\"\']}
            value=${value%[\"\']}
        fi
    done <"$file"
    printf '%s' "$value"
}

# The family names the package manager messages point at. ID first, then the
# ID_LIKE words, so a derivative is known by its parent.
distro_family() {
    local word
    for word in "$@"; do
        case $word in
            arch|manjaro|endeavouros|cachyos|garuda|artix) echo arch; return 0 ;;
            debian|ubuntu|linuxmint|pop|elementary|zorin|kali|raspbian) echo debian; return 0 ;;
            fedora|rhel|centos|rocky|almalinux|ol) echo fedora; return 0 ;;
            opensuse*|sles|suse) echo suse; return 0 ;;
            void) echo void; return 0 ;;
            gentoo) echo gentoo; return 0 ;;
            alpine) echo alpine; return 0 ;;
        esac
    done
    return 0
}

install_hint() {
    case $FAMILY in
        arch) echo "pacman -S $1" ;;
        debian) echo "apt install $1" ;;
        fedora) echo "dnf install $1" ;;
        suse) echo "zypper install $1" ;;
        void) echo "xbps-install -S $1" ;;
        gentoo) echo "emerge $1" ;;
        alpine) echo "apk add $1" ;;
        *) echo "your package manager ($1)" ;;
    esac
}

# The first dotted number on a program's --version line, or nothing.
version_of() {
    local out
    out=$("$@" 2>/dev/null | head -n 1) || :
    [[ $out =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]] && printf '%s' "${BASH_REMATCH[1]}"
    return 0
}

check_premise() {
    local os=${DOTFILES_OS_RELEASE:-} f id like tool package sys session session_env help missing=""
    local -a words=()
    if [[ -z $os ]]; then
        for f in /etc/os-release /usr/lib/os-release; do
            if [[ -r $f ]]; then os=$f; break; fi
        done
    fi
    if [[ -z $os || ! -r $os ]]; then
        PROBLEMS+=("no readable os-release, so the distribution is unknown")
    else
        id=$(os_release_field ID "$os")
        like=$(os_release_field ID_LIKE "$os")
        PRETTY=$(os_release_field PRETTY_NAME "$os")
        PRETTY=${PRETTY:-${id:-an unknown system}}
        read -ra words <<<"$id $like"
        FAMILY=$(distro_family "${words[@]}")
        if [[ -z $FAMILY ]]; then
            PROBLEMS+=("$PRETTY is not a distribution this repository recognises (Arch, Debian/Ubuntu, Fedora/RHEL, openSUSE, Void, Gentoo, Alpine)")
        fi
    fi

    for tool in "zsh:zsh:the shell this configures" "kitty:kitty:the terminal kitty.conf is for" \
                "nvim:neovim:the editor, man pager and scrollback pager" \
                "git:git:the git include, and telling this repository's files from others"; do
        IFS=: read -r f package _ <<<"$tool"
        if ! command -v "$f" >/dev/null 2>&1; then
            PROBLEMS+=("$f is not installed (${tool##*:}); install it: $(install_hint "$package")")
        fi
    done
    # busybox's mv has no -T, and every write here is a rename with it.
    # Captured, not piped into grep -q: an early close would trip pipefail.
    help=$(mv --help 2>&1 || :)
    if [[ $help != *--no-target-directory* ]]; then
        PROBLEMS+=("mv lacks -T, so this is not GNU coreutils; install it: $(install_hint coreutils)")
    fi

    if [[ ! -r $OMZ/oh-my-zsh.sh ]]; then missing+=", Oh My Zsh in $(tilde "$OMZ")"; fi
    for f in themes/powerlevel10k plugins/zsh-autosuggestions plugins/zsh-syntax-highlighting; do
        if [[ ! -d $OMZ_CUSTOM/$f ]]; then missing+=", $(tilde "$OMZ_CUSTOM/$f")"; fi
    done
    if [[ -n $missing ]]; then
        PROBLEMS+=("zshrc needs ${missing#, }; run ./bootstrap.sh first")
    fi

    # zsh reads every startup file from ZDOTDIR when it is set, so a ~/.zshrc
    # written here would be ignored. -f still reads the system zshenv.
    if [[ -n ${ZDOTDIR:-} && ${ZDOTDIR%/} != "${HOME%/}" ]]; then
        PROBLEMS+=("ZDOTDIR is $(tilde "$ZDOTDIR"), so zsh would ignore ~/.zshrc; unset it or set it to \$HOME")
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
        # A value with a space or a special comes as $'...'; read raw it was
        # taken for a relative path, and two equal settings were called
        # different.
        if [[ $session == "\$'"*"'" ]]; then
            session=${session:2:-1}
            session=${session//\\\'/\'}
            session=$(printf '%b' "$session")
        fi
        if [[ $session != /* ]]; then session=$HOME/.config; fi
        if [[ ${session%/} != "$CONFIG" ]]; then
            PROBLEMS+=("files would go to $(tilde "$CONFIG"), but the session's programs read $(tilde "${session%/}"): XDG_CONFIG_HOME differs between this shell and the systemd user manager")
        fi
    fi
    if [[ -n ${KITTY_CONFIG_DIRECTORY:-} && ${KITTY_CONFIG_DIRECTORY%/} != "$CONFIG/kitty" ]]; then
        PROBLEMS+=("KITTY_CONFIG_DIRECTORY is $(tilde "$KITTY_CONFIG_DIRECTORY"), so kitty would not read $(tilde "$CONFIG/kitty")")
    fi
}

# Even nvim --version creates ~/.local/state/nvim/nvim.log unless its log goes
# elsewhere, and --check promises to write nothing.
premise_line() {
    local line="premise: $PRETTY ($FAMILY family)" tool v
    for tool in zsh kitty nvim git; do
        v=$(NVIM_LOG_FILE=/dev/null version_of "$tool" --version)
        line+=", $tool${v:+ $v}"
    done
    printf '%s✓%s %s\n' "$GREEN" "$RESET" "$line"
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
        printf '%sinstall: no terminal to ask on; rerun in a terminal to choose, or with --force%s\n' "$YELLOW" "$RESET" >&2
        return 1
    fi
    while :; do
        printf '%s %s? [y] yes  [n] no, keep it and stop  [a] all, this and every later conflict: ' \
            "$verb" "$(tilde "$target")" >&3
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
# Whatever goes ahead is marked, so its branch says it came after a conflict.
conflict() {
    local verb=$1 target=$2
    CONFLICTED=1
    if (( FORCE )); then
        FORCED=$((FORCED + 1))
        return 0
    fi
    group_label
    printf '\n%s✗ conflict%s  %s: not what this repository installed\n' "$BOLD$RED" "$RESET" "$(tilde "$target")"
    show_diff "$target" "$4" "$(tilde "$target") (installed)" "$3"
    if ask "$verb" "$target"; then
        FORCED=$((FORCED + 1))
        return 0
    fi
    stop "kept $(tilde "$target") as it is"
}

# ---- writes --------------------------------------------------------------

# $3 is the branch's name for the file.
write_file() {
    local src=$1 dst=$2 name=$3 dir tmp
    dir=$(dirname -- "$dst")
    mkdir -p -- "$dir" || stop "could not create $(tilde "$dir")"
    tmp=$dst.new-$$
    # Never writable by group or others, whatever the checkout's mode: a
    # clone under umask 002 gives 664, and both shells skip a profile.d file
    # like that.
    if ! { cp -a -- "$src" "$tmp" && chmod go-w -- "$tmp"; }; then
        rm -f -- "$tmp"
        stop "could not write $(tilde "$dst")"
    fi
    # rename(2): a watcher never sees the path missing, and a link left by
    # an older install is replaced, not written through.
    if ! mv -fT -- "$tmp" "$dst"; then
        rm -f -- "$tmp"
        stop "could not replace $(tilde "$dst")"
    fi
    remember "$dst"
    INSTALLED=$((INSTALLED + 1))
    GROUP_WROTE=$((GROUP_WROTE + 1))
    if (( CONFLICTED )); then
        branch "${YELLOW}overwritten after a conflict: $name$RESET"
    else
        branch "$GREEN✓$RESET $name"
    fi
    CONFLICTED=0
}

remove_file() {
    local target=$1 name=$2
    rm -f -- "$target" || stop "could not remove $(tilde "$target")"
    if [[ -n ${MANIFEST[$target]:-} ]]; then MANIFEST[$target]=""; MANIFEST_DIRTY=1; fi
    REMOVED=$((REMOVED + 1))
    if (( CONFLICTED )); then
        branch "${YELLOW}removed after a conflict: $name$RESET"
    else
        branch "$GREEN✓$RESET removed $name"
    fi
    CONFLICTED=0
}

# A file the shells read from outside any repository before the repository
# took it in (shell/debug.sh was ~/.config/debug-max/debug-max.sh). It goes,
# its directory with it once empty, when it is still a version this
# repository has; one changed by hand stays, and is pointed out.
retire_file() {
    local rel=$1 dst=$2 name
    name=$(tilde "$dst")
    [[ -e $dst ]] || return 0
    if ! ours "$dst" "$SRC/$rel"; then
        NOTES+=("$name is no longer read by the shells ($rel took its place) and was changed by hand, so it stays")
        return 0
    fi
    if [[ $MODE == check ]]; then todo "${YELLOW}stale $name ($rel took its place)$RESET"; return 0; fi
    remove_file "$dst" "$name"
    rmdir -- "${dst%/*}" 2>/dev/null || :
}

# Older installs linked into the checkout; such a link is ours to replace.
old_link() {
    [[ -L $1 && $(readlink -f -- "$1" 2>/dev/null) == "$SRC"/* ]]
}

todo() {
    GROUP_TODO=$((GROUP_TODO + 1))
    DRIFT=1
    branch "$1"
}

# ---- steps ---------------------------------------------------------------

# Overwritten on every run: files this repository authors and nothing else
# writes. $3 names the file in its group's tree.
mirror_file() {
    local rel=$1 src=$SRC/$1 dst=$2 name=${3:-$(tilde "$2")}
    [[ -f $src ]] || stop "the source $rel is missing from the checkout"
    if [[ -d $dst && ! -L $dst ]]; then stop "$(tilde "$dst") is a directory where $rel should go"; fi
    if [[ -e $dst ]] && ! old_link "$dst" && cmp -s -- "$src" "$dst"; then
        if [[ -f $dst && ! -L $dst && -n $(find "$dst" -maxdepth 0 -perm /022 2>/dev/null) ]]; then
            if [[ $MODE == check ]]; then todo "${YELLOW}writable by others: $name$RESET"; return 0; fi
            chmod go-w -- "$dst" || stop "could not change the mode of $(tilde "$dst")"
            branch "$GREEN✓$RESET $name is no longer writable by others"
        fi
        if [[ $MODE == install ]]; then remember "$dst"; fi
        UNCHANGED=$((UNCHANGED + 1))
        GROUP_SAME=$((GROUP_SAME + 1))
        return 0
    fi
    if [[ $MODE == check ]]; then
        if [[ ! -e $dst && ! -L $dst ]]; then todo "${YELLOW}missing $name$RESET"
        elif old_link "$dst" || ours "$dst" "$src"; then todo "${YELLOW}behind $name$RESET"
        else todo "$RED✗ conflict $name$RESET"
        fi
        return 0
    fi
    if [[ -e $dst || -L $dst ]] && ! old_link "$dst" && ! ours "$dst" "$src"; then
        conflict Overwrite "$dst" "$rel (repository)" "$src"
    fi
    write_file "$src" "$dst" "$name"
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
        if [[ $MODE == check ]]; then todo "${YELLOW}behind $(tilde "$dst") (still a link from an older install)$RESET"; return 0; fi
        rm -f -- "$dst" || stop "could not remove the old link $(tilde "$dst")"
    elif [[ -e $dst && ! -d $dst ]]; then
        stop "$(tilde "$dst") is not a directory; move it away and run this again"
    fi
    while IFS= read -r -d '' -u 4 r; do
        mirror_file "$rel/${r#./}" "$dst/${r#./}" "${r#./}"
    done 4< <(cd -- "$src" && find . -mindepth 1 \( -type f -o -type l \) -print0 | LC_ALL=C sort -z)

    [[ -d $dst ]] || return 0
    while IFS= read -r r; do known[$r]=1; done < <(history_paths "$rel")
    while IFS= read -r -d '' -u 4 r; do
        r=${r#./}
        t=$dst/$r
        [[ -e $src/$r ]] && continue
        if [[ -z ${known[$r]:-} && -z ${MANIFEST[$t]:-} ]]; then
            branch "${YELLOW}left $r: not from this repository$RESET"
            continue
        fi
        if [[ $MODE == check ]]; then
            if ours "$t"; then todo "${YELLOW}stale $r$RESET"
            else todo "$RED✗ conflict $r (gone from the repository and changed since)$RESET"
            fi
            continue
        fi
        if ! ours "$t"; then
            conflict Remove "$t" "/dev/null (removed from the repository)" /dev/null
        fi
        remove_file "$t" "$r"
    done 4< <(cd -- "$dst" && find . -mindepth 1 \( -type f -o -type l \) -print0 | LC_ALL=C sort -z)
}

# Copied once, then left alone: p10k configure rewrites the file, and a link
# would let it write through into the checkout. Copy a change back to keep it.
seed_file() {
    local rel=$1 src=$SRC/$1 dst=$2 name
    name=$(tilde "$dst")
    if old_link "$dst"; then
        if [[ $MODE == check ]]; then todo "${YELLOW}behind $name (still a link from an older install)$RESET"; return 0; fi
        rm -f -- "$dst" || stop "could not remove the old link $name"
    fi
    if [[ -e $dst ]]; then
        if ! cmp -s -- "$src" "$dst"; then
            NOTES+=("$name differs from $rel and is left alone; copy it back into $rel to keep the change")
        fi
        UNCHANGED=$((UNCHANGED + 1))
        GROUP_SAME=$((GROUP_SAME + 1))
        return 0
    fi
    if [[ $MODE == check ]]; then todo "${YELLOW}missing $name (seeded once)$RESET"; return 0; fi
    write_file "$src" "$dst" "$name"
}

# A checkout without the executable bit (core.fileMode=false, an archive)
# still gives an el that runs.
ensure_executable() {
    [[ -x $1 ]] && return 0
    if [[ $MODE == check ]]; then todo "${YELLOW}behind $(tilde "$1") (not executable)$RESET"; return 0; fi
    chmod 755 -- "$1" || stop "could not make $(tilde "$1") executable"
    branch "$GREEN✓$RESET made $(tilde "$1") executable"
}

# gdb reads exactly one user init file, so gdb is asked which. The block at
# its top records where pwndbg's gdbinit.py is and sources presets.py. A raw
# pwndbg source line (pwndbg's setup.sh appends one) moves into the block and
# the inline debug-max block that predates gdb/debug-max.gdb is dropped.
# Other blocks stay; a symlinked init file or markers out of order are left
# alone.
#
# The scan counts the blocks gdb closes with "end": a source line inside one
# (define init-pwndbg ... end) runs with its block and stays in it. The
# bodies of python, guile and document are not gdb commands, so nothing in
# them opens a block. Rewriting, it exits 3 on a marker out of order or
# unclosed instead of dropping everything after it.
# shellcheck disable=SC2016 # an awk program: its $0 is awk's
GDB_SCAN='
function track(line) {
    if (text) {
        if (line ~ /^[[:space:]]*end[[:space:]]*$/) { text = 0; depth-- }
        return
    }
    if (line ~ /^[[:space:]]*end[[:space:]]*$/) { if (depth > 0) depth--; return }
    if (line ~ /^[[:space:]]*(python|guile)[[:space:]]*$/ || line ~ /^[[:space:]]*document([[:space:]]|$)/) { text = 1; depth++; return }
    if (line ~ /^[[:space:]]*(define|if|while|commands)([[:space:]]|$)/) depth++
}
mode == "find" {
    if (depth == 0 && $0 ~ pw_line) { print; exit }
    track($0)
    next
}
$0 == begin { if (ours) bad = 1; ours = 1; next }
ours { if ($0 == end) ours = 0; next }
$0 == end { bad = 1 }
dbg_ok && $0 ~ dbg_begin { if (dbg) bad = 1; dbg = 1; next }
dbg { if ($0 ~ dbg_end) dbg = 0; next }
depth == 0 && $0 ~ pw_line { next }
{ track($0) }
!started && /^[[:space:]]*$/ { next }
{ if (!started) { print ""; started = 1 } print }
END { if (mode != "find" && (ours || dbg || bad)) exit 3 }
'
gdb_presets() {
    local help init raw recorded pwndbg="" candidate block new tmp status=0
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
            NOTES+=("$(tilde "$init") has an unpaired gdb presets marker, so it was left alone")
            return 0
        fi
        if grep -qE -- "$dbg_begin" "$init"; then
            if grep -qE -- "$dbg_end" "$init"; then
                dbg_ok=1
            else
                NOTES+=("$(tilde "$init") has a debug-max block without its end marker; that block stays")
            fi
        fi
        raw=$(awk -v mode=find -v pw_line="$pw_line" "$GDB_SCAN" "$init" || :)
        if [[ -n $raw ]]; then
            moved=1
            raw=$(sed -E 's/^[[:space:]]*source[[:space:]]+//; s/[[:space:]]+$//' <<<"$raw")
            candidates+=("${raw/#\~/$HOME}")
        fi
        recorded=$(sed -n 's/^python gdb_presets_pwndbg_source = "\(.*\)"$/\1/p' "$init")
        recorded=${recorded%%$'\n'*}
        if [[ -n $recorded ]]; then candidates+=("$recorded"); fi
    fi
    # A git checkout (pwndbg's own way, on any distribution), then Arch's
    # package.
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
        NOTES+=("$(tilde "$init") is a symlink and was left alone; put this block at its top by hand: ${block//$'\n'/ | }")
        return 0
    fi
    new=$WORK/gdbinit
    {
        printf '%s\n' "$block"
        if [[ -f $init ]]; then
            awk -v mode=rewrite -v begin="$begin" -v end="$end" -v dbg_ok="$dbg_ok" \
                -v dbg_begin="$dbg_begin" -v dbg_end="$dbg_end" -v pw_line="$pw_line" \
                "$GDB_SCAN" "$init" || status=$?
        fi
    } >"$new"
    if (( status == 3 )); then
        NOTES+=("$(tilde "$init") has a gdb presets or debug-max marker out of order or unclosed, so it was left alone")
        return 0
    elif (( status )); then
        stop "could not read $(tilde "$init")"
    fi
    if [[ -f $init ]] && cmp -s -- "$new" "$init"; then
        UNCHANGED=$((UNCHANGED + 1))
        GROUP_SAME=$((GROUP_SAME + 1))
        return 0
    fi
    if [[ $MODE == check ]]; then todo "${YELLOW}behind the presets block in $(tilde "$init")$RESET"; return 0; fi
    mkdir -p -- "$(dirname -- "$init")" || stop "could not create the directory of $(tilde "$init")"
    tmp=$(mktemp "$init.new-XXXXXX") || stop "could not write beside $(tilde "$init")"
    cat -- "$new" >"$tmp" || stop "could not write $(tilde "$tmp")"
    if [[ -f $init ]]; then
        chmod --reference="$init" -- "$tmp" || :
        cp -p -- "$init" "$init.bak-$STAMP" || stop "could not back up $(tilde "$init")"
    fi
    mv -fT -- "$tmp" "$init" || stop "could not replace $(tilde "$init")"
    INSTALLED=$((INSTALLED + 1))
    GROUP_WROTE=$((GROUP_WROTE + 1))
    branch "$GREEN✓$RESET presets block in $(tilde "$init")${pwndbg:+, pwndbg at $(tilde "$pwndbg")}"
    if [[ -f $init.bak-$STAMP ]]; then branch "${DIM}the previous file is $(tilde "$init.bak-$STAMP")$RESET"; fi
    if (( moved )); then branch "${DIM}its own pwndbg source line moved into the block$RESET"; fi
    if (( dbg_ok )); then branch "${DIM}the inline debug-max block dropped; it is $(tilde "$CONFIG/gdb/debug-max.gdb") now$RESET"; fi
}

# Included, not linked, so ~/.gitconfig keeps the identity and its own
# entries still override. The path points into this checkout: run this again
# after moving it.
git_include() {
    local include=$SRC/git/gitconfig
    if git config --global --get-all include.path 2>/dev/null | grep -qxF -- "$include"; then
        UNCHANGED=$((UNCHANGED + 1))
        GROUP_SAME=$((GROUP_SAME + 1))
        return 0
    fi
    if [[ $MODE == check ]]; then todo "${YELLOW}missing the include of $(tilde "$include") in the global git config$RESET"; return 0; fi
    git config --global --add include.path "$include" || stop "could not add $(tilde "$include") to the global git config"
    INSTALLED=$((INSTALLED + 1))
    GROUP_WROTE=$((GROUP_WROTE + 1))
    branch "$GREEN✓$RESET included $(tilde "$include") from the global git config"
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
        printf '%s✓%s doctor: every optional tool is present\n' "$GREEN" "$RESET"
    else
        printf '%sdoctor: missing%s\n' "$YELLOW" "$RESET"
        tree_lines "$YELLOW" "${missing[@]}"
    fi
}

# ---- the run -------------------------------------------------------------

STEP_KIND=() STEP_SRC=() STEP_DST=()
step() { STEP_KIND+=("$1"); STEP_SRC+=("$2"); STEP_DST+=("$3"); }

# Directories first, then the single files as one group: files that others
# source come before the files sourcing them (zsh/config and shell before
# zshrc, repl.js before node.sh), so a stopped run leaves no file pointing at
# one not installed yet.
step dir  zsh/config        "$CONFIG/zsh"
step dir  shell             "$CONFIG/shell"
step dir  kitty             "$CONFIG/kitty"
step dir  fastfetch         "$CONFIG/fastfetch"
step file node/repl.js      "$CONFIG/node/repl.js"
# NODE_OPTIONS reaches every node, scripts included; repl.js defines nothing
# outside an interactive REPL.
step file node/node.sh      "$CONFIG/profile.d/node.sh"
# File by file: mirroring the directory would prune a gdbinit kept there.
step file gdb/presets.py    "$CONFIG/gdb/presets.py"
step file gdb/debug-max.gdb "$CONFIG/gdb/debug-max.gdb"
step file tmux/tmux.conf    "$CONFIG/tmux/tmux.conf"
step exe  bin/el            "$HOME/.local/bin/el"
step file npm/npmrc         "$HOME/.npmrc"
step file iex/iex.exs       "$HOME/.iex.exs"
step file zsh/zshenv        "$HOME/.zshenv"
step file zsh/zprofile      "$HOME/.zprofile"
step file zsh/zshrc         "$HOME/.zshrc"
step file bash/bashrc       "$HOME/.bashrc"
step gone shell/debug.sh    "$HOME/.config/debug-max/debug-max.sh"
step seed zsh/p10k.zsh      "$HOME/.p10k.zsh"
step gdb  ""                "the gdb presets block"
step git  git/gitconfig     "the global git include"
step el   bin/el            "the root copy of el in $ROOT_EL"

# The group a step's branches go under: its own directory, "home files" for
# the single files, "gdb and git" for the two managed entries.
group_of() {
    case ${STEP_KIND[$1]} in
        dir) tilde "${STEP_DST[$1]}" ;;
        file|exe|seed|gone) printf 'home files' ;;
        gdb|git) printf 'gdb and git' ;;
        *) printf '' ;;
    esac
}

run_step() {
    local i=$1
    case ${STEP_KIND[i]} in
        file) mirror_file "${STEP_SRC[i]}" "${STEP_DST[i]}" ;;
        exe)  mirror_file "${STEP_SRC[i]}" "${STEP_DST[i]}"
              if [[ -e ${STEP_DST[i]} ]]; then ensure_executable "${STEP_DST[i]}"; fi ;;
        dir)  mirror_dir "${STEP_SRC[i]}" "${STEP_DST[i]}" ;;
        seed) seed_file "${STEP_SRC[i]}" "${STEP_DST[i]}" ;;
        gone) retire_file "${STEP_SRC[i]}" "${STEP_DST[i]}" ;;
        gdb)  gdb_presets ;;
        git)  git_include ;;
        el)   el_root_copy ;;
    esac
}

finish() {
    local code=$1 i
    local -a rest=()
    FINISHING=1
    trap - ERR INT TERM
    if [[ $MODE == install ]]; then
        save_manifest || echo "install: could not record what was installed in $(tilde "$MANIFEST_FILE")" >&2
    fi
    echo
    if [[ $MODE == install ]] && (( code != 0 && STEP < ${#STEP_KIND[@]} )); then
        for (( i = STEP; i < ${#STEP_KIND[@]}; i++ )); do
            case ${STEP_KIND[i]} in
                dir|file|exe|seed|gone) rest+=("$(tilde "${STEP_DST[i]}")") ;;
                *) rest+=("${STEP_DST[i]}") ;;
            esac
        done
        printf '%snot done (%s written before the stop):%s\n' "$DIM" "$INSTALLED" "$RESET"
        tree_lines "$DIM" "${rest[@]}"
    elif (( ${#UNDONE[@]} )); then
        printf '%sleft undone%s %s(%s written)%s\n' "$BOLD$YELLOW" "$RESET" "$DIM" "$INSTALLED" "$RESET"
        tree_lines "$YELLOW" "${UNDONE[@]}"
        (( code )) || code=1
    elif [[ $MODE == install ]]; then
        printf '%s✓ everything is in place%s %s(%s written, %s unchanged)%s\n' \
            "$BOLD$GREEN" "$RESET" "$DIM" "$INSTALLED" "$UNCHANGED" "$RESET"
    fi
    for i in "${NOTES[@]}"; do printf '%snote: %s%s\n' "$DIM" "$i" "$RESET"; done
    if [[ $MODE == check ]]; then
        if (( DRIFT || ${#PROBLEMS[@]} )); then
            code=1
            printf '%srun ./install.sh to apply%s\n' "$YELLOW" "$RESET"
        else
            printf '%s✓%s everything installed is current\n' "$GREEN" "$RESET"
        fi
    fi
    if (( STEP >= ${#STEP_KIND[@]} )); then doctor; fi
    if [[ -n $WORK ]]; then rm -rf -- "$WORK"; fi
    exit "$code"
}

stop() {
    if (( GROUP_SHOWN )); then printf '%s└── stopped here%s\n' "$DIM" "$RESET"; fi
    printf '%s✗ stopped:%s %s\n' "$BOLD$RED" "$RESET" "$1" >&2
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

printf '%sdotfiles-terminal%s  %s%s %s%s\n' "$BOLD$CYAN" "$RESET" "$DIM" \
    "$([[ $MODE == check ]] && echo checking || echo installing into)" "$(tilde "$HOME")" "$RESET"
check_premise
if (( ${#PROBLEMS[@]} )); then
    if [[ $MODE == install ]]; then
        printf '%s✗ the premise is not met; nothing was written%s\n' "$RED" "$RESET" >&2
        tree_lines "" "${PROBLEMS[@]}" >&2
        exit 1
    fi
    printf '%s✗ the premise is not met%s\n' "$RED" "$RESET"
    tree_lines "" "${PROBLEMS[@]}"
else
    premise_line
fi
echo

WORK=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-terminal.XXXXXX")
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR
trap 'stop "interrupted"' INT TERM

load_manifest
if [[ $MODE == install ]]; then
    mkdir -p -- "$STATE" || stop "could not create $(tilde "$STATE")"
    exec 9>"$STATE/lock"
    flock -n 9 || stop "another ./install.sh is running"
fi

current=""
for (( STEP = 0; STEP < ${#STEP_KIND[@]}; STEP++ )); do
    label=$(group_of "$STEP")
    if [[ $label != "$current" ]]; then
        [[ -n $current ]] && group_close
        current=$label
        [[ -n $current ]] && group_open "$current"
    fi
    run_step "$STEP"
done
[[ -n $current ]] && group_close
finish 0
