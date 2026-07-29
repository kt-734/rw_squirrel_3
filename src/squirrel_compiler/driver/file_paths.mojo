from std.os import listdir
from std.os.path import isdir, isfile, join


def find_sqrrl_files(root: String) raises -> List[String]:
    """Recursively finds every `.mojo.sqrrl` file under `root`, depth-first,
    returning full paths.

    Verbatim port from rw_squirrel_2 -- directory walking is unaffected by
    the storage redesign."""
    var out = List[String]()
    _collect_sqrrl_files(root, out)
    return out^


def _collect_sqrrl_files(dir: String, mut out: List[String]) raises:
    for entry in listdir(dir):
        var full = join(dir, entry)
        if isdir(full):
            _collect_sqrrl_files(full, out)
        elif isfile(full) and entry.endswith(".mojo.sqrrl"):
            out.append(full)


def mojo_output_path(sqrrl_path: String) -> String:
    """`foo/bar.mojo.sqrrl` -> `foo/bar.mojo`, written alongside the source."""
    return String(sqrrl_path[byte = 0 : sqrrl_path.byte_length() - String(".sqrrl").byte_length()])


def mojo_impl_output_path(sqrrl_path: String) -> String:
    """`foo/bar.mojo.sqrrl` -> `foo/bar_impl.mojo` -- the companion file a
    split entry file's own struct/table declarations move into (see
    `entry_split.mojo`'s own doc comment for why the split exists at
    all). Suffixing before the *whole* `.mojo.sqrrl` extension, not just
    before `.mojo`, matches `mojo_output_path`'s own stripping point."""
    var without_ext = sqrrl_path[byte = 0 : sqrrl_path.byte_length() - String(".mojo.sqrrl").byte_length()]
    return String(without_ext) + "_impl.mojo"


def module_path_for(sqrrl_path: String, target_root: String) -> String:
    """`sub/employee.mojo.sqrrl` (rooted at `target_root`) -> `sub.employee`,
    the dotted Mojo module path a cross-file relation import needs."""
    var root_prefix = target_root
    if not root_prefix.endswith("/"):
        root_prefix += "/"
    var relative = sqrrl_path
    if relative.startswith(root_prefix):
        var trimmed = relative.removeprefix(root_prefix)
        var stripped = String(trimmed)
        relative = stripped
    var without_ext = String(
        relative[byte = 0 : relative.byte_length() - String(".mojo.sqrrl").byte_length()]
    )
    return without_ext.replace("/", ".")


def output_module_prefix_for(output_root: String, target_root: String) -> String:
    """`output_root` (`convert_directory.mojo`'s own `output_root`, the
    directory `sqrrl__world.mojo`/`sqrrl__json.mojo`/`squirrel_runtime`
    actually get written to -- see its own doc comment) as a *dotted*
    module prefix relative to `target_root`, trailing `.` included (`""`
    when they're the same directory, matching every project where the
    entry file sits at the project root -- no behavior change there at
    all). Mirrors `module_path_for`'s own prefix-stripping, just for a
    bare directory instead of a `.mojo.sqrrl` file (nothing to strip an
    extension from)."""
    # Normalize away any trailing slash on *both* sides first -- `output_
    # root` (always `dirname(some_path)`, never trailing-slashed) and
    # `target_root` (whatever the caller typed on the command line,
    # trailing slash or not) otherwise fail the equality check below for
    # the exact same directory (confirmed via a real compile: `squirrelc
    # examples/basics/` -- trailing slash -- wrongly treated `output_root
    # == target_root` as false, prefixing every import with `examples.
    # basics.`, a directory that doesn't even exist relative to itself).
    var root = target_root
    if root.endswith("/"):
        var trimmed_root = root[byte=0 : root.byte_length() - 1]
        var stripped_root = String(trimmed_root)
        root = stripped_root
    var out = output_root
    if out.endswith("/"):
        var trimmed_out = out[byte=0 : out.byte_length() - 1]
        var stripped_out = String(trimmed_out)
        out = stripped_out
    if out == root:
        return ""
    var root_prefix = root + "/"
    if out.startswith(root_prefix):
        var trimmed = out.removeprefix(root_prefix)
        var stripped = String(trimmed)
        out = stripped
    return out.replace("/", ".") + "."
