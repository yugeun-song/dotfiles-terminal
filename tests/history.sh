#!/usr/bin/env bash
# The history rules: zshrc's filter and bashrc's HISTIGNORE keep lines that
# carry a secret out of the history file and every other line in, and
# shell/history.sh moves the REPL histories to the runtime directory when
# there is one. Each shell runs on a temporary HOME, with HISTFILE there.
# The lines are literal, and the child shells expand their own variables.
# shellcheck disable=SC2016

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-terminal-history.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT

passed=0
failed=0
is() {
    if [[ $2 == "$3" ]]; then passed=$((passed + 1)); else failed=$((failed + 1)); printf 'FAIL  history: %s: got [%s], want [%s]\n' "$1" "$2" "$3"; fi
}

secret=(
    'export GITHUB_TOKEN=ghp_example'
    'password=hunter2 ./start'
    'curl -H "Authorization: Bearer example" https://example.org'
    'API_KEY=1 make'
)
plain=(
    'grep -i token notes.txt'
    'git log --grep password'
    'ssh git@github.com'
    'export PATH=$PATH:/opt/x'
    'echo done'
)

if command -v zsh >/dev/null 2>&1; then
    # The filter alone, as zshrc defines it: the rest of zshrc wants Oh My Zsh.
    sed -n '/^_history_keeps() {/,/^}/p' "$REPO/zsh/zshrc" >"$WORK/filter.zsh"
    for l in "${secret[@]}"; do
        is "zsh keeps out: $l" "$(zsh -f -c '. "$1"; _history_keeps "$2" && echo kept || echo out' zsh "$WORK/filter.zsh" "$l")" out
    done
    for l in "${plain[@]}" 'git clone https://user:pw@example.org/r.git'; do
        want=kept
        [[ $l == *user:pw@* ]] && want=out
        is "zsh: $l" "$(zsh -f -c '. "$1"; _history_keeps "$2" && echo kept || echo out' zsh "$WORK/filter.zsh" "$l")" "$want"
    done
else
    echo "SKIP  history: zsh is not installed"
fi

# An interactive bash with bashrc's HISTIGNORE, fed the lines, then asked to
# write its history.
grep '^HISTIGNORE=' "$REPO/bash/bashrc" >"$WORK/ignore.bash"
{
    echo ". '$WORK/ignore.bash'"
    for l in "${secret[@]}" "${plain[@]}"; do printf 'true %s\n' "$l"; done
    echo 'history -w'
} | env -i HOME="$WORK" HISTFILE="$WORK/bash_history" bash --norc -i >/dev/null 2>&1
saved=$(cat "$WORK/bash_history" 2>/dev/null)
for l in "${secret[@]}"; do
    if grep -qF -- "true $l" <<<"$saved"; then is "bash keeps out: $l" kept out; else is "bash keeps out: $l" out out; fi
done
for l in "${plain[@]}"; do
    if grep -qF -- "true $l" <<<"$saved"; then is "bash: $l" kept kept; else is "bash: $l" out kept; fi
done

run_dir=$WORK/run
mkdir -p "$run_dir"
is "REPL histories in the runtime directory" \
    "$(env -i XDG_RUNTIME_DIR="$run_dir" sh -c '. "$1"; echo "$NODE_REPL_HISTORY $PYTHON_HISTORY $LESSHISTFILE"' sh "$REPO/shell/history.sh")" \
    "$run_dir/node_repl_history $run_dir/python_history $run_dir/lesshst"
is "without one, the tools' defaults" \
    "$(env -i sh -c '. "$1"; echo "${NODE_REPL_HISTORY-unset}"' sh "$REPO/shell/history.sh")" unset

if (( failed )); then
    echo "FAIL  history: $failed of $((passed + failed)) checks"
    exit 1
fi
echo "PASS  history: $passed checks"
