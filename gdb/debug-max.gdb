set debuginfod enabled on
set debug-file-directory /usr/lib/debug

set print pretty on
set print elements 100000
set print repeats unlimited
set print array on
set print array-indexes on
set print max-depth unlimited
set max-value-size unlimited

set print frame-arguments all
set print entry-values both
set print symbol-loading full
set print inferior-events on
set backtrace past-main on
set backtrace past-entry on
set backtrace limit unlimited

python
import gdb
def _dbgmax_x86_flavor(*_):
    arch = ""
    try:
        arch = gdb.selected_inferior().architecture().name() or ""
    except Exception:
        try:
            arch = gdb.execute("show architecture", to_string=True) or ""
        except Exception:
            arch = ""
    if ("i386" in arch) or ("x86-64" in arch) or ("x86_64" in arch):
        try:
            gdb.execute("set disassembly-flavor intel", to_string=True)
        except gdb.error:
            pass
try:
    _dbgmax_x86_flavor()
except Exception:
    pass
for _evt in ("new_objfile", "architecture_changed"):
    _e = getattr(gdb.events, _evt, None)
    if _e is not None:
        try:
            _e.connect(_dbgmax_x86_flavor)
        except Exception:
            pass
end
python
import gdb
try:
    gdb.execute("set disable-randomization on", to_string=True)
except gdb.error:
    pass
end

set history save on
set history size unlimited
set history remove-duplicates unlimited

set pagination off
set confirm off

define maxfork
  set detach-on-fork off
  set follow-fork-mode child
  set schedule-multiple on
  echo [debug-max] now following BOTH sides of every fork\n
end
document maxfork
Follow both parent and child across fork(); keep all inferiors scheduled.
end

define logon
  set logging file gdb-session.log
  set logging enabled on
  echo [debug-max] logging this session to gdb-session.log\n
end
document logon
Tee this entire gdb session to gdb-session.log in the current directory.
end

define syscatch
  catch syscall
  echo [debug-max] stopping on every syscall (remove with: delete)\n
end
document syscatch
Catch every syscall the inferior makes.
end
