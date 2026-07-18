from squirrel_compiler.driver.discovery import DiscoveryResult, DiscoveredStruct


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
        for target in relation_schema[name].values():
            if target in by_name:
                _visit_topo(target, relation_schema, by_name, visited, out)
    if name in by_name:
        out.append(by_name[name].copy())


def topo_sort_structs(
    discovery: DiscoveryResult, relation_schema: Dict[String, Dict[String, String]]
) raises -> List[DiscoveredStruct]:
    """Every struct ordered so it comes after every struct its own relation
    fields target -- what JSON reconstruction needs (`handle_for(id)` only
    works once the target id is already live) and `sqrrl__world_to_json`
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
