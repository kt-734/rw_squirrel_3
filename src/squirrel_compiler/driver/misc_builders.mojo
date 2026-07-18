from squirrel_compiler.parser import Scanner
from squirrel_compiler.codegen import encode_container_type


def build_function_returns(sqrrl_files: List[String]) raises -> Dict[String, String]:
    """Function name -> the `@@Type` it returns, for every `def @@@funcName(
    ...) -> @@Type:` signature project-wide (a def's own signature is
    assumed to fit on one line). Also recognizes the container form,
    `-> Container[@@Type]:`. Only the function name's own marking is `@@@`
    (M3 addendum: a top-level function needing `sqrrl__world`) -- the
    return type is still plain `@@`, unaffected (`RETURN_TYPE` never needed
    `sqrrl__world` to begin with).

    Adapted from rw_squirrel_2 -- otherwise unaffected by the storage
    redesign, this only ever scans raw source text."""
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
            if sc.starts_with("def @@@"):
                var line_start = sc.pos
                var line_end = line_start
                while line_end < len(bytes) and bytes[line_end] != UInt8(ord("\n")):
                    line_end += 1
                var line_sc = Scanner(String(source[byte = line_start : line_end]))
                _ = line_sc.try_consume("def ")
                _ = line_sc.try_consume("@@@")
                var func_name = line_sc.scan_ident()
                var found_arrow = False
                while not line_sc.at_end():
                    if line_sc.try_consume("->"):
                        found_arrow = True
                        break
                    line_sc.pos += 1
                if found_arrow:
                    line_sc.skip_trivia()
                    if line_sc.try_consume("@@"):
                        var ret_type = line_sc.scan_ident()
                        if ret_type.byte_length() > 0 and func_name.byte_length() > 0:
                            out[func_name] = ret_type
                    else:
                        var wrapper = line_sc.scan_ident()
                        line_sc.skip_trivia()
                        if wrapper.byte_length() > 0 and line_sc.try_consume("["):
                            line_sc.skip_trivia()
                            if line_sc.try_consume("@@"):
                                var ret_type = line_sc.scan_ident()
                                line_sc.skip_trivia()
                                if ret_type.byte_length() > 0 and func_name.byte_length() > 0:
                                    if line_sc.try_consume("]"):
                                        out[func_name] = encode_container_type(wrapper, ret_type)
                                    elif line_sc.try_consume(","):
                                        var depth = 1
                                        while depth > 0 and not line_sc.at_end():
                                            if line_sc.peek() == UInt8(ord("[")):
                                                depth += 1
                                            elif line_sc.peek() == UInt8(ord("]")):
                                                depth -= 1
                                            line_sc.pos += 1
                                        if depth == 0:
                                            out[func_name] = encode_container_type(wrapper, ret_type)
                sc.pos = line_end
                continue
            sc.pos += 1
    return out^


def check_single_world_scope_call(sqrrl_files: List[String]) raises:
    """Rejects more than one `@@:` across the whole project -- `@@:` is the
    single point that brings `sqrrl__world` into scope for a whole script.

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
    points -- checking the *rewritten* call-site text (`sqrrl__begin_init_
    from_json(`/`sqrrl__init_from_json(`/`sqrrl__end_init_from_json(`/
    `sqrrl__world_to_json(`, exactly what `codegen/rewrite.mojo`'s four
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
        "sqrrl__begin_init_from_json(" in generated
        or "sqrrl__init_from_json(" in generated
        or "sqrrl__end_init_from_json(" in generated
        or "sqrrl__world_to_json(" in generated
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
    adds `sqrrl__JsonSerializable` conformance to a struct it's *currently
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
