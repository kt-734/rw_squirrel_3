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


def _is_directly_entity_reachable(t: TypeExpr) -> Bool:
    """True if `t` is a bare relation (`@@Employee`), or a container shape
    whose own iteration *or* indexing actually yields entities directly --
    a relation as the wrapper's own *first* type parameter (`List[
    @@Employee]`/`Set[@@Employee]`/`Optional[@@Employee]`, or `Dict[
    @@Employee, V]` -- Dict iteration only ever yields keys, the same
    restriction `container_element_of`'s own handling already hardcodes),
    a further container satisfying this same rule in that first-parameter
    position (`List[List[@@Employee]]`), *or* -- for any wrapper with at
    least two type parameters -- a relation in the *second* position
    (`Dict[String, @@Employee]`, `Grid[String, @@Employee]`), which real
    Mojo indexing (`container[key]`) yields even though iteration doesn't.
    `arg_count() >= 2`, not `== 2`: a real Mojo `Dict` actually carries a
    third (`Hasher`-bound, defaulted) type parameter that almost nothing
    ever writes explicitly -- confirmed via a real compiler crash
    (`ParamInf::inferForStruct`) when one is passed explicitly, meaning it
    genuinely exists, not just theoretically -- so a `Dict[String,
    @@Employee, SomeHasher]` (positions 3+ are never inspected, whatever
    they are) must be recognized exactly the same as the far more common
    two-argument spelling. Deliberately *not* keyed off any specific
    wrapper name (`Dict` isn't special-cased here) -- the same "first or
    second type parameter" rule applies uniformly to any wrapper, built-in
    or a hand-written custom one (`Grid[K, V]`), since it's the wrapper's
    own *position*, not its identity, that decides what a real DSL
    iteration/index would ever actually yield. A relation confined to a
    *third-or-later* parameter is never actually reachable through this
    type's own container-access surface (no iteration or indexing
    operation this DSL generates ever reaches it -- there's no defined
    "what does indexing a 3-argument wrapper yield" contract for anything
    beyond position 2), and doesn't count here.

    Deliberately narrower than `is_wrapped_relation_type`/`_is_relation_
    shaped` (which stay unchanged, "any position, any depth" -- cycle
    detection and JSON serialization/reflection both genuinely need that
    broader truth regardless of reachability: a relation buried anywhere
    in a field's type is still a real stored reference construction order
    depends on, whether or not the DSL's own access-chain machinery can
    ever walk to it). This one instead answers "does this name (a field, a
    def/var entity-param, a function/method whose call should become a
    marker position) need `@@` marking at its own declaration" --
    @@-marking a name whose type can't actually produce an entity through
    iteration/indexing buys nothing (there'd be no corresponding `.@@name`/
    call-site behavior to back the marking up): the type itself still gets
    `sqrrl__`-rewritten correctly wherever it appears (`rewritten_field_
    type`, unaffected by this), only the *name*'s own marking requirement
    narrows."""
    if t.is_relation():
        return True
    if not t.is_parameterized():
        return False
    if t.arg_count() >= 1 and _is_directly_entity_reachable(t.arg(0)):
        return True
    return t.arg_count() >= 2 and _is_directly_entity_reachable(t.arg(1))


def is_directly_entity_reachable(type_str: String) -> Bool:
    """String-typed entry point for `_is_directly_entity_reachable` -- see
    its own doc comment for the full rationale. Used wherever a name's
    own `@@`-marking requirement is decided: struct-field marking
    symmetry (both `@@struct` and hand-written plain structs), entity-
    param marking symmetry (def parameters, var-decls), mandatory marking
    on a function/method whose return type this shapes, and the matching
    generated-name/`relation_schema`-vs-`plain_value_fields` decisions
    that have to stay consistent with whichever way that symmetry check
    came out."""
    return _is_directly_entity_reachable(parse_type_expr(type_str))


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
