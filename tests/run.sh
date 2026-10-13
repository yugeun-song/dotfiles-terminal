#!/usr/bin/env bash
# Checks this repository before it is installed or committed: static checks,
# then tests/install.sh, which runs install.sh on a temporary HOME. Nothing
# here touches the installed configuration. A missing tool skips its check.

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO" || exit 2

failed=0
fail() { echo "FAIL  $*"; failed=1; }
have() { command -v "$1" >/dev/null 2>&1; }

if have shellcheck; then
    # The zsh files are not shellcheck's; shell/path.sh, which zsh sources
    # too, is checked as bash here and parsed by zsh below. SC1090 and SC1091:
    # bashrc sources files that exist only at run time.
    out=$( {
        shellcheck -x install.sh bootstrap.sh bin/el node/node.sh tests/run.sh tests/install.sh
        shellcheck -s sh shell/man.sh
        shellcheck shell/path.sh
        shellcheck -s bash -e SC1090,SC1091 bash/bashrc
    } 2>&1 )
    if [[ -z $out ]]; then echo "PASS  shellcheck: 9 scripts"; else fail "shellcheck:"; echo "$out" | head -40; fi
else
    echo "SKIP  shellcheck: not installed"
fi

if have zsh; then
    bad=0
    for f in zsh/zshrc zsh/zshenv zsh/zprofile zsh/config/caps-lock.zsh zsh/p10k.zsh shell/path.sh; do
        zsh -n "$f" || bad=1
    done
    if (( bad )); then fail "zsh syntax"; else echo "PASS  zsh syntax: 6 files"; fi
else
    echo "SKIP  zsh syntax: zsh is not installed"
fi

if out=$(python3 -c 'import ast, sys
for f in sys.argv[1:]:
    ast.parse(open(f, encoding="utf-8").read(), f)' gdb/presets.py kitty/search.py kitty/scroll_mark.py 2>&1); then
    echo "PASS  python syntax: 3 files"
else
    fail "python syntax:"; echo "$out"
fi

if have node; then
    if out=$(node --check node/repl.js 2>&1); then echo "PASS  node syntax"; else fail "node syntax:"; echo "$out"; fi
else
    echo "SKIP  node syntax: node is not installed"
fi

tests/install.sh || failed=1

if (( failed )); then
    echo "some checks failed"
    exit 1
fi
echo "all checks passed"
