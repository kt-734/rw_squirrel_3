from squirrel_compiler.parser import Scanner
from squirrel_compiler.codegen import scan_entity_return_shape, scan_bare_return_type_text
from squirrel_compiler.driver.file_paths import module_path_for


def build_function_returns(sqrrl_files: List[String]) raises -> Dict[String, String]:
    """Function name -> the `@@Type` (or `Container[@@Type]`, encoded via
    `scan_entity_return_shape`) it returns, for *every* top-level `def
    funcName(...) -> <ReturnType>:` signature project-wide (a def's own
    signature is assumed to fit on one line) -- mandatory-marking
    milestone: any function whose return type involves an `@@`-marked
    value must mark its own name too, `@@` if it doesn't also need
    `sqrrl___world`, `@@@` if it does (never both) -- so this scans and
    cross-validates *every* marking of a top-level `def`, not just
    world-marked ones, raising a real `InvalidSquirrelSyntax` the moment a
    mismatch is found (over-marked: `@@`-marked but doesn't actually
    return an `@@`-marked value; under-marked: returns one but isn't
    marked at all) -- enforced here, once, at signature-scan time, rather
    than left to surface later as a confusing "isn't a registered
    function" error at some arbitrary call site.

    This mandatory marking is what makes `rewrite_field_access.mojo`'s own
    `handle_func_call_marker` able to resolve a *direct* access-chain off
    a call's own return value at all (`@@get_dept(@@alice).name`, no
    intermediate variable, no `for` loop) -- the call itself is now always
    a real, unambiguous marker position the scanner stops at, never a
    bare (unmarked) identifier it could never have stopped at regardless
    of how this map were built.

    A `def @@@funcName(...)` (three `@`s) is call-site/method-splicing's
    own `WORLD_FUNC` shape (needs `sqrrl___world`); `def @@funcName(...)`
    (exactly two `@`s) is `ENTITY_FUNC`'s (doesn't); a fully bare `def
    funcName(...)` must return a plain, non-`@@` value, or this raises.

    Adapted from rw_squirrel_2's own scanning shape -- the mandatory-
    marking cross-validation itself is new, only ever scanning raw source
    text, same as before."""
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
                var line_sc = Scanner(String(source[byte = line_start : line_end]))
                _ = line_sc.try_consume("def ")
                if is_world_marked:
                    _ = line_sc.try_consume("@@@")
                elif is_entity_marked:
                    _ = line_sc.try_consume("@@")
                var func_name = line_sc.scan_ident()
                var shaped_type = scan_entity_return_shape(
                    String(line_sc.source[byte = line_sc.pos : line_sc.source.byte_length()])
                )
                if func_name.byte_length() > 0:
                    if is_entity_marked and not shaped_type:
                        raise Error(
                            "InvalidSquirrelSyntax: "
                            + path
                            + ": '@@"
                            + func_name
                            + "' is marked '@@' but doesn't return an"
                            " '@@'-marked value -- '@@' only marks a"
                            " function that does; remove the '@@' marking"
                        )
                    if is_bare and shaped_type:
                        raise Error(
                            "InvalidSquirrelSyntax: "
                            + path
                            + ": '"
                            + func_name
                            + "' returns an '@@'-marked value but isn't"
                            " itself marked -- write '@@"
                            + func_name
                            + "(...)' (or '@@@"
                            + func_name
                            + "(...)' if it also needs 'sqrrl___world')"
                        )
                    if shaped_type:
                        out[func_name] = shaped_type.value()
                sc.pos = line_end
                continue
            sc.pos += 1
    return out^


def build_bare_plain_function_returns(sqrrl_files: List[String]) raises -> Dict[String, String]:
    """Bare (never `@@`/`@@@`-marked) top-level function name -> its raw,
    unstripped return-type text, for every `def funcName(...) -> <Type>:`
    signature project-wide whose own name carries no marking at all --
    the counterpart `build_function_returns` doesn't track: a bare
    function's return type is allowed to be anything at all (mandatory
    marking only requires marking when the return is entity-*shaped*),
    including a plain struct or a container of one, but until now
    nothing recorded what that type actually *is* -- so a direct chain
    off such a function's own call result (`make_note(@@b).@@ref.name`,
    no intermediate variable) or a direct `for` loop over one (`for n in
    get_notes():`) had no way to resolve, the bare-call analogue of
    `PLAIN_VAR_DECL`'s own "no explicit signal, no registration" gap for
    named variables.

    Registers unconditionally, regardless of whether the return type
    turns out to be a plain struct/container of one at all (`-> Int`
    included) -- the exact same "always register, harmless" reasoning
    `PLAIN_VAR_DECL` already uses: the consumer checks `plain_struct_
    names`/`is_container_type` before ever acting on an entry, so an
    irrelevant one is just dead, unused data."""
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
            if sc.starts_with("def ") and not sc.starts_with("def @@"):
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
                    var func_name = line_sc.scan_ident()
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
