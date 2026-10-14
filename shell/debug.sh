# debug-max: maximum-visibility debugging helpers, the shell half of
# gdb/debug-max.gdb. Sourced by zshrc and bashrc from ~/.config/shell (it was
# ~/.config/debug-max/debug-max.sh, a file no repository owned; install.sh
# retires that copy). Works in both bash and zsh.
# Goal: capture every piece of information that touches a program's execution,
# while keeping your normal shell fast and quiet (heavy capture is opt-in).

# ---------------------------------------------------------------------------
# Always-on, zero-cost global settings
# ---------------------------------------------------------------------------

# Auto-download debug symbols AND source for glibc/libraries/kernel on demand
# (used by gdb, valgrind, eu-*, perf). Keep any value already set by the system.
export DEBUGINFOD_URLS="${DEBUGINFOD_URLS:-https://debuginfod.archlinux.org}"
export DEBUGINFOD_PROGRESS=1          # show a progress bar while fetching

# Always keep a core dump when something crashes (systemd-coredump collects it;
# retrieve with `coredumpctl gdb <name>`).
ulimit -c unlimited 2>/dev/null

# Where the on-demand capture helpers write their logs.
export DEBUGMAX_LOGDIR="${DEBUGMAX_LOGDIR:-$HOME/debug-logs}"

# ---------------------------------------------------------------------------
# debugmax: run a program under maximum PASSIVE instrumentation at once.
#   Usage: debugmax ./prog [args...]
#   Captures, into a timestamped dir under $DEBUGMAX_LOGDIR:
#     - strace.log : every syscall (with decoded fds/paths, timings, timestamps)
#     - ld.<pid>   : every dynamic-linker action (lib search, symbol binding,
#                    relocations, version checks) via LD_DEBUG=all
#   Also enables glibc heap checks + freed/allocated-memory poisoning so
#   use-after-free / uninitialized reads tend to fault instead of passing.
# ---------------------------------------------------------------------------
debugmax() {
  [ $# -eq 0 ] && { echo "usage: debugmax <program> [args...]" >&2; return 2; }
  local ts base dir
  ts=$(date +%Y%m%d-%H%M%S)
  base=${1##*/}
  dir="$DEBUGMAX_LOGDIR/${base}-${ts}"
  mkdir -p "$dir"
  echo "[debugmax] capturing to $dir" >&2
  LD_DEBUG=all LD_DEBUG_OUTPUT="$dir/ld" LD_SHOW_AUXV=1 \
  MALLOC_CHECK_=3 MALLOC_PERTURB_=165 GLIBC_TUNABLES=glibc.malloc.check=3 \
  strace -f -yy -T -tt -s 4096 -e trace=all -o "$dir/strace.log" "$@"
  local rc=$?
  echo "[debugmax] exit=$rc  (strace: $dir/strace.log ; ld.so: $dir/ld.<pid>)" >&2
  echo "[debugmax] crashed? -> coredumpctl gdb $base" >&2
  return $rc
}

# ---------------------------------------------------------------------------
# Focused, composable helpers — reach for one when you don't want the full blast
# ---------------------------------------------------------------------------

# Every syscall, fully decoded (fds, sockets, paths), with timing + timestamps.
straceall() { strace -f -yy -T -tt -s 4096 -e trace=all "$@"; }

# Every library call, plus the syscalls underneath them.
ltraceall() { ltrace -f -S -s 200 "$@"; }

# Dynamic linker internals only. Override the classes with LD_DEBUG_CLASSES=
# (e.g. bindings, reloc, symbols, versions, scopes, files, statistics).
lddebug() { LD_DEBUG="${LD_DEBUG_CLASSES:-all}" "$@"; }

# What shared objects a binary pulls in, and their load addresses.
loadedlibs() { LD_TRACE_LOADED_OBJECTS=1 "$@"; }

# Hardware/software perf counters + a cache/branch breakdown.
perfstat() { perf stat -d -d -d "$@"; }

# Run with ASLR OFF so addresses are reproducible run to run.
norand() { setarch "$(uname -m)" -R "$@"; }

# Open the most recent core dump (or one for NAME) in gdb+pwndbg.
lastcore() { coredumpctl gdb "${1:-}"; }

# Full static picture of an ELF: headers, segments, sections, dynamic, relocs,
# symbols, notes/build-id, and DWARF presence.
elfinfo() {
  [ -z "$1" ] && { echo "usage: elfinfo <file>" >&2; return 2; }
  eu-readelf -a "$1" 2>/dev/null || readelf -aW "$1"
}

# List every debug-max helper.
debughelp() {
  cat <<'EOF'
debug-max helpers:
  debugmax <prog> ...   run under strace + LD_DEBUG=all + heap poisoning, logs saved
  straceall <prog> ...  every syscall, decoded, timed
  ltraceall <prog> ...  every library call (+ syscalls)
  lddebug  <prog> ...   dynamic-linker internals (LD_DEBUG; set LD_DEBUG_CLASSES=)
  loadedlibs <prog>     shared objects pulled in + load addresses
  perfstat <prog> ...   hardware/software perf counters
  norand   <prog> ...   run with ASLR disabled (reproducible addresses)
  lastcore [name]       open latest core dump in gdb+pwndbg
  elfinfo  <file>       full static ELF + DWARF dump
In gdb (pwndbg): checksec, vmmap, telescope, heap/bins/tcache, got, plt, rop,
  pt (page tables), info auxv, info proc all
  linux_kernel preset (GDB_PRESET=linux_kernel gdb, or any Linux Kernel
  session): maxfork, logon, syscatch
EOF
}
