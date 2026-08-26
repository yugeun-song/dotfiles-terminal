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

# git/gitconfig carries no name or email, and nothing here fills them in
# either: an identity set by a script is an identity nobody checked, and the
# first wrong commit under it is silent. Set them by hand once:
#
#   git config --global user.name  'Your Name'
#   git config --global user.email 'you@example.com'
if [[ -z "$(git config --global user.name)" || -z "$(git config --global user.email)" ]]; then
    echo "git has no identity yet; set it before committing:" >&2
    echo "  git config --global user.name  'Your Name'" >&2
    echo "  git config --global user.email 'you@example.com'" >&2
fi

echo

# The editor configuration is a repository of its own rather than a directory
# here, so this is the only place that records where it comes from. The owner
# is taken from the authenticated account for the same reason as above.
# Beside the other configuration repositories rather than under ~/workspace,
# which is for source projects. This one is a configuration collection like the
# two dotfiles trees, and it is the one thing here that stays a symlink:
# ~/.config/nvim IS the repository, and editing it is the point.
NVIM_SRC="${NVIM_CONFIG_DIR:-$HOME/nvim-config}"
NVIM_LINK="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
if [[ -d "$NVIM_SRC/.git" ]]; then
    echo "updating nvim configuration"
    git -C "$NVIM_SRC" pull --ff-only --quiet \
        || echo "  could not fast-forward the nvim configuration; leaving it" >&2
elif [[ -e "$NVIM_SRC" || -e "$NVIM_LINK" ]]; then
    echo "an nvim configuration is already in place; leaving it alone"
elif [[ -n "${NVIM_CONFIG_URL:-}" ]] || { command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; }; then
    url="${NVIM_CONFIG_URL:-https://github.com/$(gh api user --jq '.login')/nvim-config.git}"
    echo "cloning nvim configuration from $url"
    mkdir -p "$(dirname "$NVIM_SRC")"
    git clone --quiet "$url" "$NVIM_SRC" || { echo "  clone failed" >&2; fail=1; }
else
    echo "no nvim configuration and no way to find one; set NVIM_CONFIG_URL" >&2
fi
if [[ -d "$NVIM_SRC" && ! -e "$NVIM_LINK" ]]; then
    mkdir -p "$(dirname "$NVIM_LINK")"
    ln -s "$NVIM_SRC" "$NVIM_LINK" && echo "linked $NVIM_LINK -> $NVIM_SRC"
fi

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
