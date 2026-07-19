from squirrel_compiler.parser.ast import Field, FieldModifier
from squirrel_compiler.parser.text_utils import is_ident_char
from squirrel_compiler.parser.relation_type_text import is_directly_entity_reachable
from squirrel_compiler.parser.scanner import Scanner


def parse_struct_body(body: String, mut fields: List[Field]) raises -> String:
    """Splits an `@@struct` body into `name: Type` fields, up to whatever
    point a line looks like a method definition (`def name(...):`/`fn
    name(...):`, ordinary Mojo syntax) instead of a field -- captured and
    returned (not discarded) so codegen can splice it into the generated
    entity wrapper's body once M3 lands. Returns an empty string when the
    struct declares no methods at all.

    Adapted from rw_squirrel_2: the modifier-keyword set is `unique`/
    `indexed`/`multi`/`ordered` (was `unique`/`forwardonly`/`multi`/
    `ordered`) -- see `FieldModifier`'s own doc comment for why."""
    var bs = Scanner(body)
    while True:
        bs.skip_trivia()
        if bs.at_end():
            return String()

        if (bs.starts_with("def") and not is_ident_char(bs.peek_at(3))) or (
            bs.starts_with("fn") and not is_ident_char(bs.peek_at(2))
        ):
            var line_start = bs.pos
            var body_bytes = body.as_bytes()
            while line_start > 0 and body_bytes[line_start - 1] != UInt8(ord("\n")):
                line_start -= 1
            return String(body[byte = line_start : body.byte_length()])

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
                raise bs.err(
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
            raise bs.err("InvalidSquirrelSyntax: expected field name")

        for existing in fields:
            if existing.name == name:
                raise bs.err("DuplicateFieldName: " + name)

        bs.skip_trivia()
        if not bs.try_consume(":"):
            raise bs.err("InvalidSquirrelSyntax: expected ':' after field name")
        bs.skip_trivia()

        var type_str = bs.scan_type()
        if type_str.byte_length() == 0:
            raise bs.err("InvalidSquirrelSyntax: empty field type")

        var type_is_relation = is_directly_entity_reachable(type_str)
        if name_is_marked != type_is_relation:
            raise bs.err(
                "InvalidSquirrelSyntax: @@ marking must match between field"
                " name and type"
            )
        fields.append(
            Field(
                name=name,
                type_str=type_str,
                modifier=modifier,
                is_stats=is_stats,
            )
        )
        _ = bs.try_consume(",")


def parse_hand_written_struct_fields(body: String, mut fields: List[Field]) raises:
    """Extracts a hand-written (plain-structs milestone) struct's own `var
    name: Type`/`var @@name: @@Type` field declarations from `body`
    (already isolated via `Scanner.scan_indented_block`, same as `parse_
    struct_body`'s own caller), stopping at the first `def`/`fn` -- methods
    are real, hand-written Mojo, never rewritten, so there's nothing
    further for this read-only structural pass to extract.

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
    doesn't exist at all."""
    var bs = Scanner(body)
    while True:
        bs.skip_trivia()
        if bs.at_end():
            return
        if (bs.starts_with("def") and not is_ident_char(bs.peek_at(3))) or (
            bs.starts_with("fn") and not is_ident_char(bs.peek_at(2))
        ):
            return
        if not (bs.starts_with("var") and not is_ident_char(bs.peek_at(3))):
            raise bs.err(
                "InvalidSquirrelSyntax: expected a 'var name: Type' field"
                " declaration in this hand-written struct"
            )
        bs.pos += 3
        bs.skip_trivia()
        var name_is_marked = bs.try_consume("@@")
        var name = bs.scan_ident()
        if name.byte_length() == 0:
            raise bs.err("InvalidSquirrelSyntax: expected field name")
        for existing in fields:
            if existing.name == name:
                raise bs.err("DuplicateFieldName: " + name)
        bs.skip_trivia()
        if not bs.try_consume(":"):
            raise bs.err("InvalidSquirrelSyntax: expected ':' after field name")
        bs.skip_trivia()
        var type_str = bs.scan_type()
        if type_str.byte_length() == 0:
            raise bs.err("InvalidSquirrelSyntax: empty field type")
        if type_str.startswith("Self."):
            type_str = String(type_str[byte=5 : type_str.byte_length()])
        var type_is_relation = is_directly_entity_reachable(type_str)
        if name_is_marked != type_is_relation:
            raise bs.err(
                "InvalidSquirrelSyntax: @@ marking must match between field"
                " name and type"
            )
        fields.append(Field(name=name, type_str=type_str, modifier=FieldModifier.NONE, is_stats=False))
