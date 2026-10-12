# Sourced by the login shell from profile.d, never run, so no shebang; the
# ${var//...} expansions need bash or zsh.
# shellcheck shell=bash
_node_repl="${XDG_CONFIG_HOME:-$HOME/.config}/node/repl.js"
_node_flag="--require \"$_node_repl\""
_node_opts=" ${NODE_OPTIONS-} "
_node_opts="${_node_opts//" $_node_flag "/ }"
_node_opts="${_node_opts//" --require=$_node_repl "/ }"
case $_node_repl in
    *[\"\\]*) ;;
    *)
        if command -v node >/dev/null 2>&1 && [ -f "$_node_repl" ] && [ -r "$_node_repl" ]; then
            _node_opts="$_node_opts$_node_flag "
        fi
        ;;
esac
_node_opts="${_node_opts#"${_node_opts%%[![:space:]]*}"}"
_node_opts="${_node_opts%"${_node_opts##*[![:space:]]}"}"
if [ -n "$_node_opts" ]; then
    export NODE_OPTIONS="$_node_opts"
else
    unset NODE_OPTIONS
fi
unset _node_repl _node_flag _node_opts
