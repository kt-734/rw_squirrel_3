from squirrel_compiler.parser import (
    Field,
    FieldModifier,
    parse_type_expr,
    is_wrapped_relation_type,
    is_directly_entity_reachable,
    TypeExpr,
    Scanner,
)


def sqrrl_prefixed(name: String) -> String:
    """The transformation behind every `@@`-marked identifier's generated
    Mojo name: entity types (`@@Person` -> `sqrrl__Person`) and local
    variables (`@@alice` -> `sqrrl__alice`). Point 3 of the plan: the
    `sqrrl__` prefix exactly mirrors which DSL source token was
    `@@`-marked -- including the entity type itself, unlike rw_squirrel_2,
    which left it bare (the DSL author only ever writes `@@Person`, never
    the underlying Mojo name, so there's no reason to carve out an
    exception for it here).

    `self` is the one exception (M3 addendum, point 2): a spliced method
    body writes ordinary-looking `self.field` (no marker on `self` at all
    -- `codegen/methods.mojo`'s `_mark_self_field_access` inserts `@@`
    before every bare `self` before handing off to this same machinery, so
    `self` resolves via `entity_to_type` with zero other changes to
    `rewrite_field_access.mojo`), but `self` is also Mojo's own reserved
    receiver name -- it must reach emitted output unchanged, never
    `sqrrl__self`, or the spliced method wouldn't compile as a real method
    any more. Safe and unambiguous: `self` is a reserved word, never a
    legitimate `@@`-marked identifier otherwise."""
    if name == "self":
        return name
    return "sqrrl__" + name


def is_relation_field(f: Field) -> Bool:
    """True if `f`'s declared type is a relation (`@@Type`), or a
    (possibly nested) container of one (`List[@@Type]`, `List[List[
    @@Type]]`, ...) -- `@@container` field support, plain-structs
    milestone (see the plan's Revision 3). `storage_field_name`/`param_name`
    (below) key off this to apply the `sqrrl__` naming convention correctly
    to a wrapped field too, not just a bare one."""
    return f.type_str.startswith("@@") or is_wrapped_relation_type(f.type_str)


def storage_field_name(f: Field) -> String:
    """The generated field name on `sqrrl__<Name>Inner` -- point 4 of the
    plan: every field gets a leading `_` (private storage, matching `_id`/
    `_table`'s existing convention), with `sqrrl__` added on top only for a
    field whose own name is `@@`-marked (point 3: mirrors the field's own
    declaration) -- `is_directly_entity_reachable`, not the broader `is_
    relation_field` (mandatory-marking-narrowing milestone: a relation
    confined to a `Dict`'s value position, or nested too deep to be
    directly reachable through this field's own container-access surface,
    never earns `@@`-marking on the field's own name in the first place,
    so its storage name stays plain too -- consistent with `field_parsing.
    mojo`'s own marking-symmetry check, which is the actual source of
    truth for whether a given field ended up marked). `_name` for a plain
    field, `_sqrrl__dept` for a marked one."""
    if is_directly_entity_reachable(f.type_str):
        return "_" + sqrrl_prefixed(f.name)
    return "_" + f.name


def storage_field_name_for_hop(hop: String) -> String:
    """Same naming rule as `storage_field_name`, for a hop/terminal token
    already proven to be a relation field by a `relation_schema` lookup
    (the rewrite engine never has a `Field` object in hand for a hop, only
    its name and the fact that it validated as a relation)."""
    return "_" + sqrrl_prefixed(hop)


def param_name(f: Field) -> String:
    """The name `f` is referred to by outside of its own storage/type
    positions -- `sqrrl__` mirrors the field's own `@@`-marked declaration
    (point 3: applied with no exceptions), same rule as every other
    generated identifier. Covers two shapes: a `create`/construction-call
    keyword parameter (`.@@dept = @@eng` -> `sqrrl__dept = sqrrl__eng`),
    and the field-derived suffix of a generated method name (`set_<field>`/
    `get_<field>`/`for_<field>`/`add_to_<field>`/`remove_from_<field>` ->
    `set_sqrrl__dept`/`for_sqrrl__projects`/...). A plain field's name
    stays bare in both cases, matching its own unmarked declaration --
    `is_directly_entity_reachable`, same narrowing `storage_field_name`
    just above already uses, and for the same reason (consistency with
    whichever way the field's own marking-symmetry check landed)."""
    if is_directly_entity_reachable(f.type_str):
        return sqrrl_prefixed(f.name)
    return f.name


def param_name_for_construct_field(name: String, is_relation: Bool) -> String:
    """Same naming rule as `param_name`, for a construct-site field label
    (`ConstructField`) rather than a declared `Field` -- `build_create_call`
    only has the label text and its own `.@@`-marking, not a `Field`."""
    if is_relation:
        return sqrrl_prefixed(name)
    return name


def _is_known_leaf_type_name(name: String) -> Bool:
    """True for a type name guaranteed `ImplicitlyCopyable` in this Mojo
    build -- String/Bool/Float32/64/an Int-family name -- the only plain
    (non-relation, non-container) field types safe to assign by bare
    copy. Mirrors `driver/json_module.mojo`'s own `_is_known_leaf_type`
    (kept as a separate copy here rather than a shared import: `codegen`
    doesn't otherwise depend on `driver`, and this list is small/stable
    enough that duplicating it doesn't risk drifting in practice)."""
    return (
        name == "String"
        or name == "Bool"
        or name == "Float64"
        or name == "Float32"
        or name == "Int"
        or name == "Int8"
        or name == "Int16"
        or name == "Int32"
        or name == "Int64"
        or name == "UInt8"
        or name == "UInt16"
        or name == "UInt32"
        or name == "UInt64"
    )


def is_plain_value_field(f: Field, plain_struct_names: Dict[String, Bool]) -> Bool:
    """True if `f` is an ordinary (unmarked, non-relation, non-container)
    field whose declared type isn't a known-`ImplicitlyCopyable` leaf --
    a discovered hand-written plain struct (`home: Address`, possibly
    through a generic instantiation like `item: Box[String]` -- `Box`
    itself is the name checked, never an argument, since only the outer
    type has to be plain-struct-shaped for *this* field's own storage to
    be non-`ImplicitlyCopyable`), *or* a genuinely undiscovered
    hand-written type never scanned as `@@struct`/a plain struct anywhere
    in the project (its own JSON escape hatch -- `driver/json_module.
    mojo`'s `_leaf_from_json_expr` -- assumes exactly this: a hand-written
    struct, never guaranteed `ImplicitlyCopyable`). Plain-structs
    milestone: such a field's `set_<field>`/`create()` parameter can't
    rely on a bare (implicit-copy) assignment the way a known leaf
    safely can -- confirmed via a real end-to-end compile with an
    undiscovered plain-value field (`ExternalAddress`, deliberately not
    `ImplicitlyCopyable`, same as the plan's own worked example `Address`)
    -- so it needs the same `var`+`^` (move) treatment `multi`'s `Set[T]`
    already established. `plain_struct_names` no longer changes the
    result (kept as a parameter for now since every call site already
    threads it through for the container check alongside this one) --
    moving is always safe regardless of whether the type turns out to
    *actually* be `ImplicitlyCopyable`, so there's no reason to
    distinguish "known plain struct" from "unknown hand-written type"
    here any more."""
    if is_relation_field(f) or is_container_type(f.type_str):
        return False
    return not _is_known_leaf_type_name(parse_type_expr(f.type_str).name)


def needs_move_assignment(f: Field, plain_struct_names: Dict[String, Bool]) -> Bool:
    """True if `f`'s own stored value isn't guaranteed `ImplicitlyCopyable`
    -- needs `var`+`^` (move) instead of a bare copy-assignment wherever it
    crosses a function boundary (`set_<field>`, `create()`'s own parameter/
    ctor_args, JSON reconstruction's own final construction step). Three
    cases, established at different points, all folded into one check so
    every call site agrees:
    - `multi`'s own `Set[T]` (`f.modifier == MULTI`), always, regardless
      of target.
    - *Any* container-shaped field (`is_container_type` -- `List`/`Set`/
      `Optional`/`Dict`, wrapping a relation, a plain-struct value, or a
      plain leaf, non-`multi`) -- `List[T]` turned out NOT to be
      `ImplicitlyCopyable` in this Mojo build either, despite an earlier
      spike (during the plain-structs milestone) suggesting otherwise for
      a *parameter*; a real end-to-end compile (verified directly, not
      assumed) showed the *field-assignment* case still fails without
      `var`+`^`, same as every other non-`ImplicitlyCopyable` case here.
      Widened from "wrapped relation only" once a plain leaf container
      (`tags: List[String]`) turned out to hit the identical problem for
      the identical reason -- move is always safe even for a container
      that *would* have been copyable, so applying it unconditionally to
      every container shape has no downside.
    - A plain-struct value (`home: Address`, `is_plain_value_field`) --
      never guaranteed `ImplicitlyCopyable` since it's hand-written."""
    return f.modifier == FieldModifier.MULTI or is_container_type(f.type_str) or is_plain_value_field(f, plain_struct_names)


def storage_field_name_for_plain(name: String) -> String:
    """Same naming rule as `storage_field_name`, for a terminal token
    already proven to be a *plain* (non-relation) field."""
    return "_" + name


def _render_rewritten_type_expr(t: TypeExpr, plain_struct_names: Dict[String, Bool]) -> String:
    """Recursive renderer used wherever a relation field's *type* needs
    rewriting -- a `RELATION` node's name resolves to the real generated
    name: bare if it's a plain struct (`plain_struct_names`), `sqrrl__`-
    prefixed if it's a real entity, recursing through `PARAMETERIZED` args
    either way (`List[@@Employee]` -> `List[sqrrl__Employee]`, `Box[
    @@Employee]` -> `Box[sqrrl__Employee]`, a plain struct's own generic
    instantiation stays bare at the wrapper -- `Box` is never itself
    `@@`-marked, only an argument might be). Plain-structs milestone, the
    plan's §5."""
    if t.kind == TypeExpr.RELATION:
        return t.name if t.name in plain_struct_names else sqrrl_prefixed(t.name)
    if t.kind == TypeExpr.LEAF:
        return t.name
    var out = t.name + "["
    for i in range(t.arg_count()):
        if i > 0:
            out += ", "
        out += _render_rewritten_type_expr(t.arg(i), plain_struct_names)
    out += "]"
    return out^


def rewritten_field_type(
    type_str: String, plain_struct_names: Dict[String, Bool] = Dict[String, Bool]()
) -> String:
    """The Mojo-side rewritten form of a raw `.mojo.sqrrl` type string --
    `@@Employee` -> `sqrrl__Employee` (point 3: the entity type itself is
    `sqrrl__`-prefixed now, unless it's a plain struct, which stays bare --
    `plain_struct_names`), `List[@@Employee]` -> `List[sqrrl__Employee]`
    (plain-structs milestone: `@@container` field support, same-commit
    prerequisite fix -- see the plan's Revision 3), passed through
    unchanged for an ordinary Mojo type with no relation content at all
    (`String`, `UInt32`, plain `List[String]`, ...)."""
    var t = parse_type_expr(type_str)
    if t.is_relation() or is_wrapped_relation_type(type_str):
        return _render_rewritten_type_expr(t, plain_struct_names)
    return type_str


def emit_field_type(f: Field, plain_struct_names: Dict[String, Bool] = Dict[String, Bool]()) -> String:
    """The Mojo type a field's storage/parameters operate on. A `multi`
    field's own `type_str` is the bare *element* type (`multi @@projects:
    @@Project`'s is `@@Project`, not a container) -- the keyword itself
    already means "many of these"; the actual field type is `Set[...]`
    around whatever that element rewrites to (membership is a set: this
    row either has this member or it doesn't)."""
    var t = rewritten_field_type(f.type_str, plain_struct_names)
    if f.modifier == FieldModifier.MULTI:
        return String("Set[" + t + "]")
    return t


def emit_multi_element_type(f: Field, plain_struct_names: Dict[String, Bool] = Dict[String, Bool]()) -> String:
    """The bare element type a `multi` field's `add_to_<field>`/
    `remove_from_<field>`/`for_<field>` all take -- `emit_field_type` minus
    the `Set[...]` it adds back on for the field's own storage type.
    Requires `f.modifier == FieldModifier.MULTI`."""
    return rewritten_field_type(f.type_str, plain_struct_names)


def emit_index_type(f: Field, plain_struct_names: Dict[String, Bool] = Dict[String, Bool]()) -> String:
    """The generated `sqrrl__<Name>Indexes` field type for `f` -- only
    ever called for a field whose modifier isn't `NONE` (a `NONE` field has
    no entry in `Indexes` at all, per point 6 of the plan)."""
    if f.modifier == FieldModifier.UNIQUE:
        return String("UniqueIndex[" + emit_field_type(f, plain_struct_names) + "]")
    if f.modifier == FieldModifier.MULTI:
        return String("MultiIndex[" + emit_multi_element_type(f, plain_struct_names) + "]")
    if f.modifier == FieldModifier.INDEXED:
        return String("PlainIndex[" + emit_field_type(f, plain_struct_names) + "]")
    # ORDERED -- same add/remove/get_bwd shape as PlainIndex (set_<field>,
    # __del__, and create()'s index population all already call those two
    # methods generically, no codegen changes needed there), plus its own
    # range-query methods (table.mojo).
    return String("OrderedIndex[" + emit_field_type(f, plain_struct_names) + "]")


def is_container_type(t: String) -> Bool:
    return parse_type_expr(t).is_parameterized()


def container_wrapper_of(t: String) -> String:
    return parse_type_expr(t).name


def container_element_of(t: String) -> String:
    """The element type an `@@`-marked variable bound to a container tracks
    when *iterating* it (`for @@x in @@container:`) -- for any wrapper
    with *at least two* type parameters (`Dict[K, V]`, or a custom key/
    value-shaped wrapper like `Grid[K, V]`, M4: `group_by_<field>`/`sum_
    <field>_by_<other>`/...) this is `K` alone, never `K, V, ...` --
    iterating a bare `Dict` already only ever yields keys (`for @@k in
    @@dict:`), and there's no mechanism to track both a key and a value
    type through the `@@` marker system at once (inherited restriction
    from rw_squirrel_2, not a new one). `>= 2`, not `== 2`: a real Mojo
    `Dict` actually carries a third (`Hasher`-bound, defaulted) type
    parameter almost nothing ever writes explicitly -- confirmed via a
    real compiler crash when one is passed, so `Dict[String, @@Employee,
    SomeHasher]` must be treated identically to the two-argument
    spelling, not fall through to the generic join below. Keyed on
    *argument count*, not the literal name `Dict` -- same generalization
    `is_directly_entity_reachable` already applies (not tied to any
    specific wrapper name), so a hand-written two-argument container gets
    the same treatment `Dict` does, with no special-casing needed per
    wrapper. See `container_index_result_of` for the *indexing*
    (`@@container[key]`) counterpart, which for a two-or-more-argument
    wrapper answers `V` (position 1) instead."""
    var parsed = parse_type_expr(t)
    if parsed.arg_count() >= 2:
        return parsed.arg(0).render()
    var out = String()
    for i in range(parsed.arg_count()):
        if i > 0:
            out += ", "
        out += parsed.arg(i).render()
    return out^


def _entity_iterable_leaf_name(t: TypeExpr) -> String:
    if not t.is_parameterized():
        return t.name
    if t.arg_count() == 0:
        return t.name
    return _entity_iterable_leaf_name(t.arg(0))


def is_entity_iterable_leaf(
    type_str: String, struct_names: Dict[String, Bool], plain_struct_names: Dict[String, Bool]
) -> Bool:
    """True if `type_str` -- an already-`@@`-stripped, *registered* type
    string (`relation_schema`/`function_returns`/`method_returns`'s own
    values, or a bound container variable's own tracked type) --
    recursively bottoms out, through *position 0 only* (the one position
    real iteration, `for x in container:`, ever exposes), at a known
    struct name (real or plain) -- i.e. iterating this type genuinely
    yields an entity, not a plain leaf like `String`.

    Deliberately narrower than `is_directly_entity_reachable` (which
    additionally accepts a relation confined to position 1, since
    *marking* only needs the relation reachable through *some* position,
    but *iteration* only ever exposes position 0): this is the for-loop-
    variable-marking guard's own check -- `for @@x in <a call/field whose
    iteration only reaches an entity through position 1>:` must be
    rejected, requiring bare `x` instead, since `@@x` would otherwise
    silently bind to a plain, non-entity value (`Dict[String,
    @@Employee]`'s own iteration yields the `String` key, never the
    `Employee`) -- confirmed as a real, previously-silent risk once
    marking widened to cover position 2 as well as position 1."""
    var leaf = _entity_iterable_leaf_name(parse_type_expr(type_str))
    return leaf in struct_names or leaf in plain_struct_names


def container_index_result_of(t: String) -> String:
    """The element type `@@container[key]` yields when *indexing* it --
    for any wrapper with *at least two* type parameters (`Dict[K, V]`, or
    a custom key/value-shaped wrapper like `Grid[K, V]`) this is `V`, the
    *value* (position 1) -- unlike `container_element_of`'s own `K`
    (position 0), what *iterating* the same container yields (`for k in
    dict:` only ever gives keys; `dict[k]` gives the value). `>= 2`, not
    `== 2`, for the same reason `container_element_of` uses it -- a real
    `Dict[K, V, Hasher]` (position 2+ ignored, whatever it is) indexes
    the same way `Dict[K, V]` does. Keyed on argument count, not the
    literal name `Dict`, mirroring `container_element_of`'s own
    generalization -- a custom two-argument wrapper indexes the same way
    `Dict` does, with no special-casing needed per wrapper. Indexing and
    iterating a single-argument wrapper (`List[T]`/`Set[T]`/`Optional[T]`)
    already agree (there's only one type parameter to disagree about), so
    this falls straight through to `container_element_of` for anything
    with fewer than two arguments."""
    var parsed = parse_type_expr(t)
    if parsed.arg_count() >= 2:
        return parsed.arg(1).render()
    return container_element_of(t)


def encode_container_type(wrapper: String, type_name: String) -> String:
    """`entity_to_type`'s encoding for a container-tracked `@@` variable --
    stores `"Wrapper[Type]"` as a plain string."""
    return wrapper + "[" + type_name + "]"


def scan_entity_return_shape(text: String) raises -> Optional[String]:
    """Scans `text` -- everything from right after a def's/method's own
    name through its header line's end, arrow included or not (e.g.
    `(x: Int) -> @@Employee:` for a top-level function, or `self, x: Int)
    -> List[List[@@Employee]]:` for a method, whose own name/opening `(`
    were already split off separately) -- for a `-> <ReturnType>` and, if
    found, hands the raw return-type text to `is_directly_entity_
    iterable`/`render_relation_stripped` (the same canonical predicate and
    encoding every other `@@`-marking-symmetry check in this codebase
    already uses -- struct fields, hand-written plain struct fields, def/
    var entity-params) rather than re-deriving a parallel, one-level-only
    scan: recurses through first-argument position at *any* depth
    (`List[List[@@Employee]]`), not just one wrapper deep, and correctly
    stays unmarked for a relation confined to a *non-first* argument
    position (`Dict[String, @@Employee]`, the value) -- exactly `is_
    directly_entity_iterable`'s own "a @@type in a non-first position
    does not make a @@container" rule.

    Returns None if there's no arrow, or the return type isn't directly
    entity-iterable at all.

    The arrow-search itself is a linear byte-by-byte scan for the `->`
    substring, with no depth-awareness of the parameter list it passes
    through first (inherited limitation from `driver/misc_builders.mojo`'s
    own original scan: a parameter's own default value containing a
    literal `->` would misfire, considered out of scope) -- but once past
    the arrow, the return type's own text is captured via `Scanner.scan_
    bracket_depth_aware_span` (the same shared, depth-aware span-scan
    `scan_type`/`scan_entity_param_type_text` use, terminated by `:` here
    instead of `,`/`)`/`='), so an arbitrarily nested return type's full
    text is captured intact for `parse_type_expr` to parse for real,
    rather than inspected byte-by-byte itself.

    Shared by `build_function_returns` (top-level defs, mandatory-marking's
    original milestone) and `codegen/methods.mojo`'s `_parse_method_span`
    (struct methods, mandatory-marking extended to them) -- the scan
    itself is identical once positioned right after the name, whether
    that's a top-level function or a method."""
    var sc = Scanner(text)
    var found_arrow = False
    while not sc.at_end():
        if sc.try_consume("->"):
            found_arrow = True
            break
        sc.pos += 1
    if not found_arrow:
        return None
    sc.skip_trivia()
    var type_text = sc.scan_bracket_depth_aware_span(":")
    if type_text.byte_length() == 0 or not is_directly_entity_reachable(type_text):
        return None
    return Optional[String](parse_type_expr(type_text).render_relation_stripped())
