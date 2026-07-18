from squirrel_compiler.parser import Scanner, MarkerKind, is_ident_char
from squirrel_compiler.codegen.helpers import (
    sqrrl_prefixed,
    encode_container_type,
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
from squirrel_compiler.codegen.rewrite_field_access import handle_field_access, handle_name_ref


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
    var pending_for_loop_decl: Optional[String] = None

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
                    " this function -- 'sqrrl__world' only needs declaring"
                    " once"
                )
            var scope_indent = indent_of(source, marker_start)
            var scope_end = sc.parse_world_scope()
            out += "var sqrrl__world = sqrrl__init()\n" + scope_indent + "try:"
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
            out += "sqrrl__world.sqrrl__check_no_leaks(); sqrrl__world = sqrrl__init()"
            pending_decl = None
            pending_for_loop_decl = None

        elif kind == MarkerKind.BEGIN_INIT_FROM_JSON:
            if not ctx.world_declared:
                raise sc.err(
                    "InvalidSquirrelSyntax: '@@@begin_init_from_json(...)'"
                    " needs 'sqrrl__world' -- open @@@: or add '@@' to this"
                    " function's own parameters first"
                )
            if ctx.temp_keep_alives_declared:
                raise sc.err(
                    "InvalidSquirrelSyntax: '@@@begin_init_from_json(...)'"
                    " already opened in this function -- close it with"
                    " '@@@end_init_from_json()' first"
                )
            var begin_json_expr = sc.parse_begin_init_from_json()
            out += "var sqrrl__temp_keep_alives = sqrrl__begin_init_from_json(sqrrl__world, " + begin_json_expr + ")"
            ctx.temp_keep_alives_declared = True
            pending_decl = None
            pending_for_loop_decl = None

        elif kind == MarkerKind.INIT_FROM_JSON:
            if not ctx.world_declared:
                raise sc.err(
                    "InvalidSquirrelSyntax: '@@@init_from_json(...)' needs"
                    " 'sqrrl__world' -- open @@@: or add '@@' to this"
                    " function's own parameters first"
                )
            var init_json_expr = sc.parse_init_from_json()
            out += "sqrrl__init_from_json(sqrrl__world, " + init_json_expr + ")"
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
            # Moves (not reassigns) sqrrl__temp_keep_alives into a real
            # function call -- a hard call boundary, not a bare assignment
            # the caller's own dataflow could reorder relative to earlier
            # statements. Verified with a standalone spike before wiring
            # this in: consume(x^) after several unrelated statements
            # destroys x exactly at the call, never earlier (the same fix
            # rw_squirrel_2's own world_module.mojo doc comment records for
            # the identical failure mode).
            out += "sqrrl__end_init_from_json(sqrrl__temp_keep_alives^)"
            ctx.temp_keep_alives_declared = False
            pending_decl = None
            pending_for_loop_decl = None

        elif kind == MarkerKind.TO_JSON:
            if not ctx.world_declared:
                raise sc.err(
                    "InvalidSquirrelSyntax: '@@@to_json()' needs"
                    " 'sqrrl__world' -- open @@@: or add '@@' to this"
                    " function's own parameters first"
                )
            sc.parse_to_json()
            out += "sqrrl__world_to_json(sqrrl__world)"
            pending_decl = None
            pending_for_loop_decl = None

        elif kind == MarkerKind.WORLD_FUNC:
            var func_name = sc.parse_world_func()
            sc.skip_whitespace()
            var starts_with_self = sc.starts_with("self") and not is_ident_char(sc.peek_at(4))
            var has_more_args = sc.peek() != UInt8(ord(")"))
            if is_in_def_signature(source, marker_start):
                if starts_with_self:
                    sc.pos += 4  # consume "self"
                    out += sqrrl_prefixed(func_name) + "(self, mut sqrrl__world: sqrrl__World"
                    sc.skip_trivia()
                    if sc.try_consume(","):
                        out += ", "
                    ctx.world_declared = True
                    pending_decl = None
                    pending_for_loop_decl = None
                    pos = sc.pos
                    continue
                out += sqrrl_prefixed(func_name) + "(mut sqrrl__world: sqrrl__World"
                ctx.world_declared = True
            else:
                if not ctx.world_declared:
                    raise sc.err(
                        "InvalidSquirrelSyntax: calling '@@"
                        + func_name
                        + "(...)' needs 'sqrrl__world' -- open @@:"
                        " or mark this function's own name with '@@' too"
                    )
                out += sqrrl_prefixed(func_name) + "(sqrrl__world"
                if func_name in ctx.function_returns:
                    var registered_type = ctx.function_returns[func_name]
                    if pending_decl:
                        ctx.entity_to_type[pending_decl.value()] = registered_type
                    if pending_for_loop_decl and is_container_type(registered_type):
                        ctx.entity_to_type[pending_for_loop_decl.value()] = container_element_of(registered_type)
            if has_more_args:
                out += ", "
            pending_decl = None
            pending_for_loop_decl = None

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
                if ep.wrapper:
                    out += sqrrl_prefixed(ep.name) + ": " + ep.wrapper.value() + "[" + sqrrl_prefixed(ep.type_name) + "]"
                    ctx.entity_to_type[ep.name] = encode_container_type(ep.wrapper.value(), ep.type_name)
                else:
                    out += sqrrl_prefixed(ep.name) + ": " + sqrrl_prefixed(ep.type_name)
                    ctx.entity_to_type[ep.name] = ep.type_name
            else:
                # A hand-written plain struct's own field declaration
                # (plain-structs milestone, the plan's §4) -- the only
                # other shape `@@name: @@Type` can mean, now that it's not
                # a def parameter or a var-decl initializer. The name
                # stays bare (matches "constructed with plain mojo":
                # `Address(owner=@@alice)` needs a bare keyword parameter
                # to match) -- only the type resolves to the real
                # generated name (bare if it's itself a plain struct,
                # sqrrl__-prefixed if it's a real entity). No `ctx.entity_
                # to_type` registration here -- this isn't a local-variable
                # binding, it's a struct field.
                if ep.wrapper:
                    raise sc.err(
                        "InvalidSquirrelSyntax: '@@"
                        + ep.name
                        + ": "
                        + ep.wrapper.value()
                        + "[@@"
                        + ep.type_name
                        + "]' -- a wrapped/container relation field isn't"
                        " supported as a hand-written struct's own field"
                        " declaration yet"
                    )
                out += ep.name + ": " + rewritten_field_type("@@" + ep.type_name, ctx.plain_struct_names)
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
                    + "' needs 'sqrrl__world' -- open @@: or add"
                    " '@@' to this function's own parameters first"
                )
            out += build_create_call(source, marker_start, c.type_name, c.fields, ctx)
            if pending_decl:
                ctx.entity_to_type[pending_decl.value()] = c.type_name
            pending_decl = None
            pending_for_loop_decl = None

        elif kind == MarkerKind.FOR_ENTITY_LOOP:
            var name = sc.parse_for_entity_loop()
            out += sqrrl_prefixed(name) + " in "
            pending_decl = None
            pending_for_loop_decl = Optional[String](name)

        elif kind == MarkerKind.FIELD_ACCESS:
            handle_field_access(sc, source, marker_start, ctx, pending_decl, pending_for_loop_decl, out)

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
    splits it there and inserts `finally: sqrrl__world.sqrrl__check_no_leaks()`."""
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
        + "    sqrrl__world.sqrrl__check_no_leaks()\n"
        + after
    )
