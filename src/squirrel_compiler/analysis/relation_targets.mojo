from squirrel_compiler.parser import Field, parse_type_expr, TypeExpr
from squirrel_compiler.codegen.helpers import is_relation_field


def _relation_target_base_name(t: TypeExpr) -> String:
    """The bare struct name a relation-shaped type expression points at --
    unwraps any container nesting first (`List[@@Employee]`/`List[List[
    @@Employee]]` -> `"Employee"`, `@@Box[String]` -> `"Box"`, plain
    `@@Employee` -> `"Employee"`) -- what both `plain_struct_fields`'s own
    keys and `discovery.structs`' own names are keyed by."""
    if t.kind == TypeExpr.RELATION or t.kind == TypeExpr.LEAF:
        return t.name
    return _relation_target_base_name(t.arg(0))


def collect_relation_targets(
    fields: List[Field],
    plain_struct_fields: Dict[String, List[Field]],
    mut seen: Dict[String, Bool],
    mut out: List[String],
) raises:
    """Every distinct real-entity struct `fields` needs a live table
    reference to reach, direct *or* transitive through an embedded plain
    struct's own relation field (`Address`'s own `@@owner: @@Employee`,
    embedded via `Person`'s `@@home: @@Address` field, still needs
    `Employee`'s table) -- deduplicated, first-encountered order. Safe
    against infinite recursion through plain structs embedding each other:
    the same relation graph `check_no_relation_cycles` walks (using this
    exact function) is guaranteed acyclic before this ever runs for real.

    Single source of truth for "what does this field list reach" -- shared
    by `driver/cycles.mojo` (the project-wide relation graph) and `driver/
    json_module.mojo` (which sibling tables a `from_json` companion needs)
    rather than each re-deriving an equivalent walk independently (mirrors
    rw_squirrel_2's own `analysis/relation_targets.mojo`, confirmed by
    reading it)."""
    for f in fields:
        var t = _relation_target_base_name(parse_type_expr(f.type_str))
        if not is_relation_field(f):
            # An unmarked plain-value field (`home: Address`) is never
            # itself a relation, but its value may still be a plain
            # struct embedding further relation fields of its own
            # (`Address`'s `@@owner: @@Employee`) -- recurse into it, but
            # never add the plain struct's own name to `out`: it isn't a
            # real entity, so it never gets its own sibling-table
            # parameter. Anything else unmarked (an ordinary leaf like
            # `name: String`, or a genuinely opaque hand-written type) has
            # nothing further to reach.
            if t in seen or t not in plain_struct_fields:
                continue
            seen[t] = True
            collect_relation_targets(plain_struct_fields[t], plain_struct_fields, seen, out)
            continue
        if t in seen:
            continue
        seen[t] = True
        if t in plain_struct_fields:
            collect_relation_targets(plain_struct_fields[t], plain_struct_fields, seen, out)
        else:
            out.append(t)


def _collect_plain_struct_targets_from_type(
    t: TypeExpr,
    plain_struct_fields: Dict[String, List[Field]],
    mut seen: Dict[String, Bool],
    mut out: List[String],
) raises:
    """Unlike `_relation_target_base_name` (which recurses *into* a
    container's own argument -- correct for `List[@@Employee]`, whose
    interesting name is the element `Employee`), a plain struct's own
    generic instantiation (`Tagged[String]`) is interesting at the
    *wrapper* itself (`Tagged`, a real discovered struct -- `String` is
    just a type argument, never itself relevant here). Both questions can
    apply to the very same field independently (`Box[@@Employee]` -- `Box`
    is a plain-struct wrapper needing its own `from_json` companion *and*
    `Employee` is a real relation target needing a sibling table), so this
    checks the wrapper's own name unconditionally, then always recurses
    into every argument too (covers a plain struct nested inside another
    plain struct's own instantiation as well)."""
    if t.name in plain_struct_fields and t.name not in seen:
        seen[t.name] = True
        out.append(t.name)
        collect_plain_struct_targets(plain_struct_fields[t.name], plain_struct_fields, seen, out)
    for i in range(t.arg_count()):
        _collect_plain_struct_targets_from_type(t.arg(i), plain_struct_fields, seen, out)


def collect_plain_struct_targets(
    fields: List[Field],
    plain_struct_fields: Dict[String, List[Field]],
    mut seen: Dict[String, Bool],
    mut out: List[String],
) raises:
    """Every distinct plain struct `fields` needs a generated `from_json`
    companion for, direct or transitive through further nested plain-
    struct fields -- `collect_relation_targets`'s counterpart for the
    *other* half of a from_json call graph's own dependencies (real-entity
    sibling tables there, plain-struct `from_json` companions here).
    Deduplicated, first-encountered order.

    Only a plain struct actually reachable from some real `@@struct`'s own
    field graph gets a `from_json` companion generated at all (`driver/
    json_module.mojo`'s `emit_json_module` seeds this walk from every
    `@@struct` in the project, never from `plain_struct_fields` directly)
    -- matches this project's own "no unused generated surface" principle
    (M4/M5 precedent), and matters concretely here: a structurally
    un-JSON-able plain struct (one with a field typed as its own bare,
    unbound type parameter -- see `_emit_plain_struct_from_json`'s own doc
    comment) would otherwise fail to generate at all even when nothing
    ever needs its `from_json`, since `to_json` alone (via reflection)
    never requires one."""
    for f in fields:
        _collect_plain_struct_targets_from_type(parse_type_expr(f.type_str), plain_struct_fields, seen, out)
