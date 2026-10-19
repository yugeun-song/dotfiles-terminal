ssh() {
    if [ "${TERM:-}" = xterm-kitty ] &&
        [ -n "${KITTY_WINDOW_ID:-}" ] && [ -n "${KITTY_PID:-}" ] &&
        [ -z "${SSH_CONNECTION:-}" ] && [ -z "${SSH_TTY:-}" ] &&
        [ -t 0 ] && [ -t 1 ] &&
        command -v kitten >/dev/null 2>&1; then
        kitten ssh "$@"
    else
        command ssh "$@"
    fi
}
