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
# shellcheck shell=bash
for _userbin in "$HOME/.local/bin" "$HOME/.cargo/bin" "$HOME/.elan/bin" "$HOME/.ghcup/bin"; do
    while :; do
        case ":$PATH:" in
            *":$_userbin:"*)
                PATH=":$PATH:"
                PATH="${PATH//:"$_userbin":/:}"
                PATH="${PATH#:}"
                PATH="${PATH%:}"
                ;;
            *) break ;;
        esac
    done
    [ -d "$_userbin" ] && PATH="${PATH:+$PATH:}$_userbin"
done
unset _userbin
export PATH
