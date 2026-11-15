#!/usr/bin/env bash
# Checks this repository before it is installed or committed: static checks,
# the formatters, tests/fzf.sh, which runs zshrc's fzf lookup on a fake root,
# then tests/install.sh, which runs install.sh on a temporary HOME. Nothing
# here touches the installed configuration. A missing tool skips its check.

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO" || exit 2

failed=0
fail() {
    echo "FAIL  $*"
    failed=1
}
have() { command -v "$1" >/dev/null 2>&1; }

if have shellcheck; then
    # The zsh files are not shellcheck's; shell/path.sh, which zsh sources
    # too, is checked as bash here and parsed by zsh below. SC1090 and SC1091:
    # bashrc sources files that exist only at run time.
    out=$({
        shellcheck -x install.sh bootstrap.sh bin/el node/node.sh tests/run.sh tests/install.sh tests/fzf.sh tests/path.sh tests/history.sh tests/ssh.sh packages.sh tests/packages.sh tests/repl.sh
        shellcheck -s sh shell/man.sh shell/history.sh shell/ssh.sh luajit/luajit.sh
        shellcheck -s bash shell/debug.sh
        shellcheck shell/path.sh
        shellcheck -s bash -e SC1090,SC1091 bash/bashrc
    } 2>&1)
    if [[ -z $out ]]; then
        echo "PASS  shellcheck: 20 scripts"
    else
        fail "shellcheck:"
        echo "$out" | head -40
    fi
else
    echo "SKIP  shellcheck: not installed"
fi

if have zsh; then
    bad=0
    for f in zsh/zshrc zsh/zshenv zsh/zprofile zsh/config/caps-lock.zsh zsh/p10k.zsh shell/path.sh shell/debug.sh; do
        zsh -n "$f" || bad=1
    done
    if ((bad)); then fail "zsh syntax"; else echo "PASS  zsh syntax: 7 files"; fi
else
    echo "SKIP  zsh syntax: zsh is not installed"
fi

if out=$(python3 -c 'import ast, sys
for f in sys.argv[1:]:
    ast.parse(open(f, encoding="utf-8").read(), f)' gdb/presets.py kitty/search.py kitty/scroll_mark.py 2>&1); then
    echo "PASS  python syntax: 3 files"
else
    fail "python syntax:"
    echo "$out"
fi

if have node; then
    if out=$(node --check node/repl.js 2>&1); then
        echo "PASS  node syntax"
    else
        fail "node syntax:"
        echo "$out"
    fi
else
    echo "SKIP  node syntax: node is not installed"
fi

if have ruby; then
    if out=$(ruby -c irb/irbrc 2>&1); then
        echo "PASS  ruby syntax"
    else
        fail "ruby syntax:"
        echo "$out"
    fi
else
    echo "SKIP  ruby syntax: ruby is not installed"
fi

if have elixir; then
    if out=$(elixir -e 'Code.string_to_quoted!(File.read!("iex/iex.exs"))' 2>&1); then
        echo "PASS  elixir syntax"
    else
        fail "elixir syntax:"
        echo "$out"
    fi
else
    echo "SKIP  elixir syntax: elixir is not installed"
fi

if have luajit; then
    if out=$(luajit -bl luajit/repl.lua 2>&1 >/dev/null); then
        echo "PASS  luajit syntax"
    else
        fail "luajit syntax:"
        echo "$out"
    fi
else
    echo "SKIP  luajit syntax: luajit is not installed"
fi

# The formatters: each file is kept as its formatter writes it, under the
# settings in .editorconfig, so formatting from the editor changes nothing.
# One that only Neovim's Mason installed counts as installed.
MASON=${XDG_DATA_HOME:-$HOME/.local/share}/nvim/mason/bin
formatted() {
    local name=$1 tool out
    tool=$(command -v "$2" 2>/dev/null) || tool=$MASON/$2
    if [[ ! -x $tool ]]; then
        echo "SKIP  format, $name: $2 is not installed"
        return 0
    fi
    if out=$("$tool" "${@:3}" 2>&1); then
        echo "PASS  format, $name"
    else
        fail "format, $name:"
        echo "$out" | head -40
    fi
}
formatted shell shfmt -d ./*.sh tests/*.sh shell/*.sh bin/el node/node.sh luajit/luajit.sh bash/bashrc
formatted lua stylua --check luajit/repl.lua
formatted "javascript and jsonc" oxfmt --check node/repl.js fastfetch/config.jsonc
formatted ruby rubocop irb/irbrc
formatted python ruff format --no-cache --check gdb/presets.py
formatted toml taplo fmt --check yazi/theme.toml
formatted elixir mix format --check-formatted iex/iex.exs
formatted markdown rumdl check README.md docs

tests/path.sh || failed=1
tests/history.sh || failed=1
tests/repl.sh || failed=1
tests/ssh.sh || failed=1
tests/fzf.sh || failed=1
tests/packages.sh || failed=1
tests/install.sh || failed=1

if ((failed)); then
    echo "some checks failed"
    exit 1
fi
echo "all checks passed"
