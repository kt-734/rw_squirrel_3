from squirrel_compiler.codegen import transform_source
from squirrel_compiler.driver.misc_builders import uses_json_entry_point


def _contains_word(haystack: String, needle: String) -> Bool:
    """True if `needle` appears in `haystack` at a word boundary on both
    sides (not preceded/followed by an identifier char) -- guards against a
    struct whose name is a prefix of another's (`Dept` inside `Department`)
    causing a spurious extra import a plain substring check would miss.
    Straight port of rw_squirrel_2's own `_contains_word`."""
    var h = haystack.as_bytes()
    var n = needle.as_bytes()
    if len(n) == 0 or len(n) > len(h):
        return False
    for start in range(len(h) - len(n) + 1):
        var matches = True
        for i in range(len(n)):
            if h[start + i] != n[i]:
                matches = False
                break
        if not matches:
            continue
        if start > 0 and _is_ident_char(h[start - 1]):
            continue
        var end = start + len(n)
        if end < len(h) and _is_ident_char(h[end]):
            continue
        return True
    return False


def _is_ident_char(b: UInt8) -> Bool:
    return (
        (b >= UInt8(ord("a")) and b <= UInt8(ord("z")))
        or (b >= UInt8(ord("A")) and b <= UInt8(ord("Z")))
        or (b >= UInt8(ord("0")) and b <= UInt8(ord("9")))
        or b == UInt8(ord("_"))
    )


def emit_file(
    path: String,
    own_module_path: String,
    relation_schema: Dict[String, Dict[String, String]],
    struct_names: Dict[String, Bool],
    function_returns: Dict[String, String],
    unique_fields: Dict[String, List[String]],
    indexed_fields: Dict[String, List[String]],
    multi_fields: Dict[String, List[String]],
    ordered_fields: Dict[String, List[String]],
    world_methods: Dict[String, List[String]],
    stats_fields: Dict[String, List[String]],
    cross_file_symbols: Dict[String, String],
    plain_struct_names: Dict[String, Bool] = Dict[String, Bool](),
    plain_value_fields: Dict[String, Dict[String, String]] = Dict[String, Dict[String, String]](),
    json_used: Bool = False,
) raises -> String:
    """Emits the generated Mojo source for `path` (a single `.mojo.sqrrl`
    file), prefixed with the runtime imports, an import for every
    `cross_file_symbols` (`build_entity_symbols`) entry this file's own
    transformed text actually references and that isn't declared in this
    same file (`own_module_path`), and, if this file's script body touches
    `sqrrl__world` at all, an import line for it.

    `json_used` (`driver/misc_builders.mojo`'s `project_uses_json`,
    computed project-wide *before* any file gets transformed) gates both
    the `sqrrl__JsonSerializable` import here and whether `emit_entity`
    (via `transform_source`) adds the conformance/method at all -- a
    project that never touches JSON anywhere shouldn't carry either.

    Slimmed from rw_squirrel_2's own `emit_file`: no JSON imports (M5), no
    `EntityHandle`/`TableStateLike`/`Rel`-family runtime imports -- swapped
    for `EntityStorage`/`PlainIndex`/`UniqueIndex`/`MultiIndex` (see the
    plan's Architecture/file-layout sections; `EntityStorage` alone, no
    separate `EntityTable` -- see `entity_storage.mojo`'s own doc comment
    for why that layer was folded away)."""
    var f = open(path, "r")
    var source = f.read()
    f.close()
    var transformed: String
    try:
        transformed = transform_source(
            source, relation_schema, struct_names, function_returns, unique_fields, indexed_fields, multi_fields,
            ordered_fields, world_methods, stats_fields, plain_struct_names, plain_value_fields, json_used
        )
    except e:
        raise Error(path + ": " + String(e))

    var out = String("from squirrel_runtime.entity_storage import EntityStorage\n")
    out += "from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex\n"
    # `sqrrl__to_json` itself is never imported here (the JSON-container-
    # dispatch rearchitecture): it's a per-project *generated* function
    # now (`sqrrl__json.mojo`, only emitted when the project actually
    # uses JSON at all), not static runtime code, and this entity file's
    # own generated body never actually calls it directly (`sqrrl__to_
    # json(self) -> String` on the entity wrapper itself is just the
    # row's own bare id, no recursive call) -- confirmed unused here, not
    # just moved, by checking codegen/entity.mojo's own generated method
    # body. The conformance itself is conditional too, same reason.
    if json_used:
        out += "from squirrel_runtime.json import sqrrl__JsonSerializable\n"
    out += "from std.memory import ArcPointer\n"
    out += "from std.hashlib import Hasher\n"
    out += "from std.collections import Set\n"
    out += "from std.os import abort\n"
    if "sqrrl__world" in transformed:
        out += "from sqrrl__world import sqrrl__init, sqrrl__World\n"
    # Only a file that actually calls a whole-world JSON entry point needs
    # this import -- `sqrrl__json.mojo` itself is only generated at all
    # when *some* file in the project does (`convert_directory.mojo`), so
    # importing it unconditionally alongside "uses world" would reference
    # a file that might not exist.
    if uses_json_entry_point(transformed):
        out += (
            "from sqrrl__json import sqrrl__begin_init_from_json,"
            " sqrrl__end_init_from_json, sqrrl__init_from_json, sqrrl__world_to_json\n"
        )

    for symbol in cross_file_symbols.keys():
        var target_module = cross_file_symbols[symbol]
        if target_module == own_module_path:
            continue
        if _contains_word(transformed, symbol):
            out += "from " + target_module + " import " + symbol + "\n"

    out += "\n\n"
    out += transformed
    return out
