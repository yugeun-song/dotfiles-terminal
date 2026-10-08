# dotfiles-terminal

Terminal-side configuration: shell, prompt, terminal emulator, multiplexer,
debugger. Machine independent; every path is relative to `$HOME`, apart from
the root-owned copy of `el` that `sudo el` needs.

## Layout

```
zsh/          zshrc, zshenv, zprofile, p10k.zsh (prompt), config/caps-lock.zsh
bash/         bashrc, for shells that are not zsh
shell/        man.sh, man page settings sourced by both shells
bin/          el, eza's long listing as a script that sudo can run
git/          shared git settings, no identity
gdb/          presets.py and debug-max.gdb: stock pwndbg or the Linux Kernel preset
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
  npmrc into `~`; `bin/el` into `~/.local/bin`; `zsh/config` into
  `~/.config/zsh`; `shell`, `kitty`, `fastfetch` and `tmux/tmux.conf` into
  `$XDG_CONFIG_HOME`; the two files in `gdb/` into `$XDG_CONFIG_HOME/gdb`.
  Mirrored directories lose files the repository no longer has. A symlink
  left by an older install is replaced. Edit here, then re-run.
- **Seeded** (copied once): `zsh/p10k.zsh` to `~/.p10k.zsh`, because
  `p10k configure` rewrites it and would write through a link into the
  repository. A diverged copy is reported and left alone; copy it back here to
  keep the change.
- **Included**: `git/gitconfig` is added to `include.path` in `~/.gitconfig`
  as an absolute path into this checkout. Moving the checkout breaks the
  include; re-run `install.sh` after a move.
- **Managed block**: the init file gdb reads (normally `~/.gdbinit`) starts
  with a block that records where pwndbg's `gdbinit.py` is and sources
  `presets.py`. A `source .../pwndbg/gdbinit.py` line elsewhere in the file,
  which pwndbg's `setup.sh` appends, is moved into the block, and the old
  inline debug-max block is dropped. Other blocks are left alone; the previous
  file is kept as `.bak-STAMP` whenever something changes.

`bootstrap.sh` clones Oh My Zsh with powerlevel10k, zsh-autosuggestions and
zsh-syntax-highlighting into its custom directory (Oh My Zsh does not load the
Arch-packaged plugins from `/usr/share`), clones the nvim configuration to
`~/nvim-config` and links it as `~/.config/nvim` (from `NVIM_CONFIG_URL`, or
the `gh` login's `nvim-config`), and makes zsh the login shell. Existing clones
are fast-forwarded, never replaced.

## Shell notes

- `zshenv` and `bashrc` append `~/.local/bin`, `~/.cargo/bin` and `~/.elan/bin`
  to PATH, so pacman-owned binaries always win over user-installed duplicates.
  `~/.cargo/env` is not sourced; it only prepends.
- Both shells source every `~/.config/profile.d/*.sh` owned by this user and
  not writable by group or others. Tools put their environment there
  (dotfiles-desktop installs `node.sh`).
- History is 500000 entries in both shells; bash also gets `histappend` so
  concurrent sessions do not overwrite each other.
- `el` is `eza --icons -al` as a script, `bin/el`, found through PATH. sudo
  looks for commands only in its `secure_path`, so `sudo el` needs a
  root-owned copy there. Install it once, and again after `bin/el` changes;
  `install.sh` prints the command while that copy is missing or stale:

  ```sh
  sudo install -m 0755 -o root -g root bin/el /usr/local/bin/el
  ```

  Every sudo form then works (`sudo -u USER el`, `el` in a `sudo -i` shell),
  and root runs only root-owned files: the script never reads or runs
  anything from the invoking user's home. When sudo drops `LS_COLORS`, the
  script rebuilds it with `dircolors`, as Oh My Zsh does; `~/.dircolors` is
  read only if it is a regular file owned by the user running `el`. An eza
  that fails to start is passed over for `/usr/local/bin/eza` or
  `/usr/bin/eza`; with none left it runs `ls -lAh` and says why on stderr.
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

## gdb

`presets.py` decides inside gdb what it loads, so the terminal, kbuildlab,
nvim and VS Code all get the same rule.

- **stock**: pwndbg. When pwndbg's `gdbinit.py` or its virtualenv is missing,
  plain gdb and one line saying why; pwndbg's own loader would end gdb with
  `os._exit` instead.
- **linux_kernel**: stock plus `debug-max.gdb` (print limits lifted, history
  kept, `maxfork`, `logon`, `syscatch`). Applied when `GDBTOOLS_AUTO` is set,
  as kbuildlab, the nvim kernel adapter and the VS Code wrapper do, or when a
  Linux Kernel image or module is loaded: an ELF with
  `.gnu.linkonce.this_module`, or with `.init.text` and `__ksymtab` or
  `__param`.
- `GDB_PRESET=stock` or `GDB_PRESET=linux_kernel` overrides the choice;
  `gdb -nx` reads no init file at all.

pwndbg sets `auto-load safe-path` to `/`, which runs any `.gdbinit` in the
working directory and any `*-gdb.py` beside a loaded file, such as one
shipped next to an untrusted binary. `presets.py` puts back the value in force
before pwndbg loaded, gdb's default here; the kbuildlab block below it then
adds the kernel research tree, so `lx-*` still loads there. Anywhere else gdb
declines and says how to allow the path.

pwndbg is sourced before anything imports gdb's Python package, so an Arch
cross gdb whose package lags gdb-common still starts pwndbg.

## Requirements

- kitty expects CaskaydiaCove Nerd Font Mono and Pretendard (Hangul, via
  `symbol_map`). Without them the alignment of mixed lines drifts.
- tmux copy-mode yanks through `wl-copy`.
- There is one prompt, powerlevel10k; the Caps Lock segment uses its API.
- `el` expects eza and falls back to `ls` without it.
- The gdb presets load pwndbg from wherever its `setup.sh` registered it,
  `~/pwndbg` or `/usr/share/pwndbg`; without pwndbg, gdb runs plain.
