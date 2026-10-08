def _gdb_presets(here):
    import os
    import struct
    import sys

    elf_layouts = {
        1: ("16xHHIIIIIHHHHHH", "IIIIIIIIII"),
        2: ("16xHHIQQQIHHHHHH", "IIQQQQIIQQ"),
    }
    section_index_escape = 0xFFFF
    module_marker = ".gnu.linkonce.this_module"
    image_markers = ("__ksymtab", "__param")
    gdb_default_safe_path = "$debugdir:$datadir/auto-load"

    def say(text):
        sys.stderr.write("gdb presets: %s\n" % text)
        sys.stderr.flush()

    def source(path):
        gdb = sys.modules.get("gdb")
        namespace = sys.modules["__main__"].__dict__
        saved = namespace.get("__file__")
        namespace["__file__"] = path
        try:
            if gdb is not None and hasattr(gdb, "execute"):
                gdb.execute("source " + path)
            else:
                with open(path, "rb") as handle:
                    code = compile(handle.read(), path, "exec")
                exec(code, namespace)
        finally:
            if saved is None:
                namespace.pop("__file__", None)
            else:
                namespace["__file__"] = saved

    def pwndbg_venv(loader):
        override = os.environ.get("PWNDBG_VENV_PATH")
        if override:
            return os.path.realpath(os.path.expanduser(override))
        root = os.path.dirname(os.path.realpath(loader))
        if os.path.exists(os.path.join(root, ".pwndbg_root")):
            return os.path.join(root, ".venv")
        return None

    def load_pwndbg(loader):
        loader = os.path.expanduser(loader)
        if not os.path.isfile(loader):
            say("pwndbg is not at %s; running plain gdb" % loader)
            return
        venv = pwndbg_venv(loader)
        if venv is not None and not os.path.isdir(venv):
            say("pwndbg's virtualenv %s is missing; running plain gdb" % venv)
            return
        try:
            source(loader)
        except Exception as error:
            say("pwndbg failed to load: %s" % error)

    def section_names(path):
        with open(path, "rb") as handle:
            ident = handle.read(16)
            if len(ident) < 16 or ident[:4] != b"\x7fELF":
                return set()
            if ident[4] not in elf_layouts or ident[5] not in (1, 2):
                return set()
            order = "<" if ident[5] == 1 else ">"
            header_format, section_format = elf_layouts[ident[4]]
            header = struct.Struct(order + header_format)
            section = struct.Struct(order + section_format)
            handle.seek(0)
            fields = header.unpack(handle.read(header.size))
            table_offset, entry_size, count, names_index = fields[5], fields[10], fields[11], fields[12]
            if not table_offset or entry_size < section.size:
                return set()
            file_size = os.fstat(handle.fileno()).st_size
            handle.seek(table_offset)
            first = section.unpack(handle.read(section.size))
            if count == 0:
                count = first[5]
            if names_index == section_index_escape:
                names_index = first[6]
            if names_index >= count or table_offset + count * entry_size > file_size:
                return set()
            handle.seek(table_offset)
            table = handle.read(count * entry_size)
            names_section = section.unpack_from(table, names_index * entry_size)
            if names_section[4] + names_section[5] > file_size:
                return set()
            handle.seek(names_section[4])
            strings = handle.read(names_section[5])
            names = set()
            for index in range(count):
                start = section.unpack_from(table, index * entry_size)[0]
                end = strings.find(b"\0", start)
                if end > start:
                    names.add(strings[start:end].decode("latin-1"))
            return names

    def linux_kernel_object(path):
        if not path or not os.path.isfile(path):
            return False
        try:
            names = section_names(path)
        except Exception:
            return False
        if module_marker in names:
            return True
        return ".init.text" in names and not names.isdisjoint(image_markers)

    trusted = None
    early = sys.modules.get("gdb")
    if early is not None and hasattr(early, "parameter"):
        try:
            trusted = early.parameter("auto-load safe-path")
        except Exception:
            trusted = None

    loader = sys.modules["__main__"].__dict__.get("gdb_presets_pwndbg_source")
    if loader:
        load_pwndbg(loader)

    try:
        import gdb
    except Exception as error:
        say("the gdb Python module does not load (%s); presets are off" % error)
        return

    try:
        if gdb.parameter("auto-load safe-path") != trusted:
            gdb.execute("set auto-load safe-path " + (trusted or gdb_default_safe_path))
    except Exception as error:
        say("could not restore the auto-load safe-path: %s" % error)

    choice = os.environ.get("GDB_PRESET", "")
    if choice not in ("", "stock", "linux_kernel"):
        say("GDB_PRESET=%s is neither stock nor linux_kernel; choosing automatically" % choice)
        choice = ""
    if choice == "stock":
        return

    layer = os.path.join(here, "debug-max.gdb")
    applied = []

    def apply_linux_kernel():
        if applied:
            return
        applied.append(layer)
        try:
            gdb.execute("source " + layer)
        except Exception as error:
            say("the linux_kernel preset stopped early: %s" % error)

    if choice == "linux_kernel" or os.environ.get("GDBTOOLS_AUTO"):
        apply_linux_kernel()
        return

    try:
        loaded = any(linux_kernel_object(objfile.filename) for objfile in gdb.objfiles())
    except Exception:
        loaded = False
    if loaded:
        apply_linux_kernel()
        return

    def on_new_objfile(event):
        try:
            if applied or not linux_kernel_object(getattr(event.new_objfile, "filename", None)):
                return
            gdb.events.new_objfile.disconnect(on_new_objfile)
        except Exception:
            return
        apply_linux_kernel()
        say("a Linux Kernel image is loaded; applied the linux_kernel preset")

    gdb.events.new_objfile.connect(on_new_objfile)


_gdb_presets(__import__("os").path.dirname(__import__("os").path.realpath(__file__)))
del _gdb_presets
