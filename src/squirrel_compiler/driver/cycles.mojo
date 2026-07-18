from squirrel_compiler.parser import ParsedStruct, Field
from squirrel_compiler.driver.discovery import DiscoveryResult
from squirrel_compiler.analysis import collect_relation_targets


def _relation_targets(
    fields: List[Field], plain_struct_fields: Dict[String, List[Field]]
) raises -> List[String]:
    """A field is a graph edge when it's a relation field (bare `@@Type`,
    or a `@@container` -- `is_relation_field`) -- and, since a relation
    field's target can itself be a hand-written plain struct (plain-structs
    milestone), an edge running *through* one of its own relation fields
    too, direct or transitive (`collect_relation_targets`, shared with
    `driver/json_module.mojo`'s own sibling-table computation)."""
    var seen = Dict[String, Bool]()
    var targets = List[String]()
    collect_relation_targets(fields, plain_struct_fields, seen, targets)
    return targets^


def _find_relation_cycle(
    name: String,
    targets_of: Dict[String, List[String]],
    module_of: Dict[String, String],
    mut state: Dict[String, Int],
    mut path: List[String],
) raises:
    """DFS over the project-wide relation graph. `state` tracks each
    struct as unseen (absent), in-progress (`1`), or done (`2`) -- finding
    an in-progress struct again means a cycle, however many hops it took.

    Verbatim port from rw_squirrel_2 -- graph-cycle detection over
    `@@`-marked field targets is unaffected by the storage redesign."""
    state[name] = 1
    path.append(name)
    if name in targets_of:
        for target in targets_of[name]:
            if target not in targets_of:
                continue
            if target in state:
                if state[target] == 1:
                    var cycle = String()
                    var started = False
                    for n in path:
                        if n == target:
                            started = True
                        if started:
                            if cycle.byte_length() > 0:
                                cycle += " -> "
                            cycle += n
                            if n in module_of:
                                cycle += " (" + module_of[n] + ")"
                    cycle += " -> " + target
                    raise Error("CyclicRelation: " + cycle)
            else:
                _find_relation_cycle(target, targets_of, module_of, state, path)
    _ = path.pop(len(path) - 1)
    state[name] = 2


def check_no_relation_cycles(
    discovery: DiscoveryResult, plain_struct_fields: Dict[String, List[Field]] = Dict[String, List[Field]]()
) raises:
    """Rejects a schema whose relation fields form a cycle -- `create()`
    requires every relation field's target to already exist (relation
    fields aren't `Optional`), so a cycle has no valid *first* struct to
    construct; separately, Mojo's `ArcPointer` has no cycle collector.

    `plain_struct_fields` (plain-structs milestone) lets a cycle running
    *through* a hand-written plain struct's own relation field be caught
    too (`Person.home: Address`, `Address.owner: @@Employee` -- if
    `Employee` in turn embedded a `Person`-typed relation field, that would
    be a real cycle, just as much as one running only through `@@struct`
    fields directly) -- `_relation_targets`'s own `collect_relation_targets`
    call already flattens a plain struct's own edges into whichever real
    struct embeds it, so the graph's own node set stays `discovery.structs`
    names only; a plain struct is never a node of its own."""
    ref module_of = discovery.module_of

    var targets_of = Dict[String, List[String]]()
    var all_names = List[String]()
    for ds in discovery.structs:
        targets_of[ds.parsed.name] = _relation_targets(ds.parsed.fields, plain_struct_fields)
        all_names.append(ds.parsed.name)

    var state = Dict[String, Int]()
    for name in all_names:
        if name in state:
            continue
        var path = List[String]()
        _find_relation_cycle(name, targets_of, module_of, state, path)
