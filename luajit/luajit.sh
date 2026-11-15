# shellcheck shell=sh
_luajit_repl="${XDG_CONFIG_HOME:-$HOME/.config}/luajit/repl.lua"
_luajit_init="if jit then pcall(dofile, '$_luajit_repl') end"
case $_luajit_repl in
    *[\'\\[:cntrl:]]*) ;;
    *)
        if [ "${LUA_INIT-$_luajit_init}" = "$_luajit_init" ]; then
            if command -v luajit >/dev/null 2>&1 && [ -f "$_luajit_repl" ] && [ -r "$_luajit_repl" ]; then
                export LUA_INIT="$_luajit_init"
            else
                unset LUA_INIT
            fi
        fi
        ;;
esac
unset _luajit_repl _luajit_init
