from squirrel_compiler.parser import Scanner, MarkerKind, parse_type_expr
from squirrel_compiler.codegen.helpers import (
    sqrrl_prefixed,
    is_container_type,
    container_element_of,
    rewritten_field_type,
)
from squirrel_compiler.codegen.entity import emit_entity_inner, emit_entity
from squirrel_compiler.codegen.table import emit_indexes, emit_table
from squirrel_compiler.codegen.aggregates import emit_aggregate_methods
from squirrel_compiler.codegen.methods import rewrite_method_body
from squirrel_compiler.codegen.script_utils import (
    is_in_def_signature,
    crosses_top_level_def,
    build_create_call,
    indent_of,
)
from squirrel_compiler.codegen.rewrite_context import RewriteContext
from squirrel_compiler.codegen.rewrite_field_access import (
    handle_field_access,
    handle_name_ref,
    handle_func_call_marker,
    handle_bare_call_chain,
    handle_bare_rooted_chain,
    PendingForLoopDecl,
    _require_for_loop_marking_matches,
    _finish_registered_call,
)


def rewrite_markers(source: String, mut ctx: RewriteContext) raises -> String:
    """Rewrites every `@@`-marked construct in `source` to plain Mojo,
    leaving everything else byte-for-byte untouched.

    Slimmed from rw_squirrel_2's own `rewrite_markers` for M1's scope:
    `MarkerKind.STRUCT` emits `sqrrl__<Name>Inner`/`sqrrl__<Name>` (entity.
    mojo) and `sqrrl__<Name>Indexes`/`sqrrl__<Name>Table` (table.mojo)
    instead of the old `EntityInner`/entity-wrapper/table-state/table
    quartet. `parsed.method_body` is rewritten via `codegen/methods.mojo`'s
    `rewrite_method_body` (M3) and spliced into `emit_entity`'s own
    wrapper output. `BEGIN_INIT_FROM_JSON`/`INIT_FROM_JSON`/
    `END_INIT_FROM_JSON`/`TO_JSON` (M5) each emit a single call into
    `sqrrl__json.mojo`'s generated free functions (`driver/json_module.
    mojo`'s `emit_json_module`) -- no codegen of their own lives here
    beyond that one splice. `PLAIN_VAR_DECL` (M2+) still isn't in
    `MarkerKind` at all. `FIELD_ACCESS`/`NAME_REF` move to
    `rewrite_field_access.mojo`, same split rw_squirrel_2 already made."""
    var sc = Scanner(source)
    var out = String()
    var pos = 0

    var pending_decl: Optional[String] = None
    var pending_for_loop_decl: Optional[PendingForLoopDecl] = None

    # Set by `MarkerKind.WORLD_SCOPE` (`@@:`) -- the byte offset where its
    # indented block ends, and the indentation to reproduce the spliced
    # `finally:` clause at.
    var pending_world_scope_end: Optional[Int] = None
    var pending_world_scope_indent: String = ""

    while True:
        var kind = sc.find_next_marker()
        if kind == MarkerKind.NONE:
            break
        var marker_start = sc.pos
        var between = String(source[byte = pos : marker_start])
        out += _splice_pending_world_scope_close(
            between, pos, pending_world_scope_end, pending_world_scope_indent
        )
        if pending_world_scope_end and pending_world_scope_end.value() <= marker_start:
            ctx.world_declared = False
            pending_world_scope_end = None
        if ";" in between:
            pending_decl = None
        if ":" in between:
            pending_for_loop_decl = None
        if crosses_top_level_def(between):
            ctx.entity_to_type = Dict[String, String]()
            ctx.world_declared = False
            ctx.temp_keep_alives_declared = False

        if kind == MarkerKind.STRUCT:
            var parsed = sc.parse_struct()
            out += emit_entity_inner(parsed, ctx.plain_struct_names)
            out += "\n\n"
            out += emit_entity(parsed, rewrite_method_body(parsed.method_body, parsed.name, ctx), ctx.json_used)
            out += "\n\n"
            out += emit_indexes(parsed, ctx.plain_struct_names)
            out += "\n\n"
            out += emit_table(parsed, ctx.plain_struct_names)
            out += emit_aggregate_methods(parsed)
            out += "\n"
            pending_decl = None
            pending_for_loop_decl = None

        elif kind == MarkerKind.WORLD_SCOPE:
            if ctx.world_declared:
                raise sc.err(
                    "InvalidSquirrelSyntax: '@@:' already opened in"
                    " this function -- 'sqrrl___world' only needs declaring"
                    " once"
                )
            var scope_indent = indent_of(source, marker_start)
            var scope_end = sc.parse_world_scope()
            out += "var sqrrl___world = sqrrl___init()\n" + scope_indent + "try:"
            ctx.world_declared = True
            pending_world_scope_end = scope_end
            pending_world_scope_indent = scope_indent
            pending_decl = None
            pending_for_loop_decl = None

        elif kind == MarkerKind.INIT:
            sc.parse_init()
            if not ctx.world_declared:
                raise sc.err(
                    "InvalidSquirrelSyntax: '@@init()' needs '@@:'"
                    " opened first in this function"
                )
            out += "sqrrl___world.sqrrl__check_no_leaks(); sqrrl___world = sqrrl___init()"
            pending_decl = None
            pending_for_loop_decl = None

        elif kind == MarkerKind.BEGIN_INIT_FROM_JSON:
            if not ctx.world_declared:
                raise sc.err(
                    "InvalidSquirrelSyntax: '@@@begin_init_from_json(...)'"
                    " needs 'sqrrl___world' -- open @@@: or add '@@' to this"
                    " function's own parameters first"
                )
            if ctx.temp_keep_alives_declared:
                raise sc.err(
                    "InvalidSquirrelSyntax: '@@@begin_init_from_json(...)'"
                    " already opened in this function -- close it with"
                    " '@@@end_init_from_json()' first"
                )
            var begin_json_expr = sc.parse_begin_init_from_json()
            out += "var sqrrl___temp_keep_alives = sqrrl___begin_init_from_json(sqrrl___world, " + begin_json_expr + ")"
            ctx.temp_keep_alives_declared = True
            pending_decl = None
            pending_for_loop_decl = None

        elif kind == MarkerKind.INIT_FROM_JSON:
            if not ctx.world_declared:
                raise sc.err(
                    "InvalidSquirrelSyntax: '@@@init_from_json(...)' needs"
                    " 'sqrrl___world' -- open @@@: or add '@@' to this"
                    " function's own parameters first"
                )
            var init_json_expr = sc.parse_init_from_json()
            out += "sqrrl___init_from_json(sqrrl___world, " + init_json_expr + ")"
            pending_decl = None
            pending_for_loop_decl = None

        elif kind == MarkerKind.END_INIT_FROM_JSON:
            if not ctx.temp_keep_alives_declared:
                raise sc.err(
                    "InvalidSquirrelSyntax: '@@@end_init_from_json()' with no"
                    " matching '@@@begin_init_from_json(...)' open in this"
                    " function"
                )
            sc.parse_end_init_from_json()
            # Moves (not reassigns) sqrrl___temp_keep_alives into a real
            # function call -- a hard call boundary, not a bare assignment
            # the caller's own dataflow could reorder relative to earlier
            # statements. Verified with a standalone spike before wiring
            # this in: consume(x^) after several unrelated statements
            # destroys x exactly at the call, never earlier (the same fix
            # rw_squirrel_2's own world_module.mojo doc comment records for
            # the identical failure mode).
            out += "sqrrl___end_init_from_json(sqrrl___temp_keep_alives^)"
            ctx.temp_keep_alives_declared = False
            pending_decl = None
            pending_for_loop_decl = None

        elif kind == MarkerKind.TO_JSON:
            if not ctx.world_declared:
                raise sc.err(
                    "InvalidSquirrelSyntax: '@@@to_json()' needs"
                    " 'sqrrl___world' -- open @@@: or add '@@' to this"
                    " function's own parameters first"
                )
            sc.parse_to_json()
            out += "sqrrl___world_to_json(sqrrl___world)"
            pending_decl = None
            pending_for_loop_decl = None

        elif kind == MarkerKind.WORLD_FUNC:
            handle_func_call_marker(sc, source, marker_start, ctx, True, pending_decl, pending_for_loop_decl, out)

        elif kind == MarkerKind.ENTITY_FUNC:
            handle_func_call_marker(sc, source, marker_start, ctx, False, pending_decl, pending_for_loop_decl, out)

        elif kind == MarkerKind.ENTITY_PARAM:
            var ep = sc.parse_entity_param()
            var is_param = is_in_def_signature(source, marker_start)
            var is_var_decl = False
            if not is_param:
                var save = sc.pos
                sc.skip_trivia()
                is_var_decl = sc.at_assignment()
                sc.pos = save
            if is_param or is_var_decl:
                out += sqrrl_prefixed(ep.name) + ": " + rewritten_field_type(ep.type_text, ctx.plain_struct_names)
                ctx.entity_to_type[ep.name] = parse_type_expr(ep.type_text).render_relation_stripped()
            else:
                # A hand-written plain struct's own field declaration
                # (plain-structs milestone, the plan's §4) -- the only
                # other shape `@@name: <type>` can mean, now that it's not
                # a def parameter or a var-decl initializer. The name gets
                # the same `sqrrl__` prefix a real `@@struct`'s own field
                # already always gets -- collision-proofs it against a
                # Mojo reserved word or any other existing identifier the
                # same way (confirmed via a real repro: an unprefixed
                # `@@ref: @@Type` field collided with Mojo's own `ref`
                # keyword, with zero DSL-level protection, unlike an
                # `@@struct`'s own fields, which can never collide since
                # they're always prefixed). The type resolves to the real
                # generated name same as before (bare if it's itself a
                # plain struct, sqrrl__-prefixed if it's a real entity).
                # No `ctx.entity_to_type` registration here -- this isn't a
                # local-variable binding, it's a struct field.
                #
                # Since this is an `@fieldwise_init` struct, prefixing the
                # field name also changes its own constructor's keyword
                # argument name to match (Mojo's own rule: the keyword
                # always equals the field name) -- `Note(@@owner=@@b)`'s
                # own `@@owner=` keyword marker (a *new* shape, handled by
                # `MarkerKind.CONSTRUCT_KWARG` below) is what lets the
                # `.sqrrl` source keep writing the marked name (matching
                # the field's own declaration) rather than the raw
                # internal one.
                #
                # `ep.type_text` (mandatory-marking milestone: `Scanner.
                # scan_entity_param_type_text`) is the *whole* raw type
                # text, arbitrary nesting/argument count included -- same
                # general `rewritten_field_type` a `@@struct`'s own field
                # declaration already goes through, not a bespoke single-
                # wrapper, single-argument-only rendering of this branch's
                # own. A relation in a `Dict`'s value position (`Dict[K,
                # @@V]`) renders and JSON-round-trips correctly here same
                # as everywhere else in the codebase, but inherits the
                # same pre-existing, deliberate restriction as every other
                # Dict-typed field: iterating it only ever yields keys,
                # never values -- not a new gap this fix introduces.
                out += sqrrl_prefixed(ep.name) + ": " + rewritten_field_type(ep.type_text, ctx.plain_struct_names)
            pending_decl = None
            pending_for_loop_decl = None

        elif kind == MarkerKind.PLAIN_VAR_DECL:
            # `[var ]<name>: <Type>` -- a bare local/parameter name (never
            # `@@`-marked) with an explicit type annotation, `<Type>` a
            # single identifier (`Note`) or a container of one (`List[
            # Note]`). `prefix_text` (verbatim through `name` and `:`) is
            # never rewritten, but `type_text` still might need to be --
            # it can itself embed a genuine relation even though `name`
            # stays bare (`members: List[Dict[String, @@Employee]]`, the
            # relation confined to a position that doesn't require the
            # *field's* own name to be marked) -- `rewritten_field_type`,
            # the exact same general function `ENTITY_PARAM`'s own hand-
            # written-struct-field branch already relies on, handles that
            # correctly (falling through unchanged when there's nothing
            # to rewrite) -- copying `type_text` through raw instead
            # would silently skip that rewrite, since capturing the whole
            # bracketed span (needed for a *container-of-plain-struct*
            # local's own registration below) also swallows any `@@`
            # embedded deeper inside before the outer loop could ever
            # reach it on its own.
            #
            # Three contexts, exactly mirroring `MarkerKind.ENTITY_PARAM`'s
            # own three-way split for the marked equivalent: a def's own
            # parameter (`is_param`), a var-decl (`is_var_decl`, found via
            # the same "look ahead for `=`, then rewind" `ENTITY_PARAM`
            # already uses), or -- when neither holds -- a hand-written
            # plain struct's own field declaration, which needs no
            # registration at all (that struct's own field-type
            # resolution is handled entirely elsewhere, not through `ctx.
            # entity_to_type`).
            #
            # Registration itself doesn't check whether `type_text`
            # actually names a known plain struct (or wraps one) -- always
            # registering is simpler and just as safe: `var x: Int = 5`/
            # `def foo(count: Int)` registering `ctx.entity_to_type["x"]
            # = "Int"` is never reachable through a marked chain anyway
            # (`Int` has no `@@`-markable fields for `x.@@anything` to
            # even parse against), so it's dead, harmless data, not a
            # false positive that changes behavior anywhere. This is what
            # makes `var x: Int = 5`/a struct's own `text: String` field
            # (both matching `at_plain_var_decl`'s purely syntactic check
            # just as much as `var n: Note = ...` does) total no-ops.
            #
            # Lets a later marked field-access chain rooted at this name
            # resolve (`n.@@ref.name`, `items[0].@@ref.name`) even though
            # `n`/`items` are never themselves `@@`-marked -- only a field
            # *access* through a plain-struct value can be marked, never
            # the value's own local/parameter name.
            var pvd_start = sc.pos
            var pvd = sc.parse_plain_var_decl()
            var is_param = is_in_def_signature(source, pvd_start)
            # `type_is_inferred` (`var addresses = List[Address]()`, no
            # explicit annotation) only ever matches a var-decl by
            # construction (`at_plain_var_decl`'s own second shape
            # requires the leading `var` keyword) -- the ordinary "look
            # ahead for `=`" check below doesn't apply here at all,
            # `self.pos` already sits right *past* the `=` it would be
            # looking for.
            var is_var_decl = pvd.type_is_inferred
            if not is_param and not pvd.type_is_inferred:
                var save = sc.pos
                sc.skip_trivia()
                is_var_decl = sc.at_assignment()
                sc.pos = save
            if is_param or is_var_decl:
                # For the inferred shape, `pvd.type_text` is only a
                # *type* when the RHS was actually a constructor call
                # (`Address(...)`/`List[Address]()`, `type_text` the
                # struct/container's own name) -- `at_plain_var_decl`'s
                # own syntactic check can't tell that apart from a bare
                # *function* call that happens to look identical (`var
                # addrs = make_addresses(@@bob)`, `type_text` = "make_
                # addresses", the function's own name, not a type at
                # all). Confirmed as a real, previously-silent gap: `for
                # a in addrs:` afterward left `a` completely unregistered
                # (`is_container_type("make_addresses")` is false, so
                # `PLAIN_FOR_LOOP`'s own registration never fires), the
                # same "was never constructed" error a genuinely bogus
                # type produces -- except this one had a perfectly good
                # real type available the whole time (`ctx.bare_function_
                # returns["make_addresses"]` = "List[Address]"), just
                # never consulted. `ctx.bare_function_returns` is checked
                # first and wins whenever `type_text` names a real bare
                # function -- a function and a struct can never share one
                # name in the same Mojo scope, so there's no ambiguity to
                # resolve, only a preference for the *real* type when a
                # more specific one is available.
                # `render_relation_stripped()` -- `pvd.type_text` is
                # captured raw (still `@@`-marked, e.g. `Dict[String,
                # @@Employee]`) since this marker's own span swallows it
                # whole, never letting the outer loop rediscover any `@@`
                # inside as its own separate marker; every other producer
                # of `ctx.entity_to_type` always stores the stripped form
                # (`bare_function_returns`'s own values, a marked chain's
                # resolved type, ...), so leaving this one raw silently
                # desynced a later lookup (`current_type in ctx.struct_
                # names` never matches a literal `"@@Employee"` string) --
                # confirmed via a real compile: `var d = Dict[String,
                # @@Employee](); d["k"].name` rolled back as an
                # unresolvable leaf and copied `.name` through
                # unrewritten instead of raising or resolving correctly.
                # `var x = bare_func(...).chain.further:` -- a trailing
                # chain off the call's own result, not just the call
                # itself. `pvd.type_text`'s own registered return type
                # (below) is only correct when *nothing* follows the
                # call -- otherwise the chain walks *through* it to a
                # different final type (`make_team(...).roster[0].
                # mentor()` ends at `Employee`, not `make_team`'s own
                # `Team`). Confirmed as a real, previously-silent bug:
                # registering the call's own bare return type here
                # unconditionally, then unconditionally clearing `pending_
                # decl` below, stole the registration job from `BARE_
                # CALL_CHAIN`'s own correct, chain-aware one (found next,
                # when the outer loop reaches the call itself) without
                # ever doing it right -- `x.field` afterward silently
                # passed through unrewritten instead of raising or
                # resolving. Detected here via a pure lookahead through
                # the call's own already-known name and argument list
                # (mirrors `at_plain_var_decl`'s own scan exactly, just
                # continuing one step further to peek past the closing
                # `)`), fully restored either way.
                var chain_follows_call = False
                if pvd.type_text in ctx.bare_function_returns:
                    var lookahead_pos = sc.pos
                    _ = sc.scan_ident()
                    if sc.try_consume("("):
                        _ = sc.scan_call_args_to_close()
                        chain_follows_call = sc.peek_trailing_chain_follows()
                    sc.pos = lookahead_pos
                if chain_follows_call:
                    pending_decl = Optional[String](pvd.name)
                    pending_for_loop_decl = None
                else:
                    var registered_type = (
                        ctx.bare_function_returns[pvd.type_text] if pvd.type_text in ctx.bare_function_returns
                        else parse_type_expr(pvd.type_text).render_relation_stripped()
                    )
                    # Mandatory marking dropped for a bare function's own
                    # return shape (Part 1) means `ctx.bare_function_
                    # returns` can now hold a genuinely entity-shaped type
                    # here too, not just a plain struct -- registering it
                    # against this bare name is still safe: `at_bare_
                    # rooted_chain`/`at_bare_var_decl_over_bare_chain`/
                    # `at_bare_for_loop_over_bare_chain` (`parser/scanner.
                    # mojo`) were widened to recognize a bare-rooted
                    # *plain field* hop too, not just a method call, so a
                    # later `x.field`/`for a in x.container_field:` off
                    # this name resolves correctly either way (real
                    # entity or plain struct) through the exact same,
                    # already type-agnostic `_walk_access_chain`.
                    ctx.entity_to_type[pvd.name] = registered_type
                    pending_decl = None
                    pending_for_loop_decl = None
            else:
                pending_decl = None
                pending_for_loop_decl = None
            # Inferred: `type_text` is registration-only, never emitted --
            # the constructor call it came from is left unconsumed right
            # after `prefix_text`, for the ordinary scan to re-discover
            # and emit normally (any `@@`-marked argument inside it still
            # needs that treatment); emitting it here too would duplicate
            # it.
            out += pvd.prefix_text if pvd.type_is_inferred else (
                pvd.prefix_text + rewritten_field_type(pvd.type_text, ctx.plain_struct_names)
            )

        elif kind == MarkerKind.BARE_VAR_DECL_OVER_ENTITY:
            # `var <bare_name> = @@...:` -- the var-decl mirror of `BARE_
            # FOR_ENTITY_LOOP` just below: a variable that's never itself
            # `@@`-marked, but whose initializer is rooted at a single
            # `@@` (a bound entity's own plain field, a bare method call
            # on one, a marked top-level function's own call, or a bound
            # entity referenced directly) -- needed for the identical
            # reason `BARE_FOR_ENTITY_LOOP` was: `var addr = @@bob.get_
            # home()` (a bare method returning a plain struct) has no `:
            # Address` annotation and no bare-identifier-before-`(` shape
            # for `PLAIN_VAR_DECL`'s own inferred branch to catch either
            # (its `scan_ident()` stops dead at the RHS's own leading
            # `@`) -- previously left `addr` completely unregistered, a
            # real "was never constructed" error on a real compile, not
            # hypothetical. Sets `pending_decl` and lets the outer loop
            # continue into the `@@` on its own next iteration -- the
            # existing `is_entity_method`/bare-method/`handle_func_call_
            # marker`/`handle_name_ref` registration sites (all already
            # `register_pending_decl_type=True` or unconditional) do the
            # rest, no new chain-walking logic needed at all.
            var name = sc.parse_bare_var_decl_prefix()
            out += "var " + name + " ="
            pending_decl = Optional[String](name)
            pending_for_loop_decl = None

        elif kind == MarkerKind.BARE_VAR_DECL_OVER_BARE_CHAIN:
            # `var <bare_name> = <bare_ident>.<chain>` -- the bare-rooted
            # mirror of `BARE_VAR_DECL_OVER_ENTITY` just above, for a
            # chain whose own root carries no `@@` either (`var x =
            # addr2.get_thing()`, `addr2` itself bare) -- `PLAIN_VAR_
            # DECL`'s own inferred branch only covers a *direct*
            # constructor/bare-function call (`Ident(`, no receiver);
            # this is for a receiver.method()-shaped RHS instead. Sets
            # `pending_decl` and lets the outer loop continue into `BARE_
            # ROOTED_CHAIN` (found at the receiver's own position next)
            # -- identical mechanics to the `@@`-rooted sibling, just
            # feeding a different downstream marker.
            var bare_name = sc.parse_bare_var_decl_prefix()
            out += "var " + bare_name + " ="
            pending_decl = Optional[String](bare_name)
            pending_for_loop_decl = None

        elif kind == MarkerKind.PLAIN_FOR_LOOP:
            # `for [var/ref ]<loop_var> in <container>[(...)]:` -- all
            # bare, never `@@`-marked. The bare-name/bare-call equivalent
            # of `FOR_ENTITY_LOOP`'s own `pending_for_loop_decl`
            # mechanism -- but since `<container>` here is a single bare
            # identifier (optionally called), never itself a marker the
            # outer loop would stop at again, this handler does the
            # whole lookup-and-register step in one shot rather than
            # deferring to a follow-up marker the way FOR_ENTITY_LOOP
            # does for a *marked* iterated expression. No-op (just
            # copies/reconstructs the matched span unchanged) whenever
            # `container_name` isn't actually a known, container-typed
            # local/function -- `for x in range(10):`/`for x in some_
            # list_of_ints:` match this shape exactly the same, and only
            # genuinely registering a loop variable when the container is
            # *itself* already tracked is what makes those total no-ops
            # too. The call case (`for n in get_notes(@@b):`) needs its
            # own argument list rewritten (any `@@`-marked argument still
            # needs it), so it's reconstructed rather than copied
            # verbatim -- same reasoning `handle_bare_call_chain`/
            # `handle_func_call_marker` already use for their own calls.
            var pfl_start = sc.pos
            var pfl = sc.parse_plain_for_loop()
            if pfl.is_call and sc.peek_trailing_chain_follows():
                # `for bare_loop_var in bare_func(...).chain:` -- the call
                # has a trailing chain before the loop's own `:`, so `pfl.
                # container_name`'s own return type isn't the final
                # iterated type at all (the chain walks *through* it --
                # `make_team(...).roster` ends at `List[Employee]`, not
                # `make_team`'s own `Team`). Confirmed as a real,
                # previously-silent gap: `at_plain_for_loop` never matched
                # this shape at all before (required an immediate `:`
                # right after the call), so nothing set up `pending_for_
                # loop_decl` -- the loop variable was left completely
                # unregistered, `e.field` inside the loop body silently
                # passing through unrewritten. Defers to the exact same
                # chain-aware registration a direct chain (no for-loop at
                # all) already gets via `_finish_registered_call`, rather
                # than the inline, call-only registration just below.
                var rewritten_args = rewrite_markers(pfl.arg_text, ctx)
                var binding = (pfl.binding_prefix + " ") if pfl.binding_prefix.byte_length() > 0 else String()
                var call_text = pfl.container_name + "(" + rewritten_args + ")"
                var call_end_pos = sc.pos
                out += "for " + binding + pfl.loop_var + " in "
                if pfl.container_name in ctx.bare_function_returns:
                    var pfl_pending_for_loop_decl = Optional[PendingForLoopDecl](
                        PendingForLoopDecl(name=pfl.loop_var, wants_marked=False)
                    )
                    var pfl_registered_type = ctx.bare_function_returns[pfl.container_name]
                    _finish_registered_call(
                        sc,
                        source,
                        marker_start,
                        ctx,
                        call_text,
                        call_end_pos,
                        pfl_registered_type,
                        pfl.container_name + "(...)",
                        False,
                        pending_decl,
                        pfl_pending_for_loop_decl,
                        out,
                    )
                else:
                    out += call_text
                    pending_decl = None
                    pending_for_loop_decl = None
            elif pfl.is_call:
                var rewritten_args = rewrite_markers(pfl.arg_text, ctx)
                var binding = (pfl.binding_prefix + " ") if pfl.binding_prefix.byte_length() > 0 else String()
                out += "for " + binding + pfl.loop_var + " in " + pfl.container_name + "(" + rewritten_args + ")"
                if pfl.container_name in ctx.bare_function_returns and is_container_type(ctx.bare_function_returns[pfl.container_name]):
                    # Mandatory marking dropped for a bare function's own
                    # return shape means this can now be a container of
                    # real entities, not just plain structs -- registering
                    # `pfl.loop_var` (bare) against the element type is
                    # still safe either way: a later `x.field`/`x.method(
                    # ...)` off this bare loop var resolves correctly
                    # through `at_bare_rooted_chain`'s own widened trigger
                    # (a plain-field hop, not just a call) and `_walk_
                    # access_chain`'s already type-agnostic dispatch.
                    ctx.entity_to_type[pfl.loop_var] = container_element_of(ctx.bare_function_returns[pfl.container_name])
                pending_decl = None
                pending_for_loop_decl = None
            else:
                if pfl.container_name in ctx.entity_to_type and is_container_type(ctx.entity_to_type[pfl.container_name]):
                    ctx.entity_to_type[pfl.loop_var] = container_element_of(ctx.entity_to_type[pfl.container_name])
                out += String(source[byte = pfl_start : sc.pos])
                pending_decl = None
                pending_for_loop_decl = None

        elif kind == MarkerKind.RETURN_TYPE:
            var nr = sc.parse_name_ref()
            out += sqrrl_prefixed(nr.name)
            pending_decl = None
            pending_for_loop_decl = None

        elif kind == MarkerKind.CONSTRUCT:
            var c = sc.parse_construct()
            if not ctx.world_declared:
                raise sc.err(
                    "InvalidSquirrelSyntax: constructing '@@"
                    + c.type_name
                    + "' needs 'sqrrl___world' -- open @@: or add"
                    " '@@' to this function's own parameters first"
                )
            out += build_create_call(source, marker_start, c.type_name, c.fields, ctx)
            if pending_decl:
                ctx.entity_to_type[pending_decl.value()] = c.type_name
            pending_decl = None
            pending_for_loop_decl = None

        elif kind == MarkerKind.FOR_ENTITY_LOOP:
            var name = sc.parse_for_entity_loop()
            # `parse_for_entity_loop` consumes through `in` but not the
            # whitespace after it -- no trailing space hardcoded here
            # either (cosmetic double-space bug, confirmed via a real
            # compile: `for sqrrl__m in  sqrrl__d.get_team():`), so the
            # source's own original space between `in` and the iterated
            # expression is left for the outer loop's ordinary "between
            # text" copy to reproduce verbatim, same fix as `scan_entity_
            # param_type_text`'s own missing-space-before-`=` bug, just
            # the opposite direction (double emission, not zero).
            out += sqrrl_prefixed(name) + " in"
            pending_decl = None
            # `for @@x in @@get_list(...):`/`for @@x in @@@get_list(...):`
            # -- a call rooted at an `@@`/`@@@` marker is itself a real
            # marker (`handle_func_call_marker`/`_walk_access_chain`) that
            # consumes `pending_for_loop_decl` exactly like every other
            # marker already does -- no special-casing needed here for
            # that case.
            pending_for_loop_decl = Optional[PendingForLoopDecl](PendingForLoopDecl(name=name, wants_marked=True))
            # `for @@x in bare_func(...):` -- a bare (never `@@`/`@@@`-
            # marked) top-level function's own call, with *no* further
            # trailing chain. `BARE_CALL_CHAIN`'s own forward check
            # (`at_bare_call_chain`) requires a trailing `.`/`[` to fire
            # at all (a direct chain off the call) -- a for-loop's own
            # immediately-following `:` never provides one, so nothing
            # would otherwise ever consume `pending_for_loop_decl` here.
            # Handled inline, synchronously, mirroring `PLAIN_FOR_LOOP`'s
            # own bare-call branch -- but only when no trailing chain
            # actually follows the call: if one does, `BARE_CALL_CHAIN`'s
            # own ordinary dispatch already handles it correctly the very
            # next scanner iteration (already proven working this
            # session), so this lookahead backs off and leaves `pending_
            # for_loop_decl` untouched for it.
            var fel_lookahead = sc.pos
            sc.skip_trivia()
            var fel_between = String(source[byte = fel_lookahead : sc.pos])
            var fel_func_name = sc.scan_ident()
            var fel_consumed = False
            if fel_func_name.byte_length() > 0 and sc.peek() == UInt8(ord("(")) and fel_func_name in ctx.bare_function_returns:
                sc.pos += 1
                var fel_arg_text = sc.scan_call_args_to_close()
                if sc.peek() != UInt8(ord(".")) and sc.peek() != UInt8(ord("[")):
                    var fel_registered_type = ctx.bare_function_returns[fel_func_name]
                    _require_for_loop_marking_matches(sc, ctx, fel_registered_type, pending_for_loop_decl.value())
                    ctx.entity_to_type[name] = container_element_of(fel_registered_type)
                    var fel_rewritten_args = rewrite_markers(fel_arg_text, ctx)
                    out += fel_between + fel_func_name + "(" + fel_rewritten_args + ")"
                    pending_for_loop_decl = None
                    fel_consumed = True
            if not fel_consumed:
                sc.pos = fel_lookahead

        elif kind == MarkerKind.BARE_FOR_ENTITY_LOOP:
            # `for <bare_var> in @@...:` -- the bare-loop-var mirror of
            # `FOR_ENTITY_LOOP` just above: a loop variable that's never
            # itself `@@`-marked, but whose iterated expression is rooted
            # at a single `@@` (a bound entity's own plain field, a bare
            # method call on one, a marked top-level function's own call,
            # or a bound entity referenced directly) -- needed once a
            # bare method/field could resolve to a *plain*-struct-shaped
            # container through an `@@`-marked root at all (`@@own.get_
            # notes().@@ref.name`'s own for-loop shape, `for n in @@own.
            # get_notes():` -- previously left `n` completely
            # unregistered, the exact "was never constructed" gap a bare
            # top-level function/local variable's own `PLAIN_VAR_DECL`/
            # `PLAIN_FOR_LOOP` already closed, just never for an `@@`-
            # rooted chain). `wants_marked=False` -- `_require_for_loop_
            # marking_matches` (consumed by whichever marker handles the
            # chain that follows) rejects if the terminal type turns out
            # to actually be entity-shaped after all, the same way `wants_
            # marked=True` above rejects the opposite mismatch.
            var header = sc.parse_bare_for_loop_prefix()
            var header_binding = (header.binding_prefix + " ") if header.binding_prefix.byte_length() > 0 else String()
            out += "for " + header_binding + header.loop_var + " in"
            pending_decl = None
            pending_for_loop_decl = Optional[PendingForLoopDecl](
                PendingForLoopDecl(name=header.loop_var, wants_marked=False)
            )

        elif kind == MarkerKind.BARE_FOR_LOOP_OVER_BARE_CHAIN:
            # `for <bare_var> in <bare_ident>.<chain>:` -- the bare-rooted
            # mirror of `BARE_FOR_ENTITY_LOOP` just above, for an iterated
            # chain whose own root carries no `@@` either (`for a in
            # addr2.get_thing():`). Same mechanics, feeding `BARE_ROOTED_
            # CHAIN` next instead of the `@@`-triggered dispatch.
            # `wants_marked=False` for the identical reason -- the
            # terminal type this eventually resolves to still needs to
            # not be entity-shaped, checked by whichever site actually
            # registers it.
            var bare_header = sc.parse_bare_for_loop_prefix()
            var bare_binding = (bare_header.binding_prefix + " ") if bare_header.binding_prefix.byte_length() > 0 else String()
            out += "for " + bare_binding + bare_header.loop_var + " in"
            pending_decl = None
            pending_for_loop_decl = Optional[PendingForLoopDecl](
                PendingForLoopDecl(name=bare_header.loop_var, wants_marked=False)
            )

        elif kind == MarkerKind.FIELD_ACCESS:
            handle_field_access(sc, source, marker_start, ctx, pending_decl, pending_for_loop_decl, out)

        elif kind == MarkerKind.BARE_CALL_CHAIN:
            handle_bare_call_chain(sc, source, marker_start, ctx, pending_decl, pending_for_loop_decl, out)

        elif kind == MarkerKind.BARE_ROOTED_CHAIN:
            handle_bare_rooted_chain(sc, source, marker_start, ctx, pending_decl, pending_for_loop_decl, out)

        elif kind == MarkerKind.CONSTRUCT_KWARG:
            # `Note(@@owner=@@b)` -- a hand-written plain struct's own
            # constructor call, the keyword spelled the marked way (same
            # as the field's own declaration, `var @@owner: @@Beta`)
            # rather than the raw internal name. Just the keyword itself:
            # the `=` and the value on its own right (`@@b`, an ordinary
            # `NAME_REF`) are untouched, copied/rewritten by the outer
            # loop's own general "between markers"/next-marker handling,
            # same as any other call argument already is.
            sc.pos += 2
            var kwarg_name = sc.scan_ident()
            out += sqrrl_prefixed(kwarg_name)

        else:  # MarkerKind.NAME_REF
            handle_name_ref(sc, source, marker_start, ctx, pending_decl, pending_for_loop_decl, out)

        pos = sc.pos

    var tail = String(source[byte = pos : source.byte_length()])
    out += _splice_pending_world_scope_close(
        tail, pos, pending_world_scope_end, pending_world_scope_indent
    )
    return out


def _splice_pending_world_scope_close(
    chunk: String,
    chunk_start: Int,
    pending_world_scope_end: Optional[Int],
    pending_world_scope_indent: String,
) -> String:
    """If `pending_world_scope_end` falls inside `chunk` (an ordinary
    plain-text span the main loop is about to copy through unchanged),
    splits it there and inserts `finally: sqrrl___world.sqrrl__check_no_leaks()`."""
    if not pending_world_scope_end:
        return chunk
    var end = pending_world_scope_end.value()
    if end < chunk_start or end > chunk_start + chunk.byte_length():
        return chunk
    var split = end - chunk_start
    var before = String(chunk[byte = 0 : split])
    var after = String(chunk[byte = split : chunk.byte_length()])
    return (
        before
        + pending_world_scope_indent
        + "finally:\n"
        + pending_world_scope_indent
        + "    sqrrl___world.sqrrl__check_no_leaks()\n"
        + after
    )
