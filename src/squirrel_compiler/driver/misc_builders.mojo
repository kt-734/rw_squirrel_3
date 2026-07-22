from squirrel_compiler.parser import Scanner
from squirrel_compiler.codegen import scan_bare_return_type_text
from squirrel_compiler.driver.file_paths import module_path_for


def build_bare_function_returns(sqrrl_files: List[String]) raises -> Dict[String, String]:
    """Top-level function name -> its return-type text (relation-stripped
    -- see `scan_bare_return_type_text`'s own doc comment), for *every*
    top-level `def funcName(...) -> <ReturnType>:` signature project-wide
    (a def's own signature is assumed to fit on one line) -- mandatory
    marking dropped: a function's own name no longer signals "returns an
    entity-shaped value" at all, only whether it needs `sqrrl___world`
    (`@@@`, still required for that -- world-marking is a separate,
    unchanged axis). A function's return type can be anything at all now
    -- plain, entity, or a container of either -- discovered here
    unconditionally regardless of marking, the same "always register,
    harmless" reasoning `PLAIN_VAR_DECL` already uses elsewhere: a direct
    chain off any such function's own call result (`get_dept(@@alice).
    name`, no intermediate variable), or a direct `for`/var-decl binding,
    resolves through this one map either way (`BARE_CALL_CHAIN`/
    `BARE_ROOTED_CHAIN`/`PLAIN_VAR_DECL`'s own inferred branch, all
    already built and already type-agnostic).

    A plain `@@` (two `@`s, no world) on a top-level function's own name
    is no longer a valid spelling at all -- it used to mean "returns an
    entity, doesn't need world," which is now just... bare. Rejected here
    with a migration message rather than silently accepted or left to
    surface as a confusing downstream error."""
    var out = Dict[String, String]()
    for path in sqrrl_files:
        var f = open(path, "r")
        var source = f.read()
        f.close()
        var bytes = source.as_bytes()
        var sc = Scanner(source)
        while True:
            sc.skip_trivia()
            if sc.at_end():
                break
            var is_world_marked = sc.starts_with("def @@@")
            var is_entity_marked = sc.starts_with("def @@") and not is_world_marked
            var is_bare = sc.starts_with("def ") and not sc.starts_with("def @@")
            if is_world_marked or is_entity_marked or is_bare:
                var line_start = sc.pos
                var line_end = line_start
                while line_end < len(bytes) and bytes[line_end] != UInt8(ord("\n")):
                    line_end += 1
                # Top-level only -- an indented `def` is a method inside
                # some struct's own body (`@@struct`, or a hand-written
                # plain struct), never a genuinely bare top-level
                # function; registering it *here* too, in this flat,
                # receiver-unaware map, is a real collision risk once two
                # different structs happen to declare a same-named method
                # (confirmed via a real compile: `Widget.clone()` and
                # `Address.clone()` collided, last-scanned-wins, and a
                # completely unrelated call silently used the wrong
                # one's return type) -- a method's own return type
                # belongs in `bare_method_returns`/`build_plain_struct_
                # bare_method_returns` instead, correctly scoped per
                # struct name, never here.
                var back = line_start
                while back > 0 and bytes[back - 1] != UInt8(ord("\n")):
                    back -= 1
                var is_top_level = back == line_start
                if is_top_level:
                    var line_sc = Scanner(String(source[byte = line_start : line_end]))
                    _ = line_sc.try_consume("def ")
                    if is_world_marked:
                        _ = line_sc.try_consume("@@@")
                    elif is_entity_marked:
                        _ = line_sc.try_consume("@@")
                    var func_name = line_sc.scan_ident()
                    if is_entity_marked:
                        raise Error(
                            "InvalidSquirrelSyntax: "
                            + path
                            + ": '@@"
                            + func_name
                            + "' -- '@@' marking on a function's own name is"
                            " no longer used or needed; write it bare ('"
                            + func_name
                            + "(...)'), or '@@@"
                            + func_name
                            + "(...)' if it also needs 'sqrrl___world'"
                        )
                    var raw_type = scan_bare_return_type_text(
                        String(line_sc.source[byte = line_sc.pos : line_sc.source.byte_length()])
                    )
                    if func_name.byte_length() > 0 and raw_type:
                        out[func_name] = raw_type.value()
                sc.pos = line_end
                continue
            sc.pos += 1
    return out^


def build_function_symbols(sqrrl_files: List[String], target_root: String) raises -> Dict[String, String]:
    """`sqrrl__<name>` (a top-level `@@`/`@@@`-marked function's own
    generated name -- the same `sqrrl_prefixed` spelling both a
    definition and a call site always get, `rewrite_field_access.mojo`'s
    `handle_func_call_marker`) -> the module that declares it, for every
    marked top-level function project-wide. Gives a cross-file call
    (`@@@make_vendor(...)` declared in one file, called from another) the
    same automatic-import treatment `build_entity_symbols` already gives
    every `@@struct`'s own wrapper type -- merged into the very same
    `entity_symbols`/`cross_file_symbols` map in `convert_directory.mojo`,
    so `emit_file`'s existing "scan my own transformed text for whichever
    of these symbols actually appear, import the ones that do" mechanism
    (`driver/emit_file.mojo`) needs no changes at all to also cover
    functions.

    A bare (unmarked) function is deliberately excluded: its own
    generated name carries no `sqrrl__` prefix, so auto-importing by
    scanning for a plain word match would risk colliding with an
    unrelated identifier (a stdlib name, a local variable) that merely
    happens to share the same short, common spelling -- the `sqrrl__`
    prefix is exactly what makes this scan-for-symbol mechanism safe for
    a marked function/struct in the first place."""
    var symbol_of = Dict[String, String]()
    for path in sqrrl_files:
        var module_path = module_path_for(path, target_root)
        var f = open(path, "r")
        var source = f.read()
        f.close()
        var bytes = source.as_bytes()
        var sc = Scanner(source)
        while True:
            sc.skip_trivia()
            if sc.at_end():
                break
            var is_world_marked = sc.starts_with("def @@@")
            var is_entity_marked = sc.starts_with("def @@") and not is_world_marked
            if is_world_marked or is_entity_marked:
                var line_start = sc.pos
                var line_end = line_start
                while line_end < len(bytes) and bytes[line_end] != UInt8(ord("\n")):
                    line_end += 1
                var line_sc = Scanner(String(source[byte = line_start : line_end]))
                _ = line_sc.try_consume("def ")
                if is_world_marked:
                    _ = line_sc.try_consume("@@@")
                else:
                    _ = line_sc.try_consume("@@")
                var func_name = line_sc.scan_ident()
                if func_name.byte_length() > 0:
                    symbol_of["sqrrl__" + func_name] = module_path
                sc.pos = line_end
                continue
            sc.pos += 1
    return symbol_of^


def discover_raw_imports(sqrrl_files: List[String]) raises -> Dict[String, String]:
    """Every project-wide `from <module> import <name>[, <name>...]`
    line's own *raw*, hand-written text (a `.mojo.sqrrl` file is free to
    mix DSL declarations with plain pass-through import lines; a def's
    own signature is assumed to fit on one line, and so is an import) --
    imported symbol name -> the module it's imported from. Last import
    wins if the same name is somehow imported from two different modules
    project-wide (not expected in practice).

    The one consumer this exists for: a *custom container wrapper*'s own
    JSON escape-hatch companions (`sqrrl__<Wrapper>_json_to_pairs`/`_from_
    pairs`/etc., `driver/json_module.mojo`) are hand-written raw Mojo the
    compiler never parses a declaration for at all -- unlike a real
    `@@struct`/plain struct's own `module_of` map, there's no way to know
    a custom wrapper's *true* defining module just from discovery. Before
    this existed, `json_module.mojo` fell back to "whichever struct's own
    field first referenced the wrapper," assuming *that* file happened to
    also import the escape-hatch functions itself (fragile: a schema file
    declaring `@@field: Grid[K, @@V]` had to import `sqrrl__Grid_json_to_
    pairs`/`_from_pairs` too, even though it never calls either). Scanning
    for whichever file already imports the escape-hatch functions
    *directly* (typically wherever the wrapper's actually constructed,
    which already needs that import regardless) finds the true module
    without ever reading the hand-written `.mojo` file itself."""
    var out = Dict[String, String]()
    for path in sqrrl_files:
        var f = open(path, "r")
        var source = f.read()
        f.close()
        var bytes = source.as_bytes()
        var n = len(bytes)
        var line_start = 0
        while line_start < n:
            var line_end = line_start
            while line_end < n and bytes[line_end] != UInt8(ord("\n")):
                line_end += 1
            var line = String(String(source[byte = line_start : line_end]).strip())
            if line.startswith("from "):
                var import_idx = line.find(" import ")
                if import_idx >= 0:
                    var module = String(String(line[byte = 5 : import_idx]).strip())
                    var names_part = String(line[byte = import_idx + 8 : line.byte_length()])
                    var name_bytes = names_part.as_bytes()
                    var name_n = len(name_bytes)
                    var name_start = 0
                    for i in range(name_n + 1):
                        if i == name_n or name_bytes[i] == UInt8(ord(",")):
                            var name = String(String(names_part[byte = name_start : i]).strip())
                            if name.byte_length() > 0:
                                out[name] = module
                            name_start = i + 1
            line_start = line_end + 1
    return out^


def check_single_world_scope_call(sqrrl_files: List[String]) raises:
    """Rejects more than one `@@:` across the whole project -- `@@:` is the
    single point that brings `sqrrl___world` into scope for a whole script.

    Verbatim port from rw_squirrel_2."""
    var declare_sites = List[String]()
    for path in sqrrl_files:
        var f = open(path, "r")
        var source = f.read()
        f.close()

        var sc = Scanner(source)
        while sc.find_next_world_scope_call():
            _ = sc.parse_world_scope()
            declare_sites.append(path)

    if len(declare_sites) > 1:
        var files = String()
        for i in range(len(declare_sites)):
            if i > 0:
                files += ", "
            files += declare_sites[i]
        raise Error(
            "InvalidSquirrelSyntax: @@: used "
            + String(len(declare_sites))
            + " times across the project ("
            + files
            + ") -- it should appear exactly once (typically in the"
            " entry point); thread the result to every other function via"
            " '@@' in its parameters instead of opening @@: again"
        )


def uses_json_entry_point(generated: String) -> Bool:
    """True if `generated` (a file's own already-*rewritten* Mojo output,
    from `emit_file`) actually calls one of the whole-world JSON entry
    points -- checking the *rewritten* call-site text (`sqrrl___begin_init_
    from_json(`/`sqrrl___init_from_json(`/`sqrrl___end_init_from_json(`/
    `sqrrl___world_to_json(`, exactly what `codegen/rewrite.mojo`'s four
    JSON `MarkerKind` branches each emit) rather than scanning raw `.mojo.
    sqrrl` source for the `@@@`-marked spelling, so this is a precise
    per-file check with no risk of a false match inside a comment/string --
    these are real generated identifiers, never written by a DSL author.

    Drives whether `sqrrl__json.mojo` gets generated at all (`convert_
    directory.mojo`) and whether a given file imports its four symbols
    (`emit_file.mojo`) -- a project that never calls whole-world JSON
    anywhere shouldn't be forced to make every field JSON-parseable just
    because `sqrrl__json.mojo` was generated unconditionally (real gap,
    found and fixed after `@@container` support already made "every field
    must be JSON-parseable" a much easier restriction to hit by accident)."""
    return (
        "sqrrl___begin_init_from_json(" in generated
        or "sqrrl___init_from_json(" in generated
        or "sqrrl___end_init_from_json(" in generated
        or "sqrrl___world_to_json(" in generated
    )


def project_uses_json(sqrrl_files: List[String]) raises -> Bool:
    """True if *any* file project-wide touches JSON at all -- scans each
    file's own *raw* `.mojo.sqrrl` source (before any transformation) for
    one of the three DSL-level markers (`@@@to_json`/`@@@begin_init_from_
    json`/`@@@init_from_json` -- `@@@end_init_from_json` never appears
    without a paired `@@@begin_init_from_json` in valid source, already
    enforced elsewhere, so checking it separately would be redundant).

    Deliberately a *different*, earlier check than `uses_json_entry_
    point` (which looks at each file's own already-*rewritten* text) --
    this one has to run *before* `emit_file`/`transform_source` do,
    because its own result (whether `codegen/entity.mojo`'s `emit_entity`
    adds `sqrrl___JsonSerializable` conformance to a struct it's *currently
    emitting*) can't wait for `emit_file`'s own output to exist yet. A
    plain substring scan over raw source risks a false match inside a
    comment/string in principle, but the failure mode is only ever "the
    trait gets included even though nothing needed it" -- conservative,
    never a silent miscompile, matching the same reasoning `_collect_
    dispatch_types`'s own doc comment in `driver/json_module.mojo` uses
    for a different check."""
    for path in sqrrl_files:
        var f = open(path, "r")
        var source = f.read()
        f.close()
        if "@@@to_json" in source or "@@@begin_init_from_json" in source or "@@@init_from_json" in source:
            return True
    return False
