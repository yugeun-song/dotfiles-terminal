# dotfiles-terminal

Shell, prompt, terminal and debugger configuration: zsh, bash, kitty, tmux,
gdb, git, and number-base helpers for the node, IEx, irb and LuaJIT REPLs.
The desktop (Hyprland, the bar, the session) lives in
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
tools (eza, fzf, tmux, wl-copy, gdb, pwndbg, node, IEx, irb, LuaJIT, fastfetch,
yazi, gh, the two fonts) are listed by the closing doctor line when missing; each
feature does without its tool.

## Layout

```text
zsh/          zshrc, zshenv, zprofile, p10k.zsh (the prompt), config/caps-lock.zsh
bash/         bashrc, for rescue shells and containers
shell/        path.sh (PATH order), man.sh, ssh.sh (ssh in kitty), for both shells
bin/          el: eza's long listing as a script sudo can run
kitty/        kitty.conf, ssh.conf, the spaceduck palette, the search kitten
tmux/ npm/ fastfetch/ yazi/ git/ gdb/ node/ iex/ irb/ luajit/
docs/         repl/: every case of the REPL helpers, replayed by tests/repl.sh
install.sh    places the files (below)
bootstrap.sh  clones what is not a file here, sets the login shell
packages.txt  what install.sh installs first (packages.sh)
tests/        run.sh: static checks, formatters, the REPL helpers, the fzf lookup, the installer suite
```

## Install

```sh
./bootstrap.sh          # once, first: Oh My Zsh and the rest, the nvim config, zsh as login shell
./install.sh            # every time a file here changes
./install.sh --check    # what is behind or conflicting; writes nothing
./install.sh --force    # overwrite conflicts without asking
```

On Arch, `install.sh` first installs what `packages.txt` names and the
system lacks (`packages.sh`: pacman, in a terminal, never a reinstall),
since that is what meets the premise. dotfiles-desktop's `install.sh` runs
this one as well.

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
checkout needs `install.sh` again. rdoc files the irb helpers' documentation
in ri's home store (`~/.local/share/rdoc`), beside whatever is there.

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

RHEL's default `secure_path` lacks `/usr/local/bin`; there, add it or call
`sudo /usr/local/bin/el`. As root, `el` runs only the system's eza.

## Shell notes

- `shell/path.sh` (from `zshenv`, `bashrc`, and `zprofile` again after a
  login shell's `/etc/profile`) puts `~/.local/bin`, `~/.cargo/bin`,
  `~/.elan/bin` and `~/.ghcup/bin` last in PATH, so the distribution's
  binaries win over user-installed duplicates; `~/.cargo/env` and
  `~/.ghcup/env` prepend and are not sourced. It drops empty entries (the
  current directory). Debian's and Ubuntu's `~/.profile` puts `~/.local/bin`
  in front again after reading `bashrc`, so a login bash there keeps it first.
- `bashrc` reads `/etc/bashrc` where it exists: Fedora and RHEL leave their
  system bashrc to the user's file.
- Both shells source the `~/.config/profile.d/*.sh` files this user owns and
  others cannot write; `node/node.sh` and `luajit/luajit.sh` go there.
- History holds 500000 entries in both shells; bash appends, so concurrent
  sessions do not overwrite each other. A line that carries a secret is never
  saved: an assignment to a name like `*_TOKEN`, `password` or `API_KEY`, an
  `Authorization:` header, and in zsh a URL with a password in it; a leading
  space keeps any line out.
- REPL, database-shell and pager histories (node, python, psql, sqlite,
  mysql, redis-cli, less, rdbg) live in `$XDG_RUNTIME_DIR` (`shell/history.sh`, read
  by `zshenv` and `bashrc`; irb's through `~/.irbrc`), so they last the session; what is already in `~/.node_repl_history`,
  `~/.python_history`, `~/.irb_history` or `~/.local/state/lesshst` stays until removed.
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
- `shell/debug.sh` (both shells) holds the debugging helpers: `debugmax`,
  `straceall`, `ltraceall`, `lddebug`, `perfstat`, `norand`, `lastcore`,
  `elfinfo` (`debughelp` lists them). It keeps cores on (`ulimit -c
  unlimited`) for what runs from a terminal and points `DEBUGINFOD_URLS` at
  Arch's server. It replaces `~/.config/debug-max/debug-max.sh`, which no
  repository owned; `install.sh` removes that copy.
- kitty's scrollback pager (ctrl+shift+h, ctrl+shift+g) is nvim on a file in
  nvim's private temporary directory, removed when it exits, and without
  shada, so nothing searched or yanked there reaches nvim's history file.
- Inside kitty, interactive `ssh` runs kitty's ssh kitten (remote shell
  integration, `kitten`, terminfo); `command ssh` bypasses it. `kitty/ssh.conf`
  turns connection sharing off and sends loopback hosts (kbuildlab's guests
  cannot unpack the kitten's archive) to plain ssh as `xterm-256color`.

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
- History goes to one file, `~/.local/state/gdb/history` (`XDG_STATE_HOME`),
  not to `.gdb_history` in whatever directory gdb started in, where a commit
  could carry it; `GDBHISTFILE` still names another.

pwndbg sets `auto-load safe-path` to `/`, which would run any `.gdbinit` in
the working directory and any `*-gdb.py` beside a loaded file; `presets.py`
puts back the value in force before it. `kbuildlab attach` adds the kernel
tree with `-iex`, which gdb runs after the init file, so `lx-*` still loads
there. pwndbg is sourced before anything imports gdb's Python package, so an
Arch cross gdb whose package lags gdb-common still starts it.

## node, IEx, irb and LuaJIT

`bin`, `oct`, `dec` and `hex` return their number, so they nest in arithmetic,
and the result line shows the statement's value once, in the base called
last. Numbers follow C on x86-64 Linux (GCC, LP64): with no type a value is a
`u64`, and a type after it converts as a cast does, `hex(x, u16)`, `:u16` in
IEx and irb, or a C name such as `"unsigned long"`: `u8` to `u64`, `s8` to
`s64`, `f32`, `f64`, and `big` for no width. Those names are functions too,
beside `cast(type, x)` and `sizeof`. In irb and LuaJIT a converted value
keeps its type and computes by C's rules (promotion, wrapping, truncating
division); IEx and node cannot change their operators, so there it is a plain
number, cut where it was converted. `byte`, `kb`, `mb`, `gb` and `tb` convert
sizes in steps of 1024: `gb(x)` from bytes, `gb(512, mb)`, `mb_to_gb(512)`.

[docs/repl](docs/repl/README.md) has the whole toolbox, one page per REPL with
each call and what it prints; look there for what you need. `tests/repl.sh`
runs every row of those pages.

A node or LuaJIT number is exact up to 2^53 and its bit operations are
32-bit; BigInt and `ULL` literals carry 64 bits. LuaJIT shows a value only
for `=expression` and has no `big`. In both, the helpers exist only in an
interactive REPL, never under `-e`, a script or a worker; `LUA_INIT` reaches
every `lua` as well and does nothing there. A project's own `.iex.exs`
replaces this one unless it calls `import_file("~/.iex.exs")`. In irb they
belong to the top-level object only, the completion dialog, `show_doc` and
`ri` show their documentation, and irb also runs a `.irbrc` in the directory
it starts in, after this one.

## Checks

```sh
tests/run.sh    # shellcheck, the syntax checks, the formatters, the REPL helpers, the fzf lookup, then install.sh on a temporary HOME
```

Each file is kept as its formatter writes it, under `.editorconfig`, so
formatting from the editor changes nothing: shfmt, stylua, oxfmt, rubocop,
ruff, taplo, `mix format` and rumdl. A formatter that is not installed is
skipped; the zsh files have none and are only parsed.

The installer suite never touches the real HOME: each case runs on its own
temporary home and a copy of this checkout, with stand-ins for systemctl,
gdb and fc-list and an os-release per recognised distribution, and answers
conflicts through a pty. `tests/fzf.sh` runs zshrc's fzf block on a fake
root laid out as each distribution does.

Third-party files (the p10k configuration, the spaceduck palette, the search
kitten) keep their own licenses; see `THIRD-PARTY-NOTICES`.
