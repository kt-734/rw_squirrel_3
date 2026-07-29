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
from squirrel_compiler.analysis import collect_plain_struct_targets
from squirrel_compiler.driver.discovery import DiscoveredStruct, PlainStructDiscovery
from std.memory import ArcPointer

# Generates `sqrrl__json.mojo` -- every JSON-related symbol for the whole
# project, in one file, per the user's own non-negotiable constraint (see
# the M5 plan, "Non-negotiable constraint"): free functions operating on
# `sqrrl___World`/a specific `Table`/an entity passed in as an ordinary
# parameter, never a method added to `sqrrl___World` or any generated
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
# ordinary, never-`.mojo.sqrrl` module) -- falls back to a hand-written
# `sqrrl__<TypeName>_from_json(mut sc: sqrrl___JsonScanner) raises ->
# TypeName` companion, assumed to exist and called directly, imported from
# wherever the referencing struct's own module sources the type
# (`_collect_custom_leaf_types`).
#
# `List`/`Set`/`Optional`/`Dict`-shaped ("`@@container`") fields other than
# `multi` (which has its own dedicated Set-of-ids iteration) ARE
# JSON-supported, at arbitrary nesting depth -- `_parse_value_expr`/`_emit_
# field_json_parse` generalize the same per-field explicit-codegen approach
# `multi` always used, to an arbitrary element kind (leaf/relation/plain-
# struct/*another container*, recursively) and wrapper. `List`/`Set`/
# `Dict`/`Optional` build inline; `Variant` and any custom wrapper of any
# arity (no arity restriction any more -- see the `_to_json`/`_from_json`
# contract every wrapper implements, `docs/json-and-custom-containers.md`)
# delegate to their own `sqrrl__<Wrapper>_to_json`/`_from_json` instead,
# matching and then exceeding rw_squirrel_1/2's own parity here (confirmed
# by reading their real source, not assumed) -- `sqrrl__to_json[T]`'s
# reflection genuinely can't walk a container's own internal representation
# generically, which is why this needs real, per-shape codegen rather than
# a generic dispatcher, same as `multi` always did.


def _relation_target_name(f: Field) -> String:
    return String(f.type_str[byte=2 : f.type_str.byte_length()])


def _is_supported_container_field(f: Field) -> Bool:
    """True for any container-shaped, non-`multi` field -- every arity and
    every wrapper name is handled now (`List`/`Set`/`Dict`/`Optional`
    inline, anything else via its own `sqrrl__<Wrapper>_to_json`/`_from_
    json`), so this is just `is_container_type` plus the `multi` exclusion
    -- the field-level gate shared by `_emit_to_json`'s dump dispatch and
    `_emit_from_json_with_id`/`_emit_plain_struct_from_json`'s reload
    dispatch, so the two directions can't drift apart into an asymmetric
    half-support."""
    return f.modifier != FieldModifier.MULTI and is_container_type(f.type_str)


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
    """Collects every distinct concrete type reachable from `t` that the
    generated `sqrrl__to_json[T]`/`sqrrl__from_json[T]` dispatch table
    (`emit_json_module`) needs its own explicit `elif T == ...:` branch
    for -- a container (`List`/`Set`/`Optional`/`Dict`, `Variant`, or a
    custom wrapper of any arity), or a bare relation, into `container_out`;
    a discovered plain struct's own concrete instantiation (bare or
    generic) into `plain_out`. Recurses into every match's own element/
    field types too (a container's element might itself be another
    container, a plain struct, or a bare relation; a plain struct's own
    field might be another container/plain struct/relation, or -- the case
    this whole mechanism exists for -- its *own* bare type parameter,
    substituted here to whatever concrete type this particular
    instantiation actually uses).

    Unlike an earlier version of this function, a relation-*involving*
    container or plain struct is now registered too, not skipped -- `world:
    sqrrl___World` is threaded through every dispatch branch (`_emit_
    container_dispatch_branches`/`_emit_plain_struct_dispatch_branch`), so
    `T == List[@@Employee]`/`T == Roster` (a plain struct with its own
    relation field) can resolve correctly now. This matters specifically
    for something reached *generically* from inside `Variant`'s own type
    arguments or a custom wrapper's -- `sqrrl__Variant_to_json[Int,
    @@Employee]`'s own generated body calls the *generic* `sqrrl__to_json[
    T]` for its active value, with no way to special-case "this T happens
    to be a relation/relation-involving type" at codegen time, since the
    function body is written once, generically, before any concrete `T` is
    known. A field's own *direct* declared type still prefers the existing
    `_parse_value_expr`/`_dump_value_expr` codegen over this dispatch table
    when it's relation-involving (`_type_involves_relation`'s own field-
    level gate, unchanged) -- registering it here as well is never wrong,
    just sometimes unused for that specific field, and load-bearing for
    every other call site that can only reach it generically."""
    if t.name in plain_struct_names:
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
    if t.is_relation():
        # A bare relation -- whether reached directly, or (the case this
        # branch exists for) only through something opaque to this
        # dispatch table otherwise, nested inside `Variant`'s own type
        # arguments or a custom wrapper's -- needs its own `T == sqrrl__
        # <Target>` branch too, now that `world: sqrrl___World` is
        # threaded all the way through it (`_emit_container_dispatch_
        # branches`'s own relation branch, below). No type arguments of
        # its own to recurse into, unlike every other case here.
        if t.render() not in seen_container:
            seen_container[t.render()] = True
            container_out.append(t.copy())
        return
    if not t.is_parameterized():
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
    plain_struct_type_params: Dict[String, List[TypeParam]] = Dict[String, List[TypeParam]](),
) raises -> String:
    """The generated-code *expression* evaluating to one parsed JSON value
    of type `t`, off `sc` -- the single recursive core every
    `from_json` parse path (a whole field's own declared type, or one
    element nested inside a container, at any depth) goes through.

    For a leaf/relation/discovered-plain-struct `t`, this is a single
    nested-call expression with no side effect on `out` at all (safe to
    inline directly into an outer container's own `.append(...)`/`.add(
    ...)` call -- a relation element's own id-parse, `sc.parse_
    json_int()`, is itself just a nested call, no intermediate named
    variable needed). For a *container* `t`, there's no single-expression
    reading of a JSON array/object, so this instead emits a complete parse
    loop into `out` (a local uniquely suffixed by `tmp_id`, captured once
    per call so nested/sibling emissions inside the same field's own
    generated function never collide) and returns that local's own name,
    already `^`-moved (every container type this project builds one of is
    either known non-`ImplicitlyCopyable`, or it's always safe to move
    regardless).

    `List`/`Set`/`Dict`/`Optional` build directly, inline (a known, real
    constructor and build-up method for each). Anything else -- `Variant`,
    or a custom wrapper of any arity -- always goes through the exact same
    uniform `_to_json`/`_from_json` contract instead: `sqrrl__<Wrapper>
    _from_json[T1, ..., Tn](mut sc: sqrrl___JsonScanner, world: sqrrl___
    World) raises -> Wrapper[T1, ..., Tn]` parses the *complete* JSON text
    for this value directly off `sc` itself, `world` threaded through for
    any relation nested in `T1..Tn`. No arity restriction and no special-
    casing by name beyond the four built-ins above -- a wrapper's own
    author decides what its JSON shape means, same trust-the-author stance
    this project
    already takes for a custom wrapper's own type-conformance."""
    if t.is_relation():
        var target = t.name
        return (
            sqrrl_prefixed(target)
            + "(world."
            + target
            + ".storage[].handle_for(UInt32(sc.parse_json_int())))"
        )
    if t.name in plain_struct_names:
        return _plain_struct_from_json_call(t, plain_struct_fields, plain_struct_names, plain_struct_type_params)
    if t.kind == TypeExpr.LEAF:
        return _leaf_from_json_expr(struct_name, field_name, t.name, type_param_names)

    if t.name == "List" or t.name == "Set":
        ref elem = t.arg(0)
        var elem_type_str = rewritten_field_type(elem.render(), plain_struct_names)
        tmp_id += 1
        var var_name = "nc" + String(tmp_id)
        var build_wrapper = "Set" if t.name == "Set" else "List"
        out += indent + "var " + var_name + " = " + build_wrapper + "[" + elem_type_str + "]()\n"
        out += indent + "sc.expect_byte(UInt8(ord(\"[\")))\n"
        out += indent + "if not sc.try_consume_byte(UInt8(ord(\"]\"))):\n"
        out += indent + "    while True:\n"
        var elem_expr = _parse_value_expr(
            elem, plain_struct_fields, plain_struct_names, struct_name, field_name, indent + "        ", tmp_id, out,
            type_param_names, plain_struct_type_params,
        )
        var builder = "add" if build_wrapper == "Set" else "append"
        out += indent + "        " + var_name + "." + builder + "(" + elem_expr + ")\n"
        out += indent + "        if not sc.try_consume_byte(UInt8(ord(\",\"))):\n"
        out += indent + "            break\n"
        out += indent + "    sc.expect_byte(UInt8(ord(\"]\")))\n"
        return var_name + "^"

    if t.name == "Optional" and t.arg_count() == 1:
        ref elem = t.arg(0)
        var elem_type_str = rewritten_field_type(elem.render(), plain_struct_names)
        tmp_id += 1
        var var_name = "nc" + String(tmp_id)
        out += indent + "var " + var_name + ": Optional[" + elem_type_str + "]\n"
        out += indent + "if sc.try_consume_literal(\"null\"):\n"
        out += indent + "    " + var_name + " = Optional[" + elem_type_str + "]()\n"
        out += indent + "else:\n"
        var elem_expr = _parse_value_expr(
            elem, plain_struct_fields, plain_struct_names, struct_name, field_name, indent + "    ", tmp_id, out,
            type_param_names, plain_struct_type_params,
        )
        out += indent + "    " + var_name + " = Optional[" + elem_type_str + "](" + elem_expr + ")\n"
        return var_name + "^"

    if t.name == "Dict":
        ref key_t = t.arg(0)
        ref val_t = t.arg(1)
        var key_type_str = rewritten_field_type(key_t.render(), plain_struct_names)
        var val_type_str = rewritten_field_type(val_t.render(), plain_struct_names)
        tmp_id += 1
        var this_id = tmp_id
        var var_name = "nc" + String(this_id)
        var key_var = "nck" + String(this_id)
        out += indent + "var " + var_name + " = Dict[" + key_type_str + ", " + val_type_str + "]()\n"
        out += indent + "sc.expect_byte(UInt8(ord(\"[\")))\n"
        out += indent + "if not sc.try_consume_byte(UInt8(ord(\"]\"))):\n"
        out += indent + "    while True:\n"
        out += indent + "        sc.expect_byte(UInt8(ord(\"[\")))\n"
        var key_expr = _parse_value_expr(
            key_t, plain_struct_fields, plain_struct_names, struct_name, field_name, indent + "        ", tmp_id, out,
            type_param_names, plain_struct_type_params,
        )
        out += indent + "        var " + key_var + " = " + key_expr + "\n"
        out += indent + "        sc.expect_byte(UInt8(ord(\",\")))\n"
        var val_expr = _parse_value_expr(
            val_t, plain_struct_fields, plain_struct_names, struct_name, field_name, indent + "        ", tmp_id, out,
            type_param_names, plain_struct_type_params,
        )
        out += indent + "        " + var_name + "[" + key_var + "] = " + val_expr + "\n"
        out += indent + "        sc.expect_byte(UInt8(ord(\"]\")))\n"
        out += indent + "        if not sc.try_consume_byte(UInt8(ord(\",\"))):\n"
        out += indent + "            break\n"
        out += indent + "    sc.expect_byte(UInt8(ord(\"]\")))\n"
        return var_name + "^"

    # Anything else -- `Variant`, or a custom wrapper of any arity -- the
    # uniform `_to_json`/`_from_json` contract every wrapper implements, no
    # intermediate built here at all.
    var type_args_str = String()
    for i in range(t.arg_count()):
        if i > 0:
            type_args_str += ", "
        type_args_str += rewritten_field_type(t.arg(i).render(), plain_struct_names)
    return "sqrrl__" + t.name + "_from_json[" + type_args_str + "](sc, world)"


def _emit_field_json_parse(
    f: Field,
    struct_name: String,
    plain_struct_fields: Dict[String, List[Field]],
    plain_struct_names: Dict[String, Bool],
    type_param_names: Dict[String, Bool] = Dict[String, Bool](),
    plain_struct_type_params: Dict[String, List[TypeParam]] = Dict[String, List[TypeParam]](),
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
        t, plain_struct_fields, plain_struct_names, struct_name, f.name, "                ", tmp_id, out,
        type_param_names, plain_struct_type_params,
    )
    out += "                parsed_" + f.name + " = " + expr + "\n"
    return out^


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
    genuinely undiscovered hand-written type (falls back to a hand-written
    companion -- see `_leaf_from_json_expr`) or a plain struct's own bare,
    unbound type parameter (kept as its own explicit, distinct error
    there)."""
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
    value off `sc`. A genuinely undiscovered hand-written type
    (never scanned as `@@struct` or a plain struct anywhere in the
    project -- e.g. a plain `home: ExternalAddress` field imported from an
    ordinary, never-`.mojo.sqrrl` module) falls back to a hand-written
    `sqrrl__<TypeName>_from_json(mut sc: sqrrl___JsonScanner) raises ->
    TypeName` companion (`to_json` stays fully automatic either way, via
    `sqrrl__to_json[T]`'s own reflection -- only the reload direction ever
    needs generated/hand-written code, reflection can't write fields
    back).

    A struct's own bare, unbound type parameter (`Box[T]`'s `value: T`)
    is excluded from that fallback, not guessed at as a hand-written
    companion -- there's no concrete `sqrrl__T_from_json` to call; `T` is a
    compile-time parameter of the *generated* function itself, not a
    real type name, so it gets its own explicit, distinct error instead
    of a confusing "undefined name" from a downstream Mojo compile."""
    if type_str == "String":
        return "sc.parse_json_string()"
    if type_str == "Bool":
        return "sc.parse_json_bool()"
    if type_str == "Float64" or type_str == "Float32":
        return type_str + "(sc.parse_json_float())"
    if _is_integer_leaf(type_str):
        return type_str + "(sc.parse_json_int())"
    if type_str in type_param_names:
        raise _unbound_type_param_field_error(struct_name, field_name, type_str)
    return "sqrrl__" + type_str + "_from_json(sc)"


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


def _mono_ident_for_type(t: TypeExpr) -> String:
    """A Mojo-identifier-safe rendering of a concrete type argument, for
    building a monomorphized plain-struct `from_json` companion's own
    distinct name -- `Employee` (a relation's bare target name, `@@`
    already stripped) -> `"Employee"`, `List[Employee]` -> `"List_
    Employee"`."""
    if t.kind == TypeExpr.RELATION or t.kind == TypeExpr.LEAF:
        return t.name
    var out = t.name
    for i in range(t.arg_count()):
        out += "_" + _mono_ident_for_type(t.arg(i))
    return out^


def _mono_suffix_for_type_args(t: TypeExpr) -> String:
    """`_<arg1>_<arg2>...` off `t`'s own type arguments, e.g. `Box[
    @@Employee]` -> `"_Employee"` -- appended to a generic plain struct's
    own bare name to build its monomorphized companion's distinct name
    (`sqrrl__Box_Employee_from_json`), since Mojo has no way to overload
    on a still-generic function's own compile-time type parameter the way
    this needs."""
    var out = String()
    for i in range(t.arg_count()):
        out += "_" + _mono_ident_for_type(t.arg(i))
    return out^


def _substituted_fields_for(
    t: TypeExpr,
    plain_struct_fields: Dict[String, List[Field]],
    plain_struct_type_params: Dict[String, List[TypeParam]],
) raises -> List[Field]:
    """`t`'s own base plain struct's raw field list, with every bare type
    parameter substituted by `t`'s own concrete type arguments and
    rendered back into ordinary DSL-syntax text (`value: T` -> `value:
    @@Employee`) -- what a monomorphized `sqrrl__<Name>_from_json`
    companion's own field list should look like, so every existing
    per-field dispatch branch (`is_relation_field`, `_plain_struct_value_
    base`, container-with-relation, ...) recognizes it exactly as if the
    DSL author had written the concrete type directly, with zero new
    special-casing needed in `_emit_plain_struct_from_json` itself."""
    var type_params = (
        plain_struct_type_params[t.name].copy() if t.name in plain_struct_type_params else List[TypeParam]()
    )
    var type_args = List[TypeExpr]()
    for i in range(t.arg_count()):
        type_args.append(t.arg(i).copy())
    var out = List[Field]()
    for f in plain_struct_fields[t.name]:
        var raw = parse_type_expr(f.type_str)
        var substituted = _substitute_type_params_expr(raw, type_params, type_args)
        out.append(Field(name=f.name, type_str=substituted.render(), modifier=f.modifier, is_stats=f.is_stats))
    return out^


def _collect_mono_plain_struct_targets_from_type(
    t: TypeExpr,
    plain_struct_fields: Dict[String, List[Field]],
    plain_struct_type_params: Dict[String, List[TypeParam]],
    plain_struct_names: Dict[String, Bool],
    mut seen: Dict[String, Bool],
    mut out: List[TypeExpr],
) raises:
    """Collects every distinct generic plain-struct instantiation
    reachable from `t` whose own bare type parameter(s), once substituted,
    reach a relation (`Box[@@Employee]`) -- what `emit_json_module` needs
    to generate a monomorphized `sqrrl__<Name><_MonoSuffix>_from_json`
    companion for, per `_plain_struct_from_json_call`'s own doc comment.
    A relation-free generic instantiation (`Box[String]`) is already
    fully handled by the ordinary shared dispatch table (`_collect_
    dispatch_types`) and is skipped here. Recurses into a matched
    instantiation's own substituted field graph too (a nested generic
    plain struct field might independently need its own distinct
    companion), and into every type argument either way (an argument
    might itself be an independently-reachable generic instantiation)."""
    if (
        t.name in plain_struct_names
        and t.arg_count() > 0
        and t.render() not in seen
        and _type_involves_relation(t, plain_struct_fields, plain_struct_type_params)
    ):
        seen[t.render()] = True
        out.append(t.copy())
        var type_params = (
            plain_struct_type_params[t.name].copy() if t.name in plain_struct_type_params else List[TypeParam]()
        )
        var type_args = List[TypeExpr]()
        for i in range(t.arg_count()):
            type_args.append(t.arg(i).copy())
        for f in plain_struct_fields[t.name]:
            var raw = parse_type_expr(f.type_str)
            var substituted = _substitute_type_params_expr(raw, type_params, type_args)
            _collect_mono_plain_struct_targets_from_type(
                substituted, plain_struct_fields, plain_struct_type_params, plain_struct_names, seen, out
            )
    for i in range(t.arg_count()):
        _collect_mono_plain_struct_targets_from_type(
            t.arg(i), plain_struct_fields, plain_struct_type_params, plain_struct_names, seen, out
        )


def _collect_mono_plain_struct_targets(
    fields: List[Field],
    plain_struct_fields: Dict[String, List[Field]],
    plain_struct_type_params: Dict[String, List[TypeParam]],
    plain_struct_names: Dict[String, Bool],
    mut seen: Dict[String, Bool],
    mut out: List[TypeExpr],
) raises:
    for f in fields:
        if f.modifier == FieldModifier.MULTI:
            continue
        _collect_mono_plain_struct_targets_from_type(
            parse_type_expr(f.type_str), plain_struct_fields, plain_struct_type_params, plain_struct_names, seen, out
        )


def _plain_struct_from_json_call(
    t: TypeExpr,
    plain_struct_fields: Dict[String, List[Field]],
    plain_struct_names: Dict[String, Bool],
    plain_struct_type_params: Dict[String, List[TypeParam]] = Dict[String, List[TypeParam]](),
) raises -> String:
    """The generated-code expression reconstructing a plain-struct-valued
    value's own nested JSON object off `sc`, via its auto-generated
    `sqrrl__<Base>_from_json` companion (`_emit_plain_struct_from_json`).
    `world: sqrrl___World` is passed straight through -- every generated
    `_from_json` companion takes it uniformly now, so there's no per-
    callee sibling-table list to compute any more (`world.<Target>`
    already reaches any table this or any nested plain struct needs).

    A generic instantiation whose own bare type parameter, once
    substituted, reaches a relation (`Box[@@Employee]`, detected via
    `_type_involves_relation`) routes to a distinct, fully-monomorphized
    `sqrrl__<Base><_MonoSuffix>_from_json` companion instead of the
    ordinary generic one -- `Box`'s own generic `sqrrl__Box_from_json[T]`
    is generated once, from `Box`'s raw (unsubstituted) fields, so its
    body's `value: T` field can never know `T` is actually `Employee` at
    this call site; the monomorphized companion is generated with `T`
    already substituted throughout its own field list (`_substituted_
    fields_for`), so every existing field-dispatch branch (`is_relation_
    field`, container-with-relation, ...) recognizes the relation exactly
    as if it had been written directly. A non-generic plain struct
    embedding a relation directly (`Address`'s `@@owner: @@Employee`)
    never needs this -- its own raw fields already show the relation with
    no substitution required, so the ordinary generic path (which, for a
    non-generic struct, is just the *only* path) already handles it.

    Otherwise (no relation reachable through substitution), a generic
    instantiation (`item: Box[String]`) supplies its own explicit `[...]`
    type-argument list, rendered through `rewritten_field_type` on each
    argument's own marked source text (`t.arg(i).render()`) -- the exact
    same relation-vs-plain-struct rewriting every other field type already
    goes through, just applied one argument at a time here instead of to a
    whole field's type."""
    var base = t.name
    if t.arg_count() > 0 and _type_involves_relation(t, plain_struct_fields, plain_struct_type_params):
        var mono_suffix = _mono_suffix_for_type_args(t)
        return "sqrrl__" + base + mono_suffix + "_from_json(sc, world)"
    var type_args = String()
    if t.arg_count() > 0:
        type_args += "["
        for i in range(t.arg_count()):
            if i > 0:
                type_args += ", "
            type_args += rewritten_field_type(t.arg(i).render(), plain_struct_names)
        type_args += "]"
    var call = "sqrrl__" + base + "_from_json" + type_args + "(sc, world)"
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
    plain_struct_fields: Dict[String, List[Field]] = Dict[String, List[Field]](),
    plain_struct_type_params: Dict[String, List[TypeParam]] = Dict[String, List[TypeParam]](),
) raises -> String:
    """Mirror of `_parse_value_expr`, for the dump direction: returns an
    expression evaluating to the JSON text for `value_expr` (already a
    value of type `t`). Anything `sqrrl__to_json[T]` already handles
    generically -- a leaf, a relation (its own bare id), or a plain-
    struct value at any nesting depth via `reflect[T]` -- dumps with a
    single `sqrrl__to_json(value_expr)` call. A *container* value can't go
    through reflection at all (it has no named/typed fields for `reflect
    [T]` to walk): `List`/`Set`/`Dict`/`Optional` get their own recursive
    dump loop, inline -- the mirror image of `_parse_value_expr`'s own
    handling for those four, just building a *string* accumulator instead
    of a *value* one. Anything else (`Variant`, or a custom wrapper of any
    arity) dumps via the uniform `sqrrl__<Wrapper>_to_json(value, world) ->
    String` contract instead, no special-casing by name or arity beyond
    those four built-ins.

    Needed for a container-shaped field to correctly dump a *nested*
    container element (`List[List[String]]`) -- confirmed missing via a
    real compile: the previous, non-recursive per-field dump called
    `sqrrl__to_json` on every element unconditionally, which fails
    outright for an element that's itself a container, since reflection
    can't handle one either."""
    if t.is_relation():
        # Dumped directly as its own bare id -- no generic dispatch/trait-
        # conformance detour needed at all (see this module's own doc
        # comment for why `sqrrl___JsonSerializable` was removed): a
        # relation's own JSON shape is always just its id, known
        # unconditionally at this exact call site, not something that
        # needs to be sorted out generically at runtime.
        return "String(" + value_expr + ".id())"
    if t.name in plain_struct_names:
        # A relation-involving plain struct (`Roster.@@members: List[
        # @@Employee]`) never gets a dispatch-table branch at all
        # (`_collect_dispatch_types` deliberately excludes relation-
        # involving subtrees, the same gate `_emit_plain_struct_to_json`'s
        # own field-level check already applies) -- calling `sqrrl__to_
        # json(value_expr)` here would fall through to `sqrrl__to_json_
        # default`'s reflect[T] fallback, which can't walk a container
        # field at all (confirmed via a real crash: `struct_field_types
        # requires a struct type`). Calls the explicit `sqrrl__<Name>_to_
        # json` companion directly instead -- mono-suffixed for a
        # relation-involving *generic* instantiation (mirroring `_plain_
        # struct_from_json_call`'s own identical monomorphization on the
        # reload side exactly), bare for a non-generic one (`_mono_
        # suffix_for_type_args` already returns "" when `t` has no type
        # arguments, resolving to the ordinary, non-mono companion
        # `_emit_plain_struct_to_json`'s own main emission loop always
        # generates).
        if _type_involves_relation(t, plain_struct_fields, plain_struct_type_params):
            return "sqrrl__" + t.name + _mono_suffix_for_type_args(t) + "_to_json(" + value_expr + ", world)"
        return "sqrrl__to_json(" + value_expr + ", world)"
    if not t.is_parameterized():
        return "sqrrl__to_json(" + value_expr + ", world)"

    if t.name == "Optional" and t.arg_count() == 1:
        ref elem = t.arg(0)
        tmp_id += 1
        var out_var = "ds" + String(tmp_id)
        out += indent + "var " + out_var + ": String\n"
        out += indent + "if " + value_expr + ":\n"
        var elem_expr = _dump_value_expr(
            value_expr + ".value()", elem, plain_struct_names, indent + "    ", tmp_id, out, plain_struct_fields,
            plain_struct_type_params,
        )
        out += indent + "    " + out_var + " = " + elem_expr + "\n"
        out += indent + "else:\n"
        out += indent + "    " + out_var + " = \"null\"\n"
        return out_var

    if t.name == "Dict":
        ref key_t = t.arg(0)
        ref val_t = t.arg(1)
        tmp_id += 1
        var this_id = tmp_id
        var out_var = "ds" + String(this_id)
        out += indent + "var " + out_var + " = String(\"[\")\n"
        out += indent + "var dfirst" + String(this_id) + " = True\n"
        out += indent + "for de" + String(this_id) + " in " + value_expr + ".items():\n"
        out += indent + "    if not dfirst" + String(this_id) + ":\n"
        out += indent + "        " + out_var + " += \",\"\n"
        var key_expr = _dump_value_expr(
            "de" + String(this_id) + ".key", key_t, plain_struct_names, indent + "    ", tmp_id, out, plain_struct_fields,
            plain_struct_type_params,
        )
        var val_expr = _dump_value_expr(
            "de" + String(this_id) + ".value", val_t, plain_struct_names, indent + "    ", tmp_id, out, plain_struct_fields,
            plain_struct_type_params,
        )
        out += indent + "    " + out_var + " += \"[\" + " + key_expr + " + \",\" + " + val_expr + " + \"]\"\n"
        out += indent + "    dfirst" + String(this_id) + " = False\n"
        out += indent + out_var + " += \"]\"\n"
        return out_var

    if t.name == "List" or t.name == "Set":
        ref elem = t.arg(0)
        tmp_id += 1
        var this_id = tmp_id
        var out_var = "ds" + String(this_id)
        out += indent + "var " + out_var + " = String(\"[\")\n"
        out += indent + "var dfirst" + String(this_id) + " = True\n"
        out += indent + "for dv" + String(this_id) + " in " + value_expr + ":\n"
        out += indent + "    if not dfirst" + String(this_id) + ":\n"
        out += indent + "        " + out_var + " += \",\"\n"
        var elem_expr = _dump_value_expr(
            "dv" + String(this_id), elem, plain_struct_names, indent + "    ", tmp_id, out, plain_struct_fields,
            plain_struct_type_params,
        )
        out += indent + "    " + out_var + " += " + elem_expr + "\n"
        out += indent + "    dfirst" + String(this_id) + " = False\n"
        out += indent + out_var + " += \"]\"\n"
        return out_var

    # Anything else -- `Variant`, or a custom wrapper of any arity -- the
    # uniform `_to_json`/`_from_json` contract every wrapper implements:
    # `sqrrl__<Wrapper>_to_json(value, world) -> String`, the complete JSON
    # text for this value, no intermediate built here.
    return "sqrrl__" + t.name + "_to_json(" + value_expr + ", world)"


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
    to(sqrrl___JsonSerializable)` -- the target row itself is serialized
    once, separately, as part of its own table's own dump), or a plain-
    struct value (recursing through `reflect[T]`, at any nesting depth --
    including a generic instantiation like `Box[UInt32]`, which is why the
    "unsupported container" rejection below has to exempt a plain-struct-
    shaped field explicitly: it's bracket-shaped too, but reflection
    already handles it, unlike a genuine `List[...]`/`Set[...]`/`Dict[...]`)."""
    var entity_name = sqrrl_prefixed(parsed.name)
    var out = String(
        "\ndef sqrrl__" + parsed.name + "_to_json(e: " + entity_name + ", world: sqrrl___World) -> String:\n"
    )
    out += "    var out = String(\"{\")\n"
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
            out += "    out += \",\"\n"
        out += "    out += " + _json_key_literal_source(f.name) + "\n"
        # A discovered plain struct's own generic instantiation (`Tagged[
        # String]`) is bracket-shaped too -- checked *before* any
        # container-kind dispatch below, or a plain-struct field would be
        # misrouted into an array/dict dump assuming it's iterable/mapping-
        # shaped, when reflection is what actually needs to run (and what
        # `from_json`'s own `_parse_value_expr` already correctly prefers
        # -- this check keeps `_emit_to_json` consistent with it, found via
        # a real end-to-end compile: `Tagged[String]` tried to `for x in`
        # a plain struct that isn't iterable at all).
        var plain_struct_base = _plain_struct_value_base(f, plain_struct_names)
        var is_plain_struct_field = Bool(plain_struct_base)
        if f.modifier == FieldModifier.MULTI:
            # multi's own type_str is always bare (`@@Target`, never
            # bracket-shaped -- the modifier itself already means "many
            # of these"), so it can't go through `_dump_value_expr`'s own
            # TypeExpr-based dispatch the way every other container-shaped
            # field now does; kept as its own direct, minimal case.
            out += "    out += \"[\"\n"
            out += "    var mfirst_" + f.name + " = True\n"
            out += "    ref mval_" + f.name + " = e._inner[].get_" + param_name(f) + "()\n"
            out += "    for m_" + f.name + " in mval_" + f.name + ":\n"
            out += "        if not mfirst_" + f.name + ":\n"
            out += "            out += \",\"\n"
            # A `multi` field isn't always a relation field (`multi
            # skills: String`) -- dumped via the same generic
            # `sqrrl__to_json` dispatch every other plain leaf value uses,
            # not an `.id()` call only a relation handle has.
            if is_relation_field(f):
                out += "        out += String(m_" + f.name + ".id())\n"
            else:
                out += "        out += sqrrl__to_json(m_" + f.name + ", world)\n"
            out += "        mfirst_" + f.name + " = False\n"
            out += "    out += \"]\"\n"
        elif is_plain_struct_field:
            # Same reflection-can't-walk-a-container gap `_dump_value_
            # expr`'s own plain-struct branch closes for a *nested*
            # plain-struct field -- a @@struct's own *direct* field needs
            # the identical check: a relation-involving plain struct
            # (`Roster.@@members: List[@@Employee]`) never gets a
            # dispatch-table branch at all, so `sqrrl__to_json(...)` here
            # would fall through to reflection and crash on its own
            # container field, confirmed via a real compile.
            var plain_t = plain_struct_base.value().copy()
            if _type_involves_relation(plain_t, plain_struct_fields, plain_struct_type_params):
                out += (
                    "    out += sqrrl__" + plain_t.name + _mono_suffix_for_type_args(plain_t) + "_to_json(e._inner[]"
                    ".get_" + param_name(f) + "(), world)\n"
                )
            else:
                out += "    out += sqrrl__to_json(e._inner[].get_" + param_name(f) + "(), world)\n"
        elif is_container_type(f.type_str):
            var t = parse_type_expr(f.type_str)
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
                out += "    ref fv_" + f.name + " = e._inner[].get_" + param_name(f) + "()\n"
                var dump_out = String()
                var expr = _dump_value_expr(
                    "fv_" + f.name, t, plain_struct_names, "    ", tmp_id, dump_out, plain_struct_fields,
                    plain_struct_type_params,
                )
                out += dump_out
                out += "    out += " + expr + "\n"
            else:
                out += "    out += sqrrl__to_json(e._inner[].get_" + param_name(f) + "(), world)\n"
        elif is_relation_field(f) and not is_container_type(f.type_str):
            # A bare relation's own JSON shape is always just its id --
            # dumped directly, no `sqrrl___JsonSerializable`/generic-
            # dispatch detour needed at all (this module's own doc
            # comment has the full rationale for why that trait is gone).
            out += "    out += String(e._inner[].get_" + param_name(f) + "().id())\n"
        else:
            out += "    out += sqrrl__to_json(e._inner[].get_" + param_name(f) + "(), world)\n"
        first = False
    out += "    out += \"}\"\n"
    out += "    return out^\n"
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

    var params = String(
        "table: " + table_name + ", world: sqrrl___World, id: UInt32, mut sc: sqrrl___JsonScanner"
    )

    var out = String(
        "\ndef sqrrl__" + parsed.name + "_from_json_with_id(" + params + ") raises -> " + entity_name + ":\n"
    )

    for f in parsed.fields:
        out += "    var parsed_" + f.name + ": Optional[" + emit_field_type(f) + "] = None\n"

    out += "    sc.expect_byte(UInt8(ord(\"{\")))\n"
    out += "    if not sc.try_consume_byte(UInt8(ord(\"}\"))):\n"
    out += "        while True:\n"
    out += "            var key = sc.parse_json_string()\n"
    out += "            sc.expect_byte(UInt8(ord(\":\")))\n"
    var branch_kw = "            if"
    for f in parsed.fields:
        out += branch_kw + " key == " + _quoted(f.name) + ":\n"
        branch_kw = "            elif"
        if f.modifier == FieldModifier.MULTI:
            var elem_t = emit_multi_element_type(f)
            out += "                var mset = Set[" + elem_t + "]()\n"
            out += "                sc.expect_byte(UInt8(ord(\"[\")))\n"
            out += "                if not sc.try_consume_byte(UInt8(ord(\"]\"))):\n"
            out += "                    while True:\n"
            if is_relation_field(f):
                var target = _relation_target_name(f)
                out += "                        var elem_id = UInt32(sc.parse_json_int())\n"
                out += (
                    "                        mset.add("
                    + elem_t
                    + "(world."
                    + target
                    + ".storage[].handle_for(elem_id)))\n"
                )
            else:
                # A `multi` field isn't always a relation field (`multi
                # skills: String`) -- its own bare element type is never
                # bracket-shaped (a plain leaf, per `multi`'s own
                # convention), so `_leaf_from_json_expr` alone -- not a
                # relation-id/sibling-table lookup -- reconstructs it.
                out += (
                    "                        mset.add(" + _leaf_from_json_expr(parsed.name, f.name, f.type_str) + ")\n"
                )
            out += "                        if not sc.try_consume_byte(UInt8(ord(\",\"))):\n"
            out += "                            break\n"
            out += "                    sc.expect_byte(UInt8(ord(\"]\")))\n"
            out += "                parsed_" + f.name + " = mset^\n"
        elif _is_supported_container_field(f) and _type_involves_relation(
            parse_type_expr(f.type_str), plain_struct_fields, plain_struct_type_params
        ):
            out += _emit_field_json_parse(
                f, parsed.name, plain_struct_fields, plain_struct_names, Dict[String, Bool](), plain_struct_type_params
            )
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
            out += "                var rid_" + f.name + " = UInt32(sc.parse_json_int())\n"
            out += (
                "                parsed_"
                + f.name
                + " = "
                + emit_field_type(f)
                + "(world."
                + target
                + ".storage[].handle_for(rid_"
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
                var call = _plain_struct_from_json_call(
                    plain_base.value(), plain_struct_fields, plain_struct_names, plain_struct_type_params
                )
                out += "                parsed_" + f.name + " = " + call + "\n"
            elif _is_supported_container_field(f):
                # A container that doesn't involve a relation anywhere
                # (`tags: List[String]`) -- routes through the shared,
                # generic `sqrrl__from_json[T]` dispatcher, whose own
                # dispatch-table branch for this exact type `emit_json_
                # module`'s collection pass already registered.
                out += (
                    "                parsed_"
                    + f.name
                    + " = sqrrl__from_json["
                    + emit_field_type(f)
                    + "](sc, world)\n"
                )
            else:
                # An ordinary leaf, or a genuinely undiscovered plain-
                # value type (`sqrrl__<TypeName>_from_json`, hand-written)
                # -- `_leaf_from_json_expr` already handles both, unchanged;
                # never reached for a bare, unbound type parameter here,
                # since a real `@@struct` (unlike a plain struct) is never
                # itself generic.
                out += (
                    "                parsed_"
                    + f.name
                    + " = "
                    + _leaf_from_json_expr(parsed.name, f.name, f.type_str)
                    + "\n"
                )
    out += "            else:\n"
    out += (
        "                raise Error(\"InvalidJson: unknown field \" + key + \" for "
        + parsed.name
        + "\")\n"
    )
    out += "            if not sc.try_consume_byte(UInt8(ord(\",\"))):\n"
    out += "                break\n"
    out += "        sc.expect_byte(UInt8(ord(\"}\")))\n"

    # Every field is a required parameter, same contract create() has --
    # unlike create() this can't lean on Mojo's own missing-argument check,
    # so it's an explicit runtime check here instead.
    for f in parsed.fields:
        out += "    if not parsed_" + f.name + ":\n"
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
            out += "    var v_" + f.name + " = parsed_" + f.name + ".take()\n"
            ctor_args += ", " + storage_field_name(f) + "=v_" + f.name + "^"
        else:
            out += "    var v_" + f.name + " = parsed_" + f.name + ".value()\n"
            ctor_args += ", " + storage_field_name(f) + "=v_" + f.name
    out += "    var inner = ArcPointer(" + inner_name + "(" + ctor_args + "))\n"
    out += "    table.storage[].register_weak(id, inner)\n"
    for f in parsed.fields:
        if f.modifier == FieldModifier.MULTI:
            out += (
                "    table.storage[].indexes."
                + f.name
                + ".add_many(id, inner[]."
                + storage_field_name(f)
                + ")\n"
            )
        elif f.modifier != FieldModifier.NONE:
            out += (
                "    table.storage[].indexes."
                + f.name
                + ".add(id, inner[]."
                + storage_field_name(f)
                + ")\n"
            )
    if parsed.is_keepalive:
        out += "    table.storage[].keepalive_add(id, inner.copy())\n"
    out += "    return " + entity_name + "(inner^)\n"
    return out^


def _emit_all_to_json(parsed: ParsedStruct) -> String:
    """`sqrrl__<Name>_all_to_json(table, world) -> String` -- iterates
    `table.storage[].all()` (ascending-id, for deterministic output),
    emitting `[id, json]` pairs."""
    var entity_name = sqrrl_prefixed(parsed.name)
    var table_name = entity_name + "Table"
    var out = String(
        "\ndef sqrrl__" + parsed.name + "_all_to_json(table: " + table_name + ", world: sqrrl___World) -> String:\n"
    )
    out += "    var out = String(\"[\")\n"
    out += "    var first = True\n"
    out += "    for id in table.storage[].all():\n"
    out += "        if not first:\n"
    out += "            out += \",\"\n"
    out += "        var e = " + entity_name + "(table.storage[].handle_for(id))\n"
    out += (
        "        out += \"[\" + String(id) + \",\" + sqrrl__"
        + parsed.name
        + "_to_json(e, world) + \"]\"\n"
    )
    out += "        first = False\n"
    out += "    out += \"]\"\n"
    out += "    return out^\n"
    return out^


def _emit_all_from_json(parsed: ParsedStruct) -> String:
    """`sqrrl__<Name>_all_from_json(table, world, [mut temp], mut sc)
    raises` -- parses the `[[id, obj], ...]` array, calling
    `_from_json_with_id` per entry. `temp` (a `List[sqrrl__<Name>]` slot on
    `sqrrl___TempKeepAlives`) is omitted entirely for a `keepalive`-tagged
    struct -- its own `create()`-mirrored construction inside
    `_from_json_with_id` already retains it via the table's real
    `keepalive` set, no extra hold needed."""
    var entity_name = sqrrl_prefixed(parsed.name)
    var table_name = entity_name + "Table"
    var params = String("table: " + table_name + ", world: sqrrl___World")
    if not parsed.is_keepalive:
        params += ", mut temp: List[" + entity_name + "]"
    params += ", mut sc: sqrrl___JsonScanner"

    var out = String("\ndef sqrrl__" + parsed.name + "_all_from_json(" + params + ") raises:\n")
    out += "    sc.expect_byte(UInt8(ord(\"[\")))\n"
    out += "    if not sc.try_consume_byte(UInt8(ord(\"]\"))):\n"
    out += "        while True:\n"
    out += "            sc.expect_byte(UInt8(ord(\"[\")))\n"
    out += "            var eid = UInt32(sc.parse_json_int())\n"
    out += "            sc.expect_byte(UInt8(ord(\",\")))\n"
    out += (
        "            var e = sqrrl__"
        + parsed.name
        + "_from_json_with_id(table, world, eid, sc)\n"
    )
    out += "            sc.expect_byte(UInt8(ord(\"]\")))\n"
    if not parsed.is_keepalive:
        out += "            temp.append(e)\n"
    else:
        out += "            _ = e\n"
    out += "            if not sc.try_consume_byte(UInt8(ord(\",\"))):\n"
    out += "                break\n"
    out += "        sc.expect_byte(UInt8(ord(\"]\")))\n"
    return out^


def _emit_temp_keep_alives_struct(structs: List[DiscoveredStruct]) -> String:
    """`sqrrl___TempKeepAlives` -- one `List[sqrrl__<Name>]` field per
    non-keepalive struct, threaded as a real local in the generated
    *script* (bound by `@@@begin_init_from_json`, consumed by
    `@@@end_init_from_json`), never stored on `sqrrl___World` itself (see
    project memory's own settled M5 policy)."""
    var out = String("\nstruct sqrrl___TempKeepAlives(Movable):\n")
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
    var out = String("\ndef sqrrl___world_to_json(world: sqrrl___World) -> String:\n")
    out += "    var out = String(\"{\")\n"
    var first = True
    for ds in topo_order:
        if not first:
            out += "    out += \",\"\n"
        out += "    out += " + _json_key_literal_source(ds.parsed.name) + "\n"
        out += "    out += sqrrl__" + ds.parsed.name + "_all_to_json(world." + ds.parsed.name + ", world)\n"
        first = False
    out += "    out += \"}\"\n"
    out += "    return out^\n"
    return out^


def _emit_world_from_json(topo_order: List[DiscoveredStruct]) raises -> String:
    """Dispatches on whatever top-level key order the JSON text actually
    has -- reload safety relies on the *document* being topo-ordered, which
    any dump `sqrrl___world_to_json` itself produces always is (a
    hand-edited or externally-produced dump with reordered keys could abort
    inside `handle_for` -- not a new gap this introduces, matching
    rw_squirrel_2's own identical property)."""
    var out = String(
        "\ndef sqrrl___world_from_json(mut world: sqrrl___World, mut sc: sqrrl___JsonScanner, mut"
        " temp: sqrrl___TempKeepAlives) raises:\n"
    )
    out += "    sc.expect_byte(UInt8(ord(\"{\")))\n"
    out += "    if not sc.try_consume_byte(UInt8(ord(\"}\"))):\n"
    out += "        while True:\n"
    out += "            var key = sc.parse_json_string()\n"
    out += "            sc.expect_byte(UInt8(ord(\":\")))\n"
    var branch_kw = "            if"
    for ds in topo_order:
        var call_args = String("world." + ds.parsed.name + ", world")
        if not ds.parsed.is_keepalive:
            call_args += ", temp." + ds.parsed.name
        call_args += ", sc"
        out += branch_kw + " key == " + _quoted(ds.parsed.name) + ":\n"
        out += "                sqrrl__" + ds.parsed.name + "_all_from_json(" + call_args + ")\n"
        branch_kw = "            elif"
    out += "            else:\n"
    out += "                raise Error(\"InvalidJson: unknown struct \" + key + \" in dump\")\n"
    out += "            if not sc.try_consume_byte(UInt8(ord(\",\"))):\n"
    out += "                break\n"
    out += "        sc.expect_byte(UInt8(ord(\"}\")))\n"
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
    out += "\ndef sqrrl___begin_init_from_json(mut world: sqrrl___World, json: String) raises -> sqrrl___TempKeepAlives:\n"
    out += "    world.sqrrl__check_no_leaks()\n"
    out += "    world = sqrrl___init()\n"
    out += "    var sc = sqrrl___JsonScanner(json)\n"
    out += "    var temp = sqrrl___TempKeepAlives()\n"
    out += "    sqrrl___world_from_json(world, sc, temp)\n"
    out += "    return temp^\n"

    out += "\ndef sqrrl___end_init_from_json(var temp: sqrrl___TempKeepAlives):\n"
    out += "    pass\n"

    out += "\ndef sqrrl___init_from_json(mut world: sqrrl___World, json: String) raises:\n"
    out += "    var temp = sqrrl___begin_init_from_json(world, json)\n"
    out += "    sqrrl___end_init_from_json(temp^)\n"
    return out^


def _collect_custom_container_wrappers_from_type(
    t: TypeExpr,
    plain_struct_names: Dict[String, Bool],
    mut seen: Dict[String, Bool],
    mut out: List[String],
    mut arities: Dict[String, Int],
):
    """Collects every distinct *custom, hand-written* container wrapper
    name (not `List`/`Set`/`Optional`/`Dict`, not `Variant` -- generated by
    the compiler itself, once per distinct arity, see `_collect_variant_
    arities`/`_collect_variant_arities_from_type` -- and not a discovered
    plain struct) reachable from `t`, at any nesting depth -- what
    `sqrrl__json.mojo` needs its own explicit `from <module> import
    <Wrapper>, sqrrl__<Wrapper>_to_json, sqrrl__<Wrapper>_from_json` line
    for -- same two names regardless of the wrapper's own arity (`Grid[K,
    V]`-shaped for two type arguments, `Ring[T]`-shaped for one; `arities`
    records each wrapper's own argument count purely so *other* codegen
    can pick the right call shape, not for naming the import). Unlike
    `List`/`Set`/`Optional`/`Dict`/`Variant` (generated directly into
    `sqrrl__json.mojo` itself) or a discovered plain struct (already
    imported via its own `module_of`), the compiler has no other way to
    know where a custom wrapper's own declaration -- and its `_to_json`/
    `_from_json` companions -- actually live."""
    if t.arg_count() >= 1 and t.name not in plain_struct_names:
        var wrapper = t.name
        if (
            wrapper != "List"
            and wrapper != "Set"
            and wrapper != "Optional"
            and wrapper != "Dict"
            and wrapper != "Variant"
            and wrapper not in seen
        ):
            seen[wrapper] = True
            out.append(wrapper)
            arities[wrapper] = t.arg_count()
    for i in range(t.arg_count()):
        _collect_custom_container_wrappers_from_type(t.arg(i), plain_struct_names, seen, out, arities)


def _collect_custom_container_wrappers(
    fields: List[Field],
    plain_struct_names: Dict[String, Bool],
    mut seen: Dict[String, Bool],
    mut out: List[String],
    mut arities: Dict[String, Int],
) raises:
    for f in fields:
        _collect_custom_container_wrappers_from_type(parse_type_expr(f.type_str), plain_struct_names, seen, out, arities)


def _collect_variant_arities_from_type(t: TypeExpr, mut seen: Dict[Int, Bool], mut out: List[Int]):
    """Collects every distinct arity `Variant` is instantiated at,
    reachable from `t` at any nesting depth -- unconditional, never gated
    by `_type_involves_relation` (unlike `container_dispatch_types`,
    below), since `sqrrl__Variant_to_json[T0, ..., Tn-1]`/`_from_json[T0,
    ..., Tn-1]` must exist for *every* arity actually used project-wide
    regardless of whether any particular instantiation happens to carry a
    relation in one of its type arguments -- the generic function body is
    structurally identical for any two same-arity `Variant`s, differing
    only in which concrete types fill `T0..Tn-1`, exactly mirroring how
    `_collect_custom_container_wrappers_from_type` walks unconditionally
    for the same reason."""
    if t.name == "Variant" and t.arg_count() not in seen:
        seen[t.arg_count()] = True
        out.append(t.arg_count())
    for i in range(t.arg_count()):
        _collect_variant_arities_from_type(t.arg(i), seen, out)


def _collect_variant_arities(fields: List[Field], mut seen: Dict[Int, Bool], mut out: List[Int]) raises:
    for f in fields:
        _collect_variant_arities_from_type(parse_type_expr(f.type_str), seen, out)


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


def _plain_struct_field_storage_name(
    struct_name: String, f: Field, plain_struct_fields: Dict[String, List[Field]]
) raises -> String:
    """The real generated field/keyword name a hand-written plain struct's
    own field gets -- `sqrrl__`-prefixed when `@@`-marked (matching
    `codegen/rewrite.mojo`'s own `ENTITY_PARAM` field-declaration emission
    and `MarkerKind.CONSTRUCT_KWARG`'s own constructor-call keyword
    rewriting), bare otherwise. `f.name` alone (the DSL-source spelling,
    marker stripped) is only ever correct for a *non*-relation field --
    used unconditionally throughout this file for the JSON *key* text and
    internal `parsed_<name>` temporaries (those never change), but reading
    or constructing the real Mojo value itself needs this instead.

    Deliberately checks `plain_struct_fields[struct_name]` -- the
    project-wide, never-substituted declaration -- rather than `f` itself:
    a *monomorphized* companion (`Box[@@Employee]`) is generated from a
    *substituted* field list (`_substituted_fields_for`, `value: Self.T`
    rendered as `value: @@Employee`), where `is_relation_field` on `f`
    directly would wrongly say "yes" -- but the field's own NAME was never
    `@@`-marked in the original declaration (`var value: Self.T` has no
    `@@` anywhere; only a concrete instantiation makes the *type* look
    like a relation), so `rewrite.mojo`'s own struct-declaration emission
    never prefixed it either. Confirmed via a real compile: `Box[T]`'s own
    `sqrrl__Box_to_json`/`_from_json` monomorphized companions failed
    outright ('Box[sqrrl__Employee]' value has no attribute 'sqrrl__
    value') before this lookup was corrected to check the *original*
    field, not the substituted one."""
    if struct_name in plain_struct_fields:
        for orig in plain_struct_fields[struct_name]:
            if orig.name == f.name:
                return sqrrl_prefixed(f.name) if is_relation_field(orig) else f.name
    return sqrrl_prefixed(f.name) if is_relation_field(f) else f.name


def _emit_plain_struct_to_json(
    name: String,
    fields: List[Field],
    plain_struct_fields: Dict[String, List[Field]],
    plain_struct_names: Dict[String, Bool],
    type_params: List[TypeParam] = List[TypeParam](),
    plain_struct_type_params: Dict[String, List[TypeParam]] = Dict[String, List[TypeParam]](),
    mono_suffix: String = "",
    mono_return_type: String = "",
) raises -> String:
    """`sqrrl__<Name>_to_json[<T: Bound, ...>](value: <Name>[<T, ...>]) ->
    String` -- the dump-direction companion `_emit_plain_struct_from_json`
    already has a reload one for (`_emit_plain_struct_dispatch_branch`'s
    own doc comment has the full "why this exists" rationale).

    A relation-involving container field (needs `_dump_value_expr`'s own
    explicit recursive codegen -- the shared dispatch table has no sibling
    table to resolve one with) dumps exactly like `_emit_to_json` dumps a
    real `@@struct`'s own field. A *relation-free* container field instead
    dumps via the plain `sqrrl__to_json(value.<field>)` dispatch call --
    matching `_emit_plain_struct_from_json`'s own identical gate for the
    reload direction exactly, not `_dump_value_expr`'s own container
    codegen. This distinction is load-bearing, not stylistic:
    `_dump_value_expr`'s own `Optional[T]` shape is null-or-value, while
    the shared dispatch table's (`_emit_container_dispatch_branches`)
    treats `Optional` as a 0-or-1-element list instead -- two genuinely
    different wire shapes for the same type. Using `_dump_value_expr`
    unconditionally here (an earlier version of this function did)
    produces a dump the *reload* side -- which always uses the dispatch
    table for a relation-free container field -- can't parse back,
    confirmed via a real round-trip failure on `Optional[List[String]]`
    nested in a plain struct (`InvalidJson: expected byte 91`, the reload
    side expecting the list-shaped `[[...]]` the dispatch table's own
    convention produces, not `_dump_value_expr`'s null-or-value `[...]`
    it actually got). Every other field kind (leaf, relation, plain-
    struct, relation-involving container) already agrees between the two
    directions, so only the relation-free-container case needs this
    branch at all."""
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
    var fn_name = name + mono_suffix
    var value_type = (
        mono_return_type if mono_suffix != "" else (name + "[" + type_param_names + "]" if len(type_params) > 0 else name)
    )

    var out = String(
        "\ndef sqrrl__"
        + fn_name
        + "_to_json"
        + type_param_decl
        + "(value: "
        + value_type
        + ", world: sqrrl___World) -> String:\n"
    )
    out += "    var out = String(\"{\")\n"
    var tmp_id = 0
    var first = True
    for f in fields:
        if not first:
            out += "    out += \",\"\n"
        out += "    out += " + _json_key_literal_source(f.name) + "\n"
        var t = parse_type_expr(f.type_str)
        if _is_supported_container_field(f) and not _type_involves_relation(
            t, plain_struct_fields, plain_struct_type_params
        ):
            out += "    out += sqrrl__to_json(value." + _plain_struct_field_storage_name(name, f, plain_struct_fields) + ", world)\n"
        else:
            var value_expr = _dump_value_expr(
                "value." + _plain_struct_field_storage_name(name, f, plain_struct_fields), t, plain_struct_names, "    ", tmp_id, out,
                plain_struct_fields, plain_struct_type_params,
            )
            out += "    out += " + value_expr + "\n"
        first = False
    out += "    out += \"}\"\n"
    out += "    return out^\n"
    return out^


def _emit_plain_struct_from_json(
    name: String,
    fields: List[Field],
    plain_struct_fields: Dict[String, List[Field]],
    plain_struct_names: Dict[String, Bool],
    type_params: List[TypeParam] = List[TypeParam](),
    plain_struct_type_params: Dict[String, List[TypeParam]] = Dict[String, List[TypeParam]](),
    mono_suffix: String = "",
    mono_return_type: String = "",
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
    call site, so callers never have to rely on inference.

    `mono_suffix`/`mono_return_type` (non-empty only for a monomorphized
    companion -- see `_plain_struct_from_json_call`'s own doc comment)
    generate a distinct, fully-concrete `sqrrl__<Name><mono_suffix>_from_
    json` with no `[...]` type-parameter list at all instead: `fields` is
    expected to already be fully substituted in this case (`_substituted_
    fields_for`), so `type_params` is always empty alongside it -- every
    field-dispatch branch below runs exactly as it would for a struct that
    was never generic in the first place, since a substituted field's own
    `type_str` (`"@@Employee"`, rendered by `_substituted_fields_for`)
    looks identical to one the DSL author wrote directly."""
    var params = String("mut sc: sqrrl___JsonScanner, world: sqrrl___World")

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
    var fn_name = name + mono_suffix
    var return_type = (
        mono_return_type if mono_suffix != "" else (name + "[" + type_param_names + "]" if len(type_params) > 0 else name)
    )

    var type_param_name_set = Dict[String, Bool]()
    for tp in type_params:
        type_param_name_set[tp.name] = True

    var out = String(
        "\ndef sqrrl__" + fn_name + "_from_json" + type_param_decl + "(" + params + ") raises -> " + return_type + ":\n"
    )
    for f in fields:
        out += "    var parsed_" + f.name + ": Optional[" + rewritten_field_type(f.type_str, plain_struct_names) + "] = None\n"

    out += "    sc.expect_byte(UInt8(ord(\"{\")))\n"
    out += "    if not sc.try_consume_byte(UInt8(ord(\"}\"))):\n"
    out += "        while True:\n"
    out += "            var key = sc.parse_json_string()\n"
    out += "            sc.expect_byte(UInt8(ord(\":\")))\n"
    var branch_kw = "            if"
    for f in fields:
        out += branch_kw + " key == " + _quoted(f.name) + ":\n"
        branch_kw = "            elif"
        if _is_supported_container_field(f) and _type_involves_relation(
            parse_type_expr(f.type_str), plain_struct_fields, plain_struct_type_params
        ):
            out += _emit_field_json_parse(
                f, name, plain_struct_fields, plain_struct_names, type_param_name_set, plain_struct_type_params
            )
        elif is_relation_field(f) and not is_container_type(f.type_str):
            # Same exclusion as `_emit_from_json_with_id` above -- a
            # *supported* wrapped relation (`List`/`Set`/`Optional`) was
            # already handled above; anything else wrapped (`Dict[...]`,
            # deliberately unsupported) must fall through to the
            # container rejection, not this single-bare-id dispatch.
            var target = _relation_target_name(f)
            out += "                var rid_" + f.name + " = UInt32(sc.parse_json_int())\n"
            out += (
                "                parsed_"
                + f.name
                + " = "
                + sqrrl_prefixed(target)
                + "(world."
                + target
                + ".storage[].handle_for(rid_"
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
                var call = _plain_struct_from_json_call(
                    plain_base.value(), plain_struct_fields, plain_struct_names, plain_struct_type_params
                )
                out += "                parsed_" + f.name + " = " + call + "\n"
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
                    "                parsed_"
                    + f.name
                    + " = sqrrl__from_json["
                    + rewritten_field_type(f.type_str, plain_struct_names)
                    + "](sc, world)\n"
                )
            else:
                # An ordinary leaf, or a genuinely undiscovered plain-
                # value type (the `sqrrl__<TypeName>_from_json` escape
                # hatch) -- `_leaf_from_json_expr` already handles both,
                # unchanged.
                out += (
                    "                parsed_"
                    + f.name
                    + " = "
                    + _leaf_from_json_expr(name, f.name, f.type_str, type_param_name_set)
                    + "\n"
                )
    out += "            else:\n"
    out += "                raise Error(\"InvalidJson: unknown field \" + key + \" for " + name + "\")\n"
    out += "            if not sc.try_consume_byte(UInt8(ord(\",\"))):\n"
    out += "                break\n"
    out += "        sc.expect_byte(UInt8(ord(\"}\")))\n"

    for f in fields:
        out += "    if not parsed_" + f.name + ":\n"
        out += "        raise Error(\"InvalidJson: missing field " + f.name + " for " + name + "\")\n"

    var ctor_args = String()
    var first = True
    for f in fields:
        if not first:
            ctor_args += ", "
        ctor_args += _plain_struct_field_storage_name(name, f, plain_struct_fields) + "=parsed_" + f.name + ".take()"
        first = False
    out += "    return " + return_type + "(" + ctor_args + ")\n"
    return out^


def _emit_container_dispatch_branches(
    t: TypeExpr, plain_struct_names: Dict[String, Bool], mut to_json_out: String, mut from_json_out: String
) raises:
    """Appends one `elif T == <type>:` branch each to `sqrrl__to_json[T]`'s
    own dump dispatch table and `sqrrl__from_json[T]`'s own reload one, for
    `t` -- either a bare relation, or a container (`List`/`Set`/`Dict`/
    `Optional`/`Variant`, or a custom wrapper of any arity). Fully uniform
    for every one of those kinds: each implements the same `sqrrl__
    <Wrapper>_to_json(value, world) -> String` / `sqrrl__<Wrapper>_from_
    json[T...](sc, world) raises -> Wrapper[T...]` contract (`Variant`
    generated once per distinct arity, a custom wrapper hand-written,
    `List`/`Set`/`Dict`/`Optional` generated alongside this dispatch table
    itself -- see `emit_json_module`), so the branch built here never needs
    to special-case by kind/arity/name at all any more -- `world` is what
    makes this possible: every one of those functions can now correctly
    resolve a relation nested anywhere in its own type arguments by
    recursing back into this exact dispatch table.

    A bare relation (`t.is_relation()`, registered here by `_collect_
    dispatch_types_from_type` specifically for the case where it's only
    reachable *generically* -- nested inside `Variant`'s own type
    arguments or a custom wrapper's, where no field-level codegen ever
    sees it directly) dumps as its own id directly, no wrapper call
    needed; reloads via `world.<Target>.storage[].handle_for(...)`, the
    same live-table lookup `_parse_value_expr`'s own relation branch uses.

    `type_str`/each type argument goes through `rewritten_field_type`, not
    a bare `.render()` -- unlike an earlier version of this function, `t`
    is no longer guaranteed relation-free (a relation-involving container
    reached only generically, from inside `Variant`'s own type arguments
    or a custom wrapper's, is registered too now), and `.render()` alone
    renders a relation as `"@@Employee"` -- real DSL-source syntax, not
    valid Mojo -- while `rewritten_field_type` renders it as `sqrrl__
    Employee`, the same rewriting every other generated type reference in
    this file already goes through."""
    var type_str = rewritten_field_type(t.render(), plain_struct_names)
    if t.is_relation():
        var target = t.name
        to_json_out += "    elif T == " + type_str + ":\n"
        to_json_out += "        return String(rebind[" + type_str + "](value).id())\n"
        from_json_out += "    elif T == " + type_str + ":\n"
        from_json_out += (
            "        return sqrrl__movable_rebind["
            + type_str
            + ", T]("
            + type_str
            + "(world."
            + target
            + ".storage[].handle_for(UInt32(sc.parse_json_int()))))\n"
        )
        return
    var wrapper = t.name
    var type_args = String()
    for i in range(t.arg_count()):
        if i > 0:
            type_args += ", "
        type_args += rewritten_field_type(t.arg(i).render(), plain_struct_names)
    to_json_out += "    elif T == " + type_str + ":\n"
    to_json_out += "        return sqrrl__" + wrapper + "_to_json(rebind[" + type_str + "](value), world)\n"
    from_json_out += "    elif T == " + type_str + ":\n"
    from_json_out += (
        "        return sqrrl__movable_rebind["
        + type_str
        + ", T](sqrrl__"
        + wrapper
        + "_from_json["
        + type_args
        + "](sc, world))\n"
    )


def _emit_plain_struct_dispatch_branch(
    t: TypeExpr,
    plain_struct_fields: Dict[String, List[Field]],
    plain_struct_type_params: Dict[String, List[TypeParam]],
    plain_struct_names: Dict[String, Bool],
    mut to_json_out: String,
    mut from_json_out: String,
) raises:
    """Appends one `elif T == <type>:` branch each to `sqrrl__to_json[T]`'s
    own dump dispatch table and `sqrrl__from_json[T]`'s own reload one, for
    the discovered-plain-struct instantiation `t` -- `world: sqrrl___World`
    threaded through both calls, since the companion this delegates to
    (ordinary or monomorphized) now always takes it.

    The dump-direction branch (`sqrrl__<Name>_to_json`, `_emit_plain_
    struct_to_json`) exists for the same reason the reload one always has:
    `sqrrl__to_json_default`'s own `reflect[T]`-based fallback
    (`squirrel_runtime/json.mojo`) recurses into *itself* directly per
    field, never back through this project's own dispatch table -- so a
    plain struct's own container-typed field (`Dict`/`List`/`Set`/
    `Optional`, or a custom wrapper) was never actually intercepted by the
    mechanism meant to handle it, and reflection genuinely can't walk one
    at all (confirmed via a real compile: `struct_field_types requires a
    struct type`, hit reflecting *into* a `Dict[String, Int]` field).

    A generic instantiation whose own bare type parameter, once
    substituted, reaches a relation (`Box[@@Employee]`) delegates to the
    distinct, fully-monomorphized `sqrrl__<Base><_MonoSuffix>_to_json`/
    `_from_json` companion instead of the ordinary generic one -- same
    reasoning, and the same `_mono_suffix_for_type_args` naming, as `_plain_
    struct_from_json_call` already uses for the identical case at the
    per-field call site; this dispatch branch is the *other* place that
    same monomorphized companion needs to be reachable from, now that a
    relation-involving plain struct nested inside `Variant`'s own type
    arguments or a custom wrapper's needs it resolved generically too.
    `type_str`/each type argument goes through `rewritten_field_type`, for
    the same reason `_emit_container_dispatch_branches` now does -- `t` is
    no longer guaranteed relation-free, and a bare `.render()` would leave
    `@@Employee` (real DSL syntax, not valid Mojo) in generated text."""
    var type_str = rewritten_field_type(t.render(), plain_struct_names)
    var base = t.name
    var name_suffix = String()
    var type_args = String()
    if t.arg_count() > 0 and _type_involves_relation(t, plain_struct_fields, plain_struct_type_params):
        name_suffix = _mono_suffix_for_type_args(t)
    elif t.arg_count() > 0:
        type_args += "["
        for i in range(t.arg_count()):
            if i > 0:
                type_args += ", "
            type_args += rewritten_field_type(t.arg(i).render(), plain_struct_names)
        type_args += "]"
    to_json_out += "    elif T == " + type_str + ":\n"
    to_json_out += (
        "        return sqrrl__" + base + name_suffix + "_to_json" + type_args + "(rebind[" + type_str + "](value), world)\n"
    )
    from_json_out += "    elif T == " + type_str + ":\n"
    from_json_out += (
        "        return sqrrl__movable_rebind["
        + type_str
        + ", T](sqrrl__"
        + base
        + name_suffix
        + "_from_json"
        + type_args
        + "(sc, world))\n"
    )


def emit_json_module(
    discovery_structs: List[DiscoveredStruct],
    topo_order: List[DiscoveredStruct],
    plain_struct_discovery: PlainStructDiscovery = PlainStructDiscovery(Dict[String, List[Field]](), Dict[String, String]()),
    raw_imports: Dict[String, String] = Dict[String, String](),
    output_module_prefix: String = "",
) raises -> String:
    """Emits `sqrrl__json.mojo`'s whole content -- every JSON-related
    generated symbol for the whole project, in this one file (the
    non-negotiable constraint, see this file's own module doc comment).
    `discovery_structs` (declaration order) drives the per-struct function
    definitions (order doesn't matter there); `topo_order` (dependency
    order, `driver/topo_order.mojo`) drives `sqrrl___world_to_json`'s own
    key order and `sqrrl___world_from_json`'s dispatch-branch order, so a
    genuine dump always reloads safely. `plain_struct_discovery`
    (plain-structs milestone) drives one `sqrrl__<Name>_from_json`
    companion per *non-generic* plain struct discovered project-wide.
    `raw_imports` (`discover_raw_imports`, `driver/misc_builders.mojo`) --
    imported symbol name -> the module it's imported from, scanned from
    every `.mojo.sqrrl` file's own raw `from X import Y` lines project-
    wide -- is the true-origin lookup a custom container wrapper's/leaf
    type's own escape-hatch companions use below, in place of the older
    "whichever struct's field first referenced it" guess.

    `output_module_prefix` (`convert_directory.mojo`'s own `output_
    module_prefix`, e.g. `"src."`) prefixes this file's own `squirrel_
    runtime`/`sqrrl__world` imports -- both otherwise bare, top-level
    names, which only resolve as such when this file lives at the same
    directory `-I <target_root>` itself points at. Once this file moves
    into a `src/` subdirectory instead (`entry_split.mojo`'s own reason
    for `output_root` existing at all), that directory needs its own
    `__init__.mojo` for `src.main_impl`-style cross-file imports to work
    -- but that alone makes Mojo treat `src` as a real package, and a
    bare `from squirrel_runtime import ...` from *inside* it no longer
    resolves (confirmed via a real, minimal repro) without this prefix."""
    var plain_struct_fields = plain_struct_discovery.fields.copy()
    var plain_struct_names = Dict[String, Bool]()
    var plain_struct_name_list = List[String]()
    for name in plain_struct_fields.keys():
        plain_struct_names[String(name)] = True
        plain_struct_name_list.append(String(name))

    var out = String(
        "from std.memory import ArcPointer\n"
        "from std.collections import Set\n"
        "from " + output_module_prefix + "squirrel_runtime.json import sqrrl___JsonScanner, sqrrl__json_string_literal,"
        " sqrrl__json_bool_literal, sqrrl__to_json_default, sqrrl__from_json_default, sqrrl__movable_rebind\n"
        "from " + output_module_prefix + "sqrrl__world import sqrrl___World, sqrrl___init\n"
    )

    # `Variant` itself (Mojo's own stdlib generic) is never one of
    # `discovery_structs`/`plain_struct_name_list`'s own imports -- needed
    # explicitly whenever any distinct arity was actually collected
    # (`_collect_variant_arities`, below), since this file's own generated
    # `sqrrl__Variant_to_json`/`_from_json` reference it directly, same
    # gap `driver/emit_file.mojo`'s own conditional import closes for a
    # real @@struct's own `Variant[...]`-typed field.
    var variant_arity_seen = Dict[Int, Bool]()
    var variant_arities = List[Int]()
    for ds in discovery_structs:
        _collect_variant_arities(ds.parsed.fields, variant_arity_seen, variant_arities)
    for plain_name in plain_struct_name_list:
        _collect_variant_arities(plain_struct_fields[plain_name], variant_arity_seen, variant_arities)
    if len(variant_arities) > 0:
        out += "from std.utils import Variant\n"
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

    # A custom container wrapper (any wrapper, of any arity, other than
    # List/Set/Optional/Dict/Variant, and not a discovered plain struct)
    # has no `module_of` entry at all -- the compiler never scanned a
    # declaration for it, by definition. Its hand-written `sqrrl__
    # <Wrapper>_to_json`/`sqrrl__<Wrapper>_from_json` companions (the same
    # `_to_json`/`_from_json` contract every wrapper implements, world-
    # threaded like everything else in this dispatch chain) are imported
    # from, in priority order:
    #   1. wherever `raw_imports` says `sqrrl__<Wrapper>_to_json` itself is
    #      imported from directly, project-wide -- an explicit escape
    #      valve for when the companions *don't* live alongside the
    #      wrapper (rare, but not this compiler's business to forbid):
    #      write `from <true module> import sqrrl__<Wrapper>_to_json,
    #      sqrrl__<Wrapper>_from_json` anywhere in the project (no DSL
    #      sugar needed -- it's an ordinary import line) and this takes
    #      precedence.
    #   2. else, wherever `raw_imports` says the wrapper *type itself* is
    #      imported from -- the common case, trusting the convention that
    #      the companions live alongside their wrapper.
    #   3. else, whichever real @@struct/plain struct's own module first
    #      *referenced* the wrapper as a field type -- the old guess,
    #      kept only as a last resort (`raw_imports` having neither entry
    #      shouldn't happen in practice, since nothing could construct
    #      the wrapper's value without importing it somewhere).
    var custom_wrapper_module = Dict[String, String]()
    var custom_wrapper_list = List[String]()
    var custom_wrapper_arity = Dict[String, Int]()
    var cwseen = Dict[String, Bool]()
    for ds in discovery_structs:
        var before = len(custom_wrapper_list)
        _collect_custom_container_wrappers(ds.parsed.fields, plain_struct_names, cwseen, custom_wrapper_list, custom_wrapper_arity)
        for i in range(before, len(custom_wrapper_list)):
            custom_wrapper_module[custom_wrapper_list[i]] = ds.module_path
    for plain_name in plain_struct_name_list:
        var before2 = len(custom_wrapper_list)
        _collect_custom_container_wrappers(
            plain_struct_fields[plain_name], plain_struct_names, cwseen, custom_wrapper_list, custom_wrapper_arity
        )
        for i in range(before2, len(custom_wrapper_list)):
            custom_wrapper_module[custom_wrapper_list[i]] = plain_struct_discovery.module_of[plain_name]
    for wrapper in custom_wrapper_list:
        var to_name = "sqrrl__" + wrapper + "_to_json"
        var source_module: String
        if to_name in raw_imports:
            source_module = raw_imports[to_name]
        elif wrapper in raw_imports:
            source_module = raw_imports[wrapper]
        else:
            source_module = custom_wrapper_module[wrapper]
        out += (
            "from "
            + source_module
            + " import "
            + wrapper
            + ", sqrrl__"
            + wrapper
            + "_to_json, sqrrl__"
            + wrapper
            + "_from_json\n"
        )

    # A genuinely undiscovered plain-value leaf type (the hand-written
    # companion `_leaf_from_json_expr` falls back to -- e.g. a plain
    # `home: ExternalAddress` field imported from an ordinary, never-
    # `.mojo.sqrrl` module) has no `module_of` entry either, for the same reason
    # a custom container wrapper doesn't: the compiler never scanned a
    # declaration for it. Same `raw_imports` true-origin lookup as the
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
        # Same three-tier priority as the custom-wrapper case above: an
        # explicit import of `sqrrl__<TypeName>_from_json` itself,
        # anywhere project-wide, wins first (the escape valve for when
        # it doesn't live alongside `<TypeName>`); else wherever
        # `<TypeName>` itself is imported from (the common case -- some
        # file declaring a field of this type needs it regardless); else
        # the old struct-declaring-module guess.
        var from_json_name = "sqrrl__" + leaf_type + "_from_json"
        var leaf_source_module: String
        if from_json_name in raw_imports:
            leaf_source_module = raw_imports[from_json_name]
        elif leaf_type in raw_imports:
            leaf_source_module = raw_imports[leaf_type]
        else:
            leaf_source_module = custom_leaf_module[leaf_type]
        out += "from " + leaf_source_module + " import " + leaf_type + ", " + from_json_name + "\n"

    # The shared, generic `sqrrl__to_json[T]`/`sqrrl__from_json[T]`
    # dispatch table -- one `elif T == <ConcreteType>:` branch per
    # distinct container (List/Set/Optional/Dict/Variant/a custom wrapper),
    # bare relation, or discovered-plain-struct instantiation actually
    # reachable project-wide, collected by walking every real @@struct's
    # own field graph (`_collect_dispatch_types` recurses through
    # container elements and, for a plain struct, its own -- substituted --
    # fields, so a nested/generic case is found from wherever it's first
    # reachable, with no separate top-level walk needed). This is what
    # `_emit_to_json`/`_emit_from_json_with_id`/`_emit_plain_struct_from_
    # json`'s own field-level `sqrrl__to_json(value, world)`/`sqrrl__from_
    # json[FieldType](sc, world)` calls resolve against -- including a
    # generic plain struct's own bare-type-parameter field (`Box[T]`'s
    # `value: T`), which is what actually closes that gap: `T` stays bare
    # inside `Box`'s own still-generic `from_json`, resolved only once some
    # real caller instantiates it with a type this table has a branch for
    # (or the static default handles, for a plain leaf). `world: sqrrl___
    # World` is threaded through both functions and every branch -- needed
    # so a relation reachable only generically (nested inside `Variant`'s
    # own type arguments, or a custom wrapper's) can still be reconstructed
    # from a bare id via `world.<Target>`.
    var seen_container = Dict[String, Bool]()
    var container_dispatch_types = List[TypeExpr]()
    var seen_plain = Dict[String, Bool]()
    var plain_dispatch_types = List[TypeExpr]()
    for ds in discovery_structs:
        _collect_dispatch_types(
            ds.parsed.fields, plain_struct_fields, plain_struct_discovery.type_params, plain_struct_names,
            seen_container, container_dispatch_types, seen_plain, plain_dispatch_types,
        )

    var to_json_table = String(
        "def sqrrl__to_json[T: AnyType](value: T, world: sqrrl___World) -> String:\n    comptime if False:\n        pass\n"
    )
    var from_json_table = String(
        "def sqrrl__from_json[T: Movable & ImplicitlyDeletable](mut sc: sqrrl___JsonScanner, world: sqrrl___World)"
        " raises -> T:\n"
        "    comptime if False:\n        pass\n"
    )
    for t in container_dispatch_types:
        _emit_container_dispatch_branches(t, plain_struct_names, to_json_table, from_json_table)
    for t in plain_dispatch_types:
        _emit_plain_struct_dispatch_branch(
            t, plain_struct_fields, plain_struct_discovery.type_params, plain_struct_names, to_json_table, from_json_table
        )
    to_json_table += "    else:\n        return sqrrl__to_json_default(value)\n"
    from_json_table += "    else:\n        return sqrrl__from_json_default[T](sc)\n"

    # `List`/`Set`/`Dict`/`Optional` -- generated here, unconditionally,
    # rather than living as static functions in `squirrel_runtime/json.
    # mojo` -- each implements the `_to_json`/`_from_json` contract every
    # wrapper (built-in or custom) implements directly, `world` threaded
    # through every recursive `sqrrl__to_json`/`sqrrl__from_json[T]` call
    # so a relation nested inside one of these (reached either as a field
    # directly, or generically from inside `Variant`/a custom wrapper) can
    # be reconstructed. No intermediate `list_to_json`/`pairs_to_json`
    # layer underneath any more -- each wrapper renders/consumes its own
    # complete JSON text directly.
    out += "\n\n"
    out += "def sqrrl__List_to_json[T: Movable](value: List[T], world: sqrrl___World) -> String:\n"
    out += "    var out = String(\"[\")\n"
    out += "    for i in range(len(value)):\n"
    out += "        if i > 0:\n"
    out += "            out += \",\"\n"
    out += "        out += sqrrl__to_json(value[i], world)\n"
    out += "    out += \"]\"\n"
    out += "    return out^\n"
    out += "\n\n"
    out += (
        "def sqrrl__List_from_json[T: Movable & ImplicitlyDeletable](mut sc: sqrrl___JsonScanner, world:"
        " sqrrl___World) raises -> List[T]:\n"
    )
    out += "    var out = List[T]()\n"
    out += "    sc.expect_byte(UInt8(ord(\"[\")))\n"
    out += "    if not sc.try_consume_byte(UInt8(ord(\"]\"))):\n"
    out += "        while True:\n"
    out += "            out.append(sqrrl__from_json[T](sc, world))\n"
    out += "            if sc.try_consume_byte(UInt8(ord(\",\"))):\n"
    out += "                continue\n"
    out += "            sc.expect_byte(UInt8(ord(\"]\")))\n"
    out += "            break\n"
    out += "    return out^\n"
    out += "\n\n"
    out += (
        "def sqrrl__Set_to_json[T: Movable & ImplicitlyDeletable & Hashable & Equatable](value: Set[T], world:"
        " sqrrl___World) -> String:\n"
    )
    out += "    var out = String(\"[\")\n"
    out += "    var first = True\n"
    out += "    for elem in value:\n"
    out += "        if not first:\n"
    out += "            out += \",\"\n"
    out += "        first = False\n"
    out += "        out += sqrrl__to_json(elem, world)\n"
    out += "    out += \"]\"\n"
    out += "    return out^\n"
    out += "\n\n"
    out += (
        "def sqrrl__Set_from_json[T: Copyable & ImplicitlyDeletable & Hashable & Equatable](mut sc:"
        " sqrrl___JsonScanner, world: sqrrl___World) raises -> Set[T]:\n"
    )
    out += "    var out = Set[T]()\n"
    out += "    sc.expect_byte(UInt8(ord(\"[\")))\n"
    out += "    if not sc.try_consume_byte(UInt8(ord(\"]\"))):\n"
    out += "        while True:\n"
    out += "            out.add(sqrrl__from_json[T](sc, world))\n"
    out += "            if sc.try_consume_byte(UInt8(ord(\",\"))):\n"
    out += "                continue\n"
    out += "            sc.expect_byte(UInt8(ord(\"]\")))\n"
    out += "            break\n"
    out += "    return out^\n"
    out += "\n\n"
    out += "def sqrrl__Optional_to_json[T: Movable](value: Optional[T], world: sqrrl___World) -> String:\n"
    out += "    if value:\n"
    out += "        return sqrrl__to_json(value.value(), world)\n"
    out += "    return \"null\"\n"
    out += "\n\n"
    out += (
        "def sqrrl__Optional_from_json[T: Movable & ImplicitlyDeletable](mut sc: sqrrl___JsonScanner, world:"
        " sqrrl___World) raises -> Optional[T]:\n"
    )
    out += "    if sc.try_consume_literal(\"null\"):\n"
    out += "        return None\n"
    out += "    return sqrrl__from_json[T](sc, world)\n"
    out += "\n\n"
    out += (
        "def sqrrl__Dict_to_json[K: Movable & Hashable & Equatable, V: Movable](value: Dict[K, V], world:"
        " sqrrl___World) -> String:\n"
    )
    out += "    var out = String(\"[\")\n"
    out += "    var first = True\n"
    out += "    for entry in value.items():\n"
    out += "        if not first:\n"
    out += "            out += \",\"\n"
    out += "        first = False\n"
    out += (
        "        out += \"[\" + sqrrl__to_json(entry.key, world) + \",\" + sqrrl__to_json(entry.value, world)"
        " + \"]\"\n"
    )
    out += "    out += \"]\"\n"
    out += "    return out^\n"
    out += "\n\n"
    out += (
        "def sqrrl__Dict_from_json[K: Copyable & ImplicitlyDeletable & Hashable & Equatable, V: Copyable &"
        " ImplicitlyDeletable](mut sc: sqrrl___JsonScanner, world: sqrrl___World) raises -> Dict[K, V]:\n"
    )
    out += "    var out = Dict[K, V]()\n"
    out += "    sc.expect_byte(UInt8(ord(\"[\")))\n"
    out += "    if not sc.try_consume_byte(UInt8(ord(\"]\"))):\n"
    out += "        while True:\n"
    out += "            sc.expect_byte(UInt8(ord(\"[\")))\n"
    out += "            var k = sqrrl__from_json[K](sc, world)\n"
    out += "            sc.expect_byte(UInt8(ord(\",\")))\n"
    out += "            var v = sqrrl__from_json[V](sc, world)\n"
    out += "            sc.expect_byte(UInt8(ord(\"]\")))\n"
    out += "            out[k.copy()] = v.copy()\n"
    out += "            if sc.try_consume_byte(UInt8(ord(\",\"))):\n"
    out += "                continue\n"
    out += "            sc.expect_byte(UInt8(ord(\"]\")))\n"
    out += "            break\n"
    out += "    return out^\n"

    # `Variant` -- generated once per distinct arity actually used project-
    # wide (unconditionally, never gated by `_type_involves_relation` --
    # `_collect_variant_arities`'s own doc comment has the full rationale),
    # since its own function body is structurally identical for any two
    # same-arity `Variant`s, differing only in which concrete types fill
    # `T0..Tn-1`. Wire format: `[index, value]` -- `index` is the active
    # type's 0-based position within `Variant`'s own declared type-
    # argument list (never the type's own *name*, which would be fragile
    # to serialize/parse for an arbitrary generic argument), `value` is
    # the recursively-dumped active value, via the same `sqrrl__to_json[T]`
    # / `sqrrl__from_json[T]` every other wrapper recurses through.
    # `variant_arities` itself was already collected above, to decide the
    # `Variant` import line.
    for n in variant_arities:
        var type_param_decl = String("[")
        var type_param_names = String()
        for i in range(n):
            if i > 0:
                type_param_decl += ", "
                type_param_names += ", "
            type_param_decl += "T" + String(i) + ": Movable & ImplicitlyDeletable"
            type_param_names += "T" + String(i)
        type_param_decl += "]"
        var variant_type = "Variant[" + type_param_names + "]"

        out += "\n\n"
        out += (
            "def sqrrl__Variant_to_json"
            + type_param_decl
            + "(value: "
            + variant_type
            + ", world: sqrrl___World) -> String:\n"
        )
        for i in range(n):
            if i == n - 1:
                out += "    else:\n"
            else:
                out += ("    if " if i == 0 else "    elif ") + "value.isa[T" + String(i) + "]():\n"
            out += (
                "        return \"[\" + String(" + String(i) + ") + \",\" + sqrrl__to_json(value.unsafe_get[T"
                + String(i) + "](), world) + \"]\"\n"
            )
        out += "\n\n"
        out += (
            "def sqrrl__Variant_from_json"
            + type_param_decl
            + "(mut sc: sqrrl___JsonScanner, world: sqrrl___World) raises -> "
            + variant_type
            + ":\n"
        )
        out += "    sc.expect_byte(UInt8(ord(\"[\")))\n"
        out += "    var vidx = sc.parse_json_int()\n"
        out += "    sc.expect_byte(UInt8(ord(\",\")))\n"
        out += "    var vresult: " + variant_type + "\n"
        for i in range(n):
            if i == n - 1:
                out += "    else:\n"
            else:
                out += ("    if " if i == 0 else "    elif ") + "vidx == " + String(i) + ":\n"
            out += "        vresult = " + variant_type + "(sqrrl__from_json[T" + String(i) + "](sc, world))\n"
        out += "    sc.expect_byte(UInt8(ord(\"]\")))\n"
        out += "    return vresult^\n"

    out += "\n\n"
    out += to_json_table
    out += "\n\n"
    out += from_json_table

    for ds in discovery_structs:
        out += _emit_to_json(ds.parsed, plain_struct_names, plain_struct_fields, plain_struct_discovery.type_params)
        out += _emit_from_json_with_id(ds.parsed, plain_struct_fields, plain_struct_names, plain_struct_discovery.type_params)
        out += _emit_all_to_json(ds.parsed)
        out += _emit_all_from_json(ds.parsed)

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
        out += _emit_plain_struct_to_json(
            plain_name, this_fields, plain_struct_fields, plain_struct_names, this_type_params,
            plain_struct_discovery.type_params,
        )
        out += _emit_plain_struct_from_json(
            plain_name, this_fields, plain_struct_fields, plain_struct_names, this_type_params,
            plain_struct_discovery.type_params,
        )

    # A generic plain struct's own bare type parameter can hide a relation
    # that only appears once some real caller instantiates it concretely
    # (`Box[@@Employee]`) -- the ordinary generic companion just emitted
    # above, from `Box`'s own raw (unsubstituted) fields, can never see
    # that relation (`_plain_struct_from_json_call`'s own doc comment has
    # the full rationale). Every distinct such instantiation reachable
    # project-wide gets its own additional, fully-monomorphized companion
    # here, generated from its substituted (fully concrete) field list --
    # `_plain_struct_from_json_call` routes to it instead of the generic
    # one whenever this exact instantiation is used.
    var mono_seen = Dict[String, Bool]()
    var mono_targets = List[TypeExpr]()
    for ds in discovery_structs:
        _collect_mono_plain_struct_targets(
            ds.parsed.fields, plain_struct_fields, plain_struct_discovery.type_params, plain_struct_names,
            mono_seen, mono_targets,
        )

    for mt in mono_targets:
        var mono_fields = _substituted_fields_for(mt, plain_struct_fields, plain_struct_discovery.type_params)
        var mono_suffix = _mono_suffix_for_type_args(mt)
        var mono_return_type = rewritten_field_type(mt.render(), plain_struct_names)
        out += _emit_plain_struct_to_json(
            mt.name, mono_fields, plain_struct_fields, plain_struct_names, List[TypeParam](),
            plain_struct_discovery.type_params, mono_suffix, mono_return_type,
        )
        out += _emit_plain_struct_from_json(
            mt.name, mono_fields, plain_struct_fields, plain_struct_names, List[TypeParam](),
            plain_struct_discovery.type_params, mono_suffix, mono_return_type,
        )

    out += _emit_temp_keep_alives_struct(discovery_structs)
    out += _emit_world_to_json(topo_order)
    out += _emit_world_from_json(topo_order)
    out += _emit_orchestration()
    return out^
