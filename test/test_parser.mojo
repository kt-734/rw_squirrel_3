from std.testing import assert_equal, assert_true, assert_false, TestSuite

from squirrel_compiler.parser import (
    Scanner,
    MarkerKind,
    FieldModifier,
    parse_type_expr,
    is_wrapped_relation_type,
    relation_target_of,
)


def test_parse_struct_plain_fields() raises:
    var src = String(
        "@@struct @@Person:\n"
        + "    name: String\n"
        + "    age: UInt32\n"
    )
    var s = Scanner(src)
    assert_true(s.find_next_struct_decl())
    var parsed = s.parse_struct()
    assert_equal(parsed.name, "Person")
    assert_equal(len(parsed.fields), 2)
    assert_equal(parsed.fields[0].name, "name")
    assert_equal(parsed.fields[0].type_str, "String")
    assert_true(parsed.fields[0].modifier == FieldModifier.NONE)
    assert_equal(parsed.fields[1].name, "age")


def test_parse_struct_with_modifiers_and_relation() raises:
    var src = String(
        "@@struct @@Person:\n"
        + "    indexed name: String\n"
        + "    unique ssn: String\n"
        + "    @@dept: @@Department\n"
    )
    var s = Scanner(src)
    assert_true(s.find_next_struct_decl())
    var parsed = s.parse_struct()
    assert_equal(len(parsed.fields), 3)
    assert_true(parsed.fields[0].modifier == FieldModifier.INDEXED)
    assert_true(parsed.fields[1].modifier == FieldModifier.UNIQUE)
    assert_equal(parsed.fields[2].name, "dept")
    assert_equal(parsed.fields[2].type_str, "@@Department")
    assert_true(parsed.fields[2].modifier == FieldModifier.NONE)


def test_parse_struct_rejects_mismatched_marking() raises:
    var src = String(
        "@@struct @@Person:\n"
        + "    @@dept: Department\n"  # name marked, type not -- mismatch
    )
    var s = Scanner(src)
    assert_true(s.find_next_struct_decl())
    var raised = False
    try:
        _ = s.parse_struct()
    except:
        raised = True
    assert_true(raised)


def test_parse_struct_captures_trailing_methods() raises:
    var src = String(
        "@@struct @@Person:\n"
        + "    name: String\n"
        + "\n"
        + "    def @@@greeting(self) -> String:\n"
        + "        return self.name\n"
    )
    var s = Scanner(src)
    assert_true(s.find_next_struct_decl())
    var parsed = s.parse_struct()
    assert_equal(len(parsed.fields), 1)
    assert_true(parsed.method_body.startswith("    def @@@greeting"))


def test_parse_struct_keepalive_and_equatable() raises:
    var src = String(
        "@@struct keepalive equatable @@Project:\n"
        + "    name: String\n"
    )
    var s = Scanner(src)
    assert_true(s.find_next_struct_decl())
    var parsed = s.parse_struct()
    assert_true(parsed.is_keepalive)
    assert_true(parsed.is_equatable)


def test_find_next_marker_struct() raises:
    var s = Scanner("@@struct @@Person:\n    name: String\n")
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.STRUCT)


def test_find_next_marker_world_scope() raises:
    var s = Scanner("def main() raises:\n    @@@:\n        pass\n")
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.WORLD_SCOPE)


def test_find_next_marker_world_scope_rejects_plain_two_at() raises:
    """`@@:` needs 'sqrrl__world' now (M3 addendum) -- only `@@@:` opens a
    world scope; the old two-`@` form is a hard parse error."""
    var s = Scanner("def main() raises:\n    @@:\n        pass\n")
    var raised = False
    try:
        _ = s.find_next_marker()
    except:
        raised = True
    assert_true(raised)


def test_find_next_marker_init() raises:
    var s = Scanner("@@init()")
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.INIT)


def test_find_next_marker_construct() raises:
    var s = Scanner('@@@Person { .name = "alice" }')
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.CONSTRUCT)
    var c = s.parse_construct()
    assert_equal(c.type_name, "Person")
    assert_equal(len(c.fields), 1)
    assert_equal(c.fields[0].name, "name")
    assert_false(c.fields[0].is_relation)
    assert_equal(c.fields[0].value, '"alice"')


def test_find_next_marker_construct_rejects_plain_two_at() raises:
    """Construction always needs 'sqrrl__world' (M3 addendum) -- a plain
    `@@Person{...}` (two `@`s) is now a hard parse error; only
    `@@@Person{...}` is valid."""
    var s = Scanner('@@Person { .name = "alice" }')
    var raised = False
    try:
        _ = s.find_next_marker()
    except:
        raised = True
    assert_true(raised)


def test_find_next_marker_construct_with_relation_field() raises:
    var s = Scanner('@@@Employee { .title = "Eng", .@@dept = @@eng }')
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.CONSTRUCT)
    var c = s.parse_construct()
    assert_equal(len(c.fields), 2)
    assert_true(c.fields[1].is_relation)
    assert_equal(c.fields[1].name, "dept")
    assert_equal(c.fields[1].value, "@@eng")


def test_find_next_marker_construct_with_multi_field_set_value() raises:
    """A `multi` field's construct-site value (`Set(@@a, @@b)`) needs no
    special parsing -- the existing opaque, depth-aware value scan already
    carries a comma-containing, paren-nested expression through as one
    `ConstructField.value` untouched, same as any other field's value."""
    var s = Scanner('@@@Department { .name = "Engineering", .@@projects = Set(@@website, @@app) }')
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.CONSTRUCT)
    var c = s.parse_construct()
    assert_equal(len(c.fields), 2)
    assert_true(c.fields[1].is_relation)
    assert_equal(c.fields[1].name, "projects")
    assert_equal(c.fields[1].value, "Set(@@website, @@app)")


def test_field_access_call_with_marked_field_suffix() raises:
    """A compound method call whose field-name suffix is `@@`-marked
    (`add_to_@@projects(...)`) -- mirrors `.@@dept`'s own marking
    convention, just with a non-empty literal prefix ("add_to_") before the
    marker. The combined token text is identical to the unmarked form
    either way; only `field_marked` differs."""
    var s = Scanner("@@eng.add_to_@@projects(@@website)")
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.FIELD_ACCESS)
    var fa = s.parse_field_access()
    assert_equal(fa.entity, "eng")
    assert_equal(len(fa.steps), 1)
    assert_equal(fa.steps[0].name, "add_to_projects")
    assert_true(fa.steps[0].marked)
    assert_false(fa.steps[0].marked_world)
    assert_true(fa.is_call)


def test_field_access_call_without_marked_field_suffix() raises:
    var s = Scanner("@@Department.for_name(@@website)")
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.FIELD_ACCESS)
    var fa = s.parse_field_access()
    assert_equal(len(fa.steps), 1)
    assert_equal(fa.steps[0].name, "for_name")
    assert_false(fa.steps[0].marked)
    assert_true(fa.is_call)
    assert_false(fa.entity_marked_world)


def test_field_access_call_with_world_marked_field() raises:
    """Call-site symmetry with a spliced method's own `@@@`-marked
    declaration: `@@alice.@@@greeting()` -- the entity itself stays plain
    `@@` (a bound variable), only the method name is `@@@`-marked."""
    var s = Scanner("@@alice.@@@greeting()")
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.FIELD_ACCESS)
    var fa = s.parse_field_access()
    assert_equal(fa.entity, "alice")
    assert_equal(len(fa.steps), 1)
    assert_equal(fa.steps[0].name, "greeting")
    assert_false(fa.steps[0].marked)
    assert_true(fa.steps[0].marked_world)
    assert_false(fa.entity_marked_world)
    assert_true(fa.is_call)


def test_field_access_table_level_call_needs_world_marked_entity() raises:
    """A table-level call is written `@@@Type.method(...)` (M3 addendum) --
    the scanner can't yet tell a table-level call apart from a
    bound-variable instance call (that needs `entity_to_type`), so it just
    records which prefix was used; `entity_marked_world` is what
    `rewrite_field_access.mojo` later validates against the actual case."""
    var s = Scanner("@@@Department.for_name(@@website)")
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.FIELD_ACCESS)
    var fa = s.parse_field_access()
    assert_equal(fa.entity, "Department")
    assert_equal(len(fa.steps), 1)
    assert_equal(fa.steps[0].name, "for_name")
    assert_true(fa.is_call)
    assert_true(fa.entity_marked_world)


def test_find_next_marker_field_access_read() raises:
    var s = Scanner("print(@@alice.name)")
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.FIELD_ACCESS)
    var fa = s.parse_field_access()
    assert_equal(fa.entity, "alice")
    assert_equal(len(fa.steps), 1)
    assert_equal(fa.steps[0].name, "name")
    assert_false(fa.steps[0].marked)
    assert_false(Bool(fa.write_value))


def test_find_next_marker_field_access_write() raises:
    var s = Scanner('@@alice.name = "x";')
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.FIELD_ACCESS)
    var fa = s.parse_field_access()
    assert_equal(fa.entity, "alice")
    assert_equal(len(fa.steps), 1)
    assert_equal(fa.steps[0].name, "name")
    assert_true(Bool(fa.write_value))
    assert_equal(fa.write_value.value(), '"x"')


def test_field_access_relation_hop_chain() raises:
    var s = Scanner("print(@@alice.@@dept.name)")
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.FIELD_ACCESS)
    var fa = s.parse_field_access()
    assert_equal(fa.entity, "alice")
    assert_equal(len(fa.steps), 2)
    assert_equal(fa.steps[0].name, "dept")
    assert_true(fa.steps[0].marked)
    assert_equal(fa.steps[1].name, "name")
    assert_false(fa.steps[1].marked)
    # A bound-variable access -- always plain '@@', never '@@@'.
    assert_false(fa.entity_marked_world)


def test_field_access_ends_on_relation_hop() raises:
    var s = Scanner("print(@@alice.@@dept)")
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.FIELD_ACCESS)
    var fa = s.parse_field_access()
    assert_equal(fa.entity, "alice")
    assert_equal(len(fa.steps), 1)
    assert_equal(fa.steps[0].name, "dept")
    assert_true(fa.steps[0].marked)


def test_find_next_marker_name_ref() raises:
    var s = Scanner("var @@alice = @@Person { .name = \"a\" }")
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.NAME_REF)
    var nr = s.parse_name_ref()
    assert_equal(nr.name, "alice")


def test_find_next_marker_entity_param() raises:
    var s = Scanner("def foo(@@subject: @@Person):\n    pass\n")
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.ENTITY_PARAM)
    var ep = s.parse_entity_param()
    assert_equal(ep.name, "subject")
    assert_equal(ep.type_name, "Person")
    assert_false(Bool(ep.wrapper))


def test_find_next_marker_return_type() raises:
    var s = Scanner("def make() raises -> @@Department:\n    pass\n")
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.RETURN_TYPE)


def test_find_next_marker_for_entity_loop() raises:
    var s = Scanner("for @@emp in @@Employee.all():\n    pass\n")
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.FOR_ENTITY_LOOP)
    var name = s.parse_for_entity_loop()
    assert_equal(name, "emp")


def test_type_expr_relation_and_wrapped() raises:
    var t = parse_type_expr("@@Department")
    assert_true(t.is_relation())
    assert_equal(t.name, "Department")

    assert_true(is_wrapped_relation_type("List[@@Employee]"))
    assert_equal(relation_target_of("List[@@Employee]"), "Employee")
    assert_equal(relation_target_of("@@Department"), "Department")
    assert_false(is_wrapped_relation_type("List[String]"))

    # A relation reachable through any argument position, not just the
    # first -- `Dict[String, @@Employee]` (value position), `Dict[
    # @@Employee, @@Department]` (both) -- previously invisible since the
    # check only ever followed a container's first type argument.
    assert_true(is_wrapped_relation_type("Dict[String, @@Employee]"))
    assert_true(is_wrapped_relation_type("Dict[@@Employee, @@Department]"))
    assert_false(is_wrapped_relation_type("Dict[String, Int]"))


def test_find_next_marker_begin_init_from_json() raises:
    var s = Scanner('@@@begin_init_from_json(dump)')
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.BEGIN_INIT_FROM_JSON)
    var expr = s.parse_begin_init_from_json()
    assert_equal(expr, "dump")


def test_find_next_marker_init_from_json() raises:
    var s = Scanner('@@@init_from_json(dump)')
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.INIT_FROM_JSON)
    var expr = s.parse_init_from_json()
    assert_equal(expr, "dump")


def test_find_next_marker_end_init_from_json() raises:
    var s = Scanner("@@@end_init_from_json()")
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.END_INIT_FROM_JSON)
    s.parse_end_init_from_json()
    assert_true(s.at_end())


def test_find_next_marker_to_json() raises:
    var s = Scanner("@@@to_json()")
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.TO_JSON)
    s.parse_to_json()
    assert_true(s.at_end())


def test_json_call_arg_handles_nested_parens() raises:
    var s = Scanner('@@@begin_init_from_json(make_json(a, b))')
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.BEGIN_INIT_FROM_JSON)
    var expr = s.parse_begin_init_from_json()
    assert_equal(expr, "make_json(a, b)")


def test_end_init_from_json_rejects_nonempty_args() raises:
    """A non-empty '(...)' means `peek_empty_call_follows` doesn't match, so
    `find_next_marker` doesn't classify this as END_INIT_FROM_JSON at all
    (falls through to the generic '@@@ident(' -> WORLD_FUNC dispatch, same
    as `@@init(x)`'s own precedent) -- exercises `parse_end_init_from_json`
    directly instead, the same way its own argument-rejection logic would
    still run if reached some other way."""
    var s = Scanner("@@@end_init_from_json(x)")
    var raised = False
    try:
        s.parse_end_init_from_json()
    except:
        raised = True
    assert_true(raised)


def test_to_json_rejects_nonempty_args() raises:
    var s = Scanner("@@@to_json(x)")
    var raised = False
    try:
        s.parse_to_json()
    except:
        raised = True
    assert_true(raised)


def test_begin_init_from_json_plain_two_at_is_rejected() raises:
    """Every JSON marker needs 'sqrrl__world' (three `@`s), same rule every
    other M3-addendum construct/call/scope marker already enforces -- a
    plain `@@begin_init_from_json(...)` no longer raises at the scanner
    level (mandatory-marking milestone: plain `@@name(...)` is now a
    legitimate marker, `ENTITY_FUNC`, for a function that returns an
    `@@`-marked value without needing `sqrrl__world` -- the scanner can't
    yet tell `begin_init_from_json` isn't actually such a function, only
    `rewrite.mojo`'s own `handle_func_call_marker` can, once `ctx.
    function_returns` is available). This still surfaces as a real
    `InvalidSquirrelSyntax` end-to-end (`begin_init_from_json` is never a
    registered function), just one marker-kind classification later than
    before."""
    var s = Scanner("@@begin_init_from_json(dump)")
    var kind = s.find_next_marker()
    assert_true(kind == MarkerKind.ENTITY_FUNC)


def test_at_bare_struct_keyword_word_boundaries() raises:
    """`structural`/`mystruct` don't false-positive; `@@struct` (a DSL
    declaration) isn't a bare struct either -- only a real, hand-written
    `struct` keyword counts."""
    var s1 = Scanner("structural code")
    assert_false(s1.at_bare_struct_keyword())
    var s2 = Scanner("mystruct Foo")
    assert_false(s2.at_bare_struct_keyword())
    var s3 = Scanner("@@struct @@Person:")
    assert_false(s3.at_bare_struct_keyword())
    var s4 = Scanner("struct Address:")
    assert_true(s4.at_bare_struct_keyword())


def test_find_next_hand_written_plain_struct_decl_and_parse() raises:
    """Discovery pass for a hand-written plain struct (plain-structs
    milestone): name, its own `var name: Type`/`var @@name: @@Type` field
    declarations (a marked field's `type_str` comes back in the same
    `@@Employee` pseudo-shorthand every other relation field uses), and
    stops extracting fields at the first `def`/`fn` -- methods are real,
    hand-written Mojo, never parsed as fields."""
    var src = String(
        "struct Address(Copyable, Movable, ImplicitlyDeletable):\n"
        + "    var city: String\n"
        + "    var @@owner: @@Employee\n"
        + "\n"
        + "    def greeting(self) -> String:\n"
        + "        return self.city\n"
    )
    var s = Scanner(src)
    assert_true(s.find_next_hand_written_plain_struct_decl())
    var parsed = s.parse_hand_written_plain_struct()
    assert_equal(parsed.name, "Address")
    assert_equal(len(parsed.fields), 2)
    assert_equal(parsed.fields[0].name, "city")
    assert_equal(parsed.fields[0].type_str, "String")
    assert_equal(parsed.fields[1].name, "owner")
    assert_equal(parsed.fields[1].type_str, "@@Employee")
    assert_equal(len(parsed.type_params), 0)


def test_parse_hand_written_plain_struct_generic_type_params() raises:
    var src = String(
        "struct Box[T: Copyable & ImplicitlyDeletable](Movable, ImplicitlyDeletable):\n"
        + "    var value: Self.T\n"
    )
    var s = Scanner(src)
    assert_true(s.find_next_hand_written_plain_struct_decl())
    var parsed = s.parse_hand_written_plain_struct()
    assert_equal(parsed.name, "Box")
    assert_equal(len(parsed.type_params), 1)
    assert_equal(parsed.type_params[0].name, "T")
    assert_equal(parsed.type_params[0].bound, "Copyable & ImplicitlyDeletable")
    # `Self.T` is unqualified back to bare `T` -- means nothing outside
    # the struct's own body, so every downstream consumer (relation-schema,
    # JSON's generated `from_json`) is a free function where `Self` doesn't
    # exist at all.
    assert_equal(len(parsed.fields), 1)
    assert_equal(parsed.fields[0].type_str, "T")


def test_type_expr_generic_plain_struct_instantiation_with_relation_arg() raises:
    """Plain-structs milestone: a generic plain struct's own instantiation
    is never itself `@@`-marked (only an individual argument might be --
    plan's Revision 2 point 2, which reverted an earlier draft's plan to
    make `@@`-prefixed text recurse into brackets -- that's unneeded, since
    `Box[@@Employee]`'s outer wrapper was always going to reach the
    existing PARAMETERIZED branch, which already recurses into args
    correctly). `Box[@@Employee]` parses as a bare PARAMETERIZED `Box`
    wrapping a RELATION arg -- `render()` round-trips it."""
    var t = parse_type_expr("Box[@@Employee]")
    assert_true(t.is_parameterized())
    assert_equal(t.name, "Box")
    assert_equal(t.arg_count(), 1)
    assert_true(t.arg(0).is_relation())
    assert_equal(t.arg(0).name, "Employee")
    assert_equal(t.render(), "Box[@@Employee]")

    # A marked relation still doesn't recurse into its own bracket -- `@@`
    # strips to one opaque name, matching every other relation field.
    var marked = parse_type_expr("@@Employee")
    assert_true(marked.is_relation())
    assert_equal(marked.arg_count(), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
