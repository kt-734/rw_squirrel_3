from squirrel_compiler.parser import is_ident_char, source_location, ConstructField, parse_type_expr
from squirrel_compiler.codegen.helpers import (
    is_container_type,
    container_wrapper_of,
    container_element_of,
    param_name_for_construct_field,
)
from squirrel_compiler.codegen.rewrite_context import RewriteContext


def line_start_of(source: String, pos: Int) -> Int:
    var bytes = source.as_bytes()
    var line_start = pos
    while line_start > 0 and bytes[line_start - 1] != UInt8(ord("\n")):
        line_start -= 1
    return line_start


def indent_of(source: String, pos: Int) -> String:
    """The leading whitespace of the line containing `pos` -- `@@:`'s own
    indentation, used to close the `try:` it opens with a `finally:` at
    the same level again once its indented block ends."""
    var line_start = line_start_of(source, pos)
    var bytes = source.as_bytes()
    var indent_end = line_start
    while indent_end < pos and (
        bytes[indent_end] == UInt8(ord(" ")) or bytes[indent_end] == UInt8(ord("\t"))
    ):
        indent_end += 1
    return String(source[byte = line_start : indent_end])


def is_in_def_signature(source: String, pos: Int) -> Bool:
    """True if byte offset `pos` sits on a line that starts (after
    indentation) with `def `."""
    var line_start = line_start_of(source, pos)
    var bytes = source.as_bytes()
    var indent_end = line_start
    while indent_end < pos and (
        bytes[indent_end] == UInt8(ord(" ")) or bytes[indent_end] == UInt8(ord("\t"))
    ):
        indent_end += 1
    return String(source[byte = indent_end : pos]).startswith("def ")


def is_in_import_statement(source: String, pos: Int) -> Bool:
    var line_start = line_start_of(source, pos)
    var bytes = source.as_bytes()
    var indent_end = line_start
    while indent_end < pos and (
        bytes[indent_end] == UInt8(ord(" ")) or bytes[indent_end] == UInt8(ord("\t"))
    ):
        indent_end += 1
    var prefix = String(source[byte = indent_end : pos])
    return prefix.startswith("from ") or prefix.startswith("import ")


def crosses_top_level_def(text: String) -> Bool:
    """True if `text` spans a line starting at column 0 with `def ` -- i.e.
    it crosses into a new top-level function body. `rewrite_markers` uses
    this to reset its per-function bookkeeping at each such boundary."""
    if text.startswith("def "):
        return True
    return "\ndef " in text


def is_unmarked_var_target(source: String, pos: Int) -> Bool:
    """True if, scanning backward from byte offset `pos`, the immediately
    preceding text matches `var IDENT = ` where `IDENT` is *not*
    `@@`-marked -- i.e. `pos` is the start of the right-hand side of a
    plain, unmarked variable declaration."""
    var bytes = source.as_bytes()
    var i = pos
    while i > 0 and (bytes[i - 1] == UInt8(ord(" ")) or bytes[i - 1] == UInt8(ord("\t"))):
        i -= 1
    if i == 0 or bytes[i - 1] != UInt8(ord("=")):
        return False
    if i >= 2 and bytes[i - 2] == UInt8(ord("=")):
        return False  # "==" isn't an assignment
    i -= 1
    while i > 0 and (bytes[i - 1] == UInt8(ord(" ")) or bytes[i - 1] == UInt8(ord("\t"))):
        i -= 1
    var ident_end = i
    while i > 0 and is_ident_char(bytes[i - 1]):
        i -= 1
    if i == ident_end:
        return False
    if i >= 2 and bytes[i - 1] == UInt8(ord("@")) and bytes[i - 2] == UInt8(ord("@")):
        return False  # marked -- the existing pending_decl path covers this
    while i > 0 and (bytes[i - 1] == UInt8(ord(" ")) or bytes[i - 1] == UInt8(ord("\t"))):
        i -= 1
    return i >= 3 and String(source[byte = i - 3 : i]) == "var"


def enforce_entity_binding(
    source: String,
    marker_start: Int,
    pending_decl: Optional[String],
    mut entity_to_type: Dict[String, String],
    registered_type: String,
    call_text: String,
) raises:
    """Shared by every call that returns a single entity or a container of
    them: binding it to a `var @@x = ...` declaration tracks
    `registered_type` in `entity_to_type`; binding it to a plain, unmarked
    variable instead is rejected with a clear, container-aware error.

    `is_unmarked_var_target` (a purely textual check, independent of
    `pending_decl`) is checked *first*, unconditionally -- not `elif`,
    the way it read when `pending_decl` being `Some` implied "the target
    must be `@@`-marked" by construction (true as long as only a marked
    `var @@x = ...` ever set it). `BARE_VAR_DECL_OVER_ENTITY` (`var
    <bare_name> = @@...:`) broke that assumption on purpose, to register
    a bare local reading a *plain* value off a marked chain (`var h =
    @@bob.home`) -- but it sets `pending_decl` before the scanner even
    knows whether the chain's *terminal* step turns out to be entity-
    shaped or plain, so `pending_decl` alone can no longer prove the
    target was marked. Checking the target's own marking directly first
    closes the gap this order would otherwise reopen: confirmed via a
    real compile that `var h = @@bob.@@dept` (a bare var holding a real
    entity relation) was silently accepted and compiled to `var h =
    sqrrl__bob._inner[]._sqrrl__dept` -- exactly the mandatory-marking
    violation this function exists to catch, bypassed entirely by the
    old order."""
    if is_unmarked_var_target(source, marker_start):
        raise Error(
            source_location(source, marker_start)
            + ": InvalidSquirrelSyntax: '@@"
            + call_text
            + "' returns "
            + (
                "'"
                + container_wrapper_of(registered_type)
                + "[@@"
                + container_element_of(registered_type)
                + "]'" if is_container_type(registered_type) else "'@@" + registered_type + "'"
            )
            + " -- bind it to an '@@'-marked variable"
            " ('var @@x = @@"
            + call_text
            + ";'), not a plain one"
        )
    if pending_decl:
        entity_to_type[pending_decl.value()] = registered_type


def _is_bare_identifier(s: String) -> Bool:
    """True if `s` (a construct-field's own already-*rewritten* value
    text) is a single bare identifier -- a named local variable
    reference, the only shape that actually needs (and permits) an
    explicit `^` to move. A fresh rvalue (a constructor call, a list/dict
    literal, ...) is already a temporary Mojo moves from automatically --
    `^` on one isn't the harmless no-op an earlier version of this
    function's own comment assumed; confirmed via a real compile, Mojo
    rejects it outright ("expression does not live in a memory location,
    so it need not be transferred"). Every existing example's own usage
    happened to only ever exercise the named-variable case for a plain-
    struct field (`var addr = Address(...); .home = addr`) and the fresh-
    literal case for a relation/multi field (`.@@members = [@@a, @@b]`),
    which is exactly why this distinction was never forced into the open
    before now."""
    if s.byte_length() == 0:
        return False
    # `None`/`True`/`False` are identifier-shaped text but Mojo literals,
    # not a named binding with anywhere to move *from* -- `^` on one is
    # rejected the same way as on a fresh rvalue ("cannot transfer from a
    # parameter expression"), confirmed via a real compile once a
    # `Optional`-wrapped relation field's own construction-site value
    # (`.@@advisor = None`) exercised this for the first time.
    if s == "None" or s == "True" or s == "False":
        return False
    var bytes = s.as_bytes()
    var first = bytes[0]
    if not (
        (first >= UInt8(ord("a")) and first <= UInt8(ord("z")))
        or (first >= UInt8(ord("A")) and first <= UInt8(ord("Z")))
        or first == UInt8(ord("_"))
    ):
        return False
    for i in range(len(bytes)):
        if not is_ident_char(bytes[i]):
            return False
    return True


def build_create_call(
    source: String,
    marker_start: Int,
    type_name: String,
    fields: List[ConstructField],
    mut ctx: RewriteContext,
) raises -> String:
    """Builds `sqrrl___world.TypeName.create(name = value, ...)`, validating
    each field's `@@` marking against `relation_schema[type_name]` and
    recursively rewriting every field's value through `rewrite_markers`.
    `create` still lives on the table (point 6 of the plan -- no existing
    entity to hang the call off of yet), so this branch is unaffected by
    the storage redesign."""
    from squirrel_compiler.codegen.rewrite import rewrite_markers

    var type_relations = (
        ctx.relation_schema[type_name].copy() if type_name in ctx.relation_schema else Dict[String, String]()
    )
    var type_plain_values = (
        ctx.plain_value_fields[type_name].copy() if type_name in ctx.plain_value_fields else Dict[String, String]()
    )
    var args = String()
    var first = True
    for f in fields:
        var declared_as_relation = f.name in type_relations
        # A container-of-entity relation field (`members: List[@@Employee]`)
        # is always bare now (Part 2, mandatory marking dropped) -- the
        # type alone already says it's a relation, so a construct call's
        # own `.members = ...` keyword is never marked either, unlike a
        # *single* relation field (`@@dept: @@Department`), unaffected,
        # still always marked both at declaration and here.
        var declared_as_container_relation = declared_as_relation and is_container_type(type_relations[f.name])
        if f.is_relation and not declared_as_relation:
            raise Error(
                source_location(source, marker_start)
                + ": InvalidSquirrelSyntax: '"
                + type_name
                + "."
                + f.name
                + "' isn't declared as a relation field -- use '."
                + f.name
                + "' here, not '.@@"
                + f.name
                + "'"
            )
        if declared_as_container_relation and f.is_relation:
            raise Error(
                source_location(source, marker_start)
                + ": InvalidSquirrelSyntax: '"
                + type_name
                + "."
                + f.name
                + "' -- '@@' marking on a container relation field's own"
                " name is no longer used or needed (the field's type"
                " already says so); write '."
                + f.name
                + "' here (no '@@')"
            )
        if not declared_as_container_relation and not f.is_relation and declared_as_relation:
            raise Error(
                source_location(source, marker_start)
                + ": InvalidSquirrelSyntax: '"
                + type_name
                + "."
                + f.name
                + "' is declared as a relation field (`@@"
                + f.name
                + ": @@...`) -- must be written '.@@"
                + f.name
                + "' here too"
            )
        var value = rewrite_markers(f.value, ctx)
        var needs_move = False
        if f.name in type_plain_values:
            var pt = type_plain_values[f.name]
            needs_move = is_container_type(pt) or parse_type_expr(pt).name in ctx.plain_struct_names
        elif f.name in type_relations:
            # A wrapped relation (`@@members: List[@@Employee]`/`Dict[
            # @@Employee, String]`) is stored `@@`-stripped but still
            # bracket-shaped (`render_relation_stripped`) -- container-
            # shaped either way, same non-`ImplicitlyCopyable` reasoning
            # as the plain-value case below applies here too. A *bare*
            # relation (`Employee`, no brackets) never matches, correctly
            # -- `sqrrl__Employee` is always `ImplicitlyCopyable`.
            needs_move = is_container_type(type_relations[f.name])
        if needs_move and _is_bare_identifier(value):
            # Neither a hand-written plain struct nor any container type
            # (`List`/`Set`/`Optional`/`Dict`/a custom wrapper) is
            # guaranteed `ImplicitlyCopyable` (same reason entity.mojo/
            # table.mojo's own create()/set_<field> need `var`+`^` for
            # one) -- but `^` only applies to a *named* value (`_is_bare_
            # identifier`); a fresh rvalue (`Address(...)`/`[@@a, @@b]`)
            # is already a temporary Mojo moves from automatically, and
            # explicitly `^`-ing one is rejected outright, not a harmless
            # no-op (confirmed via a real compile -- an earlier version of
            # this comment assumed otherwise). Every other plain (non-
            # relation, non-container) field -- an ordinary leaf like
            # `name: String` -- stays untouched either way, since those
            # are always `ImplicitlyCopyable` and a bare value already
            # compiles regardless of which shape it is.
            value += "^"
        if not first:
            args += ", "
        # `declared_as_relation` (the schema's own truth), not `f.is_
        # relation` (the call site's own spelling) -- a container relation
        # is unmarked at the call site now but still needs the relation's
        # own storage-param convention, same `is_relation`-not-`step.
        # marked` fix `_walk_access_chain` needed for the read side.
        args += param_name_for_construct_field(f.name, declared_as_relation) + " = " + value
        first = False
    return String("sqrrl___world." + type_name + ".create(" + args + ")")
