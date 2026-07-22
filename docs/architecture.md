# Architecture

`squirrelc` (built from `src/main.mojo`) walks a target directory and, for
every `.mojo.sqrrl` file it finds, writes a plain `.mojo` file alongside it.
It also writes two project-wide files (`sqrrl__world.mojo`, and
`sqrrl__json.mojo` if the project uses JSON) and copies `squirrel_runtime`
in. The whole thing is deterministic and stateless — no incremental
compilation, no caching; every run re-emits everything (see
`convert_directory.mojo`'s own doc comment for why this is a deliberate
choice, not a gap).

## Pipeline (`driver/convert_directory.mojo`)

1. **Enumerate** every `.mojo.sqrrl` file under the target root
   (`file_paths.find_sqrrl_files`).
2. **Discover** (`driver/discovery.mojo`) — parse every `@@struct` and every
   hand-written plain struct declaration project-wide, without emitting
   anything yet. Produces the struct/field lists plus a `name -> declaring
   module` map for each.
3. **Check** — reject a cyclic relation graph (`driver/cycles.mojo`, walking
   `analysis/relation_targets.mojo`'s shared "what does this field list
   reach" traversal) and reject more than one `@@:`/`@@@:` project-wide
   (`misc_builders.check_single_world_scope_call`).
4. **Build project-wide maps** — one small, focused builder per concern
   (`build_relation_schema`, `build_unique_fields`, `build_multi_fields`,
   `build_bare_function_returns`, `build_bare_method_returns`,
   `build_entity_symbols`, `build_function_symbols`, `discover_raw_imports`,
   ...), each scanning either the parsed struct list or every file's own raw
   text once. These are the tables the rewrite engine consults to know what
   a given name actually means, marked or bare alike.
5. **Emit `sqrrl__world.mojo`** (`driver/world_module.mojo`) — the
   `sqrrl___World` struct (one table field per entity) and the
   leak-checking `sqrrl__check_no_leaks`.
6. **Transform each file** (`driver/emit_file.mojo` → `codegen/transform_
   source`) — the actual rewrite pass, described below.
7. **Emit `sqrrl__json.mojo`** (`driver/json_module.mojo`), only if some
   file in the project actually touches a whole-world JSON entry point.
8. **Write everything out**, and copy `squirrel_runtime` into the target
   root.

## The rewrite engine (`codegen/`)

This is the part that turns DSL syntax into real Mojo, one file at a time.
It never builds a full AST of the *script* body (only of `@@struct`
declarations themselves, via the parser) — instead it scans source text
left to right, stops at the next `@@`-relevant marker
(`codegen/rewrite.mojo`'s `find_next_marker`), copies everything before it
through completely untouched, and hands the marker itself off to a
per-`MarkerKind` handler.

- **`rewrite_field_access.mojo`** is the biggest piece: `_walk_access_chain`
  resolves a whole `@@x.field[key].method().field` chain hop by hop, tracking
  what type each hop lands on so the next hop can be resolved against it.
  This is also where a table-level call
  (`@@@Employee.for_years_employed_greater_than(3)`), a marked function/
  method call, and a for-loop's own entity-marking guard all live.
- **`helpers.mojo`** holds the structural predicates everything else is
  built from — `is_directly_entity_reachable` (does a type's own shape make
  a relation reachable through indexing/iteration), `container_element_of`/
  `container_index_result_of` (what iterating/indexing a container-shaped
  type yields), `is_relation_field`. These are deliberately keyed on shape
  (argument count and position), never on a specific wrapper's name — a
  hand-written two-argument container gets identical treatment to `Dict`
  with no special-casing.
- **`entity.mojo`** emits each `@@struct`'s own generated code: the
  `...Inner`/handle/`...Table` triple, `create`/`all`/`count`, and every
  modifier-driven method from the [syntax reference](syntax-reference.md)'s
  table.
- **`rewrite_context.mojo`** bundles all the project-wide maps together and
  gives each function/method its own fresh, scoped view of local variable
  types as the rewrite walks through it.

## Runtime (`squirrel_runtime/`)

Copied verbatim into every generated project — this is what the generated
code actually calls at runtime, not something squirrelc emits fresh each
time.

- **`id_allocator.mojo`** — `IdAllocator`: allocates/frees opaque `UInt32`
  ids, tracks liveness (`live: List[Bool]`) and a free list for reuse.
- **`entity_storage.mojo`** — `EntityStorage`: one per entity, wraps an
  `IdAllocator` plus weak-reference tracking (so a dangling handle can be
  detected rather than silently reading freed memory) and the `keepalive`
  strong-hold `Dict`.
- **`index.mojo`** — `PlainIndex`/`UniqueIndex`/`MultiIndex`/`OrderedIndex`,
  the backing structures behind `indexed`/`unique`/`multi`/`ordered` field
  modifiers respectively.
- **`json.mojo`** — the scanner/writer primitives (`sqrrl___JsonScanner`,
  string/bool literal helpers, the generic `List`/`Set`/`Optional`/`Dict`
  to/from-list conversion helpers) that generated `sqrrl__json.mojo` code
  calls into.

## Design principle worth knowing

Nearly every non-trivial fix in this project's history came from widening a
*shape-based* predicate (argument count/position) rather than adding a
special case for a specific type name. `is_directly_entity_reachable`
covering a two-argument wrapper's second position, `container_element_of`
vs. `container_index_result_of` splitting iteration from indexing
semantics, `_plain_struct_base_names` walking every argument position
instead of just the first — all the same move, applied wherever a new gap
turned up. When extending this compiler, prefer that direction over adding
`if wrapper_name == "SomeSpecificType"` anywhere.
