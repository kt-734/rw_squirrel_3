from squirrel_compiler.parser.type_expr import parse_type_expr, TypeExpr


def _is_relation_shaped(t: TypeExpr) -> Bool:
    """True if `t` is itself a relation (`@@Employee`), or a container whose
    *first* type argument is (recursively) relation-shaped -- `List[
    @@Employee]`, `List[List[@@Employee]]`, ... Plain-structs milestone:
    generalizes what used to be `is_wrapped_relation_type`'s one-level-only
    check to arbitrary container nesting (`@@container` field support, the
    general recursive access chain -- see the plan's Revision 3)."""
    if t.is_relation():
        return True
    if t.is_parameterized() and t.arg_count() >= 1:
        return _is_relation_shaped(t.arg(0))
    return False


def is_wrapped_relation_type(type_str: String) -> Bool:
    """True if `type_str` looks like `Ident[@@Type]` -- e.g.
    `List[@@Employee]`, or a nested container of one, e.g. `List[List[
    @@Employee]]` -- the collection form of a relation field, alongside the
    bare `@@Type` form. Only the *first* type argument is checked."""
    var t = parse_type_expr(type_str)
    return t.is_parameterized() and t.arg_count() >= 1 and _is_relation_shaped(t.arg(0))


def relation_target_of(type_str: String) -> String:
    """The target type name of a relation field's `type_str`, whether bare
    (`@@Employee` -> `Employee`) or wrapped (`List[@@Employee]` ->
    `Employee`)."""
    var t = parse_type_expr(type_str)
    if t.is_relation():
        return t.name
    return t.arg(0).name


def relation_wrapper_of(type_str: String) -> String:
    """The container identifier of a wrapped relation field's `type_str` --
    `List[@@Employee]` -> `List`."""
    return parse_type_expr(type_str).name
