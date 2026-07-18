from squirrel_compiler.parser.type_expr import parse_type_expr, TypeExpr


def _is_relation_shaped(t: TypeExpr) -> Bool:
    """True if `t` is itself a relation (`@@Employee`), or a container
    reaching one anywhere in its own structure -- any argument position, at
    any nesting depth (`List[@@Employee]`, `List[List[@@Employee]]`,
    `Dict[String, @@Employee]` -- relation in the *value* position,
    `Dict[@@Employee, @@Department]` -- both). Originally only ever
    checked the *first* type argument (a real limitation, not a deliberate
    restriction -- a relation was always genuinely reachable through a
    later argument too, this just failed to notice); generalized to check
    every argument once a real field (`Dict[String, @@Employee]`) needed
    it. `@@container` field support, the general recursive access chain --
    see the plan's Revision 3."""
    if t.is_relation():
        return True
    for i in range(t.arg_count()):
        if _is_relation_shaped(t.arg(i)):
            return True
    return False


def is_wrapped_relation_type(type_str: String) -> Bool:
    """True if `type_str` looks like a container reaching a relation
    anywhere in its own structure -- `List[@@Employee]`, a nested container
    of one (`List[List[@@Employee]]`), `Dict[String, @@Employee]` (relation
    in the *value* position), or `Dict[@@Employee, @@Department]` (both) --
    the collection form of a relation field, alongside the bare `@@Type`
    form."""
    var t = parse_type_expr(type_str)
    return t.is_parameterized() and _is_relation_shaped(t)


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
