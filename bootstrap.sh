#!/usr/bin/env bash
# Fetch what zshrc needs but this repository does not carry: Oh My Zsh plus
# powerlevel10k and two plugins in its custom dir (Oh My Zsh does not load the
# Arch-packaged plugins from /usr/share). Also clones the nvim config and sets
# the login shell. Re-runnable: existing clones are fast-forwarded, not replaced.
set -uo pipefail

ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
CUSTOM="$ZSH_DIR/custom"

# Only chsh needs root; the keepalive stops sudo from timing out mid-run.
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

# The identity is set by hand, never by a script; only warn here.
if [[ -z "$(git config --global user.name)" || -z "$(git config --global user.email)" ]]; then
    echo "git has no identity yet; set it before committing:" >&2
    echo "  git config --global user.name  'Your Name'" >&2
    echo "  git config --global user.email 'you@example.com'" >&2
fi

echo

# nvim config is its own repository at ~/nvim-config, linked (not copied) as
# ~/.config/nvim so edits land in the checkout. The owner comes from the gh
# login unless NVIM_CONFIG_URL is set, so no account name is hardcoded.
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

# A fresh account gets bash; zshrc only applies once zsh is the login shell.
ZSH_BIN="$(command -v zsh || true)"
CURRENT_SHELL="$(getent passwd "$USER" | cut -d: -f7)"

if [[ -z "$ZSH_BIN" ]]; then
    echo "zsh is not installed, so the login shell was left as $CURRENT_SHELL" >&2
    fail=1
elif [[ "$CURRENT_SHELL" == "$ZSH_BIN" ]]; then
    echo "login shell: already $ZSH_BIN"
elif ! grep -qxF "$ZSH_BIN" /etc/shells 2>/dev/null; then
    # chsh refuses an unlisted shell without saying why.
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
