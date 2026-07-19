from std.os.path import join

from squirrel_compiler.driver.file_paths import find_sqrrl_files, mojo_output_path, module_path_for
from squirrel_compiler.driver.discovery import (
    discover_structs,
    build_struct_names,
    build_relation_schema,
    build_unique_fields,
    build_indexed_fields,
    build_multi_fields,
    build_ordered_fields,
    build_world_methods,
    build_method_returns,
    build_stats_fields,
    build_entity_symbols,
    discover_plain_structs,
    build_plain_struct_names,
    build_plain_value_fields,
    check_plain_struct_names_disjoint,
)
from squirrel_compiler.driver.cycles import check_no_relation_cycles
from squirrel_compiler.driver.misc_builders import build_function_returns, check_single_world_scope_call, project_uses_json
from squirrel_compiler.driver.world_module import emit_world_module
from squirrel_compiler.driver.topo_order import topo_sort_structs
from squirrel_compiler.driver.json_module import emit_json_module
from squirrel_compiler.driver.emit_file import emit_file
from squirrel_compiler.driver.runtime_copy import ensure_init_files, copy_runtime


def convert_directory(target_root: String) raises:
    """Walks `target_root` for `.mojo.sqrrl` files, writes a generated
    `.mojo` file alongside each one, writes the project-wide
    `sqrrl__world.mojo`, and writes `squirrel_runtime` into `target_root`.

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
    var plain_struct_discovery = discover_plain_structs(sqrrl_files, target_root)
    var plain_struct_fields = plain_struct_discovery.fields.copy()
    var struct_names = build_struct_names(discovery)
    var plain_struct_names = build_plain_struct_names(plain_struct_fields)
    check_plain_struct_names_disjoint(struct_names, plain_struct_names)
    check_no_relation_cycles(discovery, plain_struct_fields)
    check_single_world_scope_call(sqrrl_files)
    ensure_init_files(sqrrl_files, target_root)

    var relation_schema = build_relation_schema(discovery, plain_struct_fields)
    var function_returns = build_function_returns(sqrrl_files)
    var unique_fields = build_unique_fields(discovery)
    var indexed_fields = build_indexed_fields(discovery)
    var multi_fields = build_multi_fields(discovery)
    var ordered_fields = build_ordered_fields(discovery)
    var world_methods = build_world_methods(discovery)
    var method_returns = build_method_returns(discovery)
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

    var world_module = emit_world_module(discovery)
    var world_path = join(target_root, "sqrrl__world.mojo")
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
    for path in sqrrl_files:
        var out_path = mojo_output_path(path)
        var own_module_path = module_path_for(path, target_root)
        var generated = emit_file(
            path, own_module_path, relation_schema, struct_names, function_returns, unique_fields,
            indexed_fields, multi_fields, ordered_fields, world_methods, stats_fields, entity_symbols,
            plain_struct_names, plain_value_fields, json_used, method_returns=method_returns
        )
        out_paths.append(out_path)
        generated_files.append(generated^)

    if json_used:
        # All JSON-related generated code lives in this one dedicated file
        # (user's own non-negotiable notes.md constraint, M5) -- never
        # folded into emit_world_module/emit_file's own per-struct output.
        var topo_order = topo_sort_structs(discovery, relation_schema)
        var json_module = emit_json_module(discovery.structs, topo_order, plain_struct_discovery)
        var json_path = join(target_root, "sqrrl__json.mojo")
        var jf = open(json_path, "w")
        jf.write(json_module)
        jf.close()

    var converted = 0
    for i in range(len(sqrrl_files)):
        var f = open(out_paths[i], "w")
        f.write(generated_files[i])
        f.close()
        print(sqrrl_files[i], "->", out_paths[i])
        converted += 1

    copy_runtime(target_root)
    print("Done:", converted, "file(s) converted.")
