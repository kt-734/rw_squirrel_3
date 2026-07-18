from squirrel_compiler.parser import (
    ParsedStruct,
    Field,
    FieldModifier,
    parse_type_expr,
    TypeExpr,
    TypeParam,
)
from squirrel_compiler.codegen.helpers import (
    sqrrl_prefixed,
    is_relation_field,
    needs_move_assignment,
    storage_field_name,
    param_name,
    emit_field_type,
    emit_multi_element_type,
    is_container_type,
    rewritten_field_type,
)
from squirrel_compiler.analysis import collect_relation_targets, collect_plain_struct_targets
from squirrel_compiler.driver.discovery import DiscoveredStruct, PlainStructDiscovery
from std.memory import ArcPointer

# Generates `sqrrl__json.mojo` -- every JSON-related symbol for the whole
# project, in one file, per the user's own non-negotiable constraint (see
# the M5 plan, "Non-negotiable constraint"): free functions operating on
# `sqrrl__World`/a specific `Table`/an entity passed in as an ordinary
# parameter, never a method added to `sqrrl__World` or any generated
# `sqrrl__<Name>Table`.
#
# Plain-structs milestone (see the plan's §7): `to_json` is now fully
# automatic for *any* field value via `squirrel_runtime.json`'s generic,
# reflection-based `sqrrl__to_json[T]` -- `_emit_to_json` below emits one
# uniform `sqrrl__to_json(e._inner[].get_<field>())` call per field
# regardless of whether it's a leaf, a relation to a real entity, or a
# plain-struct value, at any nesting depth. `from_json` still needs
# generated code (reflection can't write fields back) -- for every plain
# struct discovered (generic or not, reachable from some real @@struct's
# own field graph), `_emit_plain_struct_from_json` generates a
# `sqrrl__<Name>_from_json[<T: Bound, ...>](...)` companion, re-declaring
# the struct's own type parameter list, reusing the same field list
# `parser/scanner.mojo`'s `parse_hand_written_plain_struct` already
# extracts. The one genuine gap left: a field typed as the struct's own
# *bare, unbound* type parameter (`Box[T]`'s `value: T`) can't be parsed
# generically -- there's no concrete type to call a `from_json` companion
# on, `T` being a compile-time parameter of the generated function itself,
# not a real type name -- `_leaf_from_json_expr` raises a clear, distinct
# error for exactly this shape rather than guessing. Everything else
# unrecognized at the LEAF level -- a genuinely undiscovered hand-written
# type, never scanned as `@@struct` or a plain struct anywhere in the
# project (e.g. a plain `home: ExternalAddress` field imported from an
# ordinary, never-`.mojo.sqrrl` module) -- gets an escape hatch instead of
# a raise: a hand-written `sqrrl__<TypeName>_from_json(mut sc:
# sqrrl__JsonScanner) raises -> TypeName` companion is assumed to exist
# and called directly, imported from wherever the referencing struct's
# own module sources the type (`_collect_custom_leaf_types`), the same
# convention/mechanism the custom container-wrapper escape hatch below
# already established.
#
# `List`/`Set`/`Optional`/`Dict`-shaped ("`@@container`") fields other than
# `multi` (which has its own dedicated Set-of-ids iteration) ARE
# JSON-supported, at arbitrary nesting depth -- `_container_wrapper_kind`/
# `_parse_value_expr`/`_emit_field_json_parse` generalize the same
# per-field explicit-codegen approach `multi` always used, to an arbitrary
# element kind (leaf/relation/plain-struct/*another container*, recursively)
# and wrapper (List/Set/Optional/Dict, or a custom single-type-argument
# wrapper via a hand-written `sqrrl__<Wrapper>_json_to_list`/`_json_from_
# list` escape-hatch pair -- see `_parse_value_expr`'s own doc comment),
# matching and then exceeding
# rw_squirrel_1/2's own parity here (confirmed by reading their real source,
# not assumed) -- `sqrrl__to_json[T]`'s reflection genuinely can't walk a
# container's own internal representation generically, which is why this
# needs real, per-shape codegen rather than a generic dispatcher, same as
# `multi` always did. Only a 2+-argument wrapper other than `Dict` stays
# genuinely unsupported (no defined JSON shape for arbitrary multi-argument
# container semantics) -- raises a clear codegen-time error instead of
# emitting Mojo that wouldn't compile (or worse, would compile but
# serialize garbage).


def _relation_target_name(f: Field) -> String:
    return String(f.type_str[byte=2 : f.type_str.byte_length()])


def _container_wrapper_kind(t: TypeExpr) -> String:
    """Classifies a container-shaped `TypeExpr`'s own JSON dump/reload
    shape -- `"array"` (`List`/`Set`/any custom single-type-argument
    wrapper, via an escape hatch -- see `_parse_value_expr`), `"optional"`
    (`Optional` -- null-or-value, not an array), `"dict"` (`Dict` -- an
    array of `[key,value]` pairs, the one two-argument wrapper with a
    defined JSON shape), or `""` for anything else (any other 2+-argument
    wrapper -- genuinely ambiguous, stays rejected: a JSON array can't
    represent arbitrary multi-argument container semantics generically the
    way it can a single-typed membership or a defined key/value pairing)."""
    if t.arg_count() == 1:
        return "optional" if t.name == "Optional" else "array"
    if t.arg_count() == 2 and t.name == "Dict":
        return "dict"
    return ""


def _is_supported_container_field(f: Field) -> Bool:
    """True for any container-shaped, non-`multi` field `_container_
    wrapper_kind` recognizes -- the field-level gate shared by `_emit_to_
    json`'s dump dispatch and `_emit_from_json_with_id`/`_emit_plain_
    struct_from_json`'s reload dispatch, so the two directions can't drift
    apart into an asymmetric half-support."""
    if f.modifier == FieldModifier.MULTI or not is_container_type(f.type_str):
        return False
    return _container_wrapper_kind(parse_type_expr(f.type_str)) != ""


def _substitute_type_params_expr(
    t: TypeExpr, type_params: List[TypeParam], type_args: List[TypeExpr]
) -> TypeExpr:
    """Walks `t` (a parsed field type), replacing every `LEAF` node whose
    name matches one of `type_params`'s own names with the correspondingly
    -positioned entry in `type_args` -- e.g. substituting `T -> String`
    turns `List[T]` into `List[String]`. Leaves a `RELATION` node alone
    (never a type parameter's own name, since `@@T` isn't grammar this DSL
    accepts) and a `PARAMETERIZED` node's own wrapper name alone too
    (`List`, `Dict`, a plain struct's own name), recursing only into
    `args`. Falls back to leaving a parameter's own name bare if `type_
    args` doesn't have a correspondingly-positioned entry (a malformed
    instantiation with too few type arguments) -- this function's job is
    to emit useful Mojo, not validate arity; a genuinely wrong arity
    surfaces as an ordinary Mojo compile error downstream instead.

    Ported from rw_squirrel_2's own identical `substitute_type_params_
    expr` (confirmed by reading their real source) -- needed here for
    `_type_involves_relation`'s own walk into a generic plain struct's
    fields at a concrete instantiation: e.g. `Box[@@Employee]`'s own
    `value: T` field only reveals it reaches a relation once `T` is
    actually substituted with `@@Employee`; `analysis.collect_relation_
    targets`/`collect_plain_struct_targets` don't do this substitution at
    all (confirmed by reading them) since they've never needed to before
    -- a bare type parameter's own field previously only ever raised a
    dedicated error, never reached generated-code-shape decisions like
    this one."""
    if t.kind == TypeExpr.LEAF:
        for idx in range(len(type_params)):
            if type_params[idx].name == t.name:
                if idx < len(type_args):
                    return type_args[idx].copy()
                return t.copy()
        return t.copy()
    if t.kind == TypeExpr.PARAMETERIZED:
        var new_args = List[ArcPointer[TypeExpr]]()
        for i in range(t.arg_count()):
            new_args.append(ArcPointer(_substitute_type_params_expr(t.arg(i), type_params, type_args)))
        return TypeExpr(kind=TypeExpr.PARAMETERIZED, name=t.name, args=new_args^)
    return t.copy()


def _type_involves_relation(
    t: TypeExpr,
    plain_struct_fields: Dict[String, List[Field]],
    plain_struct_type_params: Dict[String, List[TypeParam]],
) raises -> Bool:
    """True if `t` reaches a relation anywhere in its own structure -- a
    bare `@@Employee`, or one nested inside a container (`List[
    @@Employee]`, at any depth) or inside a discovered plain struct's own
    field graph (`Address`'s `@@owner: @@Employee`, or -- the case that
    needs `_substitute_type_params_expr` -- a generic plain struct's own
    bare-type-parameter field once actually substituted with a relation
    type argument, `Box[@@Employee]`'s own `value: T`).

    The single field-level gate deciding which of two entirely different
    reload/dump mechanisms a container-shaped (or generic-plain-struct-
    bare-type-param-shaped) field goes through: `True` keeps using the
    existing, unchanged `_parse_value_expr`/`_dump_value_expr` recursive
    codegen (the only mechanism that can thread a relation's own sibling
    table through, at any nesting depth); `False` routes the *whole*
    field through the shared, generic `sqrrl__to_json`/`sqrrl__from_json[
    T]` dispatcher instead (`driver/json_module.mojo`'s own module doc
    comment has the full rationale for why these two mechanisms can't
    simply be unified into one)."""
    if t.is_relation():
        return True
    if t.name in plain_struct_fields:
        var type_params = (
            plain_struct_type_params[t.name].copy() if t.name in plain_struct_type_params else List[TypeParam]()
        )
        var type_args = List[TypeExpr]()
        for i in range(t.arg_count()):
            type_args.append(t.arg(i).copy())
        for f in plain_struct_fields[t.name]:
            var raw = parse_type_expr(f.type_str)
            var substituted = _substitute_type_params_expr(raw, type_params, type_args)
            if _type_involves_relation(substituted, plain_struct_fields, plain_struct_type_params):
                return True
        return False
    for i in range(t.arg_count()):
        if _type_involves_relation(t.arg(i), plain_struct_fields, plain_struct_type_params):
            return True
    return False


def _collect_dispatch_types_from_type(
    t: TypeExpr,
    plain_struct_fields: Dict[String, List[Field]],
    plain_struct_type_params: Dict[String, List[TypeParam]],
    plain_struct_names: Dict[String, Bool],
    mut seen_container: Dict[String, Bool],
    mut container_out: List[TypeExpr],
    mut seen_plain: Dict[String, Bool],
    mut plain_out: List[TypeExpr],
) raises:
    """Collects every distinct, relation-free concrete type reachable from
    `t` that the generated `sqrrl__to_json[T]`/`sqrrl__from_json[T]`
    dispatch table (`emit_json_module`) needs its own explicit `elif T ==
    ...:` branch for -- a container (`List`/`Set`/`Optional`/`Dict`, or a
    custom single/double-type-argument wrapper) into `container_out`, or a
    discovered plain struct's own concrete instantiation (bare or generic)
    into `plain_out`. Recurses into a *relation-free* match's own element/
    field types too (a container's element might itself be another
    container or a plain struct; a plain struct's own field might be
    another container/plain struct, or -- the case this whole mechanism
    exists for -- its *own* bare type parameter, substituted here to
    whatever concrete type this particular instantiation actually uses).

    A relation-*involving* subtree is skipped entirely, not partially
    registered -- `_type_involves_relation` gates both branches below,
    matching the same field-level gate `_emit_to_json`/`_emit_from_json_
    with_id`/`_emit_plain_struct_from_json` use to decide whether a whole
    field routes through this dispatch table or keeps using the existing
    `_parse_value_expr`/`_dump_value_expr` codegen -- a relation nested
    *inside* an otherwise-dispatched subtree could never actually occur
    once that gate is applied consistently at the field level, but this
    function checks it again anyway at every recursion step: it's also
    reachable directly (a plain struct's own field graph can be walked
    from more than one field, at different nesting depths, independently
    of whichever top-level field first triggered the walk)."""
    if t.name in plain_struct_names:
        if _type_involves_relation(t, plain_struct_fields, plain_struct_type_params):
            return
        if t.render() not in seen_plain:
            seen_plain[t.render()] = True
            plain_out.append(t.copy())
        var type_params = (
            plain_struct_type_params[t.name].copy() if t.name in plain_struct_type_params else List[TypeParam]()
        )
        var type_args = List[TypeExpr]()
        for i in range(t.arg_count()):
            type_args.append(t.arg(i).copy())
        for f in plain_struct_fields[t.name]:
            var raw = parse_type_expr(f.type_str)
            var substituted = _substitute_type_params_expr(raw, type_params, type_args)
            _collect_dispatch_types_from_type(
                substituted, plain_struct_fields, plain_struct_type_params, plain_struct_names,
                seen_container, container_out, seen_plain, plain_out,
            )
        return
    if not t.is_parameterized():
        return
    if _container_wrapper_kind(t) == "":
        return
    if _type_involves_relation(t, plain_struct_fields, plain_struct_type_params):
        return
    if t.render() not in seen_container:
        seen_container[t.render()] = True
        container_out.append(t.copy())
    for i in range(t.arg_count()):
        _collect_dispatch_types_from_type(
            t.arg(i), plain_struct_fields, plain_struct_type_params, plain_struct_names,
            seen_container, container_out, seen_plain, plain_out,
        )


def _collect_dispatch_types(
    fields: List[Field],
    plain_struct_fields: Dict[String, List[Field]],
    plain_struct_type_params: Dict[String, List[TypeParam]],
    plain_struct_names: Dict[String, Bool],
    mut seen_container: Dict[String, Bool],
    mut container_out: List[TypeExpr],
    mut seen_plain: Dict[String, Bool],
    mut plain_out: List[TypeExpr],
) raises:
    for f in fields:
        if f.modifier == FieldModifier.MULTI:
            continue
        _collect_dispatch_types_from_type(
            parse_type_expr(f.type_str), plain_struct_fields, plain_struct_type_params, plain_struct_names,
            seen_container, container_out, seen_plain, plain_out,
        )


def _parse_value_expr(
    t: TypeExpr,
    plain_struct_fields: Dict[String, List[Field]],
    plain_struct_names: Dict[String, Bool],
    struct_name: String,
    field_name: String,
    indent: String,
    mut tmp_id: Int,
    mut out: String,
    type_param_names: Dict[String, Bool] = Dict[String, Bool](),
) raises -> String:
    """The generated-code *expression* evaluating to one parsed JSON value
    of type `t`, off `sqrrl__sc` -- the single recursive core every
    `from_json` parse path (a whole field's own declared type, or one
    element nested inside a container, at any depth) goes through.

    For a leaf/relation/discovered-plain-struct `t`, this is a single
    nested-call expression with no side effect on `out` at all (safe to
    inline directly into an outer container's own `.append(...)`/`.add(
    ...)` call -- a relation element's own id-parse, `sqrrl__sc.parse_
    json_int()`, is itself just a nested call, no intermediate named
    variable needed). For a *container* `t`, there's no single-expression
    reading of a JSON array/object, so this instead emits a complete parse
    loop into `out` (a local uniquely suffixed by `tmp_id`, captured once
    per call so nested/sibling emissions inside the same field's own
    generated function never collide) and returns that local's own name,
    already `^`-moved (every container type this project builds one of is
    either known non-`ImplicitlyCopyable`, or it's always safe to move
    regardless).

    A custom container wrapper (anything other than `List`/`Set`/
    `Optional`/`Dict`) gets an escape hatch, in the same spirit as an
    undiscovered relation target's own `from_json`: rather than assuming
    a no-arg constructor and a guessable build-up method exist (a
    `@fieldwise_init` struct's own synthesized `__init__` takes every
    field, not zero of them, and there's no trait contract this compiler
    can rely on for "how do I build an arbitrary container from parsed
    elements" generically), the elements are parsed into an ordinary
    `List` -- something this function already knows how to build
    unconditionally -- and the *whole list* is handed to a hand-written
    `sqrrl__<Wrapper>_json_from_list(var items: List[T]) -> Wrapper[T]`
    companion for the wrapper to construct itself from however it likes.
    `_emit_to_json`'s own dump direction uses the mirror-image `sqrrl__
    <Wrapper>_json_to_list(container: Wrapper[T]) -> List[T]` for the same
    reason (a custom wrapper isn't guaranteed to implement `__iter__`
    either)."""
    if t.is_relation():
        var target = t.name
        return (
            sqrrl_prefixed(target)
            + "(sqrrl__tbl_"
            + target
            + ".storage[].handle_for(UInt32(sqrrl__sc.parse_json_int())))"
        )
    if t.name in plain_struct_names:
        return _plain_struct_from_json_call(t, plain_struct_fields, plain_struct_names)
    if t.kind == TypeExpr.LEAF:
        return _leaf_from_json_expr(struct_name, field_name, t.name, type_param_names)

    var kind = _container_wrapper_kind(t)
    tmp_id += 1
    var this_id = tmp_id
    var var_name = "sqrrl__nc" + String(this_id)

    if kind == "optional":
        ref elem = t.arg(0)
        var elem_type_str = rewritten_field_type(elem.render(), plain_struct_names)
        out += indent + "var " + var_name + ": Optional[" + elem_type_str + "]\n"
        out += indent + "if sqrrl__sc.try_consume_literal(\"null\"):\n"
        out += indent + "    " + var_name + " = Optional[" + elem_type_str + "]()\n"
        out += indent + "else:\n"
        var elem_expr = _parse_value_expr(
            elem, plain_struct_fields, plain_struct_names, struct_name, field_name, indent + "    ", tmp_id, out, type_param_names
        )
        out += indent + "    " + var_name + " = Optional[" + elem_type_str + "](" + elem_expr + ")\n"
        return var_name + "^"

    if kind == "array":
        ref elem = t.arg(0)
        var elem_type_str = rewritten_field_type(elem.render(), plain_struct_names)
        var wrapper = t.name
        var is_custom = wrapper != "List" and wrapper != "Set"
        # A custom wrapper is neither guaranteed to have a no-arg
        # constructor (a `@fieldwise_init` struct's own synthesized
        # `__init__` takes every field, not zero of them -- confirmed via
        # a real compile, not assumed) nor a `.append`/`.add` method with
        # a guessable name -- so it's built as an ordinary `List` here
        # (exactly like the built-in `List` case), then converted via a
        # hand-written `sqrrl__<Wrapper>_json_from_list` companion at the
        # very end, rather than trying to construct/populate the custom
        # type directly. `Set` stays as its own real, direct build (both
        # its no-arg constructor and `.add` are already established,
        # matching `multi`'s own long-working precedent).
        var build_wrapper = "Set" if wrapper == "Set" else "List"
        out += indent + "var " + var_name + " = " + build_wrapper + "[" + elem_type_str + "]()\n"
        out += indent + "sqrrl__sc.expect_byte(UInt8(ord(\"[\")))\n"
        out += indent + "if not sqrrl__sc.try_consume_byte(UInt8(ord(\"]\"))):\n"
        out += indent + "    while True:\n"
        var elem_expr = _parse_value_expr(
            elem, plain_struct_fields, plain_struct_names, struct_name, field_name, indent + "        ", tmp_id, out, type_param_names
        )
        var builder = "add" if build_wrapper == "Set" else "append"
        out += indent + "        " + var_name + "." + builder + "(" + elem_expr + ")\n"
        out += indent + "        if not sqrrl__sc.try_consume_byte(UInt8(ord(\",\"))):\n"
        out += indent + "            break\n"
        out += indent + "    sqrrl__sc.expect_byte(UInt8(ord(\"]\")))\n"
        if is_custom:
            return "sqrrl__" + wrapper + "_json_from_list(" + var_name + "^)"
        return var_name + "^"

    if kind == "dict":
        ref key_t = t.arg(0)
        ref val_t = t.arg(1)
        var key_type_str = rewritten_field_type(key_t.render(), plain_struct_names)
        var val_type_str = rewritten_field_type(val_t.render(), plain_struct_names)
        var key_var = "sqrrl__nck" + String(this_id)
        out += indent + "var " + var_name + " = Dict[" + key_type_str + ", " + val_type_str + "]()\n"
        out += indent + "sqrrl__sc.expect_byte(UInt8(ord(\"[\")))\n"
        out += indent + "if not sqrrl__sc.try_consume_byte(UInt8(ord(\"]\"))):\n"
        out += indent + "    while True:\n"
        out += indent + "        sqrrl__sc.expect_byte(UInt8(ord(\"[\")))\n"
        var key_expr = _parse_value_expr(
            key_t, plain_struct_fields, plain_struct_names, struct_name, field_name, indent + "        ", tmp_id, out, type_param_names
        )
        out += indent + "        var " + key_var + " = " + key_expr + "\n"
        out += indent + "        sqrrl__sc.expect_byte(UInt8(ord(\",\")))\n"
        var val_expr = _parse_value_expr(
            val_t, plain_struct_fields, plain_struct_names, struct_name, field_name, indent + "        ", tmp_id, out, type_param_names
        )
        out += indent + "        " + var_name + "[" + key_var + "] = " + val_expr + "\n"
        out += indent + "        sqrrl__sc.expect_byte(UInt8(ord(\"]\")))\n"
        out += indent + "        if not sqrrl__sc.try_consume_byte(UInt8(ord(\",\"))):\n"
        out += indent + "            break\n"
        out += indent + "    sqrrl__sc.expect_byte(UInt8(ord(\"]\")))\n"
        return var_name + "^"

    raise Error(
        "JSON serialization: field '"
        + field_name
        + "' on '"
        + struct_name
        + "' has type '"
        + t.render_relation_stripped()
        + "' -- @@container JSON reload doesn't support this container"
        " shape (List/Set/Optional/Dict, or a single-type-argument custom"
        " wrapper via a hand-written 'sqrrl__<Wrapper>_json_from_list'/"
        "'sqrrl__<Wrapper>_json_to_list' pair, are the only ones supported)"
    )


def _emit_field_json_parse(
    f: Field,
    struct_name: String,
    plain_struct_fields: Dict[String, List[Field]],
    plain_struct_names: Dict[String, Bool],
    type_param_names: Dict[String, Bool] = Dict[String, Bool](),
) raises -> String:
    """`from_json` reconstruction for any container-shaped, non-`multi`
    field -- a thin per-field wrapper around the recursive `_parse_value_
    expr`, assigning its result into the field's own `Optional[...]`
    tracking local (same key-dispatch scaffold every other field kind
    already uses)."""
    var t = parse_type_expr(f.type_str)
    var tmp_id = 0
    var out = String()
    var expr = _parse_value_expr(
        t, plain_struct_fields, plain_struct_names, struct_name, f.name, "                ", tmp_id, out, type_param_names
    )
    out += "                sqrrl__parsed_" + f.name + " = " + expr + "\n"
    return out^


def _sibling_relation_targets(
    fields: List[Field], plain_struct_fields: Dict[String, List[Field]]
) raises -> List[String]:
    """Every distinct real struct `fields` needs a live table reference to
    reach, direct *or* transitive through an embedded plain struct's own
    relation field -- one sibling `sqrrl__tbl_<Target>: sqrrl__<Target>Table`
    parameter per entry, needed by `_from_json_with_id` (or a plain
    struct's own generated `from_json`) to reconstruct a live handle from a
    bare stored id. Shared with `driver/cycles.mojo`'s own project-wide
    relation-graph walk (`analysis/relation_targets.mojo`)."""
    var seen = Dict[String, Bool]()
    var out = List[String]()
    collect_relation_targets(fields, plain_struct_fields, seen, out)
    return out^


def _is_json_unsupported_container_field(f: Field) -> Bool:
    """True for a container-shaped field JSON genuinely can't handle at
    all -- any 2+-argument wrapper other than `Dict` (`_is_supported_
    container_field` returns `False`); `multi` fields never reach here,
    they're dispatched separately. A container whose *wrapper* is
    supported but whose *element* type isn't parseable raises its own,
    more specific error lazily inside `_parse_value_expr` instead -- this
    check only ever fires for the wrapper shape itself."""
    return f.modifier != FieldModifier.MULTI and is_container_type(f.type_str) and not _is_supported_container_field(f)


def _unsupported_container_field_error(struct_name: String, field_name: String, type_str: String) -> Error:
    return Error(
        "JSON serialization: field '"
        + field_name
        + "' on '"
        + struct_name
        + "' has type '"
        + type_str
        + "' -- @@@to_json/@@@init_from_json don't support this container"
        " shape (List/Set/Optional/Dict, 'multi', or a single-type-"
        "argument custom wrapper are the only ones supported)"
    )


def _is_integer_leaf(t: String) -> Bool:
    return (
        t == "Int"
        or t == "Int8"
        or t == "Int16"
        or t == "Int32"
        or t == "Int64"
        or t == "UInt8"
        or t == "UInt16"
        or t == "UInt32"
        or t == "UInt64"
    )


def _is_known_leaf_type(type_str: String) -> Bool:
    """True for a type name `_leaf_from_json_expr` already knows how to
    parse with no hand-written help at all -- String/Bool/Float32/64/an
    Int-family name. Anything else reaching the LEAF branch is either a
    genuinely undiscovered hand-written type (gets the escape hatch --
    see `_leaf_from_json_expr`) or a plain struct's own bare, unbound
    type parameter (kept as its own explicit, distinct error there)."""
    return type_str == "String" or type_str == "Bool" or type_str == "Float64" or type_str == "Float32" or _is_integer_leaf(type_str)


def _unbound_type_param_field_error(struct_name: String, field_name: String, type_str: String) -> Error:
    return Error(
        "JSON serialization: field '"
        + field_name
        + "' on '"
        + struct_name
        + "' has type '"
        + type_str
        + "' -- a generic plain struct's own bare, unbound type parameter"
        " can't be reconstructed by @@@init_from_json (there's no"
        " concrete type to call a 'from_json' companion on); give the"
        " field a concrete type instead"
    )


def _leaf_from_json_expr(
    struct_name: String,
    field_name: String,
    type_str: String,
    type_param_names: Dict[String, Bool] = Dict[String, Bool](),
) raises -> String:
    """The generated-code expression parsing a leaf-typed field's own JSON
    value off `sqrrl__sc`. A genuinely undiscovered hand-written type
    (never scanned as `@@struct` or a plain struct anywhere in the
    project -- e.g. a plain `home: ExternalAddress` field imported from an
    ordinary, never-`.mojo.sqrrl` module) falls back to a hand-written
    `sqrrl__<TypeName>_from_json(mut sc: sqrrl__JsonScanner) raises ->
    TypeName` escape-hatch companion, the same convention the custom
    container-wrapper escape hatch above already established (`to_json`
    stays fully automatic either way, via `sqrrl__to_json[T]`'s own
    reflection -- only the reload direction ever needs generated/hand-
    written code, reflection can't write fields back).

    A struct's own bare, unbound type parameter (`Box[T]`'s `value: T`)
    is excluded from that fallback, not guessed at as an escape hatch --
    there's no concrete `sqrrl__T_from_json` to call; `T` is a
    compile-time parameter of the *generated* function itself, not a
    real type name, so it gets its own explicit, distinct error instead
    of a confusing "undefined name" from a downstream Mojo compile."""
    if type_str == "String":
        return "sqrrl__sc.parse_json_string()"
    if type_str == "Bool":
        return "sqrrl__sc.parse_json_bool()"
    if type_str == "Float64" or type_str == "Float32":
        return type_str + "(sqrrl__sc.parse_json_float())"
    if _is_integer_leaf(type_str):
        return type_str + "(sqrrl__sc.parse_json_int())"
    if type_str in type_param_names:
        raise _unbound_type_param_field_error(struct_name, field_name, type_str)
    return "sqrrl__" + type_str + "_from_json(sqrrl__sc)"


def _plain_struct_value_base(f: Field, plain_struct_names: Dict[String, Bool]) -> Optional[TypeExpr]:
    """If `f` is a plain-value field (not a relation) whose declared type's
    own base name is a known plain struct -- bare (`Address`) or a generic
    instantiation (`Box[String]`) -- returns its parsed `TypeExpr`, else
    `None`."""
    if is_relation_field(f):
        return None
    var t = parse_type_expr(f.type_str)
    if t.name in plain_struct_names:
        return t^
    return None


def _plain_struct_from_json_call(
    t: TypeExpr,
    plain_struct_fields: Dict[String, List[Field]],
    plain_struct_names: Dict[String, Bool],
) raises -> String:
    """The generated-code expression reconstructing a plain-struct-valued
    value's own nested JSON object off `sqrrl__sc`, via its auto-generated
    `sqrrl__<Base>_from_json` companion (`_emit_plain_struct_from_json`).
    Sibling table arguments are computed the same way for the callee as for
    the caller (`_sibling_relation_targets`, itself recursive through
    further embedded plain structs) -- since the caller's own sibling list
    was already flattened *through* this exact plain struct, every
    `sqrrl__tbl_<Target>` this call needs is guaranteed already in scope.

    A generic instantiation (`item: Box[String]`/`item: Box[@@Employee]`)
    supplies its own explicit `[...]` type-argument list, rendered through
    `rewritten_field_type` on each argument's own marked source text
    (`t.arg(i).render()`) -- the exact same relation-vs-plain-struct
    rewriting every other field type already goes through, just applied
    one argument at a time here instead of to a whole field's type."""
    var base = t.name
    var type_args = String()
    if t.arg_count() > 0:
        type_args += "["
        for i in range(t.arg_count()):
            if i > 0:
                type_args += ", "
            type_args += rewritten_field_type(t.arg(i).render(), plain_struct_names)
        type_args += "]"
    var call = "sqrrl__" + base + "_from_json" + type_args + "("
    var base_fields = plain_struct_fields[base].copy() if base in plain_struct_fields else List[Field]()
    var siblings = _sibling_relation_targets(base_fields, plain_struct_fields)
    for target in siblings:
        call += "sqrrl__tbl_" + target + ", "
    call += "sqrrl__sc)"
    return call^


def _quoted(s: String) -> String:
    """Mojo source text for a double-quoted string literal whose *value* is
    exactly `s` -- for comparing/passing a field or struct name as an
    ordinary Mojo string literal in generated code. Never escaped: the
    parser guarantees both are plain identifiers, so `s` itself never
    contains a quote of either kind."""
    return '"' + s + '"'


def _json_key_literal_source(name: String) -> String:
    """Mojo source text for a string literal whose *value* is `name`'s own
    JSON key chunk (`"name":`) -- wrapped in single quotes in the output
    (rather than `_quoted`'s double quotes) since the *value* itself
    contains double-quote characters as part of JSON's own syntax."""
    var json_key_value = '"' + name + '":'
    return "'" + json_key_value + "'"


def _dump_value_expr(
    value_expr: String,
    t: TypeExpr,
    plain_struct_names: Dict[String, Bool],
    indent: String,
    mut tmp_id: Int,
    mut out: String,
) -> String:
    """Mirror of `_parse_value_expr`, for the dump direction: returns an
    expression evaluating to the JSON text for `value_expr` (already a
    value of type `t`). Anything `sqrrl__to_json[T]` already handles
    generically -- a leaf, a relation (its own bare id), or a plain-
    struct value at any nesting depth via `reflect[T]` -- dumps with a
    single `sqrrl__to_json(value_expr)` call. A *container* value
    (List/Set/Optional/Dict, or a custom wrapper) can't go through
    reflection at all (it has no named/typed fields for `reflect[T]` to
    walk), so those get their own recursive dump loop instead -- the
    mirror image of `_parse_value_expr`'s own container handling, just
    building a *string* accumulator instead of a *value* one.

    Needed for a container-shaped field to correctly dump a *nested*
    container element (`List[List[String]]`) -- confirmed missing via a
    real compile: the previous, non-recursive per-field dump called
    `sqrrl__to_json` on every element unconditionally, which fails
    outright for an element that's itself a container, since reflection
    can't handle one either."""
    if t.is_relation():
        # Dumped directly as its own bare id -- no generic dispatch/trait-
        # conformance detour needed at all (see this module's own doc
        # comment for why `sqrrl__JsonSerializable` was removed): a
        # relation's own JSON shape is always just its id, known
        # unconditionally at this exact call site, not something that
        # needs to be sorted out generically at runtime.
        return "String(" + value_expr + ".id())"
    var kind = _container_wrapper_kind(t)
    if t.name in plain_struct_names or kind == "":
        return "sqrrl__to_json(" + value_expr + ")"

    tmp_id += 1
    var this_id = tmp_id
    var out_var = "sqrrl__ds" + String(this_id)

    if kind == "optional":
        ref elem = t.arg(0)
        out += indent + "var " + out_var + ": String\n"
        out += indent + "if " + value_expr + ":\n"
        var elem_expr = _dump_value_expr(
            value_expr + ".value()", elem, plain_struct_names, indent + "    ", tmp_id, out
        )
        out += indent + "    " + out_var + " = " + elem_expr + "\n"
        out += indent + "else:\n"
        out += indent + "    " + out_var + " = \"null\"\n"
        return out_var

    if kind == "dict":
        ref key_t = t.arg(0)
        ref val_t = t.arg(1)
        out += indent + "var " + out_var + " = String(\"[\")\n"
        out += indent + "var sqrrl__dfirst" + String(this_id) + " = True\n"
        out += indent + "for sqrrl__de" + String(this_id) + " in " + value_expr + ".items():\n"
        out += indent + "    if not sqrrl__dfirst" + String(this_id) + ":\n"
        out += indent + "        " + out_var + " += \",\"\n"
        var key_expr = _dump_value_expr(
            "sqrrl__de" + String(this_id) + ".key", key_t, plain_struct_names, indent + "    ", tmp_id, out
        )
        var val_expr = _dump_value_expr(
            "sqrrl__de" + String(this_id) + ".value", val_t, plain_struct_names, indent + "    ", tmp_id, out
        )
        out += indent + "    " + out_var + " += \"[\" + " + key_expr + " + \",\" + " + val_expr + " + \"]\"\n"
        out += indent + "    sqrrl__dfirst" + String(this_id) + " = False\n"
        out += indent + out_var + " += \"]\"\n"
        return out_var

    # kind == "array" -- List/Set/a custom single-type-argument wrapper.
    ref elem = t.arg(0)
    var wrapper = t.name
    var iter_expr = value_expr
    if wrapper != "List" and wrapper != "Set":
        # Not guaranteed to implement `__iter__` -- converts to an
        # ordinary List via the same hand-written `sqrrl__<Wrapper>_json_
        # to_list` companion the top-level field dispatch already needs.
        iter_expr = "sqrrl__" + wrapper + "_json_to_list(" + value_expr + ")"
    out += indent + "var " + out_var + " = String(\"[\")\n"
    out += indent + "var sqrrl__dfirst" + String(this_id) + " = True\n"
    out += indent + "for sqrrl__dv" + String(this_id) + " in " + iter_expr + ":\n"
    out += indent + "    if not sqrrl__dfirst" + String(this_id) + ":\n"
    out += indent + "        " + out_var + " += \",\"\n"
    var elem_expr = _dump_value_expr(
        "sqrrl__dv" + String(this_id), elem, plain_struct_names, indent + "    ", tmp_id, out
    )
    out += indent + "    " + out_var + " += " + elem_expr + "\n"
    out += indent + "    sqrrl__dfirst" + String(this_id) + " = False\n"
    out += indent + out_var + " += \"]\"\n"
    return out_var


def _emit_to_json(
    parsed: ParsedStruct,
    plain_struct_names: Dict[String, Bool] = Dict[String, Bool](),
    plain_struct_fields: Dict[String, List[Field]] = Dict[String, List[Field]](),
    plain_struct_type_params: Dict[String, List[TypeParam]] = Dict[String, List[TypeParam]](),
) raises -> String:
    """`sqrrl__<Name>_to_json(e) -> String` -- one field at a time, in
    declaration order, comma-joined inside `{...}`. Every field's value
    goes through the uniform, reflection-based `sqrrl__to_json(...)`
    (plain-structs milestone) -- it sorts out on its own whether the value
    is a leaf, a relation to a real entity (its own bare id, via `conforms_
    to(sqrrl__JsonSerializable)` -- the target row itself is serialized
    once, separately, as part of its own table's own dump), or a plain-
    struct value (recursing through `reflect[T]`, at any nesting depth --
    including a generic instantiation like `Box[UInt32]`, which is why the
    "unsupported container" rejection below has to exempt a plain-struct-
    shaped field explicitly: it's bracket-shaped too, but reflection
    already handles it, unlike a genuine `List[...]`/`Set[...]`/`Dict[...]`)."""
    var entity_name = sqrrl_prefixed(parsed.name)
    var out = String("\ndef sqrrl__" + parsed.name + "_to_json(e: " + entity_name + ") -> String:\n")
    out += "    var sqrrl__out = String(\"{\")\n"
    var first = True
    # Shared across every field in this function, not reset per field --
    # unlike `from_json`'s own per-field parse code (each living in its
    # own `elif` branch, its own scope), every field's dump code here is
    # a flat, sequential run of statements in the *same* function body,
    # so two different container fields both starting their own `_dump_
    # value_expr` numbering at 1 would redeclare the same locals (found
    # via a real end-to-end compile with two such fields on one struct --
    # the exact same class of bug already fixed once for the old,
    # per-field-suffixed naming scheme this replaced).
    var tmp_id = 0
    for f in parsed.fields:
        if not first:
            out += "    sqrrl__out += \",\"\n"
        out += "    sqrrl__out += " + _json_key_literal_source(f.name) + "\n"
        # A discovered plain struct's own generic instantiation (`Tagged[
        # String]`) is bracket-shaped too -- checked *before* any
        # container-kind dispatch below, or a plain-struct field would be
        # misrouted into an array/dict dump assuming it's iterable/mapping-
        # shaped, when reflection is what actually needs to run (and what
        # `from_json`'s own `_parse_value_expr` already correctly prefers
        # -- this check keeps `_emit_to_json` consistent with it, found via
        # a real end-to-end compile: `Tagged[String]` tried to `for x in`
        # a plain struct that isn't iterable at all).
        var is_plain_struct_field = Bool(_plain_struct_value_base(f, plain_struct_names))
        if f.modifier == FieldModifier.MULTI:
            # multi's own type_str is always bare (`@@Target`, never
            # bracket-shaped -- the modifier itself already means "many
            # of these"), so it can't go through `_dump_value_expr`'s own
            # TypeExpr-based dispatch the way every other container-shaped
            # field now does; kept as its own direct, minimal case.
            out += "    sqrrl__out += \"[\"\n"
            out += "    var sqrrl__mfirst_" + f.name + " = True\n"
            out += "    ref sqrrl__mval_" + f.name + " = e._inner[].get_" + param_name(f) + "()\n"
            out += "    for sqrrl__m_" + f.name + " in sqrrl__mval_" + f.name + ":\n"
            out += "        if not sqrrl__mfirst_" + f.name + ":\n"
            out += "            sqrrl__out += \",\"\n"
            out += "        sqrrl__out += String(sqrrl__m_" + f.name + ".id())\n"
            out += "        sqrrl__mfirst_" + f.name + " = False\n"
            out += "    sqrrl__out += \"]\"\n"
        elif is_plain_struct_field:
            out += "    sqrrl__out += sqrrl__to_json(e._inner[].get_" + param_name(f) + "())\n"
        elif is_container_type(f.type_str):
            var t = parse_type_expr(f.type_str)
            if _container_wrapper_kind(t) == "":
                raise _unsupported_container_field_error(parsed.name, f.name, f.type_str)
            if _type_involves_relation(t, plain_struct_fields, plain_struct_type_params):
                # Only a relation-involving container still needs the
                # existing, unchanged recursive `_dump_value_expr` codegen
                # -- it's the only mechanism that can thread a relation's
                # own entity-wrapper conformance through at arbitrary
                # nesting depth. A container with no relation anywhere
                # (`tags: List[String]`) instead falls to the uniform
                # `sqrrl__to_json(...)` call every other field kind
                # already uses below -- `sqrrl__to_json[T]`'s own
                # generated dispatch table (`emit_json_module`) has a
                # branch for it.
                out += "    ref sqrrl__fv_" + f.name + " = e._inner[].get_" + param_name(f) + "()\n"
                var dump_out = String()
                var expr = _dump_value_expr("sqrrl__fv_" + f.name, t, plain_struct_names, "    ", tmp_id, dump_out)
                out += dump_out
                out += "    sqrrl__out += " + expr + "\n"
            else:
                out += "    sqrrl__out += sqrrl__to_json(e._inner[].get_" + param_name(f) + "())\n"
        elif is_relation_field(f) and not is_container_type(f.type_str):
            # A bare relation's own JSON shape is always just its id --
            # dumped directly, no `sqrrl__JsonSerializable`/generic-
            # dispatch detour needed at all (this module's own doc
            # comment has the full rationale for why that trait is gone).
            out += "    sqrrl__out += String(e._inner[].get_" + param_name(f) + "().id())\n"
        else:
            out += "    sqrrl__out += sqrrl__to_json(e._inner[].get_" + param_name(f) + "())\n"
        first = False
    out += "    sqrrl__out += \"}\"\n"
    out += "    return sqrrl__out^\n"
    return out^


def _emit_from_json_with_id(
    parsed: ParsedStruct,
    plain_struct_fields: Dict[String, List[Field]],
    plain_struct_names: Dict[String, Bool],
    plain_struct_type_params: Dict[String, List[TypeParam]] = Dict[String, List[TypeParam]](),
) raises -> String:
    """`sqrrl__<Name>_from_json_with_id(table, <sibling tables>, id, mut sc)
    raises -> sqrrl__<Name>` -- parses the JSON object into one
    `Optional[<FieldType>]` local per field (same key-dispatch shape
    `create()`'s own parameter list already mirrors), then constructs
    directly, replicating `create()`'s own body but substituting
    `alloc_specific_id(id)` for `alloc_id()`."""
    var entity_name = sqrrl_prefixed(parsed.name)
    var inner_name = entity_name + "Inner"
    var table_name = entity_name + "Table"
    var siblings = _sibling_relation_targets(parsed.fields, plain_struct_fields)

    var params = String("table: " + table_name)
    for target in siblings:
        params += ", sqrrl__tbl_" + target + ": " + sqrrl_prefixed(target) + "Table"
    params += ", id: UInt32, mut sqrrl__sc: sqrrl__JsonScanner"

    var out = String(
        "\ndef sqrrl__" + parsed.name + "_from_json_with_id(" + params + ") raises -> " + entity_name + ":\n"
    )

    for f in parsed.fields:
        out += "    var sqrrl__parsed_" + f.name + ": Optional[" + emit_field_type(f) + "] = None\n"

    out += "    sqrrl__sc.expect_byte(UInt8(ord(\"{\")))\n"
    out += "    if not sqrrl__sc.try_consume_byte(UInt8(ord(\"}\"))):\n"
    out += "        while True:\n"
    out += "            var sqrrl__key = sqrrl__sc.parse_json_string()\n"
    out += "            sqrrl__sc.expect_byte(UInt8(ord(\":\")))\n"
    var branch_kw = "            if"
    for f in parsed.fields:
        out += branch_kw + " sqrrl__key == " + _quoted(f.name) + ":\n"
        branch_kw = "            elif"
        if f.modifier == FieldModifier.MULTI:
            var target = _relation_target_name(f)
            var elem_t = emit_multi_element_type(f)
            out += "                var sqrrl__mset = Set[" + elem_t + "]()\n"
            out += "                sqrrl__sc.expect_byte(UInt8(ord(\"[\")))\n"
            out += "                if not sqrrl__sc.try_consume_byte(UInt8(ord(\"]\"))):\n"
            out += "                    while True:\n"
            out += "                        var sqrrl__elem_id = UInt32(sqrrl__sc.parse_json_int())\n"
            out += (
                "                        sqrrl__mset.add("
                + elem_t
                + "(sqrrl__tbl_"
                + target
                + ".storage[].handle_for(sqrrl__elem_id)))\n"
            )
            out += "                        if not sqrrl__sc.try_consume_byte(UInt8(ord(\",\"))):\n"
            out += "                            break\n"
            out += "                    sqrrl__sc.expect_byte(UInt8(ord(\"]\")))\n"
            out += "                sqrrl__parsed_" + f.name + " = sqrrl__mset^\n"
        elif _is_supported_container_field(f) and _type_involves_relation(
            parse_type_expr(f.type_str), plain_struct_fields, plain_struct_type_params
        ):
            out += _emit_field_json_parse(f, parsed.name, plain_struct_fields, plain_struct_names)
        elif is_relation_field(f) and not is_container_type(f.type_str):
            # A *wrapped* relation (`List[@@Employee]`, `@@container`
            # support) is also `is_relation_field(f)` (used correctly by
            # ordinary field-access rewriting) but must NOT dispatch here
            # -- this branch's own code assumes a single bare id, and would
            # otherwise generate nonsensical code trying to construct a
            # `List[...]` from one parsed id. A *supported* wrapped
            # relation (`List`/`Set`/`Optional`) was already handled
            # above; anything else wrapped (`Dict[...]`, deliberately
            # unsupported) falls through to the "unsupported container"
            # rejection below.
            var target = _relation_target_name(f)
            out += "                var sqrrl__rid_" + f.name + " = UInt32(sqrrl__sc.parse_json_int())\n"
            out += (
                "                sqrrl__parsed_"
                + f.name
                + " = "
                + emit_field_type(f)
                + "(sqrrl__tbl_"
                + target
                + ".storage[].handle_for(sqrrl__rid_"
                + f.name
                + "))\n"
            )
        else:
            # A plain-struct-typed field is checked *before* the generic
            # "unsupported container" rejection -- a generic plain
            # struct's own instantiation (`Box[UInt32]`) is bracket-shaped
            # too (`is_container_type` can't tell them apart from a real
            # `List[...]`/`Set[...]`/`Dict[...]`), but it's not actually an
            # unsupported container at all; `_plain_struct_value_base`
            # already does the real check (its base name is a discovered
            # plain struct), so it must run first.
            var plain_base = _plain_struct_value_base(f, plain_struct_names)
            if plain_base:
                var call = _plain_struct_from_json_call(plain_base.value(), plain_struct_fields, plain_struct_names)
                out += "                sqrrl__parsed_" + f.name + " = " + call + "\n"
            elif _is_json_unsupported_container_field(f):
                raise _unsupported_container_field_error(parsed.name, f.name, f.type_str)
            elif _is_supported_container_field(f):
                # A container that doesn't involve a relation anywhere
                # (`tags: List[String]`) -- routes through the shared,
                # generic `sqrrl__from_json[T]` dispatcher, whose own
                # dispatch-table branch for this exact type `emit_json_
                # module`'s collection pass already registered.
                out += (
                    "                sqrrl__parsed_"
                    + f.name
                    + " = sqrrl__from_json["
                    + emit_field_type(f)
                    + "](sqrrl__sc)\n"
                )
            else:
                # An ordinary leaf, or a genuinely undiscovered plain-
                # value type (the `sqrrl__<TypeName>_from_json` escape
                # hatch) -- `_leaf_from_json_expr` already handles both,
                # unchanged; never reached for a bare, unbound type
                # parameter here, since a real `@@struct` (unlike a plain
                # struct) is never itself generic.
                out += (
                    "                sqrrl__parsed_"
                    + f.name
                    + " = "
                    + _leaf_from_json_expr(parsed.name, f.name, f.type_str)
                    + "\n"
                )
    out += "            else:\n"
    out += (
        "                raise Error(\"InvalidJson: unknown field \" + sqrrl__key + \" for "
        + parsed.name
        + "\")\n"
    )
    out += "            if not sqrrl__sc.try_consume_byte(UInt8(ord(\",\"))):\n"
    out += "                break\n"
    out += "        sqrrl__sc.expect_byte(UInt8(ord(\"}\")))\n"

    # Every field is a required parameter, same contract create() has --
    # unlike create() this can't lean on Mojo's own missing-argument check,
    # so it's an explicit runtime check here instead.
    for f in parsed.fields:
        out += "    if not sqrrl__parsed_" + f.name + ":\n"
        out += (
            "        raise Error(\"InvalidJson: missing field "
            + f.name
            + " for "
            + parsed.name
            + "\")\n"
        )

    out += "    table.storage[].alloc_specific_id(id)\n"
    var ctor_args = String("_id=id, _table=table.storage")
    for f in parsed.fields:
        if needs_move_assignment(f, plain_struct_names):
            # Set[T] (multi) / a wrapped relation (List[T] included) / a
            # hand-written plain struct -- none is guaranteed
            # ImplicitlyCopyable, so `.value()` (a copy) can't be used to
            # read the parsed Optional back out; `.take()` (move, leaves
            # None behind) works regardless, same as create()'s own
            # parameter now needs (table.mojo).
            out += "    var sqrrl__v_" + f.name + " = sqrrl__parsed_" + f.name + ".take()\n"
            ctor_args += ", " + storage_field_name(f) + "=sqrrl__v_" + f.name + "^"
        else:
            out += "    var sqrrl__v_" + f.name + " = sqrrl__parsed_" + f.name + ".value()\n"
            ctor_args += ", " + storage_field_name(f) + "=sqrrl__v_" + f.name
    out += "    var sqrrl__inner = ArcPointer(" + inner_name + "(" + ctor_args + "))\n"
    out += "    table.storage[].register_weak(id, sqrrl__inner)\n"
    for f in parsed.fields:
        if f.modifier == FieldModifier.MULTI:
            out += (
                "    table.storage[].indexes."
                + f.name
                + ".add_many(id, sqrrl__inner[]."
                + storage_field_name(f)
                + ")\n"
            )
        elif f.modifier != FieldModifier.NONE:
            out += (
                "    table.storage[].indexes."
                + f.name
                + ".add(id, sqrrl__inner[]."
                + storage_field_name(f)
                + ")\n"
            )
    if parsed.is_keepalive:
        out += "    table.storage[].keepalive_add(id, sqrrl__inner.copy())\n"
    out += "    return " + entity_name + "(sqrrl__inner^)\n"
    return out^


def _emit_all_to_json(parsed: ParsedStruct) -> String:
    """`sqrrl__<Name>_all_to_json(table) -> String` -- iterates
    `table.storage[].all()` (ascending-id, for deterministic output),
    emitting `[id, json]` pairs."""
    var entity_name = sqrrl_prefixed(parsed.name)
    var table_name = entity_name + "Table"
    var out = String("\ndef sqrrl__" + parsed.name + "_all_to_json(table: " + table_name + ") -> String:\n")
    out += "    var sqrrl__out = String(\"[\")\n"
    out += "    var sqrrl__first = True\n"
    out += "    for sqrrl__id in table.storage[].all():\n"
    out += "        if not sqrrl__first:\n"
    out += "            sqrrl__out += \",\"\n"
    out += "        var sqrrl__e = " + entity_name + "(table.storage[].handle_for(sqrrl__id))\n"
    out += (
        "        sqrrl__out += \"[\" + String(sqrrl__id) + \",\" + sqrrl__"
        + parsed.name
        + "_to_json(sqrrl__e) + \"]\"\n"
    )
    out += "        sqrrl__first = False\n"
    out += "    sqrrl__out += \"]\"\n"
    out += "    return sqrrl__out^\n"
    return out^


def _emit_all_from_json(parsed: ParsedStruct, plain_struct_fields: Dict[String, List[Field]]) raises -> String:
    """`sqrrl__<Name>_all_from_json(table, <sibling tables>, [mut temp],
    mut sc) raises` -- parses the `[[id, obj], ...]` array, calling
    `_from_json_with_id` per entry. `temp` (a `List[sqrrl__<Name>]` slot on
    `sqrrl__TempKeepAlives`) is omitted entirely for a `keepalive`-tagged
    struct -- its own `create()`-mirrored construction inside
    `_from_json_with_id` already retains it via the table's real
    `keepalive` set, no extra hold needed."""
    var entity_name = sqrrl_prefixed(parsed.name)
    var table_name = entity_name + "Table"
    var siblings = _sibling_relation_targets(parsed.fields, plain_struct_fields)
    var params = String("table: " + table_name)
    var call_args = String("table")
    for target in siblings:
        params += ", sqrrl__tbl_" + target + ": " + sqrrl_prefixed(target) + "Table"
        call_args += ", sqrrl__tbl_" + target
    if not parsed.is_keepalive:
        params += ", mut sqrrl__temp: List[" + entity_name + "]"
    params += ", mut sqrrl__sc: sqrrl__JsonScanner"

    var out = String("\ndef sqrrl__" + parsed.name + "_all_from_json(" + params + ") raises:\n")
    out += "    sqrrl__sc.expect_byte(UInt8(ord(\"[\")))\n"
    out += "    if not sqrrl__sc.try_consume_byte(UInt8(ord(\"]\"))):\n"
    out += "        while True:\n"
    out += "            sqrrl__sc.expect_byte(UInt8(ord(\"[\")))\n"
    out += "            var sqrrl__eid = UInt32(sqrrl__sc.parse_json_int())\n"
    out += "            sqrrl__sc.expect_byte(UInt8(ord(\",\")))\n"
    out += (
        "            var sqrrl__e = sqrrl__"
        + parsed.name
        + "_from_json_with_id("
        + call_args
        + ", sqrrl__eid, sqrrl__sc)\n"
    )
    out += "            sqrrl__sc.expect_byte(UInt8(ord(\"]\")))\n"
    if not parsed.is_keepalive:
        out += "            sqrrl__temp.append(sqrrl__e)\n"
    else:
        out += "            _ = sqrrl__e\n"
    out += "            if not sqrrl__sc.try_consume_byte(UInt8(ord(\",\"))):\n"
    out += "                break\n"
    out += "        sqrrl__sc.expect_byte(UInt8(ord(\"]\")))\n"
    return out^


def _emit_temp_keep_alives_struct(structs: List[DiscoveredStruct]) -> String:
    """`sqrrl__TempKeepAlives` -- one `List[sqrrl__<Name>]` field per
    non-keepalive struct, threaded as a real local in the generated
    *script* (bound by `@@@begin_init_from_json`, consumed by
    `@@@end_init_from_json`), never stored on `sqrrl__World` itself (see
    project memory's own settled M5 policy)."""
    var out = String("\nstruct sqrrl__TempKeepAlives(Movable):\n")
    var any_field = False
    for ds in structs:
        if not ds.parsed.is_keepalive:
            out += "    var " + ds.parsed.name + ": List[" + sqrrl_prefixed(ds.parsed.name) + "]\n"
            any_field = True
    out += "\n    def __init__(out self):\n"
    if any_field:
        for ds in structs:
            if not ds.parsed.is_keepalive:
                out += "        self." + ds.parsed.name + " = List[" + sqrrl_prefixed(ds.parsed.name) + "]()\n"
    else:
        out += "        pass\n"
    return out^


def _emit_world_to_json(topo_order: List[DiscoveredStruct]) -> String:
    var out = String("\ndef sqrrl__world_to_json(world: sqrrl__World) -> String:\n")
    out += "    var sqrrl__out = String(\"{\")\n"
    var first = True
    for ds in topo_order:
        if not first:
            out += "    sqrrl__out += \",\"\n"
        out += "    sqrrl__out += " + _json_key_literal_source(ds.parsed.name) + "\n"
        out += "    sqrrl__out += sqrrl__" + ds.parsed.name + "_all_to_json(world." + ds.parsed.name + ")\n"
        first = False
    out += "    sqrrl__out += \"}\"\n"
    out += "    return sqrrl__out^\n"
    return out^


def _emit_world_from_json(
    topo_order: List[DiscoveredStruct], plain_struct_fields: Dict[String, List[Field]]
) raises -> String:
    """Dispatches on whatever top-level key order the JSON text actually
    has -- reload safety relies on the *document* being topo-ordered, which
    any dump `sqrrl__world_to_json` itself produces always is (a
    hand-edited or externally-produced dump with reordered keys could abort
    inside `handle_for` -- not a new gap this introduces, matching
    rw_squirrel_2's own identical property)."""
    var out = String(
        "\ndef sqrrl__world_from_json(mut world: sqrrl__World, mut sqrrl__sc: sqrrl__JsonScanner, mut"
        " sqrrl__temp: sqrrl__TempKeepAlives) raises:\n"
    )
    out += "    sqrrl__sc.expect_byte(UInt8(ord(\"{\")))\n"
    out += "    if not sqrrl__sc.try_consume_byte(UInt8(ord(\"}\"))):\n"
    out += "        while True:\n"
    out += "            var sqrrl__key = sqrrl__sc.parse_json_string()\n"
    out += "            sqrrl__sc.expect_byte(UInt8(ord(\":\")))\n"
    var branch_kw = "            if"
    for ds in topo_order:
        var siblings = _sibling_relation_targets(ds.parsed.fields, plain_struct_fields)
        var call_args = String("world." + ds.parsed.name)
        for target in siblings:
            call_args += ", world." + target
        if not ds.parsed.is_keepalive:
            call_args += ", sqrrl__temp." + ds.parsed.name
        call_args += ", sqrrl__sc"
        out += branch_kw + " sqrrl__key == " + _quoted(ds.parsed.name) + ":\n"
        out += "                sqrrl__" + ds.parsed.name + "_all_from_json(" + call_args + ")\n"
        branch_kw = "            elif"
    out += "            else:\n"
    out += "                raise Error(\"InvalidJson: unknown struct \" + sqrrl__key + \" in dump\")\n"
    out += "            if not sqrrl__sc.try_consume_byte(UInt8(ord(\",\"))):\n"
    out += "                break\n"
    out += "        sqrrl__sc.expect_byte(UInt8(ord(\"}\")))\n"
    return out^


def _emit_orchestration() -> String:
    """`begin`/`end`/`init_from_json` -- the three generated entry points
    `rewrite.mojo`'s `MarkerKind.BEGIN_INIT_FROM_JSON`/`INIT_FROM_JSON`/
    `END_INIT_FROM_JSON` branches each splice a single call to. `end`
    *moves* (not reassigns) its own parameter into a real function call --
    a hard call boundary, not a bare assignment the caller's own dataflow
    could reorder relative to earlier statements (verified with a
    standalone spike before this was wired into codegen: the same fix
    rw_squirrel_2's own `world_module.mojo` doc comment records for the
    identical ASAP-destruction failure mode)."""
    var out = String()
    out += "\ndef sqrrl__begin_init_from_json(mut world: sqrrl__World, json: String) raises -> sqrrl__TempKeepAlives:\n"
    out += "    world.sqrrl__check_no_leaks()\n"
    out += "    world = sqrrl__init()\n"
    out += "    var sqrrl__sc = sqrrl__JsonScanner(json)\n"
    out += "    var sqrrl__temp = sqrrl__TempKeepAlives()\n"
    out += "    sqrrl__world_from_json(world, sqrrl__sc, sqrrl__temp)\n"
    out += "    return sqrrl__temp^\n"

    out += "\ndef sqrrl__end_init_from_json(var sqrrl__temp: sqrrl__TempKeepAlives):\n"
    out += "    pass\n"

    out += "\ndef sqrrl__init_from_json(mut world: sqrrl__World, json: String) raises:\n"
    out += "    var sqrrl__temp = sqrrl__begin_init_from_json(world, json)\n"
    out += "    sqrrl__end_init_from_json(sqrrl__temp^)\n"
    return out^


def _collect_custom_container_wrappers_from_type(
    t: TypeExpr,
    plain_struct_names: Dict[String, Bool],
    mut seen: Dict[String, Bool],
    mut out: List[String],
):
    """Collects every distinct *custom* container wrapper name (not
    `List`/`Set`/`Optional`/`Dict`, and not a discovered plain struct)
    reachable from `t`, at any nesting depth -- what `sqrrl__json.mojo`
    needs its own explicit `from <module> import <Wrapper>, sqrrl__
    <Wrapper>_json_to_list, sqrrl__<Wrapper>_json_from_list` line for.
    Unlike `List`/`Set`/`Optional`/`Dict` (always available via `squirrel_
    runtime`) or a discovered plain struct (already imported via its own
    `module_of`), the compiler has no other way to know where a custom
    wrapper's own declaration -- and its two hand-written escape-hatch
    companions -- actually live."""
    if t.arg_count() >= 1 and t.name not in plain_struct_names:
        var wrapper = t.name
        if wrapper != "List" and wrapper != "Set" and wrapper != "Optional" and wrapper != "Dict" and wrapper not in seen:
            seen[wrapper] = True
            out.append(wrapper)
    for i in range(t.arg_count()):
        _collect_custom_container_wrappers_from_type(t.arg(i), plain_struct_names, seen, out)


def _collect_custom_container_wrappers(
    fields: List[Field],
    plain_struct_names: Dict[String, Bool],
    mut seen: Dict[String, Bool],
    mut out: List[String],
) raises:
    for f in fields:
        _collect_custom_container_wrappers_from_type(parse_type_expr(f.type_str), plain_struct_names, seen, out)


def _collect_custom_leaf_types_from_type(
    t: TypeExpr,
    plain_struct_names: Dict[String, Bool],
    type_param_names: Dict[String, Bool],
    mut seen: Dict[String, Bool],
    mut out: List[String],
):
    """Collects every distinct *undiscovered* plain-value leaf type name
    (never scanned as `@@struct` or a hand-written plain struct anywhere
    in the project, and not one of the enclosing struct's own type
    parameters -- e.g. `T` in `Box[T]`) reachable from `t`, at any nesting
    depth -- what `sqrrl__json.mojo` needs its own explicit `from <module>
    import <TypeName>, sqrrl__<TypeName>_from_json` line for, the escape
    hatch `_leaf_from_json_expr` falls back to for exactly this case."""
    if (
        t.kind == TypeExpr.LEAF
        and not _is_known_leaf_type(t.name)
        and t.name not in plain_struct_names
        and t.name not in type_param_names
        and t.name not in seen
    ):
        seen[t.name] = True
        out.append(t.name)
    for i in range(t.arg_count()):
        _collect_custom_leaf_types_from_type(t.arg(i), plain_struct_names, type_param_names, seen, out)


def _collect_custom_leaf_types(
    fields: List[Field],
    plain_struct_names: Dict[String, Bool],
    type_param_names: Dict[String, Bool],
    mut seen: Dict[String, Bool],
    mut out: List[String],
) raises:
    for f in fields:
        _collect_custom_leaf_types_from_type(parse_type_expr(f.type_str), plain_struct_names, type_param_names, seen, out)


def _emit_plain_struct_from_json(
    name: String,
    fields: List[Field],
    plain_struct_fields: Dict[String, List[Field]],
    plain_struct_names: Dict[String, Bool],
    type_params: List[TypeParam] = List[TypeParam](),
    plain_struct_type_params: Dict[String, List[TypeParam]] = Dict[String, List[TypeParam]](),
) raises -> String:
    """`sqrrl__<Name>_from_json[<T: Bound, ...>](<sibling tables>, mut sc)
    raises -> <Name>[<T, ...>]` -- the auto-generated reconstruction
    companion for a hand-written plain struct (plain-structs milestone,
    the plan's §7), reusing the exact field list `parser/scanner.mojo`'s
    `parse_hand_written_struct_fields` already extracts for relation-
    schema/cycle-detection purposes. Same key-dispatch parse-loop shape as
    `_emit_from_json_with_id`, minus the id/table bookkeeping a real
    entity's own row needs (a plain struct has neither). Calls the
    struct's own real constructor directly by keyword name, the same way
    `Table.create()` already does for a real `@@struct` -- this is the one
    documented contract a plain struct must satisfy for its own JSON
    reload to work: a constructor accepting each field by its own keyword
    name (`@fieldwise_init` satisfies this automatically).

    `type_params` (non-empty only for a generic plain struct) re-declares
    the struct's own `[T: Bound, ...]` list on this free function -- its
    field list already refers to those same bare names (`Self.T` -> `T`,
    unqualified by `parser/field_parsing.mojo`), so the function needs to
    bind them itself for that reference to mean anything. `_plain_struct_
    from_json_call` supplies the matching explicit type arguments at every
    call site, so callers never have to rely on inference."""
    var siblings = _sibling_relation_targets(fields, plain_struct_fields)
    var params = String()
    for target in siblings:
        params += "sqrrl__tbl_" + target + ": " + sqrrl_prefixed(target) + "Table, "
    params += "mut sqrrl__sc: sqrrl__JsonScanner"

    var type_param_decl = String()
    var type_param_names = String()
    if len(type_params) > 0:
        type_param_decl += "["
        for i in range(len(type_params)):
            if i > 0:
                type_param_decl += ", "
                type_param_names += ", "
            type_param_decl += type_params[i].name + ": " + type_params[i].bound
            type_param_names += type_params[i].name
        type_param_decl += "]"
    var return_type = name + "[" + type_param_names + "]" if len(type_params) > 0 else name

    var type_param_name_set = Dict[String, Bool]()
    for tp in type_params:
        type_param_name_set[tp.name] = True

    var out = String(
        "\ndef sqrrl__" + name + "_from_json" + type_param_decl + "(" + params + ") raises -> " + return_type + ":\n"
    )
    for f in fields:
        out += "    var sqrrl__parsed_" + f.name + ": Optional[" + rewritten_field_type(f.type_str, plain_struct_names) + "] = None\n"

    out += "    sqrrl__sc.expect_byte(UInt8(ord(\"{\")))\n"
    out += "    if not sqrrl__sc.try_consume_byte(UInt8(ord(\"}\"))):\n"
    out += "        while True:\n"
    out += "            var sqrrl__key = sqrrl__sc.parse_json_string()\n"
    out += "            sqrrl__sc.expect_byte(UInt8(ord(\":\")))\n"
    var branch_kw = "            if"
    for f in fields:
        out += branch_kw + " sqrrl__key == " + _quoted(f.name) + ":\n"
        branch_kw = "            elif"
        if _is_supported_container_field(f) and _type_involves_relation(
            parse_type_expr(f.type_str), plain_struct_fields, plain_struct_type_params
        ):
            out += _emit_field_json_parse(f, name, plain_struct_fields, plain_struct_names, type_param_name_set)
        elif is_relation_field(f) and not is_container_type(f.type_str):
            # Same exclusion as `_emit_from_json_with_id` above -- a
            # *supported* wrapped relation (`List`/`Set`/`Optional`) was
            # already handled above; anything else wrapped (`Dict[...]`,
            # deliberately unsupported) must fall through to the
            # container rejection, not this single-bare-id dispatch.
            var target = _relation_target_name(f)
            out += "                var sqrrl__rid_" + f.name + " = UInt32(sqrrl__sc.parse_json_int())\n"
            out += (
                "                sqrrl__parsed_"
                + f.name
                + " = "
                + sqrrl_prefixed(target)
                + "(sqrrl__tbl_"
                + target
                + ".storage[].handle_for(sqrrl__rid_"
                + f.name
                + "))\n"
            )
        else:
            # Same ordering fix as `_emit_from_json_with_id`: a generic
            # plain struct's own instantiation (`Box[UInt32]`) is
            # bracket-shaped too, so the plain-struct check has to run
            # before the generic "unsupported container" rejection, not
            # after.
            var plain_base = _plain_struct_value_base(f, plain_struct_names)
            if plain_base:
                var call = _plain_struct_from_json_call(plain_base.value(), plain_struct_fields, plain_struct_names)
                out += "                sqrrl__parsed_" + f.name + " = " + call + "\n"
            elif _is_json_unsupported_container_field(f):
                raise _unsupported_container_field_error(name, f.name, f.type_str)
            elif _is_supported_container_field(f) or f.type_str in type_param_name_set:
                # A container that doesn't involve a relation anywhere,
                # or -- the case this whole mechanism exists for -- a bare
                # reference to this struct's own type parameter (`Box[T]`'s
                # `value: T`): both route through the shared, generic
                # `sqrrl__from_json[T]` dispatcher, using the field's own
                # type exactly as declared (`T` stays bare here -- this
                # code lives inside `sqrrl__<Name>_from_json`'s own still-
                # generic body, substituted only once some real caller
                # instantiates it with a concrete type, at which point
                # `sqrrl__from_json[T]` -- now concrete -- either matches
                # a dispatch-table branch `emit_json_module`'s own
                # collection pass registered, or falls through to the
                # static default for a plain leaf).
                out += (
                    "                sqrrl__parsed_"
                    + f.name
                    + " = sqrrl__from_json["
                    + rewritten_field_type(f.type_str, plain_struct_names)
                    + "](sqrrl__sc)\n"
                )
            else:
                # An ordinary leaf, or a genuinely undiscovered plain-
                # value type (the `sqrrl__<TypeName>_from_json` escape
                # hatch) -- `_leaf_from_json_expr` already handles both,
                # unchanged.
                out += (
                    "                sqrrl__parsed_"
                    + f.name
                    + " = "
                    + _leaf_from_json_expr(name, f.name, f.type_str, type_param_name_set)
                    + "\n"
                )
    out += "            else:\n"
    out += "                raise Error(\"InvalidJson: unknown field \" + sqrrl__key + \" for " + name + "\")\n"
    out += "            if not sqrrl__sc.try_consume_byte(UInt8(ord(\",\"))):\n"
    out += "                break\n"
    out += "        sqrrl__sc.expect_byte(UInt8(ord(\"}\")))\n"

    for f in fields:
        out += "    if not sqrrl__parsed_" + f.name + ":\n"
        out += "        raise Error(\"InvalidJson: missing field " + f.name + " for " + name + "\")\n"

    var ctor_args = String()
    var first = True
    for f in fields:
        if not first:
            ctor_args += ", "
        ctor_args += f.name + "=sqrrl__parsed_" + f.name + ".take()"
        first = False
    out += "    return " + return_type + "(" + ctor_args + ")\n"
    return out^


def _emit_container_dispatch_branches(t: TypeExpr, mut to_json_out: String, mut from_json_out: String) raises:
    """Appends one `elif T == <type>:` branch each to `sqrrl__to_json[T]`'s
    own dump dispatch table and `sqrrl__from_json[T]`'s own reload one,
    for the container-shaped `t` (`_collect_dispatch_types` already
    guarantees relation-free, so no sibling table is ever needed here).
    `List`/`Set`/`Optional`, or a custom single-argument wrapper, all
    share the exact same `sqrrl__<Wrapper>_json_to_list`/`_from_list` +
    `list_to_json`/`list_from_json` convention; `Dict`, or a custom
    two-argument wrapper, share `_to_pairs`/`_from_pairs` + `pairs_to_
    json`/`pairs_from_json` instead -- for a *built-in* wrapper (`List`/
    `Set`/`Optional`/`Dict`) the four adapters are pre-written, always-
    available static functions (`squirrel_runtime/json.mojo`); for a
    custom wrapper they're the exact same hand-written escape-hatch
    companions this project already required before this rearchitecture
    -- the only thing that changed is *where* they get called from (a
    dispatch-table branch here, not inline per-field code), never the
    naming convention/contract itself, so no existing custom-wrapper
    author's own code needs to change."""
    var type_str = t.render()
    var wrapper = t.name
    var kind = _container_wrapper_kind(t)
    if kind == "dict":
        var key_str = t.arg(0).render()
        var val_str = t.arg(1).render()
        to_json_out += "    elif T == " + type_str + ":\n"
        to_json_out += (
            "        return pairs_to_json(sqrrl__" + wrapper + "_json_to_pairs(rebind[" + type_str + "](value)))\n"
        )
        from_json_out += "    elif T == " + type_str + ":\n"
        from_json_out += (
            "        return sqrrl__movable_rebind["
            + type_str
            + ", T](sqrrl__"
            + wrapper
            + "_json_from_pairs(pairs_from_json["
            + key_str
            + ", "
            + val_str
            + "](sc)))\n"
        )
        return
    # "array" or "optional" -- both share the single-type-argument list
    # convention; `Optional` is just a 0-or-1-element list in this scheme
    # (see `sqrrl__Optional_json_to_list`/`_from_list`'s own doc comment),
    # not a distinct `null`-or-value shape any more.
    var elem_str = t.arg(0).render()
    to_json_out += "    elif T == " + type_str + ":\n"
    to_json_out += (
        "        return list_to_json(sqrrl__" + wrapper + "_json_to_list(rebind[" + type_str + "](value)))\n"
    )
    from_json_out += "    elif T == " + type_str + ":\n"
    from_json_out += (
        "        return sqrrl__movable_rebind["
        + type_str
        + ", T](sqrrl__"
        + wrapper
        + "_json_from_list(list_from_json["
        + elem_str
        + "](sc)))\n"
    )


def _emit_plain_struct_dispatch_branch(t: TypeExpr, mut from_json_out: String):
    """Appends one `elif T == <type>:` branch to `sqrrl__from_json[T]`'s
    own reload dispatch table, for the discovered-plain-struct instantiation
    `t` (`_collect_dispatch_types` already guarantees relation-free, so
    the call needs no sibling table -- `_emit_plain_struct_from_json`'s
    own generated function for a relation-free plain struct takes only
    `sqrrl__sc`, nothing else). No dump-direction branch needed at all --
    `sqrrl__to_json_default`'s own `reflect[T]`-based fallback already
    handles *any* struct shape generically, plain-struct or not, matching
    rw_squirrel_2's own identical omission (confirmed by reading their
    real source)."""
    var type_str = t.render()
    var base = t.name
    var args_str = String()
    if t.arg_count() > 0:
        args_str += "["
        for i in range(t.arg_count()):
            if i > 0:
                args_str += ", "
            args_str += t.arg(i).render()
        args_str += "]"
    from_json_out += "    elif T == " + type_str + ":\n"
    from_json_out += (
        "        return sqrrl__movable_rebind[" + type_str + ", T](sqrrl__" + base + "_from_json" + args_str + "(sc))\n"
    )


def emit_json_module(
    discovery_structs: List[DiscoveredStruct],
    topo_order: List[DiscoveredStruct],
    plain_struct_discovery: PlainStructDiscovery = PlainStructDiscovery(Dict[String, List[Field]](), Dict[String, String]()),
) raises -> String:
    """Emits `sqrrl__json.mojo`'s whole content -- every JSON-related
    generated symbol for the whole project, in this one file (the
    non-negotiable constraint, see this file's own module doc comment).
    `discovery_structs` (declaration order) drives the per-struct function
    definitions (order doesn't matter there); `topo_order` (dependency
    order, `driver/topo_order.mojo`) drives `sqrrl__world_to_json`'s own
    key order and `sqrrl__world_from_json`'s dispatch-branch order, so a
    genuine dump always reloads safely. `plain_struct_discovery`
    (plain-structs milestone) drives one `sqrrl__<Name>_from_json`
    companion per *non-generic* plain struct discovered project-wide."""
    var plain_struct_fields = plain_struct_discovery.fields.copy()
    var plain_struct_names = Dict[String, Bool]()
    var plain_struct_name_list = List[String]()
    for name in plain_struct_fields.keys():
        plain_struct_names[String(name)] = True
        plain_struct_name_list.append(String(name))

    var out = String(
        "from std.memory import ArcPointer\n"
        "from std.collections import Set\n"
        "from squirrel_runtime.json import sqrrl__JsonScanner, sqrrl__json_string_literal,"
        " sqrrl__json_bool_literal, sqrrl__to_json_default, sqrrl__from_json_default,"
        " sqrrl__List_json_to_list, sqrrl__List_json_from_list, sqrrl__Set_json_to_list,"
        " sqrrl__Set_json_from_list, sqrrl__Optional_json_to_list, sqrrl__Optional_json_from_list,"
        " sqrrl__Dict_json_to_pairs, sqrrl__Dict_json_from_pairs, sqrrl__movable_rebind\n"
        "from sqrrl__world import sqrrl__World, sqrrl__init\n"
    )
    for ds in discovery_structs:
        var module_path = ds.module_path
        var name = ds.parsed.name
        out += (
            "from "
            + module_path
            + " import "
            + sqrrl_prefixed(name)
            + ", "
            + sqrrl_prefixed(name)
            + "Inner, "
            + sqrrl_prefixed(name)
            + "Table\n"
        )
    for plain_name in plain_struct_name_list:
        out += "from " + plain_struct_discovery.module_of[plain_name] + " import " + plain_name + "\n"

    # A custom container wrapper (the escape hatch -- any single-type-
    # argument wrapper other than List/Set/Optional, and not a discovered
    # plain struct) has no `module_of` entry at all -- the compiler never
    # scanned a declaration for it, by definition. Imports it (and its two
    # hand-written `sqrrl__<Wrapper>_json_to_list`/`_json_from_list`
    # companions) from whichever real @@struct/plain struct's own module
    # first referenced it, on the assumption that module itself already
    # imports it to declare the field in the first place (so it's
    # re-exportable from there) -- the same transitive-import assumption
    # `build_entity_symbols`'s own cross-file import mechanism already
    # relies on.
    var custom_wrapper_module = Dict[String, String]()
    var custom_wrapper_list = List[String]()
    var cwseen = Dict[String, Bool]()
    for ds in discovery_structs:
        var before = len(custom_wrapper_list)
        _collect_custom_container_wrappers(ds.parsed.fields, plain_struct_names, cwseen, custom_wrapper_list)
        for i in range(before, len(custom_wrapper_list)):
            custom_wrapper_module[custom_wrapper_list[i]] = ds.module_path
    for plain_name in plain_struct_name_list:
        var before2 = len(custom_wrapper_list)
        _collect_custom_container_wrappers(plain_struct_fields[plain_name], plain_struct_names, cwseen, custom_wrapper_list)
        for i in range(before2, len(custom_wrapper_list)):
            custom_wrapper_module[custom_wrapper_list[i]] = plain_struct_discovery.module_of[plain_name]
    for wrapper in custom_wrapper_list:
        out += (
            "from "
            + custom_wrapper_module[wrapper]
            + " import "
            + wrapper
            + ", sqrrl__"
            + wrapper
            + "_json_to_list, sqrrl__"
            + wrapper
            + "_json_from_list\n"
        )

    # A genuinely undiscovered plain-value leaf type (the escape hatch
    # `_leaf_from_json_expr` falls back to -- e.g. a plain `home:
    # ExternalAddress` field imported from an ordinary, never-`.mojo.
    # sqrrl` module) has no `module_of` entry either, for the same reason
    # a custom container wrapper doesn't: the compiler never scanned a
    # declaration for it. Same transitive-import assumption as the
    # custom-wrapper case above, just for the type itself plus its own
    # hand-written `sqrrl__<TypeName>_from_json` companion instead of the
    # two list-conversion companions a container needs.
    var custom_leaf_module = Dict[String, String]()
    var custom_leaf_list = List[String]()
    var clseen = Dict[String, Bool]()
    for ds in discovery_structs:
        var before3 = len(custom_leaf_list)
        _collect_custom_leaf_types(ds.parsed.fields, plain_struct_names, Dict[String, Bool](), clseen, custom_leaf_list)
        for i in range(before3, len(custom_leaf_list)):
            custom_leaf_module[custom_leaf_list[i]] = ds.module_path
    for plain_name in plain_struct_name_list:
        var this_type_param_names = Dict[String, Bool]()
        if plain_name in plain_struct_discovery.type_params:
            for tp in plain_struct_discovery.type_params[plain_name]:
                this_type_param_names[tp.name] = True
        var before4 = len(custom_leaf_list)
        _collect_custom_leaf_types(plain_struct_fields[plain_name], plain_struct_names, this_type_param_names, clseen, custom_leaf_list)
        for i in range(before4, len(custom_leaf_list)):
            custom_leaf_module[custom_leaf_list[i]] = plain_struct_discovery.module_of[plain_name]
    for leaf_type in custom_leaf_list:
        out += "from " + custom_leaf_module[leaf_type] + " import " + leaf_type + ", sqrrl__" + leaf_type + "_from_json\n"

    # The shared, generic `sqrrl__to_json[T]`/`sqrrl__from_json[T]`
    # dispatch table -- one `elif T == <ConcreteType>:` branch per
    # distinct, relation-free container (List/Set/Optional/Dict/a custom
    # wrapper) or discovered-plain-struct instantiation actually reachable
    # project-wide, collected by walking every real @@struct's own field
    # graph (`_collect_dispatch_types` recurses through container
    # elements and, for a plain struct, its own -- substituted -- fields,
    # so a nested/generic case is found from wherever it's first
    # reachable, with no separate top-level walk needed). This is what
    # `_emit_to_json`/`_emit_from_json_with_id`/`_emit_plain_struct_from_
    # json`'s own field-level `sqrrl__to_json(value)`/`sqrrl__from_json[
    # FieldType](sqrrl__sc)` calls resolve against -- including a generic
    # plain struct's own bare-type-parameter field (`Box[T]`'s `value:
    # T`), which is what actually closes that gap: `T` stays bare inside
    # `Box`'s own still-generic `from_json`, resolved only once some real
    # caller instantiates it with a type this table has a branch for (or
    # the static default handles, for a plain leaf).
    var seen_container = Dict[String, Bool]()
    var container_dispatch_types = List[TypeExpr]()
    var seen_plain = Dict[String, Bool]()
    var plain_dispatch_types = List[TypeExpr]()
    for ds in discovery_structs:
        _collect_dispatch_types(
            ds.parsed.fields, plain_struct_fields, plain_struct_discovery.type_params, plain_struct_names,
            seen_container, container_dispatch_types, seen_plain, plain_dispatch_types,
        )

    var to_json_table = String("def sqrrl__to_json[T: AnyType](value: T) -> String:\n    comptime if False:\n        pass\n")
    var from_json_table = String(
        "def sqrrl__from_json[T: Movable & ImplicitlyDeletable](mut sc: sqrrl__JsonScanner) raises -> T:\n"
        "    comptime if False:\n        pass\n"
    )
    for t in container_dispatch_types:
        _emit_container_dispatch_branches(t, to_json_table, from_json_table)
    for t in plain_dispatch_types:
        _emit_plain_struct_dispatch_branch(t, from_json_table)
    to_json_table += "    else:\n        return sqrrl__to_json_default(value)\n"
    from_json_table += "    else:\n        return sqrrl__from_json_default[T](sc)\n"

    out += "\n\n"
    out += "def list_to_json[T: Movable](lst: List[T]) -> String:\n"
    out += "    var out = String(\"[\")\n"
    out += "    for i in range(len(lst)):\n"
    out += "        if i > 0:\n"
    out += "            out += \",\"\n"
    out += "        out += sqrrl__to_json(lst[i])\n"
    out += "    out += \"]\"\n"
    out += "    return out^\n"
    out += "\n\n"
    out += "def list_from_json[T: Movable & ImplicitlyDeletable](mut sc: sqrrl__JsonScanner) raises -> List[T]:\n"
    out += "    var lst = List[T]()\n"
    out += "    sc.expect_byte(UInt8(ord(\"[\")))\n"
    out += "    if not sc.try_consume_byte(UInt8(ord(\"]\"))):\n"
    out += "        while True:\n"
    out += "            lst.append(sqrrl__from_json[T](sc))\n"
    out += "            if sc.try_consume_byte(UInt8(ord(\",\"))):\n"
    out += "                continue\n"
    out += "            sc.expect_byte(UInt8(ord(\"]\")))\n"
    out += "            break\n"
    out += "    return lst^\n"
    out += "\n\n"
    out += "def pairs_to_json[K: Movable, V: Movable](pairs: List[Tuple[K, V]]) -> String:\n"
    out += "    var out = String(\"[\")\n"
    out += "    for i in range(len(pairs)):\n"
    out += "        if i > 0:\n"
    out += "            out += \",\"\n"
    out += (
        "        out += \"[\" + sqrrl__to_json(pairs[i][0]) + \",\" + sqrrl__to_json(pairs[i][1])"
        " + \"]\"\n"
    )
    out += "    out += \"]\"\n"
    out += "    return out^\n"
    out += "\n\n"
    out += (
        "def pairs_from_json[K: Copyable & ImplicitlyDeletable, V: Copyable & ImplicitlyDeletable](mut sc:"
        " sqrrl__JsonScanner) raises -> List[Tuple[K, V]]:\n"
    )
    out += "    var pairs = List[Tuple[K, V]]()\n"
    out += "    sc.expect_byte(UInt8(ord(\"[\")))\n"
    out += "    if not sc.try_consume_byte(UInt8(ord(\"]\"))):\n"
    out += "        while True:\n"
    out += "            sc.expect_byte(UInt8(ord(\"[\")))\n"
    out += "            var k = sqrrl__from_json[K](sc)\n"
    out += "            sc.expect_byte(UInt8(ord(\",\")))\n"
    out += "            var v = sqrrl__from_json[V](sc)\n"
    out += "            sc.expect_byte(UInt8(ord(\"]\")))\n"
    out += "            pairs.append((k.copy(), v.copy()))\n"
    out += "            if sc.try_consume_byte(UInt8(ord(\",\"))):\n"
    out += "                continue\n"
    out += "            sc.expect_byte(UInt8(ord(\"]\")))\n"
    out += "            break\n"
    out += "    return pairs^\n"
    out += "\n\n"
    out += to_json_table
    out += "\n\n"
    out += from_json_table

    for ds in discovery_structs:
        out += _emit_to_json(ds.parsed, plain_struct_names, plain_struct_fields, plain_struct_discovery.type_params)
        out += _emit_from_json_with_id(ds.parsed, plain_struct_fields, plain_struct_names, plain_struct_discovery.type_params)
        out += _emit_all_to_json(ds.parsed)
        out += _emit_all_from_json(ds.parsed, plain_struct_fields)

    # Only a plain struct actually reachable from some real @@struct's own
    # field graph gets a `from_json` companion generated at all -- "no
    # unused generated surface" (see `collect_plain_struct_targets`'s own
    # doc comment for why this matters concretely, not just as tidiness:
    # a structurally un-JSON-able generic plain struct, one with a field
    # typed as its own bare type parameter, would otherwise fail to
    # generate even when nothing ever needs its from_json).
    var needed_plain_structs = List[String]()
    var pseen = Dict[String, Bool]()
    for ds in discovery_structs:
        collect_plain_struct_targets(ds.parsed.fields, plain_struct_fields, pseen, needed_plain_structs)

    for plain_name in needed_plain_structs:
        var this_fields = plain_struct_fields[plain_name].copy()
        var this_type_params = (
            plain_struct_discovery.type_params[plain_name].copy()
            if plain_name in plain_struct_discovery.type_params
            else List[TypeParam]()
        )
        out += _emit_plain_struct_from_json(
            plain_name, this_fields, plain_struct_fields, plain_struct_names, this_type_params,
            plain_struct_discovery.type_params,
        )

    out += _emit_temp_keep_alives_struct(discovery_structs)
    out += _emit_world_to_json(topo_order)
    out += _emit_world_from_json(topo_order, plain_struct_fields)
    out += _emit_orchestration()
    return out^
