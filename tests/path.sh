#!/usr/bin/env bash
# Sources shell/path.sh in bash and in zsh with PATHs a session can hand it,
# on a temporary HOME (with a space in it) that has ~/.local/bin and
# ~/.cargo/bin but no ~/.elan/bin or ~/.ghcup/bin. Each run is under timeout:
# a zsh whose PATH was typeset -U once kept the old loop going forever.

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-terminal-path.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT
H="$WORK/my home"
mkdir -p "$H/.local/bin" "$H/.cargo/bin"
USER_DIRS="$H/.local/bin:$H/.cargo/bin"

passed=0
failed=0
is() {
    if [[ $2 == "$3" ]]; then passed=$((passed + 1)); else failed=$((failed + 1)); printf 'FAIL  path: %s: got [%s], want [%s]\n' "$1" "$2" "$3"; fi
}

# $1 shell, $2 PATH to start from, $3 a command run before path.sh.
order() {
    local shell=$1 start=$2 before=${3:-:}
    env -i HOME="$H" START="$start" FILE="$REPO/shell/path.sh" \
        timeout 5 "$shell" -c "$before; PATH=\$START; . \"\$FILE\"; printf %s \"\$PATH\"" 2>&1
    local code=$?
    (( code == 124 )) && printf 'TIMEOUT'
}

for shell in bash zsh; do
    command -v "$shell" >/dev/null 2>&1 || { echo "SKIP  path: $shell is not installed"; continue; }
    is "$shell: a user directory in front moves last" "$(order "$shell" "$H/.local/bin:/usr/bin:/bin")" "/usr/bin:/bin:$USER_DIRS"
    is "$shell: one in the middle" "$(order "$shell" "/usr/bin:$H/.local/bin:/bin")" "/usr/bin:/bin:$USER_DIRS"
    is "$shell: with a trailing slash" "$(order "$shell" "/usr/bin:$H/.local/bin/:/bin")" "/usr/bin:/bin:$USER_DIRS"
    is "$shell: empty entries go" "$(order "$shell" "/usr/bin::/bin:")" "/usr/bin:/bin:$USER_DIRS"
    is "$shell: an empty PATH" "$(order "$shell" "")" "$USER_DIRS"
    is "$shell: a missing user directory is not added" "$(order "$shell" "/usr/bin:$H/.ghcup/bin")" "/usr/bin:$USER_DIRS"
    is "$shell: twice is once" "$(order "$shell" "/usr/bin" ". \"\$FILE\"")" "/usr/bin:$USER_DIRS"
done
if command -v zsh >/dev/null 2>&1; then
    is "zsh: PATH typeset -U, a user directory last" \
        "$(order zsh "/usr/bin:$H/.local/bin" "typeset -U PATH path")" "/usr/bin:$USER_DIRS"
fi

if (( failed )); then
    echo "FAIL  path: $failed of $((passed + failed)) checks"
    exit 1
fi
echo "PASS  path: $passed checks"
