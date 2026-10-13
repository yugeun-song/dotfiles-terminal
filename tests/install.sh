#!/usr/bin/env bash
# Runs install.sh against a temporary HOME. Nothing reaches the real one: each
# case gets its own HOME, a copy of this checkout as its own repository (so a
# case can commit a change and the installer's git checks see it), stand-ins
# for systemctl, gdb and fc-list, and DOTFILES_OS_RELEASE and DOTFILES_ROOT_EL
# pointing at files of its own. Conflict prompts are answered through a pty.
# Output is plain (NO_COLOR) unless a case asks for colour.
# shellcheck disable=SC2016 # the stand-ins expand their own variables

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-terminal-test.XXXXXX")
trap 'chmod -R u+w -- "$WORK" 2>/dev/null; rm -rf -- "$WORK"' EXIT

passed=0
failed=0
pass() { passed=$((passed + 1)); }
fail() { failed=$((failed + 1)); printf 'FAIL  install: %s\n' "$*"; }
is() { if [[ $2 == "$3" ]]; then pass; else fail "$1: got [$2], want [$3]"; fi; }
has() { if grep -qF -- "$3" <<<"$2"; then pass; else fail "$1: no [$3] in:"; printf '%s\n' "$2" | sed 's/^/      /'; fi; }
lacks() { if grep -qF -- "$3" <<<"$2"; then fail "$1: unexpected [$3] in:"; printf '%s\n' "$2" | sed 's/^/      /'; else pass; fi; }
same() { if cmp -s -- "$2" "$3"; then pass; else fail "$1: $2 differs from $3"; fi; }
differs() { if cmp -s -- "$2" "$3"; then fail "$1: $2 equals $3"; else pass; fi; }

# PATHs without kitty, and without nvim, for the missing-premise cases.
mkdir -p "$WORK/nokitty" "$WORK/nonvim"
for f in /usr/bin/*; do
    [[ ${f##*/} == kitty ]] || ln -s "$f" "$WORK/nokitty/${f##*/}"
    [[ ${f##*/} == nvim ]] || ln -s "$f" "$WORK/nonvim/${f##*/}"
done

# Answers prompts on a pty: each answer is sent when the next prompt appears.
cat >"$WORK/answer.py" <<'EOF'
import os, pty, select, sys, time
answers, cmd = sys.argv[1], sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
out, sent, deadline = b"", 0, time.time() + 60
prompt = b"[a] all, this and every later conflict: "
while time.time() < deadline:
    if select.select([fd], [], [], 0.2)[0]:
        try:
            data = os.read(fd, 65536)
        except OSError:
            break
        if not data:
            break
        out += data
        while sent < min(out.count(prompt), len(answers)):
            os.write(fd, answers[sent].encode() + b"\n")
            sent += 1
else:
    os.kill(pid, 9)
_, status = os.waitpid(pid, 0)
sys.stdout.write(out.decode("utf-8", "replace").replace("\r\n", "\n"))
sys.exit(os.waitstatus_to_exitcode(status))
EOF

# One case: $T holds home/, repo/ and the stand-ins.
setup() {
    T=$(mktemp -d "$WORK/case.XXXXXX")
    mkdir -p "$T/home" "$T/bin" "$T/repo"
    (cd "$REPO" && git ls-files -z --cached --others --exclude-standard | xargs -0 cp -a --parents -t "$T/repo")
    git -C "$T/repo" init -q
    git -C "$T/repo" add -A
    git -C "$T/repo" -c user.name=test -c user.email=test@test commit -qm initial
    mkdir -p "$T/home/.oh-my-zsh/custom/themes/powerlevel10k" \
        "$T/home/.oh-my-zsh/custom/plugins/zsh-autosuggestions" \
        "$T/home/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
    : >"$T/home/.oh-my-zsh/oh-my-zsh.sh"
    printf 'NAME="Arch Linux"\nPRETTY_NAME="Arch Linux"\nID=arch\n' >"$T/os-release"
    cp -a "$T/repo/bin/el" "$T/root-el"
    : >"$T/session-env"
    printf '#!/bin/sh\n[ "$1 $2" = "--user show-environment" ] && cat "%s"\nexit 0\n' "$T/session-env" >"$T/bin/systemctl"
    printf '#!/bin/sh\necho "   * user-specific init file: $HOME/.gdbinit"\n' >"$T/bin/gdb"
    printf '#!/bin/sh\nprintf "CaskaydiaCove Nerd Font Mono\\nPretendard\\n"\n' >"$T/bin/fc-list"
    chmod +x "$T/bin/"*
    TPATH=$T/bin:/usr/bin
}

# The installer with a clean environment; extra NAME=value pairs before "--".
installer() {
    local -a extra=()
    while (( $# )) && [[ $1 != -- ]]; do extra+=("$1"); shift; done
    shift
    env -i HOME="$T/home" PATH="$TPATH" LANG=C.UTF-8 TMPDIR="$T" NO_COLOR=1 GIT_CONFIG_NOSYSTEM=1 \
        DOTFILES_OS_RELEASE="$T/os-release" DOTFILES_ROOT_EL="$T/root-el" "${extra[@]}" "$@"
}
run() { out=$(installer -- setsid -w bash "$T/repo/install.sh" "$@" </dev/null 2>&1); code=$?; }
run_with() { local -a e=(); while [[ $1 != -- ]]; do e+=("$1"); shift; done; shift
    out=$(installer "${e[@]}" -- setsid -w bash "$T/repo/install.sh" "$@" </dev/null 2>&1); code=$?; }
answer() { local a=$1; shift; out=$(installer -- python3 -I "$WORK/answer.py" "$a" bash "$T/repo/install.sh" "$@" 2>&1); code=$?; }
# On a pty and without NO_COLOR, as a terminal would run it.
coloured() {
    out=$(env -i HOME="$T/home" PATH="$TPATH" LANG=C.UTF-8 TMPDIR="$T" TERM=xterm GIT_CONFIG_NOSYSTEM=1 \
        DOTFILES_OS_RELEASE="$T/os-release" DOTFILES_ROOT_EL="$T/root-el" \
        python3 -I "$WORK/answer.py" "" bash "$T/repo/install.sh" "$@" 2>&1)
    code=$?
}
esc=$'\e['
plain() { if [[ $2 != *"$esc"* ]]; then pass; else fail "$1: an escape sequence in plain output"; fi; }
commit() { git -C "$T/repo" add -A && git -C "$T/repo" -c user.name=test -c user.email=test@test commit -qm "$1"; }
tree() { (cd "$T/home" && find . -printf '%p %s %T@\n' | LC_ALL=C sort); }
entries() { find "$T/home" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort | tr '\n' ' '; }

# ---- usage ----
setup
run --bogus; is "an unknown argument" "$code" 2
has "an unknown argument prints usage" "$out" "usage: ./install.sh"
run --help; is "--help" "$code" 0
run --check --force; is "--check with --force" "$code" 2
is "usage errors write nothing" "$(entries)" ".oh-my-zsh "

# ---- fresh install, then a no-op ----
setup
run; is "fresh install" "$code" 0
has "fresh install installs zshrc" "$out" "├── ✓ ~/.zshrc"
has "fresh install names the premise" "$out" "✓ premise: Arch Linux (arch family), zsh"
has "fresh install ends in place" "$out" "✓ everything is in place"
plain "plain output without a terminal" "$out"
same "zshrc content" "$T/home/.zshrc" "$T/repo/zsh/zshrc"
same "caps-lock goes under XDG_CONFIG_HOME's default" "$T/home/.config/zsh/caps-lock.zsh" "$T/repo/zsh/config/caps-lock.zsh"
if [[ -x $T/home/.local/bin/el ]]; then pass; else fail "el is executable"; fi
if [[ -s $T/home/.local/state/dotfiles-terminal/installed ]]; then pass; else fail "the manifest is written"; fi
has "the git include is in the temporary HOME" "$(cat "$T/home/.gitconfig")" "path = $T/repo/git/gitconfig"
has "the gdb block" "$(cat "$T/home/.gdbinit")" "source $T/home/.config/gdb/presets.py"
before=$(tree)
run; is "re-run" "$code" 0
has "re-run installs nothing" "$out" "everything is in place (0 written,"
# shellcheck disable=SC2088 # the installer prints the ~ itself
has "an unchanged directory is one line" "$out" "~/.config/kitty  4 unchanged"
is "re-run touches nothing" "$(tree | grep -v '/dotfiles-terminal/lock ')" "$(grep -v '/dotfiles-terminal/lock ' <<<"$before")"
run --check; is "--check when current" "$code" 0
has "--check says current" "$out" "everything installed is current"

# ---- conflicts ----
setup
run
printf '# added by another tool\nexport FOO=1\n' >>"$T/home/.zshrc"
before=$(tree)
run --check; is "--check with a conflict" "$code" 1
has "--check names the conflict" "$out" "✗ conflict ~/.zshrc"
is "--check writes nothing" "$(tree)" "$before"

answer y; is "conflict answered y" "$code" 0
has "the conflict header" "$out" "✗ conflict  ~/.zshrc: not what this repository installed"
has "the installed side of the diff" "$out" "--- ~/.zshrc (installed)"
has "the repository side of the diff" "$out" "+++ zsh/zshrc (repository)"
has "removed lines carry their number" "$out" "│ -export FOO=1"
has "the prompt" "$out" "Overwrite ~/.zshrc? [y] yes  [n] no, keep it and stop  [a] all, this and every later conflict:"
has "y marks the overwrite" "$out" "overwritten after a conflict: ~/.zshrc"
plain "plain output on a pty with NO_COLOR" "$out"
same "y overwrites" "$T/home/.zshrc" "$T/repo/zsh/zshrc"

printf 'export FOO=1\n' >>"$T/home/.zshrc"
printf 'export BAR=1\n' >>"$T/home/.bashrc"
answer n; is "conflict answered n" "$code" 1
has "n stops there" "$out" "✗ stopped: kept ~/.zshrc as it is"
has "n lists what was not done" "$out" "not done ("
has "the rest is listed" "$out" "├── ~/.bashrc"
differs "n keeps the file" "$T/home/.zshrc" "$T/repo/zsh/zshrc"
differs "n reaches nothing after it" "$T/home/.bashrc" "$T/repo/bash/bashrc"

answer a; is "conflict answered a" "$code" 0
is "a asks once" "$(grep -c 'every later conflict:' <<<"$out")" 1
has "a forces the rest" "$out" "overwritten after a conflict: ~/.bashrc"
same "a overwrites the first" "$T/home/.zshrc" "$T/repo/zsh/zshrc"
same "a overwrites the second" "$T/home/.bashrc" "$T/repo/bash/bashrc"

printf 'export FOO=1\n' >>"$T/home/.zshrc"
run; is "no terminal" "$code" 1
has "no terminal says what to do" "$out" "rerun in a terminal to choose, or with --force"
differs "no terminal keeps the file" "$T/home/.zshrc" "$T/repo/zsh/zshrc"
run --force; is "--force" "$code" 0
has "--force names what it overwrote" "$out" "overwritten after a conflict: ~/.zshrc"
same "--force overwrites" "$T/home/.zshrc" "$T/repo/zsh/zshrc"

# An existing file that was there before any install is a conflict too.
setup
mkdir -p "$T/home/.config/tmux"
printf 'set -g status off\n' >"$T/home/.config/tmux/tmux.conf"
run; is "a file from before the first install" "$code" 1
has "a file from before the first install is a conflict" "$out" "✗ conflict  ~/.config/tmux/tmux.conf"

# ---- what counts as ours ----
setup
run
printf '\n# local change, not committed\n' >>"$T/repo/zsh/zshrc"
run; is "an uncommitted edit installs" "$code" 0
printf '# another uncommitted change\n' >>"$T/repo/zsh/zshrc"
run; is "the next uncommitted edit is not a conflict" "$code" 0
lacks "the manifest knows the uncommitted install" "$out" "not what this repository installed"
git -C "$T/repo" checkout -q -- zsh/zshrc
printf 'alias x=y\n' >>"$T/repo/zsh/zshrc"
commit "change zshrc"
run --check; is "--check after a commit" "$code" 1
has "--check calls it behind" "$out" "behind ~/.zshrc"
ln -sf "$T/repo/bash/bashrc" "$T/home/.bashrc"
run; is "a link from an older install" "$code" 0
if [[ -f $T/home/.bashrc && ! -L $T/home/.bashrc ]]; then pass; else fail "the old link became a file"; fi

# ---- prune ----
setup
run
printf 'include x\n' >"$T/home/.config/kitty/current-theme.conf"
git -C "$T/repo" rm -q kitty/scroll_mark.py
commit "drop scroll_mark"
run --check; is "--check sees the stale file" "$code" 1
has "--check calls it stale" "$out" "├── stale scroll_mark.py"
run; is "prune" "$code" 0
if [[ ! -e $T/home/.config/kitty/scroll_mark.py ]]; then pass; else fail "a dropped file is removed"; fi
if [[ -e $T/home/.config/kitty/current-theme.conf ]]; then pass; else fail "a file the repository never had stays"; fi
has "and it is pointed out" "$out" "left current-theme.conf: not from this repository"
has "the removal is a branch" "$out" "├── ✓ removed scroll_mark.py"
printf '# mine\n' >>"$T/home/.config/kitty/search.py"
git -C "$T/repo" rm -q kitty/search.py
commit "drop search"
answer n; is "removing a changed file, answered n" "$code" 1
has "the removal prompt" "$out" "Remove ~/.config/kitty/search.py?"
has "the removal diff" "$out" "+++ /dev/null (removed from the repository)"
if [[ -e $T/home/.config/kitty/search.py ]]; then pass; else fail "n keeps the changed file"; fi
answer y; is "removing a changed file, answered y" "$code" 0
if [[ ! -e $T/home/.config/kitty/search.py ]]; then pass; else fail "y removes it"; fi

# ---- premise ----
setup
for fixture in "debian:debian:Debian GNU/Linux 13:" "ubuntu:debian:Ubuntu 24.04 LTS:debian" \
               "fedora:fedora:Fedora Linux 42:" "rhel:fedora:Red Hat Enterprise Linux 9.5:fedora" \
               "opensuse-tumbleweed:suse:openSUSE Tumbleweed:opensuse suse" "void:void:Void Linux:" \
               "gentoo:gentoo:Gentoo Linux:" "alpine:alpine:Alpine Linux v3.21:" "linuxmint:debian:Linux Mint 22:ubuntu debian"; do
    IFS=: read -r id family name like <<<"$fixture"
    printf 'ID=%s\nID_LIKE="%s"\nPRETTY_NAME="%s"\n' "$id" "$like" "$name" >"$T/os-release"
    run --check
    has "$id is recognised" "$out" "✓ premise: $name ($family family)"
done
is "recognising writes nothing" "$(entries)" ".oh-my-zsh "
printf 'ID=nixos\nPRETTY_NAME="NixOS 25.05"\n' >"$T/os-release"
run; is "an unknown distribution" "$code" 1
has "an unknown distribution says why" "$out" "NixOS 25.05 is not a distribution this repository recognises"
has "the premise failure heads the output" "$out" "✗ the premise is not met; nothing was written"
is "an unknown distribution writes nothing" "$(entries)" ".oh-my-zsh "
printf 'ID=endeavouros\nID_LIKE=arch\n' >"$T/os-release"
run; is "an Arch derivative" "$code" 0

setup
TPATH=$T/bin:$WORK/nokitty
run; is "kitty missing" "$code" 1
has "kitty missing says so" "$out" "kitty is not installed"
has "kitty missing names Arch's package" "$out" "install it: pacman -S kitty"
is "kitty missing writes nothing" "$(entries)" ".oh-my-zsh "

setup
TPATH=$T/bin:$WORK/nonvim
printf 'ID=debian\nPRETTY_NAME="Debian GNU/Linux 13"\n' >"$T/os-release"
run; is "nvim missing on Debian" "$code" 1
has "nvim missing on Debian names apt" "$out" "install it: apt install neovim"
printf 'ID=fedora\nPRETTY_NAME="Fedora Linux 42"\n' >"$T/os-release"
run; has "nvim missing on Fedora names dnf" "$out" "install it: dnf install neovim"
printf 'ID=rocky\nID_LIKE="rhel centos fedora"\nPRETTY_NAME="Rocky Linux 9"\n' >"$T/os-release"
run; has "nvim missing on Rocky names dnf too" "$out" "install it: dnf install neovim"
printf 'ID=void\nPRETTY_NAME="Void Linux"\n' >"$T/os-release"
run; has "nvim missing on Void names xbps" "$out" "install it: xbps-install -S neovim"

setup
rm -rf -- "$T/home/.oh-my-zsh/custom/themes/powerlevel10k"
run; is "powerlevel10k missing" "$code" 1
has "powerlevel10k missing points at bootstrap" "$out" "run ./bootstrap.sh first"

setup
run_with ZDOTDIR="$T/home/.config/zsh" --; is "ZDOTDIR elsewhere" "$code" 1
has "ZDOTDIR says why" "$out" "so zsh would ignore ~/.zshrc"
is "ZDOTDIR writes nothing" "$(entries)" ".oh-my-zsh "

setup
run_with XDG_CONFIG_HOME="$T/xdg" --; is "XDG_CONFIG_HOME only in this shell" "$code" 1
has "the mismatch is named" "$out" "XDG_CONFIG_HOME differs between this shell and the systemd user manager"
printf 'XDG_CONFIG_HOME=%s\n' "$T/xdg" >"$T/session-env"
run_with XDG_CONFIG_HOME="$T/xdg" --; is "XDG_CONFIG_HOME in both" "$code" 0
if [[ -f $T/xdg/kitty/kitty.conf && -f $T/xdg/zsh/caps-lock.zsh ]]; then pass; else fail "files follow XDG_CONFIG_HOME"; fi

# ---- left undone, failures ----
setup
printf '#!/bin/sh\n' >"$T/root-el"
run; is "a stale root copy of el" "$code" 1
has "the sudo command is printed" "$out" "sudo install -m 0755 -o root -g root '$T/repo/bin/el' $T/root-el"

setup
run
printf '# change\n' >>"$T/repo/kitty/kitty.conf"
chmod 555 "$T/home/.config/kitty"
run; is "an unwritable directory" "$code" 1
has "the failed write is named" "$out" "✗ stopped: could not write ~/.config/kitty/kitty.conf"
has "what remains is listed" "$out" "── ~/.zshrc"
chmod 755 "$T/home/.config/kitty"

# ---- colour ----
setup
coloured; is "a coloured run" "$code" 0
has "colour on a terminal" "$out" "$esc"
has "the check mark is green" "$out" "$esc""32m✓"
has "the title is bold cyan" "$out" "$esc""1m$esc""36mdotfiles-terminal"
coloured --check
has "--check is coloured too" "$out" "$esc""32m✓$esc""0m everything installed is current"

# ---- fixes from the 2026-10-14 review ----
# A pwndbg source line inside a define runs with it and stays there; one at
# the top level moves into the presets block.
setup
mkdir -p "$T/home/pwndbg" && : >"$T/home/pwndbg/gdbinit.py"
printf 'define init-pwndbg\n  source %s/pwndbg/gdbinit.py\nend\nset pagination off\n' "$T/home" >"$T/home/.gdbinit"
run
is "a pwndbg line inside a define stays in it" "$(sed -n '/^define init-pwndbg$/,/^end$/p' "$T/home/.gdbinit")" \
    "$(printf 'define init-pwndbg\n  source %s/pwndbg/gdbinit.py\nend' "$T/home")"
lacks "and nothing says it moved" "$out" "its own pwndbg source line moved"
setup
mkdir -p "$T/home/pwndbg" && : >"$T/home/pwndbg/gdbinit.py"
printf 'source %s/pwndbg/gdbinit.py\nset pagination off\n' "$T/home" >"$T/home/.gdbinit"
run
lacks "a top-level pwndbg line moves" "$(sed -n '/<<< dotfiles-terminal gdb presets <<</,$p' "$T/home/.gdbinit")" "pwndbg/gdbinit.py"
has "and says so" "$out" "its own pwndbg source line moved into the block"

# Markers out of order or unclosed: the file stays as it is, with a note,
# not cut at the first marker.
setup
printf '# <<< dotfiles-terminal gdb presets <<<\nset history save on\n# >>> dotfiles-terminal gdb presets >>>\nset pagination off\n' >"$T/home/.gdbinit"
cp "$T/home/.gdbinit" "$T/gdbinit.before"
run
same "an end marker before its begin leaves the file" "$T/home/.gdbinit" "$T/gdbinit.before"
has "and says why" "$out" "marker out of order or unclosed, so it was left alone"
setup
printf '# ===== debug-max (managed) =====\nset a 1\n# ===== debug-max (managed) =====\nset b 2\n# ===== end debug-max =====\ndefine keep\nend\n' >"$T/home/.gdbinit"
cp "$T/home/.gdbinit" "$T/gdbinit.before"
run
same "a debug-max block opened twice leaves the file" "$T/home/.gdbinit" "$T/gdbinit.before"

if (( failed )); then
    echo "FAIL  install: $failed of $((passed + failed)) checks"
    exit 1
fi
echo "PASS  install: $passed checks"
