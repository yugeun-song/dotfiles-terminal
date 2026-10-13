# User bin directories go last, so a name a distribution package owns resolves
# to its copy (a `cargo install` duplicate cannot shadow it); an override in
# ~/.local/bin no longer wins. ~/.cargo/env and ~/.ghcup/env prepend, so they
# are not sourced. Each directory is moved, not added: a parent shell may have
# put it in front.
#
# Sourced by zshenv and bashrc, and by zprofile again: a login zsh can read
# /etc/profile after zshenv (Arch's /etc/zsh/zprofile does), which appended
# rustup's, the JRE's and perl's directories behind these, so the packages
# lost to them there.
#
# PATH is rebuilt entry by entry. A loop that replaced ":dir:" until it was
# gone never ended in a zsh whose PATH had typeset -U, and it missed "dir/".
# An empty entry, which means the current directory, is dropped on the way.
# shellcheck shell=bash
_path_user() {
    for _u in "$HOME/.local/bin" "$HOME/.cargo/bin" "$HOME/.elan/bin" "$HOME/.ghcup/bin"; do
        [ "${1%/}" = "$_u" ] && return 0
    done
    return 1
}
_path_new=
_path_rest=$PATH:
while [ -n "$_path_rest" ]; do
    _path_dir=${_path_rest%%:*}
    _path_rest=${_path_rest#*:}
    [ -n "$_path_dir" ] || continue
    _path_user "$_path_dir" && continue
    _path_new=${_path_new:+$_path_new:}$_path_dir
done
for _u in "$HOME/.local/bin" "$HOME/.cargo/bin" "$HOME/.elan/bin" "$HOME/.ghcup/bin"; do
    [ -d "$_u" ] && _path_new=${_path_new:+$_path_new:}$_u
done
PATH=$_path_new
unset _path_new _path_rest _path_dir _u
unset -f _path_user
export PATH
