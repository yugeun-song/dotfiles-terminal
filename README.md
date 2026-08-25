# dotfiles-terminal

Terminal-side configuration: shell, prompt, terminal emulator, multiplexer.

Everything here is machine independent. Paths are relative to `$HOME`, so the
files work under any account name.

## Layout

```
zsh/        zshrc, zshenv, powerlevel10k prompt, drop-ins under config/
kitty/      kitty.conf with the spaceduck palette and two kittens
tmux/       tmux.conf
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

The prompt is powerlevel10k, and there is deliberately only one. starship
would do the same job and works under zsh perfectly well, but running both
means one of them is dead configuration, and the Caps Lock segment below is
written against p10k's segment API.

`zsh/config/caps-lock.zsh` adds a Caps Lock segment to the prompt by watching
`/sys/class/leds/*::capslock/brightness`. It costs nothing when Caps Lock is
off and disables itself when the LED nodes are absent.
