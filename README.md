# dotfiles-terminal

Terminal-side configuration: shell, prompt, terminal emulator, multiplexer.
Machine independent; every path is relative to `$HOME`.

## Layout

```
zsh/          zshrc, zshenv, zprofile, p10k.zsh (prompt), config/caps-lock.zsh
bash/         bashrc, for shells that are not zsh
shell/        man.sh, man page settings sourced by both shells
git/          shared git settings, no identity
kitty/        kitty.conf, spaceduck palette, search kitten (search.py + scroll_mark.py)
tmux/         tmux.conf
npm/          npmrc
fastfetch/    config.jsonc
install.sh    places the files (below)
bootstrap.sh  clones what is not a file here, sets the login shell
```

## Install

```sh
./install.sh      # every time a file here changes
./bootstrap.sh    # once on a fresh machine; reaches the network, runs sudo chsh
```

`install.sh` copies; it creates no symlinks.

- **Mirrored** (overwritten on every run): zshrc, zshenv, zprofile, bashrc,
  npmrc into `~`; `zsh/config` into `~/.config/zsh`; `shell`, `kitty`,
  `fastfetch` and `tmux/tmux.conf` into `$XDG_CONFIG_HOME`. Mirrored
  directories lose files the repository no longer has. A symlink left by an
  older install is replaced. Edit here, then re-run.
- **Seeded** (copied once): `zsh/p10k.zsh` to `~/.p10k.zsh`, because
  `p10k configure` rewrites it and would write through a link into the
  repository. A diverged copy is reported and left alone; copy it back here to
  keep the change.
- **Included**: `git/gitconfig` is added to `include.path` in `~/.gitconfig`
  as an absolute path into this checkout. Moving the checkout breaks the
  include; re-run `install.sh` after a move.

`bootstrap.sh` clones Oh My Zsh with powerlevel10k, zsh-autosuggestions and
zsh-syntax-highlighting into its custom directory (Oh My Zsh does not load the
Arch-packaged plugins from `/usr/share`), clones the nvim configuration to
`~/nvim-config` and links it as `~/.config/nvim` (from `NVIM_CONFIG_URL`, or
the `gh` login's `nvim-config`), and makes zsh the login shell. Existing clones
are fast-forwarded, never replaced.

## Shell notes

- `zshenv` appends `~/.local/bin`, `~/.cargo/bin` and `~/.elan/bin` to PATH,
  so pacman-owned binaries always win over user-installed duplicates. `bashrc`
  still prepends `~/.local/bin` and sources `~/.cargo/env`.
- Both shells source every `~/.config/profile.d/*.sh` owned by this user and
  not writable by group or others. Tools put their environment there
  (dotfiles-desktop installs `node.sh`).
- History is 500000 entries in both shells; bash also gets `histappend` so
  concurrent sessions do not overwrite each other.
- Vi-mode yanks (`y`, `yy`, `Y`) in zsh also copy to the first working
  clipboard: wl-copy, xclip, xsel, pbcopy, tmux, or OSC 52 on a terminal known
  to accept it.
- `zsh/config/caps-lock.zsh` adds a right-prompt CAPS LOCK segment. A
  background loop polls `/sys/class/leds/*::capslock/brightness` every 200 ms
  while the shell lives (`CAPSLOCK_LED_PATHS`, `CAPSLOCK_POLL_CS` override).
  It disables itself without LED nodes or without p10k.

## Git

`git/gitconfig` has no `user.name` or `user.email`, and nothing sets them.
Set them once, by hand:

```sh
git config --global user.name  'Your Name'
git config --global user.email 'you@example.com'
```

There is no plaintext `credential.helper`; GitHub credentials come from
`gh auth git-credential`.

## Requirements

- kitty expects CaskaydiaCove Nerd Font Mono and Pretendard (Hangul, via
  `symbol_map`). Without them the alignment of mixed lines drifts.
- tmux copy-mode yanks through `wl-copy`.
- There is one prompt, powerlevel10k; the Caps Lock segment uses its API.
