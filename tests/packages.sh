#!/usr/bin/env bash
# packages.sh on stubs for pacman and sudo, with no /usr/bin on PATH: only
# the missing ones go to pacman -S --needed, never -y; nothing without a
# terminal or under --check; nothing off Arch.
set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf -- "${WORK:?}"' EXIT
failed=0 passed=0
ok() {
    if [[ "$2" == "$3" ]]; then passed=$((passed + 1))
    else failed=$((failed + 1)); printf 'FAIL  packages: %s: got [%s], want [%s]\n' "$1" "$2" "$3"; fi
}

S=$WORK/stub
mkdir -p "$WORK/bin" "$WORK/sys" "$S" "$WORK/repo"
cp "$REPO/packages.sh" "$WORK/repo/"
printf 'zsh\nkitty # a note\n\neza\n' >"$WORK/repo/packages.txt"
cat >"$WORK/bin/pacman" <<'STUB'
#!/usr/bin/env bash
case $1 in
    -T) shift; shift; m=0
        for p in "$@"; do grep -qxF -- "$p" "$STUB/missing" && { echo "$p"; m=1; }; done
        exit $(( m ? 127 : 0 )) ;;
    -Si) shift; shift; b=0
        for p in "$@"; do grep -qxF -- "$p" "$STUB/absent" 2>/dev/null && { echo "error: package '$p' was not found" >&2; b=1; }; done
        exit "$b" ;;
    *) echo "pacman $*" >>"$STUB/log" ;;
esac
STUB
cat >"$WORK/bin/sudo" <<'STUB'
#!/usr/bin/env bash
echo "sudo $*" >>"$STUB/log"
exec "$@"
STUB
chmod +x "$WORK/bin"/*
for t in bash env setsid timeout python3 dirname readlink sed sort grep cat tr; do ln -s -- "$(command -v "$t")" "$WORK/sys/$t"; done
cat >"$WORK/pty.py" <<'PTY'
import os, pty, select, sys
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])
out = b""
while select.select([fd], [], [], 20)[0]:
    try:
        data = os.read(fd, 4096)
    except OSError:
        break
    if not data:
        break
    out += data
sys.stdout.write(out.decode(errors="replace"))
sys.exit(os.waitstatus_to_exitcode(os.waitpid(pid, 0)[1]))
PTY
printf 'ID=arch\n' >"$WORK/arch"; printf 'ID=debian\n' >"$WORK/debian"
run() { env -i HOME="$WORK" PATH="$WORK/bin:$WORK/sys" STUB="$S" DOTFILES_OS_RELEASE="$WORK/$1" timeout 30 "${@:2}"; }
for t in pacman sudo; do
    [[ $(run arch bash -c "command -v $t") == "$WORK/bin/$t" ]] || { echo "FAIL  packages: $t is not its stub; no test was run"; exit 1; }
done
setup() { : >"$S/log"; rm -f "$S/absent"; printf '%s\n' "$@" >"$S/missing"; }
log() { tr '\n' ';' <"$S/log"; }

setup ""
out=$(run arch setsid -w bash "$WORK/repo/packages.sh" </dev/null 2>&1); code=$?
ok "nothing missing: silent" "$code:$out:$(log)" "0::"
setup kitty eza
out=$(run arch python3 -I "$WORK/pty.py" bash "$WORK/repo/packages.sh" 2>&1); code=$?
ok "the missing ones only, --needed" "$code:$(log)" "0:sudo pacman -S --needed -- eza kitty;pacman -S --needed -- eza kitty;"
setup kitty eza; printf 'eza\n' >"$S/absent"
out=$(run arch python3 -I "$WORK/pty.py" bash "$WORK/repo/packages.sh" 2>&1); code=$?
ok "one no repository carries is left" "$code:$(log)" "0:sudo pacman -S --needed -- kitty;pacman -S --needed -- kitty;"
setup kitty
out=$(run arch setsid -w bash "$WORK/repo/packages.sh" </dev/null 2>&1); code=$?
ok "no terminal: exit 3, nothing installed" "$code:$(log)" "3:"
out=$(run arch setsid -w bash "$WORK/repo/packages.sh" --check </dev/null 2>&1); code=$?
ok "--check installs nothing" "$code:$(log)" "0:"
out=$(run debian python3 -I "$WORK/pty.py" bash "$WORK/repo/packages.sh" 2>&1); code=$?
ok "off Arch: nothing" "$code:$(log)" "0:"

if (( failed )); then exit 1; fi
echo "PASS  packages: $passed checks"
