# dotfiles-terminal

Terminal-side configuration: shell, prompt, terminal emulator, multiplexer.

Everything here is machine independent. Paths are relative to `$HOME`, so the
files work under any account name.

## Layout

```
zsh/        zshrc, zshenv, zprofile, powerlevel10k prompt, drop-ins under config/
bash/       bashrc, for the sessions that are not zsh
git/        shared git settings, with no identity in them
kitty/      kitty.conf with the spaceduck palette and two kittens
tmux/       tmux.conf
bootstrap.sh  what has to be cloned rather than linked
```

## Install

```sh
./install.sh
```

The script symlinks each file into place and moves an existing config aside
with a timestamped suffix rather than overwriting it.

On a machine that has never had this setup, one more step:

```sh
./bootstrap.sh
```

`zsh/zshrc` expects an Oh My Zsh tree with a theme and two plugins cloned into
it, and none of the three is an Arch package: powerlevel10k is not in the
official repositories at all, and the zsh-users plugins are packaged but Oh My
Zsh loads them from its own custom path rather than from `/usr/share`. So a
fresh machine has a zshrc referencing a theme that is not there, and zsh prints
an error on every prompt. `bootstrap.sh` clones what is missing, updates what
is already there, restores the editor configuration, and switches the login
shell to zsh. It is separate from `install.sh` because it reaches the network
and changes an account setting, and `install.sh` only places links.

## History

Oh My Zsh caps saved history at 10000 entries and stops there. At the rate this
account actually runs commands that ceiling filled in 284 days, and once it is
reached every new command silently evicts the oldest one. Both shells now keep
500000, which is about 24MB and adds roughly 290ms to shell startup — a cost
that is not felt, because the powerlevel10k instant prompt at the top of zshrc
draws the prompt before the history file is read. Searching the full set with
fzf measures around 80ms, so Ctrl-R stays immediate.

bash had a worse problem than a small ceiling: without `histappend`, whichever
shell exits last overwrites the file with only its own session, discarding
every other terminal's history. It is not the login shell here, but a rescue
shell or a container gets one, and there is no reason for those to throw their
history away.

## Git

`git/gitconfig` carries the settings that are the same everywhere and no
identity. The file is public and meant to work on any machine, so `user.name`
and `user.email` are deliberately absent and nothing fills them in: an identity
set by a script is one nobody checked, and the first commit under the wrong
name is silent. Set them once, by hand.

```sh
git config --global user.name  'Your Name'
git config --global user.email 'you@example.com'
```

`install.sh` includes the file from `~/.gitconfig` rather than linking over it,
because linking would replace the one place the identity lives. Later entries
win in git config, so anything set directly in `~/.gitconfig` still overrides
what is included.

There is no `credential.helper` either. The `store` helper writes tokens in
plaintext to `~/.git-credentials`, and `gh` already keeps one in the system
keyring, so the per-host helpers are the whole credential story.

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
