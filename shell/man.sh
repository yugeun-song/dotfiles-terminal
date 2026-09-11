# Man page rendering. Sourced by both zshrc and bashrc; POSIX sh only.
#
# Every setting here degrades to a no-op rather than an error when the piece it
# talks to is absent, so the same file works on a machine with no nvim, on
# mandoc systems that have no groff, and on a plain BSD man.

# groff 1.23 and later emit SGR escapes directly, which leaves less nothing to
# color. -c asks grotty for overstrike instead, which is what LESS_TERMCAP and
# nvim's man.lua both read. GROFF_NO_SGR is the older spelling, kept for older
# groff; mandoc ignores both.
export MANROFFOPT=-c
export GROFF_NO_SGR=1

# Section search order. The stock order puts 3 before 2, so `man open` lands on
# open(3perl) and the syscall it was asking for is three pages down the -a list.
# Moving 2 ahead of 3 fixes that without disturbing 1, so `man ls` is still
# ls(1). Colon-separated: MANSECT is not spelled like man_db.conf's SECTION.
export MANSECT='1:1p:n:l:8:2:3:3p:0:0p:3type:5:4:9:6:7'

# Palette: spaceduck, matching kitty/spaceduck.conf.
LESS_TERMCAP_mb=$(printf '\033[1;38;2;227;52;0m')
LESS_TERMCAP_md=$(printf '\033[1;38;2;0;163;204m')
LESS_TERMCAP_me=$(printf '\033[0m')
LESS_TERMCAP_so=$(printf '\033[1;38;2;15;17;27;48;2;242;206;0m')
LESS_TERMCAP_se=$(printf '\033[0m')
LESS_TERMCAP_us=$(printf '\033[3;38;2;179;161;230m')
LESS_TERMCAP_ue=$(printf '\033[0m')
export LESS_TERMCAP_mb LESS_TERMCAP_md LESS_TERMCAP_me
export LESS_TERMCAP_so LESS_TERMCAP_se LESS_TERMCAP_us LESS_TERMCAP_ue

# nvim renders man with the editor's own colorscheme and keeps K on a reference
# and gO for the table of contents. Guarded: without nvim the LESS_TERMCAP path
# above is what runs, and it needs no MANPAGER at all.
if command -v nvim >/dev/null 2>&1; then
    export MANPAGER='nvim +Man!'
fi

# Long lines are the other half of an unreadable man page. nvim clamps to
# min(MANWIDTH, window width) on its own; less takes MANWIDTH literally and
# scrolls sideways on a narrow terminal, so the width is computed per call
# rather than exported once at login, where it would freeze at whatever the
# window happened to be.
man() {
    _man_w=${COLUMNS:-0}
    [ "$_man_w" -le 0 ] && _man_w=$(tput cols 2>/dev/null || echo 80)
    [ "$_man_w" -gt 100 ] && _man_w=100
    MANWIDTH=$_man_w command man "$@"
}
