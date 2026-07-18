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


def module_path_for(sqrrl_path: String, target_root: String) -> String:
    """`sub/employee.mojo.sqrrl` (rooted at `target_root`) -> `sub.employee`,
    the dotted Mojo module path a cross-file relation import needs."""
    var root_prefix = target_root
    if not root_prefix.endswith("/"):
        root_prefix += "/"
    var relative = sqrrl_path
    if relative.startswith(root_prefix):
        relative = String(relative.removeprefix(root_prefix))
    var without_ext = String(
        relative[byte = 0 : relative.byte_length() - String(".mojo.sqrrl").byte_length()]
    )
    return without_ext.replace("/", ".")
