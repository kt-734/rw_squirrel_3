from std.os.path import join, dirname

from squirrel_compiler.driver.file_paths import (
    find_sqrrl_files,
    mojo_output_path,
    mojo_impl_output_path,
    module_path_for,
    output_module_prefix_for,
)
from squirrel_compiler.driver.discovery import (
    discover_structs,
    resolve_struct_inheritance,
    check_key_groups_after_inheritance,
    build_struct_fields,
    build_struct_key_groups,
    build_struct_method_bodies,
    build_struct_names,
    build_relation_schema,
    build_unique_fields,
    build_indexed_fields,
    build_multi_fields,
    build_ordered_fields,
    build_key_group_lookup_names,
    check_key_groups_dont_collide_with_fields,
    build_world_methods,
    build_bare_method_returns,
    build_plain_struct_bare_method_returns,
    build_stats_fields,
    build_entity_symbols,
    discover_plain_structs,
    build_plain_struct_names,
    build_plain_value_fields,
    check_plain_struct_names_disjoint,
)
from squirrel_compiler.driver.cycles import check_no_relation_cycles
from squirrel_compiler.driver.misc_builders import (
    build_bare_function_returns,
    build_function_symbols,
    check_single_world_scope_call,
    project_uses_json,
    discover_raw_imports,
)
from squirrel_compiler.driver.world_module import emit_world_module
from squirrel_compiler.driver.topo_order import topo_sort_structs
from squirrel_compiler.driver.json_module import emit_json_module
from squirrel_compiler.driver.emit_file import emit_file
from squirrel_compiler.driver.runtime_copy import ensure_init_files, copy_runtime
from squirrel_compiler.driver.entry_split import (
    file_has_top_level_main,
    struct_declaration_ranges,
    raw_import_line_ranges,
    mask_source,
    collapse_blank_runs,
)


def convert_directory(target_root: String) raises:
    """Walks `target_root` for `.mojo.sqrrl` files, writes a generated
    `.mojo` file alongside each one, and writes the project-wide
    `sqrrl__world.mojo`/`sqrrl__json.mojo`/`squirrel_runtime` next to
    whichever file has the literal top-level `def main(` -- `output_root`,
    computed below -- rather than always at `target_root` itself (see its
    own inline comment): `target_root` still anchors every generated
    module path (`-I <target_root> <entry>.mojo` stays the required
    invocation), but a project that nests its own `.mojo.sqrrl` files
    under a `src/` subdirectory gets all of squirrelc's own generated
    output grouped there too, instead of split between the project root
    and `src/`.

    Slimmed from rw_squirrel_2's own `convert_directory`: no
    `build_plain_struct_fields` (plain structs are still M2+ scope, not
    built), no JSON module (`build_json_module_source` -- M5), no per-file
    incremental-compile caching (`compute_signature`/`load_cached_signature`
    -- deliberately not building this, see memory) -- every run re-emits
    every file unconditionally. Still runs discovery, cycle-checking, and
    every project-wide map this milestone set needs (`struct_names`/
    `relation_schema`/`function_returns`/`unique_fields`/`indexed_fields`/
    `multi_fields`/`ordered_fields`/`entity_symbols`) the same way
    rw_squirrel_2 does, just a smaller set of them -- `entity_symbols`
    (`build_entity_symbols`) is what lets a relation field whose target is
    declared in a *different* `.mojo.sqrrl` file actually compile: `emit_file`
    imports whichever cross-file `sqrrl__<Name>` symbols its own transformed
    output actually references."""
    var sqrrl_files = find_sqrrl_files(target_root)
    var discovery = discover_structs(sqrrl_files, target_root)
    # Struct inheritance (`@@struct @@Name < @@Other:`) resolves first,
    # before anything else touches `discovery` -- every downstream
    # builder/check below reads `ds.parsed.fields`/`ds.parsed.key_groups`
    # directly, so once this mutates an inheriting struct's copy of those
    # in place, none of them need their own inheritance-awareness at all.
    resolve_struct_inheritance(discovery)
    check_key_groups_after_inheritance(discovery)
    var plain_struct_discovery = discover_plain_structs(sqrrl_files, target_root)
    var plain_struct_fields = plain_struct_discovery.fields.copy()

    # Read every source once, up front, and reuse it everywhere below --
    # both for deciding which files need splitting (this step) and for
    # the actual per-file emission further down -- rather than having
    # `emit_file` (or this function) re-read the same file from disk
    # more than once.
    var sources = Dict[String, String]()
    for path in sqrrl_files:
        var f = open(path, "r")
        sources[path] = f.read()
        f.close()

    # A file needs splitting (its own struct/table declarations moved
    # into a separate `<name>_impl` module, `<name>` itself reduced to
    # imports plus its own top-level script) exactly when it's a literal
    # `mojo run`/`mojo build` target (a top-level `def main(`) that also
    # declares at least one struct of its own -- nothing to split out
    # otherwise, so a script-only file (no structs at all) is left alone
    # rather than growing a pointless, empty `_impl` companion. See
    # `entry_split.mojo`'s own module doc comment for the compiler bug
    # this works around: compiling the *same* file as both the direct
    # entry point and a module `sqrrl__world.mojo`/`sqrrl__json.mojo`
    # import back gives Mojo two inconsistent identities for the types
    # it declares, corrupting generic-instantiation resolution for
    # `Variant`'s own dispatch methods (confirmed via a real, external
    # reproduction). Keyed by *module path*, not file path -- every
    # consumer below (`DiscoveredStruct.module_path`, `PlainStructDiscovery.
    # module_of`) already stores the dotted module path, not the file.
    var has_any_struct = Dict[String, Bool]()
    for ds in discovery.structs:
        has_any_struct[ds.module_path] = True
    for plain_name in plain_struct_discovery.module_of.keys():
        has_any_struct[plain_struct_discovery.module_of[String(plain_name)]] = True

    var needs_split = Dict[String, Bool]()
    # `sqrrl__world.mojo`/`sqrrl__json.mojo`/`squirrel_runtime` land next
    # to whichever file has the literal top-level `def main(` (the same
    # file `needs_split` cares about, real entity-declaring or not),
    # rather than always at `target_root` -- lets a project that puts
    # its own `.mojo.sqrrl` files under a `src/` subdirectory (`target_
    # root` itself still the project root, so `-I src src/main.mojo`'s
    # own module paths -- `src.main_impl` -- stay unaffected) get all of
    # squirrelc's generated output grouped there too, instead of
    # scattered between the project root and `src/`. Falls back to
    # `target_root` itself if no file has one at all (never expected in
    # practice -- `mojo run`/`build` needs *some* file to declare `main`
    # -- but this function has never required one either, so it stays
    # that lenient).
    var output_root = target_root
    for path in sqrrl_files:
        var own_module_path = module_path_for(path, target_root)
        var has_main = file_has_top_level_main(sources[path])
        if has_main:
            output_root = dirname(path)
        if own_module_path in has_any_struct and has_main:
            needs_split[own_module_path] = True
    var output_module_prefix = output_module_prefix_for(output_root, target_root)

    # Push the adjusted module path into `discovery`/`plain_struct_
    # discovery` *before* any downstream builder (`build_entity_symbols`,
    # `build_relation_schema`, ...) reads `module_path`/`module_of` --
    # every one of them, plus `emit_world_module`/`emit_json_module`/
    # `emit_file`'s own cross-file import scan, already derives its own
    # import lines purely from these two maps, so this one adjustment is
    # the only change any of them need to correctly import a split
    # file's own structs from its new `_impl` module instead.
    for i in range(len(discovery.structs)):
        if discovery.structs[i].module_path in needs_split:
            var impl_path = discovery.structs[i].module_path + "_impl"
            discovery.structs[i].module_path = impl_path
            discovery.module_of[discovery.structs[i].parsed.name] = impl_path
    for plain_name in plain_struct_discovery.module_of.keys():
        var name = String(plain_name)
        if plain_struct_discovery.module_of[name] in needs_split:
            plain_struct_discovery.module_of[name] = plain_struct_discovery.module_of[name] + "_impl"

    var struct_names = build_struct_names(discovery)
    var plain_struct_names = build_plain_struct_names(plain_struct_fields)
    check_plain_struct_names_disjoint(struct_names, plain_struct_names)
    check_no_relation_cycles(discovery, plain_struct_fields)
    check_single_world_scope_call(sqrrl_files)
    check_key_groups_dont_collide_with_fields(discovery)
    ensure_init_files(sqrrl_files, target_root)

    var relation_schema = build_relation_schema(discovery, plain_struct_fields)
    var bare_function_returns = build_bare_function_returns(sqrrl_files)
    var unique_fields = build_unique_fields(discovery)
    var indexed_fields = build_indexed_fields(discovery)
    var multi_fields = build_multi_fields(discovery)
    var ordered_fields = build_ordered_fields(discovery)
    var key_group_lookup_names = build_key_group_lookup_names(discovery)
    var struct_fields = build_struct_fields(discovery)
    var struct_key_groups = build_struct_key_groups(discovery)
    var struct_method_body = build_struct_method_bodies(discovery)
    var world_methods = build_world_methods(discovery)
    var bare_method_returns = build_bare_method_returns(discovery)
    # A plain struct's own bare methods are discovered separately (`plain_
    # struct_discovery`, not `discovery`'s own `@@struct`-only list) but
    # merge into the exact same map -- struct names are disjoint by
    # construction (`check_plain_struct_names_disjoint`, already run
    # above), so there's no key collision to resolve, just letting
    # `_handle_instance_call`'s plain-struct-owner branch consult the same
    # `ctx.bare_method_returns` a real `@@struct`'s own bare method
    # already does.
    var plain_struct_bare_method_returns = build_plain_struct_bare_method_returns(plain_struct_discovery)
    for struct_name in plain_struct_bare_method_returns.keys():
        bare_method_returns[String(struct_name)] = plain_struct_bare_method_returns[String(struct_name)].copy()
    var stats_fields = build_stats_fields(discovery)
    var plain_value_fields = build_plain_value_fields(discovery, plain_struct_fields)
    var entity_symbols = build_entity_symbols(discovery)
    # A plain struct's own bare name (never `sqrrl__`-prefixed) needs the
    # exact same cross-file import treatment as a real entity's `sqrrl__
    # <Name>` -- a plain struct used as a field's type in a *different*
    # file than the one declaring it (`schema/employee.mojo.sqrrl`'s
    # `profile: Profile`, declared in `schema/profile.mojo.sqrrl`) is just
    # as real a cross-file reference as a relation field's own target
    # type, but `build_entity_symbols` only ever walked `@@struct`
    # declarations -- every existing example happened to declare its
    # plain structs in the same file as whatever `@@struct` used them, so
    # this gap stayed latent until a real multi-file schema (the kitchen
    # sink example) exercised it.
    for plain_name in plain_struct_discovery.module_of.keys():
        entity_symbols[String(plain_name)] = plain_struct_discovery.module_of[String(plain_name)]
    # A cross-file `@@@`/`@@`-marked top-level function call needs the
    # exact same automatic import treatment -- merged into the very same
    # map, so `emit_file`'s existing symbol-scan-and-import mechanism
    # covers it with no changes of its own.
    var function_symbols = build_function_symbols(sqrrl_files, target_root)
    for func_symbol in function_symbols.keys():
        entity_symbols[String(func_symbol)] = function_symbols[String(func_symbol)]
    # A hand-written trait declared in a split file moves into that
    # file's own `_impl` module right alongside whatever `@@struct`
    # conforms to it (`struct_declaration_ranges` folds trait ranges in
    # alongside struct ones) -- but nothing else project-wide tracks a
    # trait's own name at all (traits were pure pass-through text before
    # this split existed), so it needs registering into `entity_symbols`
    # by hand here, the one place that actually knows.
    for path in sqrrl_files:
        var own_module_path = module_path_for(path, target_root)
        if own_module_path in needs_split:
            for r in struct_declaration_ranges(sources[path]):
                if r.name != "":
                    entity_symbols[r.name] = own_module_path + "_impl"

    var world_module = emit_world_module(discovery)
    var world_path = join(output_root, "sqrrl__world.mojo")
    var wf = open(world_path, "w")
    wf.write(world_module)
    wf.close()

    # Per-file output is computed *before* deciding whether to generate
    # `sqrrl__json.mojo` -- a project that never calls a whole-world JSON
    # entry point anywhere (`project_uses_json`, scanning every file's own
    # *raw* source up front -- has to run before `emit_file` does, since
    # its result now also gates `codegen/entity.mojo`'s own `sqrrl___
    # JsonSerializable` conformance while a struct is *being* emitted, not
    # just whether `sqrrl__json.mojo` gets written afterward) shouldn't be
    # forced to make every field JSON-parseable, or carry JSON-only
    # conformance on every entity, just because generation used to be
    # unconditional (real gap: any struct with a container field JSON
    # doesn't support -- `Dict[@@X,V]`, a custom container type -- used to
    # fail the *entire project's* conversion even when the script never
    # touched JSON at all). If genuinely unused project-wide, skip both
    # rather than half-supporting them.
    var json_used = project_uses_json(sqrrl_files)
    var out_paths = List[String]()
    var generated_files = List[String]()
    # One entry per *output* file, not per source -- a split source
    # produces two outputs, so this can't just be `sqrrl_files` itself
    # (kept parallel to `out_paths`/`generated_files` purely to label the
    # final "converted" printout with the real source path each output
    # came from).
    var source_paths = List[String]()
    for path in sqrrl_files:
        var own_module_path = module_path_for(path, target_root)
        var source = sources[path]
        if own_module_path in needs_split:
            # Split: the struct/table declarations move to `<name>_impl`
            # (`own_module_path + "_impl"`, matching the adjustment
            # already pushed into `discovery`/`plain_struct_discovery`
            # above), leaving `<name>` itself with only the original
            # top-level script -- `mask_source` keeps each half's own
            # line numbers exactly accurate (see its own doc comment),
            # so error positions in either half still point at the real
            # file.
            var ranges = struct_declaration_ranges(source)
            # The impl half also needs every raw, hand-written import line
            # kept (a struct's own field can reference a type from one,
            # e.g. a custom container wrapper's `from ring_module import
            # Ring`) -- the entry half needs no equivalent, since `mask_
            # source(..., keep=False)` already preserves everything
            # outside `ranges` verbatim, imports included.
            var impl_ranges = ranges.copy()
            for r in raw_import_line_ranges(source):
                impl_ranges.append(r)
            var impl_source = mask_source(source, impl_ranges, keep=True)
            var entry_source = mask_source(source, ranges, keep=False)
            var impl_module_path = own_module_path + "_impl"
            var impl_generated = emit_file(
                path, impl_source, impl_module_path, relation_schema, struct_names, unique_fields,
                indexed_fields, multi_fields, ordered_fields, world_methods, stats_fields, entity_symbols,
                key_group_lookup_names=key_group_lookup_names,
                struct_fields=struct_fields, struct_key_groups=struct_key_groups,
                struct_method_body=struct_method_body,
                plain_struct_names=plain_struct_names, plain_value_fields=plain_value_fields, json_used=json_used,
                bare_function_returns=bare_function_returns, bare_method_returns=bare_method_returns,
                output_module_prefix=output_module_prefix,
            )
            out_paths.append(mojo_impl_output_path(path))
            # Collapsed only *after* `emit_file`'s own transformation
            # (and any `InvalidSquirrelSyntax` it might have raised,
            # reporting a position against the still-uncollapsed, line-
            # count-preserving masked source) has already succeeded --
            # see `collapse_blank_runs`'s own doc comment for why the
            # ordering matters, not just the collapsing itself.
            generated_files.append(collapse_blank_runs(impl_generated))
            source_paths.append(path)
            var entry_generated = emit_file(
                path, entry_source, own_module_path, relation_schema, struct_names, unique_fields,
                indexed_fields, multi_fields, ordered_fields, world_methods, stats_fields, entity_symbols,
                key_group_lookup_names=key_group_lookup_names,
                struct_fields=struct_fields, struct_key_groups=struct_key_groups,
                struct_method_body=struct_method_body,
                plain_struct_names=plain_struct_names, plain_value_fields=plain_value_fields, json_used=json_used,
                bare_function_returns=bare_function_returns, bare_method_returns=bare_method_returns,
                output_module_prefix=output_module_prefix,
            )
            out_paths.append(mojo_output_path(path))
            generated_files.append(collapse_blank_runs(entry_generated))
            source_paths.append(path)
        else:
            var generated = emit_file(
                path, source, own_module_path, relation_schema, struct_names, unique_fields,
                indexed_fields, multi_fields, ordered_fields, world_methods, stats_fields, entity_symbols,
                key_group_lookup_names=key_group_lookup_names,
                struct_fields=struct_fields, struct_key_groups=struct_key_groups,
                struct_method_body=struct_method_body,
                plain_struct_names=plain_struct_names, plain_value_fields=plain_value_fields, json_used=json_used,
                bare_function_returns=bare_function_returns, bare_method_returns=bare_method_returns,
                output_module_prefix=output_module_prefix,
            )
            out_paths.append(mojo_output_path(path))
            generated_files.append(generated^)
            source_paths.append(path)

    if json_used:
        # All JSON-related generated code lives in this one dedicated file
        # (user's own non-negotiable notes.md constraint, M5) -- never
        # folded into emit_world_module/emit_file's own per-struct output.
        var topo_order = topo_sort_structs(discovery, relation_schema)
        var raw_imports = discover_raw_imports(sqrrl_files)
        var json_module = emit_json_module(
            discovery.structs, topo_order, plain_struct_discovery, raw_imports,
            output_module_prefix=output_module_prefix,
        )
        var json_path = join(output_root, "sqrrl__json.mojo")
        var jf = open(json_path, "w")
        jf.write(json_module)
        jf.close()

    var converted = 0
    for i in range(len(out_paths)):
        var f = open(out_paths[i], "w")
        f.write(generated_files[i])
        f.close()
        print(source_paths[i], "->", out_paths[i])
        converted += 1

    copy_runtime(output_root, import_prefix=output_module_prefix)
    print("Done:", converted, "file(s) converted.")
