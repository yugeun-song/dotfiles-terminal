# dotfiles-terminal

Shell, prompt, terminal and debugger configuration: zsh, bash, kitty, tmux,
gdb, git, and number-base helpers for the node and IEx REPLs. The desktop
(Hyprland, the bar, the session) lives in
[dotfiles-desktop](https://github.com/yugeun-song/dotfiles-desktop); no file
is installed by both.

## Premise

A recognised distribution with GNU coreutils, zsh with Oh My Zsh,
powerlevel10k and its two plugins, kitty, nvim and git. Arch is tested. Its
derivatives and Debian/Ubuntu, Fedora/RHEL, openSUSE, Void, Gentoo and
Alpine (derivatives known by `ID_LIKE`) are recognised but untested: a
missing program is named with that package manager's command. `install.sh`
checks the premise first and writes nothing when it is not met, an
unrecognised distribution included. Within it, the files adapt: fzf's two
scripts come from the distribution's files, or from `fzf --zsh` where those
are incomplete; pwndbg from `~/pwndbg` or `/usr/share/pwndbg`. Optional
tools (eza, fzf, tmux, wl-copy, gdb, pwndbg, node, IEx, fastfetch, gh, the
two fonts) are listed by the closing doctor line when missing; each feature
does without its tool.

## Layout

```
zsh/          zshrc, zshenv, zprofile, p10k.zsh (the prompt), config/caps-lock.zsh
bash/         bashrc, for rescue shells and containers
shell/        path.sh (PATH order) and man.sh (man page settings), for both shells
bin/          el: eza's long listing as a script sudo can run
kitty/        kitty.conf, the spaceduck palette, the scrollback search kitten
tmux/ npm/ fastfetch/ git/ gdb/ node/ iex/
install.sh    places the files (below)
bootstrap.sh  clones what is not a file here, sets the login shell
tests/        run.sh: static checks, the fzf lookup, the installer suite
```

## Install

```sh
./bootstrap.sh          # once, first: Oh My Zsh and the rest, the nvim config, zsh as login shell
./install.sh            # every time a file here changes
./install.sh --check    # what is behind or conflicting; writes nothing
./install.sh --force    # overwrite conflicts without asking
```

Each step prints a tree of what it wrote (✓) or found in conflict (✗), in
colour on a terminal unless `NO_COLOR` is set. `bootstrap.sh` sets the login
shell with `chsh`, or `usermod` where `chsh` is missing (Fedora and RHEL ship
it in `util-linux-user`).

Files are copied, never linked. **Mirrored** files are overwritten on every
run: the shell files into `~`, `bin/el` into `~/.local/bin`, the rest under
`$XDG_CONFIG_HOME` (default `~/.config`). A mirrored directory loses the files
the repository dropped and keeps the ones it never had (kitty's
`current-theme.conf`, say). `zsh/p10k.zsh` is **seeded**: copied once, since
`p10k configure` rewrites it; copy a change back here to keep it. The init
file gdb reads gets a **managed block** at its top (pwndbg's location and
`presets.py`), with a `.bak-STAMP` of the previous file. `git/gitconfig` is
**included** from the global git config by its absolute path, so a moved
checkout needs `install.sh` again.

A target holding content this repository did not install (another tool's
edit, or a file that was there first) is a **conflict**: the diff is shown,
line-numbered, and the answer decides: `y` overwrites, `n` keeps the file and
stops there, `a` overwrites it and every later conflict. Without a terminal
to ask on, the install stops; `--force` answers `a` up front. Ours means: the
same as the repository, any version committed here, or what the last run
recorded in `~/.local/state/dotfiles-terminal/installed`.

The install also stops, before writing anything, when the premise is not met,
when `ZDOTDIR` would make zsh ignore `~/.zshrc`, when `XDG_CONFIG_HOME` differs
between this shell and the systemd user manager, or when
`KITTY_CONFIG_DIRECTORY` points elsewhere. Exit status: 0 everything applied
and current, 1 stopped or a step left undone (named in the summary), 2 usage.

`sudo el` needs a root-owned copy in sudo's `secure_path`; the script never
runs sudo, so it prints the command, and exits 1, while that copy is missing
or stale:

```sh
sudo install -m 0755 -o root -g root bin/el /usr/local/bin/el
```

## Shell notes

- `shell/path.sh` (from `zshenv`, `bashrc`, and `zprofile` again after a
  login shell's `/etc/profile`) puts `~/.local/bin`, `~/.cargo/bin`,
  `~/.elan/bin` and `~/.ghcup/bin` last in PATH, so the distribution's
  binaries win over user-installed duplicates; `~/.cargo/env` and
  `~/.ghcup/env` prepend and are not sourced.
- Both shells source the `~/.config/profile.d/*.sh` files this user owns and
  others cannot write; `node/node.sh` goes there.
- History holds 500000 entries in both shells; bash appends, so concurrent
  sessions do not overwrite each other.
- `el` is `eza --icons -al`. Root runs only root-owned files: it reads nothing
  from the invoking user's home, except `~/.dircolors` when that is a regular
  file owned by the user running it. An eza that fails to start is passed
  over for `/usr/local/bin/eza` or `/usr/bin/eza`, then `ls -lAh`.
- Vi-mode yanks in zsh also reach the first clipboard that works: wl-copy,
  xclip, xsel, pbcopy, tmux, or OSC 52 on a terminal known to accept it.
- `caps-lock.zsh` adds a CAPS LOCK segment to the right prompt, polling
  `/sys/class/leds/*::capslock/brightness` every 200 ms
  (`CAPSLOCK_LED_PATHS`, `CAPSLOCK_POLL_CS`); without LED nodes or p10k it
  stays off.
- kitty's scrollback pager (ctrl+shift+h, ctrl+shift+g) is nvim on a file in
  nvim's private temporary directory, removed when it exits.

## Git

`git/gitconfig` carries no identity; set `user.name` and `user.email` by hand
in `~/.gitconfig`. GitHub credentials come only from `gh auth git-credential`.

## gdb

`presets.py` decides inside gdb what it loads, so the terminal, kbuildlab,
nvim and VS Code get the same rule:

- **stock**: pwndbg, or plain gdb with one line saying why when its
  `gdbinit.py` or virtualenv is missing (pwndbg's own loader would end gdb).
- **linux_kernel**: stock plus `debug-max.gdb` (limits lifted, history kept,
  `maxfork`, `logon`, `syscatch`), when `GDBTOOLS_AUTO` is set or a Linux
  Kernel image or module is loaded (`.gnu.linkonce.this_module`, or
  `.init.text` with `__ksymtab` or `__param`).
- `GDB_PRESET=stock|linux_kernel` overrides; `gdb -nx` reads no init file.

pwndbg sets `auto-load safe-path` to `/`, which would run any `.gdbinit` in
the working directory and any `*-gdb.py` beside a loaded file; `presets.py`
puts back the value in force before it, and the kbuildlab block after it adds
the kernel tree, so `lx-*` still loads there. pwndbg is sourced before anything
imports gdb's Python package, so an Arch cross gdb whose package lags
gdb-common still starts it.

## node and IEx

`hex`, `oct` and `bin` print a number in that base and return it, so they nest
in arithmetic; a single character stands for its code point (`hex("A")` is
`0x41`). In node they exist only in an interactive REPL, never under `-e`,
`-p`, a script or a worker. A project's own `.iex.exs` replaces this one
unless it calls `import_file("~/.iex.exs")`.

## Checks

```sh
tests/run.sh    # shellcheck, zsh/python/node syntax, the fzf lookup, then install.sh on a temporary HOME
```

The installer suite never touches the real HOME: each case runs on its own
temporary home and a copy of this checkout, with stand-ins for systemctl,
gdb and fc-list and an os-release per recognised distribution, and answers
conflicts through a pty. `tests/fzf.sh` runs zshrc's fzf block on a fake
root laid out as each distribution does.

Third-party files (the p10k configuration, the spaceduck palette, the search
kitten) keep their own licenses; see `THIRD-PARTY-NOTICES`.
