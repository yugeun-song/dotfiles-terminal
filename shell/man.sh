# Man page rendering. Sourced by zshrc and bashrc; POSIX sh only. Each setting
# is a no-op without its target (no nvim, mandoc instead of groff, BSD man).

# Make grotty emit overstrike, not SGR, so LESS_TERMCAP and nvim's man.lua can
# color it. GROFF_NO_SGR is the older-groff spelling; mandoc ignores both.
export MANROFFOPT=-c
export GROFF_NO_SGR=1

# 2 before 3, so `man open` finds open(2) rather than open(3perl). Colons, not
# the space-separated SECTION syntax of man_db.conf.
export MANSECT='1:1p:n:l:8:2:3:3p:0:0p:3type:5:4:9:6:7'

# spaceduck, matching kitty/spaceduck.conf.
LESS_TERMCAP_mb=$(printf '\033[1;38;2;227;52;0m')
LESS_TERMCAP_md=$(printf '\033[1;38;2;0;163;204m')
LESS_TERMCAP_me=$(printf '\033[0m')
LESS_TERMCAP_so=$(printf '\033[1;38;2;15;17;27;48;2;242;206;0m')
LESS_TERMCAP_se=$(printf '\033[0m')
LESS_TERMCAP_us=$(printf '\033[3;38;2;179;161;230m')
LESS_TERMCAP_ue=$(printf '\033[0m')
export LESS_TERMCAP_mb LESS_TERMCAP_md LESS_TERMCAP_me
export LESS_TERMCAP_so LESS_TERMCAP_se LESS_TERMCAP_us LESS_TERMCAP_ue

# Without nvim, less with the LESS_TERMCAP colors above is used.
if command -v nvim >/dev/null 2>&1; then
    export MANPAGER='nvim +Man!'
fi

# Width capped at 100, computed per call: less takes MANWIDTH literally, so a
# value exported at login would go stale when the window is resized.
_man_width() {
    w=${COLUMNS:-0}
    [ "$w" -le 0 ] && w=$(tput cols 2>/dev/null || echo 80)
    [ "$w" -gt 100 ] && w=100
    echo "$w"
}

man() {
    MANWIDTH=$(_man_width) command man "$@"
}
