from std.testing import assert_equal, assert_true, assert_false, TestSuite

from squirrel_runtime.json import (
    sqrrl__JsonScanner,
    sqrrl__escape_json_string,
    sqrrl__json_string_literal,
    sqrrl__json_bool_literal,
    sqrrl__to_json,
    sqrrl__JsonSerializable,
)


@fieldwise_init
struct _FakeEntity(sqrrl__JsonSerializable, Movable, ImplicitlyDeletable):
    """Stands in for a generated entity wrapper -- conforms to
    `sqrrl__JsonSerializable` directly, same as `codegen/entity.mojo`'s
    `emit_entity` adds to every real one, to exercise `sqrrl__to_json[T]`'s
    `conforms_to` branch without needing a whole generated table/world."""

    var row_id: UInt32

    def sqrrl__to_json(self) -> String:
        return String(self.row_id)


@fieldwise_init
struct _Inner(Copyable, Movable, ImplicitlyDeletable):
    var label: String
    var count: UInt32


@fieldwise_init
struct _Outer(Copyable, Movable, ImplicitlyDeletable):
    var name: String
    var inner: _Inner


def test_escape_json_string_handles_quotes_backslash_and_control_chars() raises:
    assert_equal(sqrrl__escape_json_string("plain"), "plain")
    assert_equal(sqrrl__escape_json_string('he said "hi"'), 'he said \\"hi\\"')
    assert_equal(sqrrl__escape_json_string("a\\b"), "a\\\\b")
    assert_equal(sqrrl__escape_json_string("line1\nline2\ttab\rcr"), "line1\\nline2\\ttab\\rcr")


def test_json_string_literal_wraps_and_escapes() raises:
    assert_equal(sqrrl__json_string_literal("alice"), '"alice"')
    assert_equal(sqrrl__json_string_literal('a"b'), '"a\\"b"')


def test_json_bool_literal_is_lowercase() raises:
    assert_equal(sqrrl__json_bool_literal(True), "true")
    assert_equal(sqrrl__json_bool_literal(False), "false")


def test_scanner_parses_string_with_standard_escapes() raises:
    var sc = sqrrl__JsonScanner('"he said \\"hi\\"\\nnext\\tline\\\\end"')
    assert_equal(sc.parse_json_string(), 'he said "hi"\nnext\tline\\end')
    assert_true(sc.at_end())


def test_scanner_parses_string_rejects_unicode_escape() raises:
    """Known, documented limitation -- no `\\uXXXX` support."""
    var sc = sqrrl__JsonScanner('"\\u0041"')
    var raised = False
    try:
        _ = sc.parse_json_string()
    except:
        raised = True
    assert_true(raised)


def test_scanner_parses_int_positive_and_negative() raises:
    var sc = sqrrl__JsonScanner("42")
    assert_equal(sc.parse_json_int(), 42)
    var sc2 = sqrrl__JsonScanner("-17")
    assert_equal(sc2.parse_json_int(), -17)


def test_scanner_parses_float() raises:
    var sc = sqrrl__JsonScanner("-3.5")
    assert_equal(sc.parse_json_float(), -3.5)


def test_scanner_parses_bool() raises:
    var sc = sqrrl__JsonScanner("true")
    assert_true(sc.parse_json_bool())
    var sc2 = sqrrl__JsonScanner("false")
    assert_false(sc2.parse_json_bool())


def test_scanner_bool_rejects_other_text() raises:
    var sc = sqrrl__JsonScanner("nope")
    var raised = False
    try:
        _ = sc.parse_json_bool()
    except:
        raised = True
    assert_true(raised)


def test_scanner_structural_bytes_skip_whitespace() raises:
    var sc = sqrrl__JsonScanner('  {  "a"  :  1  ,  "b" : 2 }')
    sc.expect_byte(UInt8(ord("{")))
    assert_equal(sc.parse_json_string(), "a")
    sc.expect_byte(UInt8(ord(":")))
    assert_equal(sc.parse_json_int(), 1)
    assert_true(sc.try_consume_byte(UInt8(ord(","))))
    assert_equal(sc.parse_json_string(), "b")
    sc.expect_byte(UInt8(ord(":")))
    assert_equal(sc.parse_json_int(), 2)
    assert_false(sc.try_consume_byte(UInt8(ord(","))))
    sc.expect_byte(UInt8(ord("}")))
    assert_true(sc.at_end())


def test_scanner_expect_byte_raises_on_mismatch() raises:
    var sc = sqrrl__JsonScanner("[")
    var raised = False
    try:
        sc.expect_byte(UInt8(ord("{")))
    except:
        raised = True
    assert_true(raised)


def test_round_trip_through_literal_helpers_and_scanner() raises:
    var original = 'quote " and backslash \\ and newline\n'
    var literal = sqrrl__json_string_literal(original)
    var sc = sqrrl__JsonScanner(literal)
    assert_equal(sc.parse_json_string(), original)


def test_sqrrl_to_json_leaf_types() raises:
    assert_equal(sqrrl__to_json(String("hi")), '"hi"')
    assert_equal(sqrrl__to_json(Bool(True)), "true")
    assert_equal(sqrrl__to_json(Bool(False)), "false")
    assert_equal(sqrrl__to_json(Int(42)), "42")
    assert_equal(sqrrl__to_json(UInt32(7)), "7")
    assert_equal(sqrrl__to_json(Float64(2.0)), "2.0")


def test_sqrrl_to_json_dispatches_json_serializable_conformance_to_bare_id() raises:
    """A real entity wrapper's own value is always just its bare id (the
    row itself is dumped once, separately, as part of its own table's own
    dump) -- `sqrrl__to_json[T]` picks this branch via `conforms_to(T,
    sqrrl__JsonSerializable)`, never the `reflect[T]` fallback, for
    anything that conforms."""
    var e = _FakeEntity(row_id=9)
    assert_equal(sqrrl__to_json(e), "9")


def test_sqrrl_to_json_reflects_nested_plain_struct_at_any_depth() raises:
    """The `reflect[T]` fallback -- anything that's neither a known leaf
    nor `sqrrl__JsonSerializable` -- walks field names/types/offsets at
    comptime and recurses back into `sqrrl__to_json` per field, so this
    needs no generated code and no DSL-side declaration at all (plan's
    §7), including through a struct nested inside another one."""
    var o = _Outer(name="alice", inner=_Inner(label="x", count=3))
    assert_equal(sqrrl__to_json(o), '{"name":"alice","inner":{"label":"x","count":3}}')


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
