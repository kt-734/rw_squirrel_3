from std.os import listdir, makedirs
from std.os.path import dirname, isfile, isdir, join, realpath


def ensure_init_files(sqrrl_files: List[String], target_root: String) raises:
    """Writes an empty `__init__.mojo` in every directory (below
    `target_root`, exclusive) that contains a converted file -- Mojo only
    treats a directory as an importable package if it has one.
    `target_root` itself never gets one, deliberately (see
    `copy_runtime`'s own doc comment for the matching reason).

    Verbatim port from rw_squirrel_2."""
    var root = target_root
    if root.endswith("/"):
        var trimmed = root[byte=0 : root.byte_length() - 1]
        var stripped = String(trimmed)
        root = stripped
    var seen = List[String]()
    for path in sqrrl_files:
        var dir = dirname(path)
        while dir != root and dir not in seen:
            seen.append(dir)
            var init_path = join(dir, "__init__.mojo")
            if not isfile(init_path):
                var f = open(init_path, "w")
                f.close()
            dir = dirname(dir)


def _copy_dir(src_dir: String, dest_dir: String, import_prefix: String) raises:
    makedirs(dest_dir, exist_ok=True)
    for entry in listdir(src_dir):
        var src_path = join(src_dir, entry)
        var dest_path = join(dest_dir, entry)
        if isdir(src_path):
            _copy_dir(src_path, dest_path, import_prefix)
        elif entry.endswith(".mojo"):
            var f = open(src_path, "r")
            var content = f.read()
            f.close()
            # `squirrel_runtime`'s own files are static, hand-written, and
            # never templated by squirrelc -- their own internal cross-file
            # imports (`from squirrel_runtime.id_allocator import ...`)
            # are hardcoded assuming `squirrel_runtime` itself is a bare,
            # top-level package. That's only true when it lands at
            # `output_root` (`convert_directory.mojo`) directly; once it's
            # nested under a `src/` subdirectory instead (which needs its
            # own `__init__.mojo` for `src.main_impl`-style cross-file
            # imports to work at all), Mojo treats `src` as a real package
            # and these same bare imports no longer resolve from within it
            # (confirmed via a real compile) -- so they're rewritten here,
            # at copy time, exactly the same way `emit_file`/`emit_json_
            # module`'s own generated `from squirrel_runtime...` lines
            # already are.
            if import_prefix != "":
                content = content.replace("from squirrel_runtime.", "from " + import_prefix + "squirrel_runtime.")
            var out = open(dest_path, "w")
            out.write(content)
            out.close()


def _find_runtime_source_dir() raises -> String:
    """Locates this checkout's own `src/squirrel_runtime`, anchored to
    where the currently-running process's own binary actually lives
    (`/proc/self/exe`, resolved via `realpath`) -- not the current
    working directory, and deliberately not `argv()[0]` either: once
    `squirrelc` sits on `PATH` and gets invoked by its bare name, a shell
    is free to hand the exec'd process whatever string was actually typed
    as `argv[0]` (often just `"squirrelc"`, no directory component at
    all) rather than the resolved path it found via its own `PATH`
    search -- confirmed via a real repro (`realpath failed to resolve: No
    such file or directory`, `realpath("squirrelc")` trying to resolve a
    bare relative name against the current *working* directory, where no
    such file exists). `/proc/self/exe` has no such ambiguity: the kernel
    always points it at whatever binary is actually executing, regardless
    of how it was invoked.

    Searches upward from there for a `src/squirrel_runtime` -- this one
    fixed relative suffix, tried at every ancestor, covers every way
    `squirrelc` is ever started from *this* checkout without needing to
    tell the cases apart: a compiled binary sits at the checkout root
    (`src/squirrel_runtime` matches immediately); `pixi run run`'s `mojo
    run -I src src/main.mojo` runs the real `mojo` binary itself (`/proc/
    self/exe` points there, not at `main.mojo`), which lives inside this
    same checkout's own `.pixi/envs/.../bin/mojo` -- several levels
    deeper, but the search just keeps walking up until it reaches the
    checkout root and matches there too."""
    var dir = dirname(realpath("/proc/self/exe"))
    while True:
        var candidate = join(dir, "src/squirrel_runtime")
        if isdir(candidate):
            return candidate
        var parent = dirname(dir)
        if parent == dir:
            raise Error(
                "InternalError: couldn't find 'src/squirrel_runtime' anywhere"
                " above '" + dirname(realpath("/proc/self/exe")) + "' -- is"
                " this a genuine rw_squirrel_3 checkout's own 'squirrelc'?"
            )
        dir = parent


def copy_runtime(dest_root: String, import_prefix: String = "") raises:
    """Writes `squirrel_runtime`'s `.mojo` files into
    `dest_root/squirrel_runtime`, so generated files' `from
    squirrel_runtime...` imports resolve at the conversion root.

    `import_prefix` (`convert_directory.mojo`'s own `output_module_
    prefix`, e.g. `"src."`) rewrites `squirrel_runtime`'s own internal
    cross-file imports to match, when `dest_root` isn't `target_root`
    itself -- see `_copy_dir`'s own doc comment for the full "why".

    M1 scope: a plain filesystem copy from this checkout's own `src/
    squirrel_runtime` (`_find_runtime_source_dir`, anchored to where
    `squirrelc` itself actually lives, not the current working directory
    -- see its own doc comment), not the embedded-in-the-binary trick
    rw_squirrel_2 uses (`tools/generate_embedded_runtime.mojo`) -- that's
    deferred to M7, a packaging convenience with no architectural weight
    (see the plan's Milestones section)."""
    _copy_dir(_find_runtime_source_dir(), join(dest_root, "squirrel_runtime"), import_prefix)
