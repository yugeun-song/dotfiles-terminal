# REPL, database-shell and pager histories in the runtime directory, a tmpfs
# that goes at logout: what is typed or pasted into them (a token tried in
# node, a password in a psql session) lasts the session, not for good. The
# shells' own histories stay on disk (zshrc, bashrc), less the lines that
# carry a secret. Without a runtime directory each keeps its default.
# Sourced by both shells from profile.d, never run.
# shellcheck shell=sh
if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ]; then
    export NODE_REPL_HISTORY="$XDG_RUNTIME_DIR/node_repl_history"
    export PYTHON_HISTORY="$XDG_RUNTIME_DIR/python_history"
    export LESSHISTFILE="$XDG_RUNTIME_DIR/lesshst"
    export PSQL_HISTORY="$XDG_RUNTIME_DIR/psql_history"
    export SQLITE_HISTORY="$XDG_RUNTIME_DIR/sqlite_history"
    export MYSQL_HISTFILE="$XDG_RUNTIME_DIR/mysql_history"
    export REDISCLI_HISTFILE="$XDG_RUNTIME_DIR/rediscli_history"
fi
