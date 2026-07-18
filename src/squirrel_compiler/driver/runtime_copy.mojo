from std.os import listdir, makedirs
from std.os.path import dirname, isfile, isdir, join


def ensure_init_files(sqrrl_files: List[String], target_root: String) raises:
    """Writes an empty `__init__.mojo` in every directory (below
    `target_root`, exclusive) that contains a converted file -- Mojo only
    treats a directory as an importable package if it has one.
    `target_root` itself never gets one, deliberately (see
    `copy_runtime`'s own doc comment for the matching reason).

    Verbatim port from rw_squirrel_2."""
    var root = target_root
    if root.endswith("/"):
        root = String(root[byte=0 : root.byte_length() - 1])
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


def _copy_dir(src_dir: String, dest_dir: String) raises:
    makedirs(dest_dir, exist_ok=True)
    for entry in listdir(src_dir):
        var src_path = join(src_dir, entry)
        var dest_path = join(dest_dir, entry)
        if isdir(src_path):
            _copy_dir(src_path, dest_path)
        elif entry.endswith(".mojo"):
            var f = open(src_path, "r")
            var content = f.read()
            f.close()
            var out = open(dest_path, "w")
            out.write(content)
            out.close()


def copy_runtime(dest_root: String) raises:
    """Writes `squirrel_runtime`'s `.mojo` files into
    `dest_root/squirrel_runtime`, so generated files' `from
    squirrel_runtime...` imports resolve at the conversion root.

    M1 scope: a plain filesystem copy from this checkout's own `src/
    squirrel_runtime` (relative to the current working directory --
    matching `pixi run run`'s own `mojo run -I src src/main.mojo`
    invocation convention), not the embedded-in-the-binary trick
    rw_squirrel_2 uses (`tools/generate_embedded_runtime.mojo`) -- that's
    deferred to M7, a packaging convenience with no architectural
    weight (see the plan's Milestones section)."""
    _copy_dir("src/squirrel_runtime", join(dest_root, "squirrel_runtime"))
