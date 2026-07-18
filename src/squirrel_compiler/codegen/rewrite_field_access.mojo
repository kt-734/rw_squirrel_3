from squirrel_compiler.parser import Scanner, AccessStep, FieldAccess, NameRef, is_ident_char
from squirrel_compiler.codegen.helpers import (
    sqrrl_prefixed,
    encode_container_type,
    is_container_type,
    container_wrapper_of,
    container_element_of,
    storage_field_name_for_hop,
    storage_field_name_for_plain,
    param_name_for_construct_field,
)
from squirrel_compiler.codegen.script_utils import (
    is_in_import_statement,
    is_in_def_signature,
    enforce_entity_binding,
    _is_bare_identifier,
)
from squirrel_compiler.codegen.rewrite_context import RewriteContext


def handle_field_access(
    mut sc: Scanner,
    source: String,
    marker_start: Int,
    mut ctx: RewriteContext,
    mut pending_decl: Optional[String],
    mut pending_for_loop_decl: Optional[String],
    mut out: String,
) raises:
    """Handles `MarkerKind.FIELD_ACCESS` (`@@entity<steps...>`, a general
    chain of `.field`/`[index]` steps, a table-level call, or a write).

    General recursive access chain (plain-structs milestone -- see the
    plan's Revision 3): a *read*, however deeply chained, is mechanical
    field/index access -- `._inner[]` inserted after every real-struct hop
    (never after a plain-struct one -- `_render`'d inline below via each
    step's own `owner_is_plain` check), `relation_schema`/`plain_value_
    fields` used only to *validate* the chain and to carry `current_type`
    forward, never to build a `get_<field>` call. A *write*'s terminal step
    is either `.set_<field>(...)` (a real-struct owner) or a direct `field
    = value;` assignment (a plain-struct owner), or `container[index] =
    value;` when the terminal step is itself an `INDEX`. Table-level calls
    (`create`/`all`/`count`/`for_<field>`/...) and a spliced user method
    that's `@@@`-marked still need `sqrrl__world`; `fa.entity_marked_world`
    is validated against which case this actually is (a bound variable
    always needs plain `@@`, a table-level call always needs `@@@`).

    The scanner's own chain-parsing is deliberately greedy/syntactic and
    can't tell a relation/container hop apart from a native Mojo leaf
    method/index (`@@alice.name.upper()`/`@@alice.name[0]`, `name` being a
    plain `String` field) -- the "premature-leaf rollback" mechanism below
    detects the first step whose *owner* type isn't a known struct (or,
    for an `INDEX` step, isn't container-typed), rewinds `sc.pos` to the
    previous step's own `end_pos`, and emits everything up to there as an
    ordinary read -- letting `rewrite_markers`'s outer loop resume plain
    text-copying exactly where our own knowledge of the chain ran out."""
    var fa = sc.parse_field_access()

    if fa.entity not in ctx.entity_to_type:
        # @@Type.method(args) -- a table-level call, not an instance
        # access. Only reachable when `entity` isn't itself a declared
        # variable. A table-level call is always exactly one FIELD step --
        # relation hops/indexing aren't valid before it.
        if not fa.is_call:
            raise sc.err(
                "InvalidSquirrelSyntax: '"
                + fa.entity
                + "' was never constructed via @@Type{...} in this"
                " function -- can't tell which table its fields live in"
            )
        if len(fa.steps) != 1 or not fa.steps[0].is_field():
            raise sc.err(
                "InvalidSquirrelSyntax: '@@"
                + fa.entity
                + "' -- relation hops/indexing aren't valid before a"
                " table-level call"
            )
        if fa.entity not in ctx.struct_names:
            raise sc.err(
                "InvalidSquirrelSyntax: '@@"
                + fa.entity
                + "' is neither a constructed entity nor a known"
                " @@struct -- can't call '"
                + fa.steps[0].name
                + "' on it"
            )
        if not fa.entity_marked_world:
            raise sc.err(
                "InvalidSquirrelSyntax: '@@"
                + fa.entity
                + "."
                + fa.steps[0].name
                + "(...)' is a table-level call -- needs 'sqrrl__world',"
                " write '@@@"
                + fa.entity
                + "."
                + fa.steps[0].name
                + "(...)'"
            )
        if not ctx.world_declared:
            raise sc.err(
                "InvalidSquirrelSyntax: calling '@@"
                + fa.entity
                + "."
                + fa.steps[0].name
                + "(...)' needs 'sqrrl__world' -- open @@: or"
                " add '@@' to this function's own parameters first"
            )
        _handle_table_level_call(sc, fa, ctx, pending_decl, pending_for_loop_decl, out)
        return

    # Instance access -- @@entity<steps...>, a bound variable.
    if fa.entity_marked_world:
        raise sc.err(
            "InvalidSquirrelSyntax: '@@@"
            + fa.entity
            + "' -- '"
            + fa.entity
            + "' is a bound variable, not a struct type -- use plain '@@"
            + fa.entity
            + "'"
        )

    var current_type = ctx.entity_to_type[fa.entity]
    var expr = sqrrl_prefixed(fa.entity)
    var prev_end_pos = marker_start + (3 if fa.entity_marked_world else 2) + fa.entity.byte_length()

    _walk_access_chain(
        sc,
        source,
        marker_start,
        ctx,
        fa.steps,
        fa.is_call,
        fa.write_value,
        current_type,
        expr,
        prev_end_pos,
        fa.entity,
        pending_decl,
        pending_for_loop_decl,
        out,
    )


def _walk_access_chain(
    mut sc: Scanner,
    source: String,
    marker_start: Int,
    mut ctx: RewriteContext,
    steps: List[AccessStep],
    is_call: Bool,
    write_value: Optional[String],
    current_type_in: String,
    expr_in: String,
    prev_end_pos_in: Int,
    entity_label: String,
    mut pending_decl: Optional[String],
    mut pending_for_loop_decl: Optional[String],
    mut out: String,
) raises:
    """The general per-step chain walk shared by `handle_field_access`
    (a chain rooted at a bound `@@entity`) and `handle_func_call_marker`
    (mandatory-marking milestone -- a chain rooted at the *return value*
    of an `@@`/`@@@`-marked function call, `@@get_dept(@@alice).name`,
    which has no `FieldAccess.entity`/`.entity_marked_world` of its own
    to carry `is_call`/`write_value` on, hence those two arrive as plain
    parameters here instead of a whole `fa`).

    `current_type_in`/`expr_in`/`prev_end_pos_in` seed the walk exactly
    the way `handle_field_access`'s own pre-loop setup already did
    inline before this was extracted -- `current_type` is the walked
    type so far, `expr` the Mojo text already emitted for it, `prev_end_
    pos` the byte offset `sc.pos` rolls back to on a "premature-leaf"
    exit (see the module doc comment). `entity_label` is purely for error
    messages (`enforce_entity_binding`'s own `call_text`) -- `fa.entity`
    in the bound-variable case, the function's own call text in the
    func-call-chain case."""
    from squirrel_compiler.codegen.rewrite import rewrite_markers

    var current_type = current_type_in
    var expr = expr_in
    var prev_end_pos = prev_end_pos_in

    for i in range(len(steps)):
        ref step = steps[i]
        var is_last = i == len(steps) - 1

        if is_container_type(current_type) and container_wrapper_of(current_type) in ctx.plain_struct_names:
            # A generic plain-struct instantiation (`Tagged[String]`) is
            # bracket-shaped too, but it isn't a real DSL container -- it
            # never varies its own field *shape* per instantiation, so
            # every downstream lookup (`plain_struct_names`/`plain_value_
            # fields`/`relation_schema`) is keyed by the bare wrapper name
            # alone, exactly like a non-generic plain struct. Collapse to
            # that bare name and fall through to the ordinary FIELD/INDEX
            # dispatch below, rather than the real-container branch.
            current_type = container_wrapper_of(current_type)

        if is_container_type(current_type):
            if step.is_index():
                var rewritten_index = rewrite_markers(step.name, ctx)
                expr += "[" + rewritten_index + "]"
                var elem_type = container_element_of(current_type)
                if is_last:
                    if write_value:
                        var rewritten_value = rewrite_markers(write_value.value(), ctx)
                        out += expr + " = " + rewritten_value + ";"
                        pending_decl = None
                        pending_for_loop_decl = None
                        return
                    if pending_decl:
                        ctx.entity_to_type[pending_decl.value()] = elem_type
                    # `for @@x in @@entity.@@field[i]:` -- same registration
                    # a terminal *FIELD* step already does for `pending_for_
                    # loop_decl` (`for @@x in @@entity.@@field:`), just off
                    # the index-unwrapped `elem_type` instead of the raw
                    # field type: an *further* level down, since the loop
                    # iterates whatever `elem_type` itself is (only
                    # meaningful when that's still container-shaped --
                    # `@@entity.@@field[i]` yielding a bare relation/leaf
                    # would never appear as a for-loop's own iterable in
                    # the first place). Confirmed missing via a real
                    # compile: `@@field: List[Dict[String, @@Employee]]`,
                    # `for @@e in @@entity.@@field[0]:` left `@@e`
                    # completely unregistered, surfacing as a misleading
                    # "was never constructed" error one statement later,
                    # not a "Dict iteration only yields keys" one -- the
                    # actual, correct outcome once this registers at all.
                    if pending_for_loop_decl and is_container_type(elem_type):
                        ctx.entity_to_type[pending_for_loop_decl.value()] = container_element_of(elem_type)
                    out += expr
                    pending_decl = None
                    pending_for_loop_decl = None
                    return
                current_type = elem_type
                prev_end_pos = step.end_pos
                continue
            # A FIELD step directly on a container-bound value -- a call on
            # the container itself (`.append(...)`, needs no sqrrl__world,
            # no `._inner[]`), or an invalid non-indexed, non-iterated
            # field access.
            if is_last and is_call and step.name != "":
                out += expr + "." + step.name
                pending_decl = None
                pending_for_loop_decl = None
                return
            var wrapper = container_wrapper_of(current_type)
            var how_to_access = (
                "index into it first ('...[i]." + step.name + "')"
            ) if wrapper == "List" else (
                "iterate over it first ('for @@x in ...: ... @@x." + step.name + "')"
            )
            raise sc.err(
                "InvalidSquirrelSyntax: '"
                + current_type
                + "' is a "
                + wrapper
                + " of '@@"
                + container_element_of(current_type)
                + "' -- "
                + how_to_access
            )

        if step.is_index():
            # `current_type` isn't a container -- premature-leaf rollback:
            # this might be legitimate native indexing on a leaf value
            # (`@@alice.name[0]`, String indexing) that our own knowledge
            # of the chain simply doesn't extend to.
            out += expr
            sc.pos = prev_end_pos
            pending_decl = None
            pending_for_loop_decl = None
            return

        # FIELD step, current_type not a container.
        var owner_is_real = current_type in ctx.struct_names
        var owner_is_plain = current_type in ctx.plain_struct_names
        if not owner_is_real and not owner_is_plain:
            # Premature-leaf rollback -- `current_type` isn't a known
            # struct at all (a native Mojo leaf type reached through an
            # earlier plain field, e.g. `String` after `.name`).
            out += expr
            sc.pos = prev_end_pos
            pending_decl = None
            pending_for_loop_decl = None
            return

        if is_last and is_call:
            _handle_instance_call(sc, step, current_type, owner_is_real, expr, ctx, pending_decl, pending_for_loop_decl, out)
            return

        var is_relation = current_type in ctx.relation_schema and step.name in ctx.relation_schema[current_type]
        var is_plain_value = current_type in ctx.plain_value_fields and step.name in ctx.plain_value_fields[current_type]

        if is_relation and not step.marked:
            raise sc.err(
                "InvalidSquirrelSyntax: '"
                + current_type
                + "."
                + step.name
                + "' is a relation field -- read it as '.@@"
                + step.name
                + "', not '."
                + step.name
                + "'"
            )
        if step.marked and is_plain_value:
            raise sc.err(
                "InvalidSquirrelSyntax: '"
                + current_type
                + "."
                + step.name
                + "' is a plain field -- '@@"
                + step.name
                + "' marks a relation; use '."
                + step.name
                + "' (no '@@') for a plain field"
            )
        if step.marked and not is_relation and not is_plain_value:
            raise sc.err(
                "InvalidSquirrelSyntax: '"
                + current_type
                + "' has no relation field '"
                + step.name
                + "' -- '@@"
                + step.name
                + "' marks a relation; use '."
                + step.name
                + "' (no '@@') for a plain field"
            )
        if not is_relation and not is_plain_value and not is_last:
            raise sc.err(
                "InvalidSquirrelSyntax: '"
                + current_type
                + "' has no field '"
                + step.name
                + "' to continue the access chain through"
            )

        var deref = "" if owner_is_plain else "._inner[]"
        var storage_name = step.name if owner_is_plain else (
            storage_field_name_for_hop(step.name) if step.marked else storage_field_name_for_plain(step.name)
        )

        if is_last:
            if write_value:
                var rewritten_value = rewrite_markers(write_value.value(), ctx)
                # A direct `.field = value` write, same as `set_<field>`'s
                # own generated signature (`needs_move_assignment`) and
                # `build_create_call`'s own construction args -- a `multi`
                # field's `Set[T]`, any container-shaped field (`List`/
                # `Set`/`Optional`/`Dict`, relation or plain leaf), or a
                # plain-struct value isn't guaranteed `ImplicitlyCopyable`,
                # so the call site has to move (`^`) the already-owned RHS
                # in -- but only when it's a *named* value (`_is_bare_
                # identifier`); a fresh rvalue (`Set(...)`/`[@@a, @@b]`) is
                # already a temporary Mojo moves from automatically, and
                # `^`-ing one is rejected outright, not a harmless no-op
                # (`build_create_call`'s own doc comment has the full
                # rationale, confirmed via a real compile there already).
                var target_type_text = (
                    ctx.relation_schema[current_type][step.name] if is_relation
                    else (ctx.plain_value_fields[current_type][step.name] if is_plain_value else "")
                )
                var is_multi_field = current_type in ctx.multi_fields and _contains(
                    ctx.multi_fields[current_type], step.name
                )
                var needs_move = (
                    is_multi_field
                    or is_container_type(target_type_text)
                    or target_type_text in ctx.plain_struct_names
                )
                var value_arg = (
                    rewritten_value + "^" if (needs_move and _is_bare_identifier(rewritten_value)) else rewritten_value
                )
                if owner_is_plain:
                    out += expr + deref + "." + storage_name + " = " + value_arg + ";"
                else:
                    out += (
                        expr
                        + deref
                        + ".set_"
                        + param_name_for_construct_field(step.name, is_relation)
                        + "("
                        + value_arg
                        + ");"
                    )
                pending_decl = None
                pending_for_loop_decl = None
                return
            expr += deref + "." + storage_name
            if is_relation:
                var registered_type = ctx.relation_schema[current_type][step.name]
                enforce_entity_binding(
                    source,
                    marker_start,
                    pending_decl,
                    ctx.entity_to_type,
                    registered_type,
                    entity_label + "." + step.name,
                )
                # `for @@x in @@entity.@@container_field:` -- register the
                # loop variable's own element type the same way a table-
                # level call's own List-returning result already does
                # (`_handle_instance_call`) -- an ordinary field read
                # through a container-shaped relation reaches this same
                # terminal branch and was missing the equivalent
                # registration entirely (confirmed missing via a real
                # transform_source check, not assumed).
                if pending_for_loop_decl and is_container_type(registered_type):
                    ctx.entity_to_type[pending_for_loop_decl.value()] = container_element_of(registered_type)
            elif is_plain_value:
                var registered_type = ctx.plain_value_fields[current_type][step.name]
                if pending_for_loop_decl and is_container_type(registered_type):
                    ctx.entity_to_type[pending_for_loop_decl.value()] = container_element_of(registered_type)
            out += expr
            pending_decl = None
            pending_for_loop_decl = None
            return

        expr += deref + "." + storage_name
        current_type = (
            ctx.relation_schema[current_type][step.name] if is_relation else ctx.plain_value_fields[current_type][step.name]
        )
        prev_end_pos = step.end_pos

    # Unreachable -- the loop above always returns from its last iteration
    # (only ever called with a non-empty `steps`, guaranteed by both call
    # sites -- `Scanner.parse_field_access`'s own non-empty check, and
    # `handle_func_call_marker`'s own "chain follows" lookahead).


def handle_func_call_marker(
    mut sc: Scanner,
    source: String,
    marker_start: Int,
    mut ctx: RewriteContext,
    is_world: Bool,
    mut pending_decl: Optional[String],
    mut pending_for_loop_decl: Optional[String],
    mut out: String,
) raises:
    """Handles `MarkerKind.WORLD_FUNC` (`@@@name(...)`, needs `sqrrl__
    world`) and `MarkerKind.ENTITY_FUNC` (`@@name(...)`, doesn't -- both a
    definition and a call site, same as `WORLD_FUNC` always covered).

    Mandatory-marking milestone: any function whose return type involves
    an `@@`-marked value must mark its own name (`@@` if it doesn't also
    need `sqrrl__world`, `@@@` if it does -- never both; `build_function_
    returns` enforces this project-wide, at signature-scan time, so by the
    time rewriting reaches a call site here `ctx.function_returns` is
    already the full, validated truth). This is what makes a *direct*
    access-chain off a call's own return value tractable at all --
    `@@get_dept(@@alice).name`, no intermediate variable, no `for` loop --
    since the call itself is now a real, unambiguous marker position the
    scanner already stops at (`find_next_marker`'s own `@@ident(`
    dispatch), unlike a *bare* (unmarked) function name, which it never
    could.

    A definition's own signature is rewritten exactly as before (`WORLD_
    FUNC`'s pre-existing `self`/`mut sqrrl__world` injection, verbatim --
    an `ENTITY_FUNC` definition needs none of that, just its own name
    rewritten). A call site now consumes its *entire* argument list
    synchronously (`scan_call_args_to_close`, recursively re-run through
    `rewrite_markers` -- any `@@`-marked argument still rewrites exactly
    as it always did) instead of letting the outer loop step through it
    marker-by-marker, specifically so `sc.pos` lands right past the
    matching `)` and a trailing `.field`/`[index]` chain (if any) can be
    detected and handed to `_walk_access_chain`, seeded with the
    function's own registered return type."""
    from squirrel_compiler.codegen.rewrite import rewrite_markers

    var func_name = sc.parse_world_func() if is_world else sc.parse_entity_func()

    if is_in_def_signature(source, marker_start):
        if is_world:
            sc.skip_whitespace()
            var starts_with_self = sc.starts_with("self") and not is_ident_char(sc.peek_at(4))
            var has_more_args = sc.peek() != UInt8(ord(")"))
            if starts_with_self:
                sc.pos += 4  # consume "self"
                out += sqrrl_prefixed(func_name) + "(self, mut sqrrl__world: sqrrl__World"
                sc.skip_trivia()
                if sc.try_consume(","):
                    out += ", "
                ctx.world_declared = True
                pending_decl = None
                pending_for_loop_decl = None
                return
            out += sqrrl_prefixed(func_name) + "(mut sqrrl__world: sqrrl__World"
            ctx.world_declared = True
            if has_more_args:
                out += ", "
        else:
            out += sqrrl_prefixed(func_name) + "("
        pending_decl = None
        pending_for_loop_decl = None
        return

    # Call site.
    if is_world and not ctx.world_declared:
        raise sc.err(
            "InvalidSquirrelSyntax: calling '@@@"
            + func_name
            + "(...)' needs 'sqrrl__world' -- open @@:"
            " or mark this function's own name with '@@@' too"
        )
    var arg_text = sc.scan_call_args_to_close()
    var rewritten_args = rewrite_markers(arg_text, ctx)
    var call_end_pos = sc.pos
    var registered: Optional[String] = (
        Optional[String](ctx.function_returns[func_name]) if func_name in ctx.function_returns else None
    )
    if not is_world and not registered:
        raise sc.err(
            "InvalidSquirrelSyntax: '@@"
            + func_name
            + "(...)' -- '"
            + func_name
            + "' doesn't return an '@@'-marked value (or isn't defined) --"
            " '@@' only marks a function that returns one; write '"
            + func_name
            + "(...)' (no '@@') otherwise"
        )
    var call_text: String
    if is_world:
        call_text = (
            sqrrl_prefixed(func_name) + "(sqrrl__world"
            + (", " + rewritten_args if arg_text.strip().byte_length() > 0 else "")
            + ")"
        )
    else:
        call_text = sqrrl_prefixed(func_name) + "(" + rewritten_args + ")"

    if sc.peek_trailing_chain_follows():
        if not registered:
            raise sc.err(
                "InvalidSquirrelSyntax: can't continue an access chain off"
                " '@@" + ("@" if is_world else "") + func_name
                + "(...)' -- '" + func_name + "' doesn't return an"
                " '@@'-marked value"
            )
        var steps = sc.scan_access_steps()
        var tail = sc.scan_call_or_write_tail()
        _walk_access_chain(
            sc,
            source,
            marker_start,
            ctx,
            steps,
            tail.is_call,
            tail.write_value,
            registered.value(),
            call_text,
            call_end_pos,
            func_name + "(...)",
            pending_decl,
            pending_for_loop_decl,
            out,
        )
        return

    out += call_text
    if registered:
        if pending_decl:
            ctx.entity_to_type[pending_decl.value()] = registered.value()
        if pending_for_loop_decl and is_container_type(registered.value()):
            ctx.entity_to_type[pending_for_loop_decl.value()] = container_element_of(registered.value())
    pending_decl = None
    pending_for_loop_decl = None


def _handle_instance_call(
    mut sc: Scanner,
    step: AccessStep,
    current_type: String,
    owner_is_real: Bool,
    expr: String,
    mut ctx: RewriteContext,
    mut pending_decl: Optional[String],
    mut pending_for_loop_decl: Optional[String],
    mut out: String,
) raises:
    """The terminal step of a chain is a call (`is_call`, checked by
    `_walk_access_chain` before calling here) whose owner (`current_type`)
    is a known struct, real or plain. A plain-struct owner's call is
    always a direct passthrough -- real Mojo, calling a real, hand-written
    method the DSL doesn't track at all (out of scope for `@@`-marked
    dispatch, see the plan's §6). A real-struct owner's call is `add_to_
    <field>`/`remove_from_<field>` (a `multi` field's own instance
    mutation, M2) or a spliced user method (M3), re-keyed to the walked
    `current_type` instead of always assuming the chain's own root type --
    the general access-chain redesign's whole point."""
    if not owner_is_real:
        if step.marked or step.marked_world:
            raise sc.err(
                "InvalidSquirrelSyntax: '"
                + step.name
                + "' isn't a relation field -- a method call on a plain"
                " struct value is never '@@'-marked at its own call site"
            )
        if not sc.try_consume("("):
            raise sc.err("InvalidSquirrelSyntax: expected '(' after '" + step.name + "'")
        out += expr + "." + step.name + "("
        pending_decl = None
        pending_for_loop_decl = None
        return

    var multi_call_field: Optional[String] = None
    var multi_call_prefix = String()
    if step.name.startswith("add_to_"):
        multi_call_prefix = "add_to_"
        multi_call_field = String(step.name[byte=7 : step.name.byte_length()])
    elif step.name.startswith("remove_from_"):
        multi_call_prefix = "remove_from_"
        multi_call_field = String(step.name[byte=12 : step.name.byte_length()])
    if (
        multi_call_field
        and current_type in ctx.multi_fields
        and _contains(ctx.multi_fields[current_type], multi_call_field.value())
    ):
        # A `multi` field isn't always a relation field (`multi skills:
        # String` -- a plain, `Set[String]`-backed one) -- `param_name`'s
        # own rule (mirrored here via `param_name_for_construct_field`)
        # decides the call-site marking/generated-name prefix, same as
        # every other field-derived method name, not an unconditional
        # "multi implies relation" assumption.
        var is_multi_relation = (
            current_type in ctx.relation_schema and multi_call_field.value() in ctx.relation_schema[current_type]
        )
        if is_multi_relation and not step.marked:
            raise sc.err(
                "InvalidSquirrelSyntax: '" + multi_call_field.value()
                + "' on '" + current_type + "' is a relation field --"
                " write '" + multi_call_prefix + "@@"
                + multi_call_field.value() + "', not '" + step.name + "'"
            )
        if step.marked and not is_multi_relation:
            raise sc.err(
                "InvalidSquirrelSyntax: '" + multi_call_field.value()
                + "' on '" + current_type + "' is a plain field --"
                " write '" + multi_call_prefix
                + multi_call_field.value() + "', not '" + step.name + "'"
            )
        if not sc.try_consume("("):
            raise sc.err("InvalidSquirrelSyntax: expected '(' after '" + step.name + "'")
        out += (
            expr + "._inner[]." + multi_call_prefix
            + param_name_for_construct_field(multi_call_field.value(), is_multi_relation) + "("
        )
        pending_decl = None
        pending_for_loop_decl = None
        return

    # A spliced user method (M3) -- lives directly on the wrapper, not
    # Inner, so `expr` (already wrapper-typed after walking any prior
    # steps) needs no `._inner[]`. `step.marked` (plain `.@@name`) never
    # applies to a method call -- a method is never a relation field.
    # `step.marked_world` (`.@@@name`) is call-site symmetry with the
    # method's own `@@@`-marked declaration, validated against `ctx.
    # world_methods` (mismatch in either direction rejected, same shape as
    # `entity_marked_world`'s own validation).
    if step.marked:
        raise sc.err(
            "InvalidSquirrelSyntax: '"
            + step.name
            + "' isn't a relation field -- '@@"
            + step.name
            + "' marks a relation; a method call is never '@@'-marked"
            " at its own call site"
        )
    var is_world_method = current_type in ctx.world_methods and _contains(ctx.world_methods[current_type], step.name)
    if is_world_method and not step.marked_world:
        raise sc.err(
            "InvalidSquirrelSyntax: '"
            + step.name
            + "' on '"
            + current_type
            + "' needs 'sqrrl__world' -- write '@@@"
            + step.name
            + "(...)', not '"
            + step.name
            + "(...)'"
        )
    if step.marked_world and not is_world_method:
        raise sc.err(
            "InvalidSquirrelSyntax: '"
            + step.name
            + "' on '"
            + current_type
            + "' doesn't need 'sqrrl__world' -- write '"
            + step.name
            + "(...)', not '@@@"
            + step.name
            + "(...)'"
        )
    if not sc.try_consume("("):
        raise sc.err("InvalidSquirrelSyntax: expected '(' after '" + step.name + "'")
    if is_world_method:
        if not ctx.world_declared:
            raise sc.err(
                "InvalidSquirrelSyntax: calling '"
                + step.name
                + "(...)' needs 'sqrrl__world' -- open @@: or add '@@'"
                " to this function's own parameters first"
            )
        out += expr + "." + step.name + "(sqrrl__world"
        sc.skip_trivia()
        if sc.peek() != UInt8(ord(")")):
            out += ", "
    else:
        out += expr + "." + step.name + "("
    pending_decl = None
    pending_for_loop_decl = None


def _handle_table_level_call(
    mut sc: Scanner,
    fa: FieldAccess,
    mut ctx: RewriteContext,
    mut pending_decl: Optional[String],
    mut pending_for_loop_decl: Optional[String],
    mut out: String,
) raises:
    """`@@@Type.method(...)` -- unchanged dispatch from before the general
    access-chain redesign, re-keyed to `fa.steps[0].name`/`.marked`
    (always exactly one FIELD step for a table-level call, `handle_field_
    access` already validated this before calling here)."""
    var field = fa.steps[0].name
    var field_marked = fa.steps[0].marked
    var is_entity_returning = False
    var is_list_returning = False
    var registered_type = fa.entity
    var method_name = field
    if field == "create":
        is_entity_returning = True
    elif field == "all":
        is_list_returning = True
        registered_type = encode_container_type("Set", fa.entity)
    elif field == "count":
        pass  # bare Int -- nothing to track
    elif field.startswith("for_"):
        var target_field = String(field[byte=4 : field.byte_length()])
        var range_match = _match_ordered_range_call(
            target_field, ctx.ordered_fields[fa.entity].copy() if fa.entity in ctx.ordered_fields else List[String]()
        )
        if range_match:
            var range_field = range_match.value().field_name
            var is_range_relation = fa.entity in ctx.relation_schema and range_field in ctx.relation_schema[fa.entity]
            if is_range_relation != field_marked:
                raise sc.err(
                    "InvalidSquirrelSyntax: '" + range_field + "' on '"
                    + fa.entity + "' is a "
                    + ("relation" if is_range_relation else "plain")
                    + " field -- write 'for_"
                    + ("@@" if is_range_relation else "")
                    + range_field + "_" + range_match.value().comparator
                    + "', not 'for_" + target_field + "'"
                )
            method_name = (
                "for_" + param_name_for_construct_field(range_field, is_range_relation)
                + "_" + range_match.value().comparator
            )
            is_list_returning = True
            registered_type = encode_container_type("List", fa.entity)
        else:
            var is_unique = fa.entity in ctx.unique_fields and _contains(ctx.unique_fields[fa.entity], target_field)
            var is_indexed = fa.entity in ctx.indexed_fields and _contains(ctx.indexed_fields[fa.entity], target_field)
            var is_multi = fa.entity in ctx.multi_fields and _contains(ctx.multi_fields[fa.entity], target_field)
            var is_ordered = fa.entity in ctx.ordered_fields and _contains(ctx.ordered_fields[fa.entity], target_field)
            # A `multi` field isn't always a relation field (`multi
            # skills: String`) -- gated on `relation_schema` membership
            # alone, same as every other field-derived-name marking
            # decision, not an unconditional "multi implies relation"
            # assumption.
            var is_relation_target = fa.entity in ctx.relation_schema and target_field in ctx.relation_schema[fa.entity]
            if is_relation_target and not field_marked:
                raise sc.err(
                    "InvalidSquirrelSyntax: '" + target_field + "' on '"
                    + fa.entity + "' is a relation field -- write 'for_@@"
                    + target_field + "', not 'for_" + target_field + "'"
                )
            if field_marked and not is_relation_target:
                raise sc.err(
                    "InvalidSquirrelSyntax: '" + target_field + "' on '"
                    + fa.entity + "' is a plain field -- write 'for_"
                    + target_field + "', not 'for_@@" + target_field + "'"
                )
            method_name = "for_" + param_name_for_construct_field(target_field, is_relation_target)
            if is_unique:
                is_entity_returning = True
            elif is_indexed or is_multi or is_ordered:
                is_list_returning = True
                registered_type = encode_container_type("Set", fa.entity)
            else:
                raise sc.err(
                    "InvalidSquirrelSyntax: field '"
                    + target_field
                    + "' on '"
                    + fa.entity
                    + "' has no backward index -- tag it 'indexed' or"
                    " 'unique' to get 'for_"
                    + target_field
                    + "'"
                )
    elif field.startswith("count_by_"):
        var target_field = String(field[byte=9 : field.byte_length()])
        var m = _match_groupable_field(sc, fa, ctx, "count_by_", target_field)
        method_name = m.method_name
        if m.is_relation_or_multi:
            is_list_returning = True
            registered_type = encode_container_type("Dict", m.relation_target)
    elif field.startswith("count_"):
        var target_field = String(field[byte=6 : field.byte_length()])
        var m = _match_groupable_field(sc, fa, ctx, "count_", target_field)
        method_name = m.method_name
    elif field.startswith("group_by_"):
        var target_field = String(field[byte=9 : field.byte_length()])
        var m = _match_groupable_field(sc, fa, ctx, "group_by_", target_field)
        method_name = m.method_name
        if m.is_relation_or_multi:
            is_list_returning = True
            registered_type = encode_container_type("Dict", m.relation_target)
    elif field.startswith("distinct_"):
        var target_field = String(field[byte=9 : field.byte_length()])
        var m = _match_groupable_field(sc, fa, ctx, "distinct_", target_field)
        method_name = m.method_name
        if m.is_relation_or_multi:
            is_list_returning = True
            registered_type = encode_container_type("Set", m.relation_target)
    elif (
        field.startswith("sum_")
        or field.startswith("avg_")
        or field.startswith("min_")
        or field.startswith("max_")
        or field.startswith("median_")
    ):
        var kind: String
        var rest: String
        if field.startswith("median_"):
            kind = "median"
            rest = String(field[byte=7 : field.byte_length()])
        else:
            kind = String(field[byte=0 : 3])
            rest = String(field[byte=4 : field.byte_length()])
        var am = _match_aggregate_call(sc, fa, ctx, kind, rest)
        method_name = am.method_name
        if am.has_grouping and not am.is_for and am.x_is_relation_or_multi:
            is_list_returning = True
            registered_type = encode_container_type("Dict", am.x_relation_target)
    else:
        raise sc.err(
            "InvalidSquirrelSyntax: '@@"
            + fa.entity
            + "."
            + field
            + "(...)' isn't supported yet -- only create/all/count/"
            "for_<field>/count_<field>/group_by_<field>/count_by_<field>/"
            "distinct_<field> are, so far"
        )
    if is_entity_returning or is_list_returning:
        enforce_entity_binding(
            sc.source,
            sc.pos,
            pending_decl,
            ctx.entity_to_type,
            registered_type,
            fa.entity + "." + field + "(...)",
        )
    if is_list_returning and pending_for_loop_decl:
        ctx.entity_to_type[pending_for_loop_decl.value()] = container_element_of(registered_type)
    out += "sqrrl__world." + fa.entity + "." + method_name
    pending_decl = None
    pending_for_loop_decl = None


def handle_name_ref(
    mut sc: Scanner,
    source: String,
    marker_start: Int,
    mut ctx: RewriteContext,
    mut pending_decl: Optional[String],
    mut pending_for_loop_decl: Optional[String],
    mut out: String,
) raises:
    """Handles the `MarkerKind.NAME_REF` fallback (a bare `@@name`).

    Slimmed from rw_squirrel_2's own `handle_name_ref`: drops the
    implicit-unmarked-prefix reinterpretation (plain structs, M2+) --
    otherwise unchanged, since a bare name reference was never routed
    through the storage layer at all."""
    var nr = sc.parse_name_ref()
    out += sqrrl_prefixed(nr.name)
    var save = sc.pos
    sc.skip_trivia()
    var is_decl = sc.at_assignment()
    if not is_decl and not is_in_import_statement(source, marker_start) and nr.name not in ctx.entity_to_type:
        raise sc.err(
            "InvalidSquirrelSyntax: '@@"
            + nr.name
            + "' is referenced but was never constructed or bound"
            " -- every '@@'-marked entity must come from a"
            " '@@Type{...}' construct, an entity-returning call, or"
            " an entity parameter before it can be used"
        )
    if is_decl:
        sc.pos += 1  # consume '='
        sc.skip_trivia()
        if not sc.starts_with("@@"):
            # Mandatory-marking milestone: a function that returns an
            # `@@`-marked value is now *always* itself marked (`@@` or
            # `@@@`, `handle_func_call_marker`'s own doc comment has the
            # full rationale) -- so `var @@x = some_func(...)` unmarked
            # here is never that case any more, just the one remaining
            # unmarked shape that's still valid: a container constructor
            # (`List[@@Type]()`). A marked call (`var @@x = @@get_dept(
            # ...)`) instead falls straight through to the `pending_decl`
            # this function already sets below -- consumed by `handle_
            # func_call_marker` once it reaches that marker next, exactly
            # like every other "@@"-prefixed initializer shape.
            var lookahead = sc.pos
            var matched = False
            var wrapper = sc.scan_ident()
            sc.skip_trivia()
            if wrapper.byte_length() > 0 and sc.try_consume("["):
                sc.skip_trivia()
                if sc.try_consume("@@"):
                    var type_name = sc.scan_ident()
                    if type_name.byte_length() > 0:
                        matched = True
                        ctx.entity_to_type[nr.name] = encode_container_type(wrapper, type_name)
            sc.pos = lookahead
            if not matched:
                raise sc.err(
                    "InvalidSquirrelSyntax: '@@"
                    + nr.name
                    + "' must be initialized from a '@@'-marked"
                    " value (e.g. '@@Type{...}', another"
                    " '@@'-marked entity, an '@@'/'@@@'-marked"
                    " function call, or a container constructor like"
                    " 'List[@@Type]()') -- an unmarked right-hand"
                    " side would silently skip the construct"
                    " rewrite"
                )
    sc.pos = save
    if not is_decl and pending_for_loop_decl and nr.name in ctx.entity_to_type and is_container_type(ctx.entity_to_type[nr.name]):
        ctx.entity_to_type[pending_for_loop_decl.value()] = container_element_of(ctx.entity_to_type[nr.name])
    pending_decl = String(nr.name) if is_decl else None
    pending_for_loop_decl = None


def _contains(items: List[String], value: String) -> Bool:
    for item in items:
        if item == value:
            return True
    return False


@fieldwise_init
struct _OrderedRangeMatch(Copyable, Movable):
    var field_name: String
    var comparator: String


def _match_ordered_range_call(target_field: String, ordered_names: List[String]) -> Optional[_OrderedRangeMatch]:
    """If `target_field` is `<name>_<comparator>` for some `name` in
    `ordered_names` and a known range-query comparator, returns which --
    else None. Checked against the actual declared field list rather than
    blind suffix-length slicing, since a field's own name can itself
    contain underscores (`for_years_employed_greater_than` -- is the field
    `years_employed` or something else? only the declared name list can
    say)."""
    for name in ordered_names:
        for comparator in ["greater_than", "less_than", "at_least", "at_most", "between"]:
            if target_field == name + "_" + comparator:
                return _OrderedRangeMatch(field_name=name, comparator=comparator)
    return None


@fieldwise_init
struct _GroupableFieldMatch(Copyable, Movable):
    """What `_match_groupable_field` found -- `method_name` already carries
    the field's own `@@`-marking (point 3, no exceptions); `relation_target`
    is only meaningful when `is_relation_or_multi`, and is the struct name a
    `group_by_<field>`/`count_by_<field>`/`distinct_<field>` result's own
    Dict/Set *key* type should track (a multi field's target, same as its
    own `for_<field>`, not `fa.entity` itself -- unlike `for_<field>`, whose
    result holds entities of `fa.entity`'s own type)."""

    var method_name: String
    var is_relation_or_multi: Bool
    var relation_target: String


@fieldwise_init
struct _FieldTarget(Copyable, Movable):
    """What `_resolve_groupable_target` found -- `relation_target` is only
    meaningful when `is_relation_or_multi`."""

    var is_unique: Bool
    var is_relation_or_multi: Bool
    var relation_target: String


def _resolve_groupable_target(
    mut sc: Scanner, fa: FieldAccess, ctx: RewriteContext, prefix_for_error: String, target_field: String
) raises -> _FieldTarget:
    """Validates `target_field` is a real indexed-family field on
    `fa.entity` (any modifier but NONE) and that the table-level call's own
    single step's `marked` flag matches whether it's actually a
    relation/multi field -- shared by `count_<field>`/`group_by_<field>`/
    `count_by_<field>`/`distinct_<field>` (via `_match_groupable_field`)
    and the `_by_<x>`/`_for_<x>` grouping side of `sum_`/`avg_`/`min_`/
    `max_`/`median_` (via `_match_aggregate_call`) -- both M4."""
    var is_unique = fa.entity in ctx.unique_fields and _contains(ctx.unique_fields[fa.entity], target_field)
    var is_indexed = fa.entity in ctx.indexed_fields and _contains(ctx.indexed_fields[fa.entity], target_field)
    var is_multi = fa.entity in ctx.multi_fields and _contains(ctx.multi_fields[fa.entity], target_field)
    var is_ordered = fa.entity in ctx.ordered_fields and _contains(ctx.ordered_fields[fa.entity], target_field)
    if not (is_unique or is_indexed or is_multi or is_ordered):
        raise sc.err(
            "InvalidSquirrelSyntax: field '"
            + target_field
            + "' on '"
            + fa.entity
            + "' has no backward index -- tag it 'indexed', 'unique',"
            " 'multi', or 'ordered' to get '"
            + prefix_for_error
            + target_field
            + "'"
        )
    # A `multi` field isn't always a relation field (`multi skills:
    # String`) -- gated on `relation_schema` membership alone, same as
    # every other field-derived-name marking decision, not an
    # unconditional "multi implies relation" assumption.
    var is_relation_target = fa.entity in ctx.relation_schema and target_field in ctx.relation_schema[fa.entity]
    if is_relation_target and not fa.steps[0].marked:
        raise sc.err(
            "InvalidSquirrelSyntax: '"
            + target_field
            + "' on '"
            + fa.entity
            + "' is a relation field -- write '"
            + prefix_for_error
            + "@@"
            + target_field
            + "', not '"
            + prefix_for_error
            + target_field
            + "'"
        )
    if fa.steps[0].marked and not is_relation_target:
        raise sc.err(
            "InvalidSquirrelSyntax: '"
            + target_field
            + "' on '"
            + fa.entity
            + "' is a plain field -- write '"
            + prefix_for_error
            + target_field
            + "', not '"
            + prefix_for_error
            + "@@"
            + target_field
            + "'"
        )
    var relation_target = ctx.relation_schema[fa.entity][target_field] if is_relation_target else String()
    return _FieldTarget(is_unique=is_unique, is_relation_or_multi=is_relation_target, relation_target=relation_target)


def _match_groupable_field(
    mut sc: Scanner, fa: FieldAccess, ctx: RewriteContext, prefix: String, target_field: String
) raises -> _GroupableFieldMatch:
    """Shared validation for `count_<field>`/`group_by_<field>`/
    `count_by_<field>`/`distinct_<field>` (M4) -- unlike `for_<field>`'s own
    range-query family, these have fixed prefixes with no suffix ambiguity
    to resolve, so this is a straight lookup against the entity's own
    declared-field maps, not a `_match_ordered_range_call`-style search."""
    var t = _resolve_groupable_target(sc, fa, ctx, prefix, target_field)
    if prefix == "count_by_" and t.is_unique:
        raise sc.err(
            "InvalidSquirrelSyntax: '"
            + target_field
            + "' on '"
            + fa.entity
            + "' is 'unique' -- every group is exactly 1 by construction,"
            " so there's no 'count_by_"
            + target_field
            + "' (use 'group_by_"
            + target_field
            + "' directly)"
        )
    var method_name = prefix + param_name_for_construct_field(target_field, t.is_relation_or_multi)
    return _GroupableFieldMatch(
        method_name=method_name, is_relation_or_multi=t.is_relation_or_multi, relation_target=t.relation_target
    )


@fieldwise_init
struct _AggregateCallMatch(Copyable, Movable):
    """What `_match_aggregate_call` found. `has_grouping` is False for the
    whole-table form; `is_for` distinguishes `_for_<x>` (scalar, `raises`)
    from `_by_<x>` (`Dict`-returning) when `has_grouping` is True.
    `x_relation_target` is only meaningful when `x_is_relation_or_multi`."""

    var method_name: String
    var has_grouping: Bool
    var is_for: Bool
    var x_is_relation_or_multi: Bool
    var x_relation_target: String


def _match_aggregate_call(
    mut sc: Scanner, fa: FieldAccess, ctx: RewriteContext, kind: String, rest: String
) raises -> _AggregateCallMatch:
    """Method-name grammar is `{kind}_{y}[_by_{x}|_for_{x}]`, and both `y`/
    `x` can themselves contain underscores -- tries each of the entity's own
    aggregatable field names as a candidate `y` prefix (matching against the
    actual declared field list, never blind suffix slicing, same discipline
    `_match_ordered_range_call` already established), then checks whether
    what's left is empty (whole-table) or `_by_<x>`/`_for_<x>` for some
    known groupable `x` (validated via `_resolve_groupable_target`, shared
    with `_match_groupable_field`).

    `y` candidates: `stats_fields[entity]` minus any `multi` field (a
    `multi` field's storage is `Set[...]`, never the aggregated value
    itself -- `analysis.is_aggregatable`'s own rule, mirrored here since
    the rewrite engine only has field *names* via project-wide maps, not
    `Field` objects), plus `ordered_fields[entity]` too but *only* for
    `min`/`max`/`median` (an `ordered` field earns those for free; `sum`/
    `avg` still need `stats` for the `+` it additionally promises)."""
    var y_candidates = List[String]()
    if fa.entity in ctx.stats_fields:
        for name in ctx.stats_fields[fa.entity]:
            var is_multi = fa.entity in ctx.multi_fields and _contains(ctx.multi_fields[fa.entity], name)
            if not is_multi and not _contains(y_candidates, name):
                y_candidates.append(name)
    if (kind == "min" or kind == "max" or kind == "median") and fa.entity in ctx.ordered_fields:
        for name in ctx.ordered_fields[fa.entity]:
            if not _contains(y_candidates, name):
                y_candidates.append(name)

    for y_name in y_candidates:
        if rest == y_name:
            return _AggregateCallMatch(
                method_name=kind + "_" + y_name,
                has_grouping=False,
                is_for=False,
                x_is_relation_or_multi=False,
                x_relation_target=String(),
            )
        if rest.startswith(y_name + "_by_"):
            var x_name = String(rest[byte = y_name.byte_length() + 4 : rest.byte_length()])
            var t = _resolve_groupable_target(sc, fa, ctx, kind + "_" + y_name + "_by_", x_name)
            return _AggregateCallMatch(
                method_name=kind + "_" + y_name + "_by_" + param_name_for_construct_field(x_name, t.is_relation_or_multi),
                has_grouping=True,
                is_for=False,
                x_is_relation_or_multi=t.is_relation_or_multi,
                x_relation_target=t.relation_target,
            )
        if rest.startswith(y_name + "_for_"):
            var x_name = String(rest[byte = y_name.byte_length() + 5 : rest.byte_length()])
            var t = _resolve_groupable_target(sc, fa, ctx, kind + "_" + y_name + "_for_", x_name)
            return _AggregateCallMatch(
                method_name=kind + "_" + y_name + "_for_" + param_name_for_construct_field(x_name, t.is_relation_or_multi),
                has_grouping=True,
                is_for=True,
                x_is_relation_or_multi=t.is_relation_or_multi,
                x_relation_target=t.relation_target,
            )
    raise sc.err(
        "InvalidSquirrelSyntax: '"
        + kind
        + "_"
        + rest
        + "' on '"
        + fa.entity
        + "' doesn't match any aggregatable field -- '"
        + kind
        + "_<field>[_by_<other>|_for_<other>]', where <field> is"
        + (" 'stats'-tagged" if (kind == "sum" or kind == "avg") else " 'stats'-tagged or 'ordered'")
        + " and <other> has a backward index"
    )
