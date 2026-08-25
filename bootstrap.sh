#!/usr/bin/env bash
# Fetch the parts of the shell setup that are not files in this repository.
#
# zshrc expects an Oh My Zsh tree at ~/.oh-my-zsh with three things cloned
# into its custom directory. None of them is an Arch package: powerlevel10k
# is not in the official repositories at all, and the two zsh-users plugins
# are packaged but Oh My Zsh loads them from its own custom path rather than
# from /usr/share. So a fresh machine has a zshrc that references a theme and
# plugins that are not there, and zsh prints an error on every prompt.
#
# Running this fixes that. It is safe to run again: an existing clone is
# updated rather than replaced, so local changes are never thrown away.
set -uo pipefail

ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
CUSTOM="$ZSH_DIR/custom"

# Privilege is asked for once, up front, rather than in the middle. The only
# step that needs it is the login shell change at the end, and a password
# prompt appearing after several git clones have already run is a prompt
# nobody is waiting at.
sudo_keepalive=
acquire_sudo() {
    [[ $EUID -eq 0 ]] && return 0
    command -v sudo >/dev/null 2>&1 || return 1
    sudo -n true 2>/dev/null && return 0
    sudo -v 2>/dev/null || return 1
    ( while true; do sudo -n true 2>/dev/null; sleep 50; done ) &
    sudo_keepalive=$!
    return 0
}
cleanup() { [[ -n "$sudo_keepalive" ]] && kill "$sudo_keepalive" 2>/dev/null; return 0; }
trap cleanup EXIT

fail=0

clone() {
    local url="$1" dest="$2" name="$3"
    if [[ -d "$dest/.git" ]]; then
        echo "updating $name"
        git -C "$dest" pull --ff-only --quiet \
            || echo "  could not fast-forward $name; leaving it as it is" >&2
        return 0
    fi
    if [[ -e "$dest" ]]; then
        echo "$dest exists and is not a git clone; leaving it alone" >&2
        fail=1
        return 0
    fi
    echo "cloning $name"
    # --depth 1 because none of these are read for their history, and
    # powerlevel10k in particular is large enough for the difference to show.
    if ! git clone --depth 1 --quiet "$url" "$dest"; then
        echo "  failed to clone $name from $url" >&2
        fail=1
    fi
}

command -v git >/dev/null 2>&1 || { echo "git is not installed" >&2; exit 1; }

clone https://github.com/ohmyzsh/ohmyzsh.git \
      "$ZSH_DIR" "oh-my-zsh"
clone https://github.com/romkatv/powerlevel10k.git \
      "$CUSTOM/themes/powerlevel10k" "powerlevel10k (the prompt)"
clone https://github.com/zsh-users/zsh-autosuggestions \
      "$CUSTOM/plugins/zsh-autosuggestions" "zsh-autosuggestions"
clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
      "$CUSTOM/plugins/zsh-syntax-highlighting" "zsh-syntax-highlighting"

echo

# A fresh Arch install gives the account bash. Everything in zshrc, including
# the history size that is the whole reason the file is worth keeping, only
# applies once zsh is the login shell.
ZSH_BIN="$(command -v zsh || true)"
CURRENT_SHELL="$(getent passwd "$USER" | cut -d: -f7)"

if [[ -z "$ZSH_BIN" ]]; then
    echo "zsh is not installed, so the login shell was left as $CURRENT_SHELL" >&2
    fail=1
elif [[ "$CURRENT_SHELL" == "$ZSH_BIN" ]]; then
    echo "login shell: already $ZSH_BIN"
elif ! grep -qxF "$ZSH_BIN" /etc/shells 2>/dev/null; then
    # chsh refuses a shell that is not listed, and the message it prints does
    # not say why.
    echo "$ZSH_BIN is missing from /etc/shells, so the login shell was not changed" >&2
    echo "  echo $ZSH_BIN | sudo tee -a /etc/shells" >&2
    fail=1
elif acquire_sudo && sudo chsh -s "$ZSH_BIN" "$USER"; then
    echo "login shell: $CURRENT_SHELL -> $ZSH_BIN (takes effect at the next login)"
else
    echo "could not change the login shell; it is still $CURRENT_SHELL" >&2
    echo "  sudo chsh -s $ZSH_BIN $USER" >&2
    fail=1
fi

echo
if (( fail )); then
    echo "finished with problems; see the messages above" >&2
    exit 1
fi
echo "shell environment ready"
