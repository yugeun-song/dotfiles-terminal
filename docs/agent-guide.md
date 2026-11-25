# dotfiles-terminal

Shell, prompt, terminal and debugger configuration: zsh, bash, kitty, tmux,
gdb, git, and number-base helpers for the node, IEx, irb and LuaJIT REPLs.

- Read `README.md` first. It covers the layout, how `install.sh` places each
  file (mirrored, seeded, managed block or included), and the checks.
  `docs/repl/` holds one page per REPL and one for `cnum`, with each helper
  call and what it prints.
- Check a change with `tests/run.sh`. It runs shellcheck, the syntax checks,
  the formatters, the REPL pages, the fzf lookup, and `install.sh` on a
  temporary home. It never touches the installed configuration, and a
  missing tool skips its check.
- `tests/run.sh` names most files it checks one by one. Add a new file to
  each check there that should cover it.
- Keep each file as its formatter writes it, under the settings in
  `.editorconfig`; `README.md` names the formatters. Files from other
  projects stay byte for byte (`.editorconfig`, `THIRD-PARTY-NOTICES`).
- A change to a REPL helper (`irb/irbrc`, `iex/iex.exs`, `node/repl.js`,
  `luajit/repl.lua`, `cnum/cnum.rkt`) needs the same change in its page
  under `docs/repl/`. `tests/repl.sh` runs every row of those pages, so a
  page that falls behind the code fails the checks.
- Files are copied, never linked, so a change takes effect only after
  `./install.sh` runs again. No file is installed by both this repository
  and dotfiles-desktop.
