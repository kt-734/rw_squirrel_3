from squirrel_compiler.parser import parse_type_expr, TypeExpr
from squirrel_compiler.driver.discovery import DiscoveryResult, DiscoveredStruct


def _relation_schema_target_base_name(target: String) -> String:
    """`relation_schema[name][field]`'s own stored value is `render_
    relation_stripped` text -- the *whole* container shape for a wrapped
    relation field (`List[@@Person]` -> `"List[Person]"`, `Optional[
    @@Employee]` -> `"Optional[Employee]"`), not just the bare target
    name a *bare* relation field's entry already is (`"Department"`).
    Unwraps down to that innermost bare name either way -- what actually
    needs to exist in `by_name` for `_visit_topo` to find the edge at
    all. Missing this unwrap was a real, confirmed bug (not just an
    edge case): `target in by_name` is trivially always `False` for a
    wrapped value, since `by_name` is keyed by bare struct names only --
    silently dropping the dependency edge entirely for *any* relation
    field wrapped in a container, letting a struct sort before a target
    it only ever reaches that way (`Team`'s own `lead: Assignment`
    embedding `@@person: @@Person` is *also* directly reachable via
    `@@members: List[@@Person]` -- itself wrapped, so *that* edge was
    silently dropped too) -- confirmed via a real crash during reload
    (`EntityStorage.handle_for: id is no longer live`) once a large
    enough project (the kitchen-sink example) had a struct whose only
    live dependency edges were wrapped ones."""
    var t = parse_type_expr(target)
    while t.is_parameterized():
        t = t.arg(0).copy()
    return t.name


def _visit_topo(
    name: String,
    relation_schema: Dict[String, Dict[String, String]],
    by_name: Dict[String, DiscoveredStruct],
    mut visited: Dict[String, Bool],
    mut out: List[DiscoveredStruct],
) raises:
    if name in visited:
        return
    visited[name] = True
    if name in relation_schema:
        # Sorted field names, not raw `Dict.values()` iteration order --
        # a struct with 2+ relation fields targeting different structs
        # would otherwise visit its own targets in a hash-seed-dependent
        # order from one compiler run to the next, producing a
        # *different*, but equally "valid" (no cycle exists either way),
        # topo order/dump-key order each time -- reproducibility, not a
        # correctness requirement on its own (unlike the unwrap in
        # `_relation_schema_target_base_name` above, which *is*).
        var field_names = List[String]()
        for k in relation_schema[name].keys():
            field_names.append(String(k))
        sort(field_names)
        for field_name in field_names:
            var target = _relation_schema_target_base_name(relation_schema[name][field_name])
            if target in by_name:
                _visit_topo(target, relation_schema, by_name, visited, out)
    if name in by_name:
        out.append(by_name[name].copy())


def topo_sort_structs(
    discovery: DiscoveryResult, relation_schema: Dict[String, Dict[String, String]]
) raises -> List[DiscoveredStruct]:
    """Every struct ordered so it comes after every struct its own relation
    fields target -- what JSON reconstruction needs (`handle_for(id)` only
    works once the target id is already live) and `sqrrl___world_to_json`
    reuses too, so a dump's own top-level key order is always safe to
    reload directly (M5's whole-world JSON, `driver/json_module.mojo`).
    Plain postorder DFS over the project-wide relation graph --
    `check_no_relation_cycles` (`driver/cycles.mojo`) already guarantees
    the graph is acyclic before this ever runs, so unlike that module's own
    DFS, no in-progress/done bookkeeping is needed here to detect one."""
    var by_name = Dict[String, DiscoveredStruct]()
    for ds in discovery.structs:
        by_name[ds.parsed.name] = ds.copy()

    var visited = Dict[String, Bool]()
    var out = List[DiscoveredStruct]()
    for ds in discovery.structs:
        _visit_topo(ds.parsed.name, relation_schema, by_name, visited, out)
    return out^
