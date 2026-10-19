#!/usr/bin/env bash

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ ! -f $REPO/shell/ssh.sh ]]; then
    echo "FAIL  ssh: shell/ssh.sh is missing"
    exit 1
fi
WORK=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-terminal-ssh.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT

passed=0
failed=0
pass() { passed=$((passed + 1)); }
fail() { failed=$((failed + 1)); printf 'FAIL  ssh: %s\n' "$*"; }

if ! SCRIPT=$(command -v script); then
    echo "SKIP  ssh on a terminal: script is not installed"
elif ! env -i "$SCRIPT" -qec 'test -t 0 && test -t 1' /dev/null </dev/null >/dev/null 2>&1; then
    echo "SKIP  ssh on a terminal: script cannot open a pty here"
    SCRIPT=
fi

stubs=$WORK/stubs
nokitten=$WORK/nokitten
mkdir -p "$stubs" "$nokitten"
cat >"$stubs/ssh" <<'STUB'
#!/bin/sh
{ printf '%s' "${0##*/}"; printf ' [%s]' "$@"; echo; } >>"$CALLS"
exit "$STATUS"
STUB
chmod +x "$stubs/ssh"
cp "$stubs/ssh" "$stubs/kitten"
cp "$stubs/ssh" "$nokitten/ssh"

IFS= read -r -d '' driver <<'DRIVER'
if [ -n "${ZSH_VERSION-}" ]; then
    list_vars() { print -rl -- ${(k)parameters}; }
    list_funcs() { print -rl -- ${(k)functions}; }
else
    list_vars() { compgen -v; }
    list_funcs() { compgen -A function; }
fi
list_funcs >"$OUT/funcs.before"
list_vars >"$OUT/vars.before"
. "$FILE"
set -- -p 2222 host 'a b' '' '  c  ' ''
case $IO in
    stdin) ssh "$@" </dev/null ;;
    stdout) ssh "$@" >/dev/null ;;
    *) ssh "$@" ;;
esac
echo $? >"$OUT/status"
list_vars >"$OUT/vars.after"
list_funcs >"$OUT/funcs.after"
DRIVER

ARGS='[-p] [2222] [host] [a b] [] [  c  ] []'
KITTEN="kitten [ssh] $ARGS"
PLAIN="ssh $ARGS"

added() { grep -vxF -f "$1.before" -- "$1.after" 2>/dev/null | LC_ALL=C sort | paste -sd ' '; }

check() {
    local name=$1 io=$2 bin=$3 want="$4|exit 3|new variables []|new functions [ssh]" dir out got
    shift 4
    local -a run=("$shell" -c "$driver")
    if [[ $io != none ]]; then run=("$SCRIPT" -qec "$driver" /dev/null); fi
    dir=$(mktemp -d "$WORK/case.XXXXXX")
    out=$(env -i HOME="$dir" SHELL="$shell" PATH="$bin" FILE="$REPO/shell/ssh.sh" OUT="$dir" CALLS="$dir/calls" \
        STATUS=3 IO="$io" "$@" "${run[@]}" </dev/null 2>&1)
    got="$(cat -- "$dir/calls" 2>/dev/null)|exit $(cat -- "$dir/status" 2>/dev/null)"
    got+="|new variables [$(added "$dir/vars")]|new functions [$(added "$dir/funcs")]"
    if [[ $got == "$want" ]]; then
        pass
    else
        fail "$sh: $name: got [$got], want [$want]"
        if [[ -n $out ]]; then printf '%s\n' "${out//$'\r'/}" | sed 's/^/      /'; fi
    fi
}

for sh in bash zsh; do
    shell=$(command -v "$sh") || { echo "SKIP  ssh: $sh is not installed"; continue; }
    check "no terminal at all" none "$stubs" "$PLAIN" TERM=xterm-kitty KITTY_WINDOW_ID=1 KITTY_PID=4242
    [[ -n $SCRIPT ]] || continue
    check "every condition holds" tty "$stubs" "$KITTEN" TERM=xterm-kitty KITTY_WINDOW_ID=1 KITTY_PID=4242
    check "SSH_CONNECTION and SSH_TTY set but empty" tty "$stubs" "$KITTEN" \
        TERM=xterm-kitty KITTY_WINDOW_ID=1 KITTY_PID=4242 SSH_CONNECTION= SSH_TTY=
    check "stdin is not a terminal" stdin "$stubs" "$PLAIN" TERM=xterm-kitty KITTY_WINDOW_ID=1 KITTY_PID=4242
    check "stdout is not a terminal" stdout "$stubs" "$PLAIN" TERM=xterm-kitty KITTY_WINDOW_ID=1 KITTY_PID=4242
    check "TERM is tmux-256color" tty "$stubs" "$PLAIN" TERM=tmux-256color KITTY_WINDOW_ID=1 KITTY_PID=4242
    check "TERM is unset" tty "$stubs" "$PLAIN" KITTY_WINDOW_ID=1 KITTY_PID=4242
    check "KITTY_WINDOW_ID is unset" tty "$stubs" "$PLAIN" TERM=xterm-kitty KITTY_PID=4242
    check "KITTY_WINDOW_ID is empty" tty "$stubs" "$PLAIN" TERM=xterm-kitty KITTY_WINDOW_ID= KITTY_PID=4242
    check "KITTY_PID is unset" tty "$stubs" "$PLAIN" TERM=xterm-kitty KITTY_WINDOW_ID=1
    check "KITTY_PID is empty" tty "$stubs" "$PLAIN" TERM=xterm-kitty KITTY_WINDOW_ID=1 KITTY_PID=
    check "SSH_CONNECTION is set" tty "$stubs" "$PLAIN" \
        TERM=xterm-kitty KITTY_WINDOW_ID=1 KITTY_PID=4242 SSH_CONNECTION='192.0.2.1 50022 192.0.2.2 22'
    check "SSH_TTY is set" tty "$stubs" "$PLAIN" TERM=xterm-kitty KITTY_WINDOW_ID=1 KITTY_PID=4242 SSH_TTY=/dev/pts/7
    check "kitten is not on PATH" tty "$nokitten" "$PLAIN" TERM=xterm-kitty KITTY_WINDOW_ID=1 KITTY_PID=4242
done

if (( failed )); then
    echo "FAIL  ssh: $failed of $((passed + failed)) checks"
    exit 1
fi
echo "PASS  ssh: $passed checks"
