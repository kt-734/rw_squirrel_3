from squirrel_compiler.parser.ast import Field, FieldModifier
from squirrel_compiler.parser.text_utils import is_ident_char, source_location
from squirrel_compiler.parser.relation_type_text import is_directly_entity_reachable
from squirrel_compiler.parser.scanner import Scanner
from squirrel_compiler.parser.type_expr import parse_type_expr


def _body_err(full_source: String, body_start: Int, local_pos: Int, msg: String) -> Error:
    """`Scanner.err()`'s own `source_location(self.source, self.pos)`
    computation, but for a `Scanner(body)` built from an already-
    extracted substring (`parse_struct_body`/`parse_hand_written_struct_
    fields`, both scanning a struct's own isolated body text, not the
    real file) -- `bs.err(...)` there would report "line 1" of the
    *substring* for every single field, no matter where the struct is
    actually declared in the real file. Confirmed via a real compile: a
    marking-mismatch error on a struct declared starting at line 40
    reported "1:36" instead of the real location. `body_start` (the
    substring's own absolute byte offset within `full_source`, captured
    by the caller right after `scan_indented_block` returns) plus the
    scanner's own substring-relative `pos` gives the real, file-relative
    offset `source_location` needs."""
    return Error(source_location(full_source, body_start + local_pos) + ": " + msg)


def _capture_method_body_suffix(
    bs: Scanner, body: String, body_start: Int, mut method_body_start_offset: Int
) -> Optional[String]:
    """Shared by `parse_struct_body`/`parse_hand_written_struct_fields`:
    both stop scanning fields the moment a line looks like a method
    definition (`def name(...):`/`fn name(...):`), walk back to that
    line's own start (a modifier keyword or the field type itself could
    still be mid-line at `bs.pos`), and return everything from there to
    the end of `body` as the method text to splice/discover separately.
    `None` when `bs.pos` isn't at such a line at all -- the two callers
    keep scanning fields in that case."""
    if not (
        (bs.starts_with("def") and not is_ident_char(bs.peek_at(3)))
        or (bs.starts_with("fn") and not is_ident_char(bs.peek_at(2)))
    ):
        return None
    var line_start = bs.pos
    var body_bytes = body.as_bytes()
    while line_start > 0 and body_bytes[line_start - 1] != UInt8(ord("\n")):
        line_start -= 1
    method_body_start_offset = body_start + line_start
    return String(body[byte = line_start : body.byte_length()])


def _check_container_marking(
    name: String, name_is_marked: Bool, type_str: String, full_source: String, body_start: Int, bs_pos: Int
) raises:
    """Shared by `parse_struct_body`/`parse_hand_written_struct_fields`:
    the marking-symmetry rule for a field's own name against its type.
    A container of a relation (`List[@@Employee]`) is always bare now --
    the type itself already says it's a relation, so the field's own
    name no longer needs to repeat that -- unlike a *single* (non-
    container) relation field (`@@dept: @@Department`), which has no
    container wrapper of its own for the type alone to carry that
    signal, and so is still required to match exactly."""
    var type_is_relation = is_directly_entity_reachable(type_str)
    var type_is_container = parse_type_expr(type_str).is_parameterized()
    if type_is_relation and type_is_container:
        if name_is_marked:
            raise _body_err(full_source, body_start, bs_pos,
                "InvalidSquirrelSyntax: '@@" + name + "' -- '@@'"
                " marking on a container field's own name is no"
                " longer used or needed (the type itself, '"
                + type_str + "', already says so); write it bare: '"
                + name + ": " + type_str + "'"
            )
    elif name_is_marked != type_is_relation:
        raise _body_err(full_source, body_start, bs_pos,
            "InvalidSquirrelSyntax: @@ marking must match between field"
            " name and type"
        )


def parse_struct_body(
    body: String,
    full_source: String,
    body_start: Int,
    mut fields: List[Field],
    mut method_body_start_offset: Int,
    mut key_groups: List[List[String]],
) raises -> String:
    """Splits an `@@struct` body into `name: Type` fields, up to whatever
    point a line looks like a method definition (`def name(...):`/`fn
    name(...):`, ordinary Mojo syntax) instead of a field -- captured and
    returned (not discarded) so codegen can splice it into the generated
    entity wrapper's body once M3 lands. Returns an empty string when the
    struct declares no methods at all.

    Adapted from rw_squirrel_2: the modifier-keyword set is `unique`/
    `indexed`/`multi`/`ordered` (was `unique`/`forwardonly`/`multi`/
    `ordered`) -- see `FieldModifier`'s own doc comment for why.

    A `key(field1, field2, ...)` line is recognized separately, *before*
    the modifier-keyword loop below -- it isn't a field declaration at all
    (no name/type/modifier of its own), just a list of *other* fields'
    names, so it can't fall through into the same name/`:`/type grammar
    every field line uses. Each one appends a fresh `List[String]` to
    `key_groups` (the out-param, accumulated across every `key(...)` line
    in this body -- a struct with several gets one independent entry per
    line, in declaration order) and `continue`s straight back to the top
    of the outer loop. Field-name validation against `fields` (do these
    names actually exist, no duplicates within one group, no two groups
    with an identical field set) is deferred to `Scanner.parse_struct`,
    once every field has actually been parsed -- a `key(...)` line may
    itself appear before the fields it names.

    `full_source`/`body_start` are for error-location reporting only
    (`_body_err`, above) -- `bs` itself still scans the isolated `body`
    substring, not `full_source`, deliberately: bounding a malformed
    field's own scan (an unterminated `[`, say) to the struct's own body
    means it still fails fast and locally, rather than scanning off into
    unrelated, unbounded file content looking for a stray closing
    bracket somewhere else entirely.

    `method_body_start_offset` (out-param, only ever set when methods are
    found below) is the real file's own absolute *byte offset* where the
    returned method-body text starts -- `codegen/methods.mojo`'s own
    `rewrite_method_body` re-scans that text through a *separate*,
    freshly-constructed `Scanner`, on its own with no `full_source`/
    `body_start` of its own to correct against, so any error raised
    while rewriting a method's body (the single most common error
    surface in the whole compiler -- marking mismatches, undefined
    entities, bad chains) needs this to translate its own reported
    line:col back to reality instead of reporting "line 1 of the method
    text"."""
    var bs = Scanner(body)
    while True:
        bs.skip_trivia()
        if bs.at_end():
            return String()

        var method_suffix = _capture_method_body_suffix(bs, body, body_start, method_body_start_offset)
        if method_suffix:
            return method_suffix.value()

        if bs.starts_with("pass") and not is_ident_char(bs.peek_at(4)):
            # A bare `pass` -- the real Mojo/Python convention for "this
            # block is intentionally empty." A genuinely empty body (zero
            # lines at all) already parses fine with no error at all (the
            # `bs.at_end()` check above returns first) -- `pass` support
            # exists purely for the common instinct of writing it
            # explicitly, most useful on a struct-inheritance target
            # (`@@struct @@Name < @@Other: pass`) that adds nothing of its
            # own beyond the inherited fields. Only legal as the *entire*
            # body -- anything else following it (another field, another
            # `pass`) is rejected rather than silently ignored.
            bs.pos += 4
            bs.skip_trivia()
            if not bs.at_end():
                raise _body_err(full_source, body_start, bs.pos,
                    "InvalidSquirrelSyntax: 'pass' must be the only content"
                    " in a struct body -- found more after it"
                )
            return String()

        if bs.starts_with("key") and not is_ident_char(bs.peek_at(3)):
            bs.pos += 3
            bs.skip_trivia()
            if not bs.try_consume("("):
                raise _body_err(full_source, body_start, bs.pos,
                    "InvalidSquirrelSyntax: expected '(' after 'key'"
                )
            var group = List[String]()
            bs.skip_trivia()
            if not bs.try_consume(")"):
                while True:
                    bs.skip_trivia()
                    var field_name = bs.scan_ident()
                    if field_name.byte_length() == 0:
                        raise _body_err(full_source, body_start, bs.pos,
                            "InvalidSquirrelSyntax: expected a field name in"
                            " 'key(...)'"
                        )
                    group.append(field_name)
                    bs.skip_trivia()
                    if bs.try_consume(","):
                        continue
                    if bs.try_consume(")"):
                        break
                    raise _body_err(full_source, body_start, bs.pos,
                        "InvalidSquirrelSyntax: expected ',' or ')' in"
                        " 'key(...)'"
                    )
            if len(group) == 0:
                raise _body_err(full_source, body_start, bs.pos,
                    "InvalidSquirrelSyntax: 'key()' needs at least one field"
                    " name"
                )
            key_groups.append(group^)
            _ = bs.try_consume(",")
            continue

        var modifier = FieldModifier.NONE
        var modifier_keyword = String()
        var is_stats = False
        while True:
            if bs.starts_with("stats") and not is_ident_char(bs.peek_at(5)):
                is_stats = True
                bs.pos += 5
                bs.skip_trivia()
                continue
            var next_keyword: String
            var next_modifier: FieldModifier
            if bs.starts_with("unique") and not is_ident_char(bs.peek_at(6)):
                next_keyword = "unique"
                next_modifier = FieldModifier.UNIQUE
            elif bs.starts_with("indexed") and not is_ident_char(bs.peek_at(7)):
                next_keyword = "indexed"
                next_modifier = FieldModifier.INDEXED
            elif bs.starts_with("multi") and not is_ident_char(bs.peek_at(5)):
                next_keyword = "multi"
                next_modifier = FieldModifier.MULTI
            elif bs.starts_with("ordered") and not is_ident_char(bs.peek_at(7)):
                next_keyword = "ordered"
                next_modifier = FieldModifier.ORDERED
            else:
                break
            if modifier != FieldModifier.NONE:
                raise _body_err(full_source, body_start, bs.pos,
                    "InvalidSquirrelSyntax: a field can't be both '"
                    + modifier_keyword
                    + "' and '"
                    + next_keyword
                    + "' -- each selects its own, mutually exclusive storage"
                    " shape"
                )
            modifier = next_modifier
            modifier_keyword = next_keyword
            bs.pos += next_keyword.byte_length()
            bs.skip_trivia()

        var name_is_marked = bs.try_consume("@@")
        var name = bs.scan_ident()
        if name.byte_length() == 0:
            raise _body_err(full_source, body_start, bs.pos,"InvalidSquirrelSyntax: expected field name")

        for existing in fields:
            if existing.name == name:
                raise _body_err(full_source, body_start, bs.pos,"DuplicateFieldName: " + name)

        bs.skip_trivia()
        if not bs.try_consume(":"):
            raise _body_err(full_source, body_start, bs.pos,"InvalidSquirrelSyntax: expected ':' after field name")
        bs.skip_trivia()

        var type_str = bs.scan_type()
        if type_str.byte_length() == 0:
            raise _body_err(full_source, body_start, bs.pos,"InvalidSquirrelSyntax: empty field type")

        _check_container_marking(name, name_is_marked, type_str, full_source, body_start, bs.pos)
        fields.append(
            Field(
                name=name,
                type_str=type_str,
                modifier=modifier,
                is_stats=is_stats,
            )
        )
        _ = bs.try_consume(",")


def parse_hand_written_struct_fields(
    body: String, full_source: String, body_start: Int, mut fields: List[Field], mut method_body_start_offset: Int
) raises -> String:
    """Extracts a hand-written (plain-structs milestone) struct's own `var
    name: Type`/`var @@name: @@Type` field declarations from `body`
    (already isolated via `Scanner.scan_indented_block`, same as `parse_
    struct_body`'s own caller), stopping at the first `def`/`fn` -- methods
    are real, hand-written Mojo, never rewritten *in place*, but their own
    raw text (from that first `def`/`fn` line onward) is captured and
    returned regardless -- mirrors `parse_struct_body`'s own identical
    return-the-suffix behavior exactly, so a plain struct's own methods can
    be discovered (bare return-type text via `codegen/methods.mojo`'s
    `bare_method_returns`, reused as-is) the same way an `@@struct`'s own
    already are, letting a chain continue off a plain struct's own bare
    method call (`addr2.get_extra().@@dept.name`) instead of the
    "always a direct, untracked passthrough" fallback that's still correct
    for anything this discovery pass doesn't find.

    Unlike `parse_struct_body`, no modifier keywords are ever recognized:
    `unique`/`indexed`/`multi`/`ordered`/`stats` are backward-index
    concepts with no meaning outside a generated `@@struct`'s own table, so
    every extracted field's `modifier` is `FieldModifier.NONE`/`is_stats`
    is `False` unconditionally. A relation-shaped field's own type
    (`@@Employee`) is recorded in the same pseudo-shorthand `.mojo.sqrrl`-
    declared fields already use -- no `recover_relation_type_str`-style
    inference needed (unlike rw_squirrel_2), since the marking is already
    explicit in the source. `Self.<Param>` (Mojo's own required spelling
    for a generic struct's own field referencing its own type parameter)
    is unqualified back to bare `<Param>` here, once, since every
    downstream consumer of this field list (relation-schema, JSON's
    generated `from_json` companion) is a *free function*, where `Self`
    doesn't exist at all.

    `full_source`/`body_start`: same as `parse_struct_body`'s own --
    error-location reporting only (`_body_err`), scanning itself still
    bounded to `body`. `method_body_start_offset` is likewise set (same
    as `parse_struct_body`'s own) but never consulted by this function's
    own caller today -- a hand-written plain struct's methods are never
    re-scanned by `rewrite_method_body` the way an `@@struct`'s own are
    (they're real, hand-written Mojo, left in place) -- kept as a real
    out-param anyway so both functions share `_capture_method_body_
    suffix` instead of duplicating it."""
    var bs = Scanner(body)
    while True:
        bs.skip_trivia()
        if bs.at_end():
            return String()
        var method_suffix = _capture_method_body_suffix(bs, body, body_start, method_body_start_offset)
        if method_suffix:
            return method_suffix.value()
        if not (bs.starts_with("var") and not is_ident_char(bs.peek_at(3))):
            raise _body_err(full_source, body_start, bs.pos,
                "InvalidSquirrelSyntax: expected a 'var name: Type' field"
                " declaration in this hand-written struct"
            )
        bs.pos += 3
        bs.skip_trivia()
        var name_is_marked = bs.try_consume("@@")
        var name = bs.scan_ident()
        if name.byte_length() == 0:
            raise _body_err(full_source, body_start, bs.pos,"InvalidSquirrelSyntax: expected field name")
        for existing in fields:
            if existing.name == name:
                raise _body_err(full_source, body_start, bs.pos,"DuplicateFieldName: " + name)
        bs.skip_trivia()
        if not bs.try_consume(":"):
            raise _body_err(full_source, body_start, bs.pos,"InvalidSquirrelSyntax: expected ':' after field name")
        bs.skip_trivia()
        var type_str = bs.scan_type()
        if type_str.byte_length() == 0:
            raise _body_err(full_source, body_start, bs.pos,"InvalidSquirrelSyntax: empty field type")
        if type_str.startswith("Self."):
            type_str = String(type_str[byte=5 : type_str.byte_length()])
        _check_container_marking(name, name_is_marked, type_str, full_source, body_start, bs.pos)
        fields.append(Field(name=name, type_str=type_str, modifier=FieldModifier.NONE, is_stats=False))
