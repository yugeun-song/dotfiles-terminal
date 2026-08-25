[[ -o interactive ]] || return 0
(( $+functions[p10k] )) || return 0

zmodload zsh/system 2>/dev/null || return 0
zmodload zsh/zselect 2>/dev/null || return 0
autoload -Uz add-zsh-hook

typeset -ga _capslock_leds
if [[ -n $CAPSLOCK_LED_PATHS ]]; then
  _capslock_leds=(${(s.:.)CAPSLOCK_LED_PATHS})
else
  _capslock_leds=(/sys/class/leds/*::capslock/brightness(N))
fi
(( $#_capslock_leds )) || return 0

typeset -g  _capslock_on=
typeset -gi _capslock_fd=0
typeset -gi _capslock_pid=0
typeset -gi _capslock_fails=0
typeset -gi _capslock_interval=${CAPSLOCK_POLL_CS:-20}

_capslock_probe() {
  local f v
  REPLY=
  for f in $_capslock_leds; do
    [[ -r $f ]] || continue
    v=$(<$f)
    [[ $v == 0 ]] || { REPLY=1; return 0 }
  done
  return 0
}

_capslock_watch_loop() {
  emulate -L zsh
  local -i owner=$1
  local REPLY prev=x
  while [[ -e /proc/$owner ]]; do
    _capslock_probe
    if [[ $REPLY != $prev ]]; then
      prev=$REPLY
      print -r -- ${REPLY:-0} || return 0
    fi
    zselect -t $_capslock_interval
  done
}

_capslock_detach() {
  local -i fd=$1
  (( fd )) || fd=$_capslock_fd
  (( fd )) || return 0
  zle -F $fd 2>/dev/null
  exec {fd}<&-
  (( fd == _capslock_fd )) && _capslock_fd=0
  return 0
}

_capslock_zle_handler() {
  local -i fd=$1
  if [[ -n $2 ]]; then
    _capslock_detach $fd
    return 0
  fi
  local line last
  local -i got=0
  while read -r -u $fd -t 0 line; do
    last=$line
    got=1
  done
  (( got )) || return 0
  local new=
  [[ $last == 1 ]] && new=1
  [[ $new == $_capslock_on ]] && return 0
  _capslock_on=$new
  (( $+functions[p10k] )) && p10k display -r
  return 0
}

_capslock_watch_start() {
  (( _capslock_fd )) && return 0
  (( _capslock_fails > 2 )) && return 0
  if ! sysopen -r -o cloexec -u _capslock_fd <(_capslock_watch_loop $$ 2>/dev/null) 2>/dev/null; then
    _capslock_fd=0
    (( ++_capslock_fails ))
    return 1
  fi
  _capslock_pid=${sysparams[procsubstpid]:-0}
  if ! zle -F $_capslock_fd _capslock_zle_handler 2>/dev/null; then
    _capslock_detach $_capslock_fd
    (( ++_capslock_fails ))
    return 1
  fi
  _capslock_fails=0
  return 0
}

_capslock_watch_stop() {
  _capslock_detach $_capslock_fd
  (( _capslock_pid > 1 )) && kill -- $_capslock_pid 2>/dev/null
  _capslock_pid=0
  return 0
}

_capslock_precmd() {
  local REPLY
  _capslock_probe
  _capslock_on=$REPLY
  _capslock_watch_start
}

function prompt_caps_lock() {
  p10k segment -c '$_capslock_on' -b '#f7768e' -f '#0f111b' -i $'\U000F033E' -t 'CAPS LOCK'
}

typeset -ga POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS
(( ${POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS[(I)caps_lock]} )) ||
  POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(caps_lock $POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS)

add-zsh-hook precmd  _capslock_precmd
add-zsh-hook zshexit _capslock_watch_stop
