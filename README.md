# dotfiles-terminal

Terminal-side configuration: shell, prompt, terminal emulator, multiplexer.

Everything here is machine independent. Paths are relative to `$HOME`, so the
files work under any account name.

## Layout

```
zsh/        zshrc, zshenv, powerlevel10k prompt, drop-ins under config/
kitty/      kitty.conf with the spaceduck palette and two kittens
tmux/       tmux.conf
starship/   starship.toml, an alternative prompt to powerlevel10k
```

## Install

```sh
./install.sh
```

The script symlinks each file into place and moves an existing config aside
with a timestamped suffix rather than overwriting it.

## Notes

The kitty configuration expects two fonts: CaskaydiaCove Nerd Font Mono for
text and Pretendard for Hangul, wired through `symbol_map` so mixed lines stay
aligned. Without them kitty falls back and the alignment drifts.

`zsh/config/caps-lock.zsh` adds a Caps Lock segment to the prompt by watching
`/sys/class/leds/*::capslock/brightness`. It costs nothing when Caps Lock is
off and disables itself when the LED nodes are absent.
