from squirrel_compiler.parser.ast import (
    Field,
    TypeParam,
    ParsedStruct,
    ConstructField,
    Construct,
    AccessStep,
    FieldAccess,
    NameRef,
    EntityParam,
    MarkerKind,
)
from squirrel_compiler.parser.text_utils import (
    is_ident_char,
    source_location,
    line_indent_of,
    is_after_arrow,
    is_after_for_keyword,
    is_after_container_bracket,
    find_end_of_indented_block,
)
from squirrel_compiler.parser.field_parsing import parse_struct_body, parse_hand_written_struct_fields


def parse_construct_fields(body: String) raises -> List[ConstructField]:
    """Splits a construct's braced body into `.name = value` /
    `.@@name = value` segments, each becoming a `ConstructField`.

    Verbatim port from rw_squirrel_2."""
    var bs = Scanner(body)
    var out = List[ConstructField]()
    while True:
        bs.skip_trivia()
        if bs.at_end():
            break
        if not bs.try_consume("."):
            raise bs.err(
                "InvalidSquirrelSyntax: expected '.' before field name in"
                " construct"
            )
        var is_relation = bs.try_consume("@@")
        var name = bs.scan_ident()
        if name.byte_length() == 0:
            raise bs.err("InvalidSquirrelSyntax: expected field name in construct")
        bs.skip_trivia()
        if not bs.try_consume("="):
            raise bs.err(
                "InvalidSquirrelSyntax: expected '=' after field name in"
                " construct"
            )
        bs.skip_whitespace()
        var value_start = bs.pos
        var depth = 0
        while not bs.at_end():
            var before = bs.pos
            bs.skip_non_code()
            if bs.pos != before:
                continue
            var b = bs.peek()
            if b == UInt8(ord("(")) or b == UInt8(ord("[")) or b == UInt8(ord("{")):
                depth += 1
            elif b == UInt8(ord(")")) or b == UInt8(ord("]")) or b == UInt8(ord("}")):
                depth -= 1
            elif b == UInt8(ord(",")) and depth == 0:
                break
            bs.pos += 1
        var value = String(body[byte = value_start : bs.pos]).strip()
        out.append(ConstructField(name=name, is_relation=is_relation, value=String(value)))
        _ = bs.try_consume(",")
    return out^


struct Scanner(Movable):
    """A cursor over `.mojo.sqrrl` source text. Every scanning/skipping
    operation routes through `skip_non_code` so a `{`, `}`, `,`, or `@@`
    sitting inside a `#`/`//` comment or a `"`/`'` string literal never
    desyncs anything.

    Adapted from rw_squirrel_2's own `Scanner`: DSL-syntax scanning itself
    is unaffected by the storage redesign, so this is a close port, minus
    the marker kinds/grammar M1 defers (JSON reload, plain structs, plain
    `var` declarations -- see the plan's Milestones section and
    `MarkerKind`'s own doc comment)."""

    var source: String
    var pos: Int

    def __init__(out self, var source: String):
        self.source = source^
        self.pos = 0

    def err(self, msg: String) -> Error:
        return Error(source_location(self.source, self.pos) + ": " + msg)

    def at_end(self) -> Bool:
        return self.pos >= self.source.byte_length()

    def byte_at(self, i: Int) -> UInt8:
        return self.source.as_bytes()[i]

    def peek(self) -> UInt8:
        if self.at_end():
            return 0
        return self.byte_at(self.pos)

    def peek_at(self, offset: Int) -> UInt8:
        var i = self.pos + offset
        if i >= self.source.byte_length():
            return 0
        return self.byte_at(i)

    def starts_with(self, literal: String) -> Bool:
        var end = self.pos + literal.byte_length()
        if end > self.source.byte_length():
            return False
        return self.source[byte = self.pos : end] == literal

    def try_consume(mut self, literal: String) -> Bool:
        if self.starts_with(literal):
            self.pos += literal.byte_length()
            return True
        return False

    def skip_whitespace(mut self):
        while not self.at_end():
            var b = self.peek()
            if (
                b == UInt8(ord(" "))
                or b == UInt8(ord("\t"))
                or b == UInt8(ord("\n"))
                or b == UInt8(ord("\r"))
            ):
                self.pos += 1
            else:
                break

    def skip_non_code(mut self):
        """If positioned at a `#`/`//` line comment or a `"`/`'` string
        literal, advances past it. No-op otherwise."""
        if self.at_end():
            return
        if self.peek() == UInt8(ord("#")) or (
            self.peek() == UInt8(ord("/")) and self.peek_at(1) == UInt8(ord("/"))
        ):
            while not self.at_end() and self.peek() != UInt8(ord("\n")):
                self.pos += 1
            return
        if self.peek() == UInt8(ord('"')) or self.peek() == UInt8(ord("'")):
            var quote = self.peek()
            self.pos += 1
            while not self.at_end() and self.peek() != quote:
                if self.peek() == UInt8(ord("\\")) and not self.at_end():
                    self.pos += 1
                self.pos += 1
            if not self.at_end():
                self.pos += 1  # consume closing quote

    def skip_same_line_whitespace(mut self):
        """Like `skip_whitespace`, but stops at (without consuming) a
        newline instead of crossing it."""
        while not self.at_end():
            var b = self.peek()
            if b == UInt8(ord(" ")) or b == UInt8(ord("\t")) or b == UInt8(ord("\r")):
                self.pos += 1
            else:
                break

    def skip_same_line_trivia(mut self):
        while True:
            var before = self.pos
            self.skip_same_line_whitespace()
            self.skip_non_code()
            if self.pos == before:
                return

    def skip_trivia(mut self):
        while True:
            var before = self.pos
            self.skip_whitespace()
            self.skip_non_code()
            if self.pos == before:
                return

    def scan_ident(mut self) -> String:
        var start = self.pos
        while not self.at_end() and is_ident_char(self.peek()):
            self.pos += 1
        return String(self.source[byte = start : self.pos])

    def scan_braced_span(mut self) raises -> String:
        """Requires `self.pos` at `{`. Returns the body between the matching
        braces (exclusive), and advances `self.pos` past the closing `}`."""
        if self.peek() != UInt8(ord("{")):
            raise self.err("InvalidSquirrelSyntax: expected '{'")
        self.pos += 1
        var body_start = self.pos
        var depth = 1
        while not self.at_end() and depth > 0:
            var before = self.pos
            self.skip_non_code()
            if self.pos != before:
                continue
            var b = self.peek()
            if b == UInt8(ord("{")):
                depth += 1
            elif b == UInt8(ord("}")):
                depth -= 1
            self.pos += 1
        if depth != 0:
            raise self.err("InvalidSquirrelSyntax: unterminated '{'")
        return String(self.source[byte = body_start : self.pos - 1])

    def scan_indented_block(mut self, header_indent: Int) -> String:
        """Requires `self.pos` right after a block header's own trailing
        `:` (e.g. `@@struct @@Name:`). Consumes the rest of the header line
        plus every following line that's blank or indented more than
        `header_indent`, matching Python/Mojo's own indentation-block
        convention."""
        while not self.at_end() and self.peek() != UInt8(ord("\n")):
            self.pos += 1
        if not self.at_end():
            self.pos += 1
        var body_start = self.pos
        var bytes = self.source.as_bytes()
        while not self.at_end():
            var line_start = self.pos
            var i = line_start
            while i < len(bytes) and (
                bytes[i] == UInt8(ord(" ")) or bytes[i] == UInt8(ord("\t"))
            ):
                i += 1
            var is_blank = i >= len(bytes) or bytes[i] == UInt8(ord("\n"))
            if not is_blank and (i - line_start) <= header_indent:
                break
            while not self.at_end() and self.peek() != UInt8(ord("\n")):
                self.pos += 1
            if not self.at_end():
                self.pos += 1
        return String(self.source[byte = body_start : self.pos])

    def scan_bracketed_span(mut self) raises -> String:
        """Requires `self.pos` at `[`. Returns the body between the matching
        brackets (exclusive), and advances `self.pos` past the closing `]`
        -- mirrors `scan_braced_span`, for `@@entity[index_expr]`."""
        if self.peek() != UInt8(ord("[")):
            raise self.err("InvalidSquirrelSyntax: expected '['")
        self.pos += 1
        var body_start = self.pos
        var depth = 1
        while not self.at_end() and depth > 0:
            var before = self.pos
            self.skip_non_code()
            if self.pos != before:
                continue
            var b = self.peek()
            if b == UInt8(ord("[")):
                depth += 1
            elif b == UInt8(ord("]")):
                depth -= 1
            self.pos += 1
        if depth != 0:
            raise self.err("InvalidSquirrelSyntax: unterminated '['")
        return String(self.source[byte = body_start : self.pos - 1])

    def scan_type(mut self) -> String:
        """Scans a field's type text: up to the next top-level `,` or `\\n`
        (ignoring either nested inside `[]`/`()`/`{}`) or end of input."""
        var start = self.pos
        var depth = 0
        while not self.at_end():
            var before = self.pos
            self.skip_non_code()
            if self.pos != before:
                continue
            var b = self.peek()
            if b == UInt8(ord("[")) or b == UInt8(ord("(")) or b == UInt8(ord("{")):
                depth += 1
            elif b == UInt8(ord("]")) or b == UInt8(ord(")")) or b == UInt8(ord("}")):
                depth -= 1
            elif b == UInt8(ord(",")) and depth == 0:
                break
            elif b == UInt8(ord("\n")) and depth == 0:
                break
            self.pos += 1
        var raw = String(self.source[byte = start : self.pos])
        return String(raw.strip())

    def parse_trait_list(mut self) raises -> List[String]:
        """Requires `self.pos` at the `(` of an optional `@@struct
        @@Name(Trait1, Trait2, ...):` trait list -- spliced verbatim into
        the generated entity wrapper's own conformance list once M3 lands.
        Trusts the user (never checks the struct actually satisfies any
        listed trait)."""
        if not self.try_consume("("):
            raise self.err("InvalidSquirrelSyntax: expected '(' to start trait list")
        var out = List[String]()
        self.skip_trivia()
        if self.try_consume(")"):
            return out^
        while True:
            self.skip_trivia()
            var name = self.scan_ident()
            if name.byte_length() == 0:
                raise self.err("InvalidSquirrelSyntax: expected trait name in trait list")
            out.append(name)
            self.skip_trivia()
            if self.try_consume(","):
                continue
            if self.try_consume(")"):
                break
            raise self.err("InvalidSquirrelSyntax: expected ',' or ')' in trait list")
        return out^

    def find_next_struct_decl(mut self) -> Bool:
        """Advances to the start of the next `@@struct` occurrence at
        real-code depth. Returns False (leaving `self.pos` at the end) if
        there isn't one."""
        while True:
            self.skip_trivia()
            if self.at_end():
                return False
            if self.starts_with("@@struct"):
                return True
            self.pos += 1

    def at_bare_struct_keyword(self) -> Bool:
        """True if `self.pos` sits at a bare `struct` keyword -- not
        `@@struct` (a DSL-declared entity) and not part of a longer
        identifier on either side (so `structural`/`mystruct` don't
        false-positive). Ported from rw_squirrel_2's own `at_bare_struct_
        keyword` (plain-structs milestone: the only form a plain struct
        may be declared in is real, hand-written Mojo)."""
        if not self.starts_with("struct"):
            return False
        var before_is_ident = self.pos > 0 and is_ident_char(self.byte_at(self.pos - 1))
        var before_is_at = (
            self.pos >= 2
            and self.byte_at(self.pos - 1) == UInt8(ord("@"))
            and self.byte_at(self.pos - 2) == UInt8(ord("@"))
        )
        var after = self.pos + String("struct").byte_length()
        var after_is_ident = after < self.source.byte_length() and is_ident_char(self.byte_at(after))
        return not before_is_ident and not before_is_at and not after_is_ident

    def find_next_hand_written_plain_struct_decl(mut self) -> Bool:
        """Advances to the start of the next bare `struct Name(...):`/
        `struct Name:` occurrence (not `@@struct`) -- a real, hand-written
        Mojo struct, the only form a plain struct may be declared in.
        Returns False (leaving `self.pos` at the end) once there are none
        left."""
        while True:
            self.skip_trivia()
            if self.at_end():
                return False
            if self.at_bare_struct_keyword():
                return True
            self.pos += 1

    def _scan_type_param_bound(mut self) -> String:
        """Like `scan_type`, but for a `[T: Bound, ...]` type-parameter
        list's own bound text specifically -- stops (without consuming) at
        a top-level `,` *or* a top-level closing `]`/`)`/`}`, rather than
        `scan_type`'s `,`/`\\n`. `scan_type` can't be reused here: its own
        depth counter starts at 0 assuming it's scanning a type that owns
        its *own* brackets, so hitting the type-parameter list's closing
        `]` (already owned by the caller, not part of any type this scans)
        would decrement past zero and keep consuming instead of stopping.
        Ported from rw_squirrel_2's own `_scan_type_param_bound`."""
        var start = self.pos
        var depth = 0
        while not self.at_end():
            var before = self.pos
            self.skip_non_code()
            if self.pos != before:
                continue
            var b = self.peek()
            if b == UInt8(ord("[")) or b == UInt8(ord("(")) or b == UInt8(ord("{")):
                depth += 1
            elif b == UInt8(ord("]")) or b == UInt8(ord(")")) or b == UInt8(ord("}")):
                if depth == 0:
                    break
                depth -= 1
            elif b == UInt8(ord(",")) and depth == 0:
                break
            self.pos += 1
        var raw = String(self.source[byte = start : self.pos])
        return String(raw.strip())

    def parse_type_params(mut self) raises -> List[TypeParam]:
        """Requires `self.pos` at `[` -- a hand-written plain struct's own
        `[T: Bound, ...]` type-parameter list, immediately after its name.
        Returns the parsed list, advancing `self.pos` past the closing
        `]`. A parameter with no explicit `: Bound` gets `"Copyable &
        Movable & ImplicitlyDeletable"` -- see `TypeParam`'s own doc
        comment. Ported from rw_squirrel_2's own `parse_type_params`."""
        if not self.try_consume("["):
            raise self.err("InvalidSquirrelSyntax: expected '['")
        var out = List[TypeParam]()
        self.skip_trivia()
        if self.try_consume("]"):
            return out^
        while True:
            self.skip_trivia()
            var name = self.scan_ident()
            if name.byte_length() == 0:
                raise self.err("InvalidSquirrelSyntax: expected type parameter name")
            self.skip_trivia()
            var bound = "Copyable & Movable & ImplicitlyDeletable"
            if self.try_consume(":"):
                self.skip_trivia()
                bound = self._scan_type_param_bound()
                if bound.byte_length() == 0:
                    raise self.err("InvalidSquirrelSyntax: expected type parameter bound after ':'")
            out.append(TypeParam(name=name, bound=bound))
            self.skip_trivia()
            if self.try_consume(","):
                continue
            if self.try_consume("]"):
                break
            raise self.err("InvalidSquirrelSyntax: expected ',' or ']' in type parameter list")
        return out^

    def parse_hand_written_plain_struct(mut self) raises -> ParsedStruct:
        """Requires `self.pos` at the bare `struct` token of a hand-written
        plain struct, e.g. right after `find_next_hand_written_plain_
        struct_decl` returns True. Extracts the struct's own name, its own
        optional `[T: Bound, ...]` type-parameter list (real Mojo syntax
        order: type parameters before an optional parenthesized trait
        list, which is skipped over -- never captured, since it's emitted
        completely unchanged elsewhere), and its leading `var name: Type`/
        `var @@name: @@Type` field declarations (`parse_hand_written_
        struct_fields`). A read-only structural pass for the compiler's
        own bookkeeping (relation-schema/cycle-detection/JSON) -- never
        rewrites anything; the struct's own declaration reaches generated
        output completely unchanged via `rewrite_markers`'s ordinary
        "between markers" text-copying (nothing about a bare `struct`
        keyword or an unmarked field triggers any marker at all)."""
        var header_indent = line_indent_of(self.source, self.pos)
        if not self.try_consume("struct"):
            raise self.err("InvalidSquirrelSyntax: expected 'struct'")
        self.skip_trivia()
        var name = self.scan_ident()
        if name.byte_length() == 0:
            raise self.err("InvalidSquirrelSyntax: expected struct name")
        self.skip_trivia()
        var type_params = List[TypeParam]()
        if self.peek() == UInt8(ord("[")):
            type_params = self.parse_type_params()
            self.skip_trivia()
        if self.peek() == UInt8(ord("(")):
            # A real Mojo trait list -- skip it (balanced parens), never
            # captured: nothing here needs its contents.
            var depth = 0
            while not self.at_end():
                var before = self.pos
                self.skip_non_code()
                if self.pos != before:
                    continue
                var b = self.peek()
                if b == UInt8(ord("(")):
                    depth += 1
                elif b == UInt8(ord(")")):
                    depth -= 1
                    if depth == 0:
                        self.pos += 1
                        break
                self.pos += 1
            self.skip_trivia()
        if not self.try_consume(":"):
            raise self.err("InvalidSquirrelSyntax: expected ':' after struct name")
        var body = self.scan_indented_block(header_indent)
        var struct_fields = List[Field]()
        parse_hand_written_struct_fields(body, struct_fields)
        return ParsedStruct(name=name, fields=struct_fields^, type_params=type_params^)

    def peek_empty_call_follows(mut self) -> Bool:
        """True if, from `self.pos` (skipping trivia around both the `(`
        and `)`), an empty call `()` follows. Never moves `self.pos`
        permanently."""
        var save = self.pos
        self.skip_trivia()
        var matched = False
        if self.peek() == UInt8(ord("(")):
            self.pos += 1
            self.skip_trivia()
            matched = self.peek() == UInt8(ord(")"))
        self.pos = save
        return matched

    def find_next_world_scope_call(mut self) -> Bool:
        """Advances to the start of the next `@@@:` occurrence at real-code
        depth -- used only to *count* occurrences project-wide
        (`driver.check_single_world_scope_call`, which rejects more than
        one total)."""
        while True:
            self.skip_trivia()
            if self.at_end():
                return False
            if self.starts_with("@@@") and self.peek_at(3) == UInt8(ord(":")):
                return True
            if self.starts_with("@@"):
                self.pos += 2
                continue
            self.pos += 1

    def at_assignment(self) -> Bool:
        """True if the byte at `self.pos` is `=` (assignment) and not `==`
        (equality). A pure lookahead -- doesn't move `self.pos`."""
        return self.peek() == UInt8(ord("=")) and self.peek_at(1) != UInt8(ord("="))

    def parse_struct(mut self) raises -> ParsedStruct:
        """Requires `self.pos` at the `@@struct` token. Grammar: `@@struct
        [keepalive] [equatable] @@Name[(Trait1, Trait2, ...)]:` (every part
        but the name optional) followed by an indented block -- fields
        first (newline-separated, no commas), then optionally user-written
        methods (captured verbatim, spliced in once M3 lands)."""
        var header_indent = line_indent_of(self.source, self.pos)
        if not self.try_consume("@@struct"):
            raise self.err("InvalidSquirrelSyntax: expected '@@struct'")
        self.skip_trivia()
        var is_keepalive = False
        var is_equatable = False
        while True:
            if self.starts_with("keepalive") and not is_ident_char(self.peek_at(9)):
                self.pos += 9
                self.skip_trivia()
                is_keepalive = True
                continue
            if self.starts_with("equatable") and not is_ident_char(self.peek_at(9)):
                self.pos += 9
                self.skip_trivia()
                is_equatable = True
                continue
            break
        if not self.try_consume("@@"):
            raise self.err("InvalidSquirrelSyntax: expected '@@' before struct name ('@@struct @@Name:')")
        var name = self.scan_ident()
        if name.byte_length() == 0:
            raise self.err("InvalidSquirrelSyntax: expected struct name")
        self.skip_trivia()
        var trait_list = List[String]()
        if self.peek() == UInt8(ord("(")):
            trait_list = self.parse_trait_list()
            self.skip_trivia()
        if not self.try_consume(":"):
            raise self.err("InvalidSquirrelSyntax: expected ':' after struct name")
        var body = self.scan_indented_block(header_indent)
        var struct_fields = List[Field]()
        var method_body = parse_struct_body(body, struct_fields)
        return ParsedStruct(
            name=name,
            fields=struct_fields^,
            is_keepalive=is_keepalive,
            is_equatable=is_equatable,
            trait_list=trait_list^,
            method_body=method_body^,
        )

    def find_next_marker(mut self) raises -> MarkerKind:
        """Advances to the next `@@`-marked construct at real-code depth and
        reports which kind it is, leaving `self.pos` at the start of the
        marker (ready for the matching `parse_*` call).

        `@@@` (three `@`s) is checked before plain `@@` (longest-match-first,
        same reasoning as the earlier `add_to_@@field` scanner change) --
        it's the M3 addendum's marker for "this reference needs
        `sqrrl__world`": world-scope (`@@@:`), a top-level function
        definition/call (`@@@func(...)`), construction (`@@@Type{...}`), and
        a table-level call (`@@@Type.method(...)`, folded into
        `FIELD_ACCESS` same as a bound-variable field access -- the scanner
        can't yet tell those two apart, only `rewrite_field_access.mojo` can
        once it has `entity_to_type`). Plain `@@` at each of those same
        shapes is now a hard parse error (no silent fallback): a struct
        field/type/relation reference (`@@Person`, `.@@dept`,
        `add_to_@@projects`, an entity parameter, a return type, a `for
        @@x in ...` loop) is completely unaffected and still uses plain
        `@@`, unchanged.

        Slimmed from rw_squirrel_2 for M1's scope -- see `MarkerKind`'s own
        doc comment for exactly what's dropped."""
        while True:
            self.skip_trivia()
            if self.at_end():
                return MarkerKind.NONE
            if self.starts_with("@@struct"):
                return MarkerKind.STRUCT
            if self.starts_with("@@@"):
                var marker_start = self.pos
                self.pos += 3
                if self.peek() == UInt8(ord(":")):
                    # `@@@:` -- the world-scope marker. Checked before
                    # scan_ident() below since a bare `@@@:` has no
                    # identifier at all.
                    self.pos = marker_start
                    return MarkerKind.WORLD_SCOPE
                var ident_start = self.pos
                var ident = self.scan_ident()
                if self.pos == ident_start:
                    raise self.err(
                        "InvalidSquirrelSyntax: '@@@' must be followed by an"
                        " identifier -- a type name for construction"
                        " ('@@@Type{...}') or a table-level call"
                        " ('@@@Type.method(...)'), or a function name that"
                        " needs 'sqrrl__world' ('@@@func(...)'), or ':' to"
                        " open a world scope ('@@@:')"
                    )
                # M5's four JSON markers -- matched on identifier text
                # (checked before the ordinary `{`/`.`/`(` dispatch below,
                # same longest-match-first discipline `@@init` already uses
                # in the plain-`@@` branch). `begin_init_from_json`/
                # `init_from_json` match on text alone, no lookahead -- a
                # missing '(' becomes a clean parse error from their own
                # `parse_*` rather than a silent fallthrough to WORLD_FUNC.
                # `end_init_from_json`/`to_json` require an immediately
                # following empty `()` (mirroring `@@init`'s own
                # `peek_empty_call_follows` convention); when that's absent
                # they fall through to the generic dispatch below, same as
                # `@@init` does.
                if ident == "begin_init_from_json":
                    self.pos = marker_start
                    return MarkerKind.BEGIN_INIT_FROM_JSON
                if ident == "init_from_json":
                    self.pos = marker_start
                    return MarkerKind.INIT_FROM_JSON
                if ident == "end_init_from_json" and self.peek_empty_call_follows():
                    self.pos = marker_start
                    return MarkerKind.END_INIT_FROM_JSON
                if ident == "to_json" and self.peek_empty_call_follows():
                    self.pos = marker_start
                    return MarkerKind.TO_JSON
                self.skip_trivia()
                if self.peek() == UInt8(ord("{")):
                    self.pos = marker_start
                    return MarkerKind.CONSTRUCT
                if self.peek() == UInt8(ord(".")):
                    self.pos = marker_start
                    return MarkerKind.FIELD_ACCESS
                if self.peek() == UInt8(ord("(")):
                    self.pos = marker_start
                    return MarkerKind.WORLD_FUNC
                raise self.err(
                    "InvalidSquirrelSyntax: '@@@"
                    + ident
                    + "' isn't a valid construction ('@@@"
                    + ident
                    + "{...}'), table-level call ('@@@"
                    + ident
                    + ".method(...)'), or function definition/call ('@@@"
                    + ident
                    + "(...)')"
                )
            if self.starts_with("@@"):
                var marker_start = self.pos
                self.pos += 2
                if self.peek() == UInt8(ord(":")):
                    # A bare `@@:` -- world-scope now needs `sqrrl__world`
                    # marked explicitly via `@@@:`, no silent two-`@` form.
                    raise self.err(
                        "InvalidSquirrelSyntax: '@@:' needs 'sqrrl__world'"
                        " -- write '@@@:'"
                    )
                var ident_start = self.pos
                var ident = self.scan_ident()
                if self.pos == ident_start:
                    # Bare "@@" with no identifier and no ':' immediately
                    # after -- stray noise; step past it so the outer loop
                    # makes progress.
                    self.pos = marker_start + 1
                    continue
                if ident == "init" and self.peek_empty_call_follows():
                    self.pos = marker_start
                    return MarkerKind.INIT
                self.skip_trivia()
                var kind: MarkerKind
                if self.peek() == UInt8(ord("{")):
                    raise self.err(
                        "InvalidSquirrelSyntax: constructing '@@"
                        + ident
                        + "' needs 'sqrrl__world' -- write '@@@"
                        + ident
                        + "{...}'"
                    )
                elif self.peek() == UInt8(ord(".")) or self.peek() == UInt8(ord("[")):
                    kind = MarkerKind.FIELD_ACCESS
                elif self.peek() == UInt8(ord("(")):
                    raise self.err(
                        "InvalidSquirrelSyntax: calling '@@"
                        + ident
                        + "(...)' needs 'sqrrl__world' -- write '@@@"
                        + ident
                        + "(...)'"
                    )
                elif self.peek() == UInt8(ord(":")):
                    var save_colon = self.pos
                    self.pos += 1
                    self.skip_same_line_trivia()
                    if is_after_arrow(self.source, marker_start):
                        kind = MarkerKind.RETURN_TYPE
                    elif self.starts_with("@@"):
                        kind = MarkerKind.ENTITY_PARAM
                    elif self.at_wrapped_entity_param():
                        kind = MarkerKind.ENTITY_PARAM
                    else:
                        kind = MarkerKind.NAME_REF
                    self.pos = save_colon
                elif self.peek() == UInt8(ord("]")):
                    if is_after_container_bracket(self.source, marker_start):
                        kind = MarkerKind.RETURN_TYPE
                    else:
                        kind = MarkerKind.NAME_REF
                elif self.peek() == UInt8(ord(",")) and is_after_container_bracket(self.source, marker_start):
                    kind = MarkerKind.RETURN_TYPE
                elif (
                    self.starts_with("in")
                    and not is_ident_char(self.peek_at(2))
                    and is_after_for_keyword(self.source, marker_start)
                ):
                    kind = MarkerKind.FOR_ENTITY_LOOP
                else:
                    kind = MarkerKind.NAME_REF
                self.pos = marker_start
                return kind
            self.pos += 1

    def at_wrapped_entity_param(mut self) -> Bool:
        """True if, from the current position, the text matches
        `Ident[@@` -- a container-wrapped entity-param type
        (`List[@@Person]`). Restores `self.pos` before returning either
        way -- purely a lookahead."""
        var save = self.pos
        var wrapper = self.scan_ident()
        if wrapper.byte_length() == 0:
            self.pos = save
            return False
        self.skip_trivia()
        if self.peek() != UInt8(ord("[")):
            self.pos = save
            return False
        self.pos += 1
        self.skip_trivia()
        var result = self.starts_with("@@")
        self.pos = save
        return result

    def parse_entity_param(mut self) raises -> EntityParam:
        """Requires `self.pos` at the `@@` of `@@name: @@Type` (or the
        container form, `@@name: Container[@@Type]`)."""
        if not self.try_consume("@@"):
            raise self.err("InvalidSquirrelSyntax: expected '@@'")
        var name = self.scan_ident()
        if name.byte_length() == 0:
            raise self.err("InvalidSquirrelSyntax: expected entity parameter name")
        self.skip_trivia()
        if not self.try_consume(":"):
            raise self.err("InvalidSquirrelSyntax: expected ':' after entity parameter name")
        self.skip_trivia()

        var wrapper: Optional[String] = None
        if not self.starts_with("@@"):
            var w = self.scan_ident()
            if w.byte_length() == 0:
                raise self.err("InvalidSquirrelSyntax: expected '@@Type' or 'Container[@@Type]' after ':'")
            self.skip_trivia()
            if not self.try_consume("["):
                raise self.err("InvalidSquirrelSyntax: expected '[' after '" + w + "'")
            self.skip_trivia()
            wrapper = w

        if not self.try_consume("@@"):
            raise self.err("InvalidSquirrelSyntax: expected '@@Type' after ':'")
        var type_name = self.scan_ident()
        if type_name.byte_length() == 0:
            raise self.err("InvalidSquirrelSyntax: expected entity parameter type")

        if wrapper:
            self.skip_trivia()
            if not self.try_consume("]"):
                raise self.err("InvalidSquirrelSyntax: expected ']' after '" + wrapper.value() + "[@@" + type_name + "'")

        return EntityParam(name=name, type_name=type_name, wrapper=wrapper)

    def parse_construct(mut self) raises -> Construct:
        """Requires `self.pos` at the `@@@` of a `@@@TypeName { ... }`
        construct -- construction always needs `sqrrl__world` (M3 addendum),
        so this is the one marker family entry point that only ever accepts
        the three-`@` form; a plain `@@TypeName{...}` never reaches here
        (`find_next_marker` raises before returning `MarkerKind.CONSTRUCT`
        for it)."""
        if not self.try_consume("@@@"):
            raise self.err("InvalidSquirrelSyntax: expected '@@@'")
        var type_name = self.scan_ident()
        if type_name.byte_length() == 0:
            raise self.err("InvalidSquirrelSyntax: expected type name")
        self.skip_trivia()
        var body = self.scan_braced_span()
        return Construct(type_name=type_name, fields=parse_construct_fields(body))

    def _scan_write_value_span(mut self) raises -> String:
        """Scans an opaque write-value expression from `self.pos` (already
        positioned right after the '=' and any whitespace) through the
        first top-level `;` or `\\n` (ignoring either nested inside
        `[]`/`()`/`{}`), or end of input -- consuming a trailing `;` if
        that's what stopped it. Factored out of `parse_field_access`'s
        single write call site (general access-chain redesign, plain-
        structs milestone -- see the plan's Revision 3)."""
        var value_start = self.pos
        var depth = 0
        var hit_semicolon = False
        while not self.at_end():
            var before = self.pos
            self.skip_non_code()
            if self.pos != before:
                continue
            var b = self.peek()
            if b == UInt8(ord("(")) or b == UInt8(ord("[")) or b == UInt8(ord("{")):
                depth += 1
            elif b == UInt8(ord(")")) or b == UInt8(ord("]")) or b == UInt8(ord("}")):
                depth -= 1
            elif depth == 0 and b == UInt8(ord(";")):
                hit_semicolon = True
                break
            elif depth == 0 and b == UInt8(ord("\n")):
                break
            self.pos += 1
        if depth != 0:
            raise self.err("InvalidSquirrelSyntax: unterminated write expression")
        var value = String(self.source[byte = value_start : self.pos])
        if hit_semicolon:
            self.pos += 1  # consume ';'
        return String(value.strip())

    def parse_field_access(mut self) raises -> FieldAccess:
        """Requires `self.pos` at the `@@` or `@@@` of `@@entity.field` (or
        an arbitrary chain of `.field`/`[index]` steps, `@@entity.@@dept.
        @@members[0].name`, ...) -- `@@@` marks a table-level call
        (`@@@Type.method(...)`, needs `sqrrl__world`); plain `@@` marks a
        bound-variable access (a relation hop chain, an instance method
        call, a container index). The scanner can't yet tell those two
        cases apart (that needs `entity_to_type`, only available once
        rewriting actually reaches this point), so it just records which
        prefix was used (`entity_marked_world`) and leaves validating it
        against the actual case to `rewrite_field_access.mojo`.

        General recursive access chain (plain-structs milestone, the plan's
        Revision 3): loops consuming a `.`-step or `[...]`-step for as long
        as either continues, collecting each into `FieldAccess.steps` --
        replacing the old fixed-depth `hops`/`field`/`index_expr`/
        `post_index_expr`/`post_field` shape entirely (a bare indexed
        reference like `@@matches[0]` is now simply `steps == [AccessStep(
        kind=INDEX, ...)]`, no longer special-cased at all). A `.@@@name`
        step (call-site symmetry with a spliced method's own `@@@`-marked
        declaration) unconditionally terminates the chain -- the one
        deliberate exception to "the loop just keeps going". The scanner
        itself is deliberately greedy/syntactic here and can't tell a
        relation/container hop apart from a native Mojo leaf method/index
        (`@@alice.name.upper()`/`@@alice.name[0]`) -- that's `handle_field_
        access`'s own job (the "premature-leaf rollback" mechanism), using
        each `AccessStep.end_pos` to roll back to a known-good boundary."""
        var entity_marked_world = self.try_consume("@@@")
        if not entity_marked_world and not self.try_consume("@@"):
            raise self.err("InvalidSquirrelSyntax: expected '@@'")
        var entity = self.scan_ident()
        if entity.byte_length() == 0:
            raise self.err("InvalidSquirrelSyntax: expected entity name")

        var steps = List[AccessStep]()
        while True:
            var save = self.pos
            self.skip_trivia()
            if self.peek() == UInt8(ord("[")):
                var idx = self.scan_bracketed_span()
                steps.append(
                    AccessStep(kind=AccessStep.INDEX, name=idx, marked=False, marked_world=False, end_pos=self.pos)
                )
                continue
            if self.peek() != UInt8(ord(".")):
                self.pos = save
                break
            self.pos += 1  # consume '.'
            self.skip_trivia()
            if self.try_consume("@@@"):
                # `.@@@name` -- call-site symmetry with a spliced method's
                # own `@@@`-marked declaration (needs `sqrrl__world`).
                # Always terminal -- a world-marked call never continues
                # into a further step.
                var wf = self.scan_ident()
                if wf.byte_length() == 0:
                    raise self.err(
                        "InvalidSquirrelSyntax: expected method name after"
                        " '@@@'"
                    )
                steps.append(
                    AccessStep(kind=AccessStep.FIELD, name=wf, marked=False, marked_world=True, end_pos=self.pos)
                )
                break
            var marked: Bool
            var name: String
            if self.try_consume("@@"):
                marked = True
                name = self.scan_ident()
                if name.byte_length() == 0:
                    raise self.err(
                        "InvalidSquirrelSyntax: expected relation field name"
                        " after '@@'"
                    )
            else:
                name = self.scan_ident()
                if name.byte_length() == 0:
                    raise self.err("InvalidSquirrelSyntax: expected field name")
                marked = False
                if self.try_consume("@@"):
                    # A compound call whose field-name suffix is @@-marked,
                    # e.g. `add_to_@@projects(...)`/`for_@@projects(...)` --
                    # mirrors `.@@dept`'s own marking convention (a relation
                    # field reference is `@@`-marked), just with a
                    # non-empty literal prefix before the marker. The fixed
                    # "add_to_"/"remove_from_"/"for_" text is a codegen
                    # concern the parser doesn't need to know about; it
                    # only records that `@@`-marking was present somewhere
                    # in this token.
                    var suffix = self.scan_ident()
                    if suffix.byte_length() == 0:
                        raise self.err(
                            "InvalidSquirrelSyntax: expected relation field"
                            " name after '@@'"
                        )
                    name = name + suffix
                    marked = True
            steps.append(AccessStep(kind=AccessStep.FIELD, name=name, marked=marked, marked_world=False, end_pos=self.pos))

        if len(steps) == 0:
            raise self.err(
                "InvalidSquirrelSyntax: expected '.' or '[' after"
                " entity/relation name"
            )
        var after_chain = self.pos

        self.skip_trivia()
        if self.peek() == UInt8(ord("(")):
            self.pos = after_chain
            return FieldAccess(
                entity=entity, entity_marked_world=entity_marked_world, steps=steps^, is_call=True, write_value=None
            )

        if not self.at_assignment():
            self.pos = after_chain
            return FieldAccess(
                entity=entity, entity_marked_world=entity_marked_world, steps=steps^, is_call=False, write_value=None
            )

        self.pos += 1  # consume '='
        self.skip_whitespace()
        var value = self._scan_write_value_span()
        return FieldAccess(
            entity=entity,
            entity_marked_world=entity_marked_world,
            steps=steps^,
            is_call=False,
            write_value=String(value),
        )

    def parse_world_scope(mut self) raises -> Int:
        """Requires `self.pos` at the `@@@` of `@@@:`. Consumes just the
        3-byte `@@@` plus the `:` (4 bytes total) -- `@@@:`'s block extent is
        the indented suite that follows it (real Mojo/Python indentation,
        no second explicit closing token), so this returns the byte offset
        where that suite ends, *without* consuming the suite itself."""
        var header_indent = line_indent_of(self.source, self.pos)
        if not self.try_consume("@@@"):
            raise self.err("InvalidSquirrelSyntax: expected '@@@'")
        if not self.try_consume(":"):
            raise self.err("InvalidSquirrelSyntax: expected ':' after '@@@'")
        return find_end_of_indented_block(self.source, self.pos, header_indent)

    def parse_init(mut self) raises:
        """Requires `self.pos` at the `@@` of `@@init()`. Takes no
        arguments -- just consumes the token."""
        if not self.try_consume("@@init"):
            raise self.err("InvalidSquirrelSyntax: expected '@@init'")
        self.skip_trivia()
        if not self.try_consume("("):
            raise self.err("InvalidSquirrelSyntax: expected '(' after '@@init'")
        self.skip_trivia()
        if not self.try_consume(")"):
            raise self.err("InvalidSquirrelSyntax: '@@init' takes no arguments")

    def parse_world_func(mut self) raises -> String:
        """Requires `self.pos` at the `@@@` of `@@@name(` -- a top-level
        function that needs `sqrrl__world`, whether this is its own
        definition or a call site. Consumes through the opening `(` and
        returns `name`."""
        if not self.try_consume("@@@"):
            raise self.err("InvalidSquirrelSyntax: expected '@@@'")
        var name = self.scan_ident()
        if name.byte_length() == 0:
            raise self.err("InvalidSquirrelSyntax: expected function name")
        self.skip_trivia()
        if not self.try_consume("("):
            raise self.err("InvalidSquirrelSyntax: expected '(' after function name")
        return name

    def _parse_json_call_arg(mut self, call_text: String) raises -> String:
        """Scans from just after `call_text`'s own '(' through the matching
        ')' at real-code depth, returns the raw, trimmed argument text
        unparsed -- codegen splices it straight into a String-typed
        parameter, same 'opaque text' treatment a construct field's own
        value already gets (never re-run through `rewrite_markers`: an
        `@@`-marked entity reference inside a JSON-source expression is
        nonsensical). Mirrors `scan_braced_span`'s own depth-tracking shape,
        for `(...)` instead of `{...}`."""
        self.skip_trivia()
        if not self.try_consume("("):
            raise self.err("InvalidSquirrelSyntax: expected '(' after '" + call_text + "'")
        var body_start = self.pos
        var depth = 1
        while not self.at_end() and depth > 0:
            var before = self.pos
            self.skip_non_code()
            if self.pos != before:
                continue
            var b = self.peek()
            if b == UInt8(ord("(")):
                depth += 1
            elif b == UInt8(ord(")")):
                depth -= 1
            self.pos += 1
        if depth != 0:
            raise self.err("InvalidSquirrelSyntax: unterminated '(' in '" + call_text + "(...)'")
        var raw = String(self.source[byte = body_start : self.pos - 1])
        return String(raw.strip())

    def parse_begin_init_from_json(mut self) raises -> String:
        """Requires `self.pos` at the `@@@` of `@@@begin_init_from_json(expr)`.
        Returns the raw, unparsed JSON-source expression text."""
        if not self.try_consume("@@@begin_init_from_json"):
            raise self.err("InvalidSquirrelSyntax: expected '@@@begin_init_from_json'")
        return self._parse_json_call_arg("@@@begin_init_from_json")

    def parse_init_from_json(mut self) raises -> String:
        """Requires `self.pos` at the `@@@` of `@@@init_from_json(expr)`.
        Returns the raw, unparsed JSON-source expression text."""
        if not self.try_consume("@@@init_from_json"):
            raise self.err("InvalidSquirrelSyntax: expected '@@@init_from_json'")
        return self._parse_json_call_arg("@@@init_from_json")

    def parse_end_init_from_json(mut self) raises:
        """Requires `self.pos` at the `@@@` of `@@@end_init_from_json()`.
        Takes no arguments -- raises if anything is inside the parens."""
        if not self.try_consume("@@@end_init_from_json"):
            raise self.err("InvalidSquirrelSyntax: expected '@@@end_init_from_json'")
        var arg = self._parse_json_call_arg("@@@end_init_from_json")
        if arg.byte_length() > 0:
            raise self.err("InvalidSquirrelSyntax: '@@@end_init_from_json' takes no arguments")

    def parse_to_json(mut self) raises:
        """Requires `self.pos` at the `@@@` of `@@@to_json()`. Takes no
        arguments -- raises if anything is inside the parens."""
        if not self.try_consume("@@@to_json"):
            raise self.err("InvalidSquirrelSyntax: expected '@@@to_json'")
        var arg = self._parse_json_call_arg("@@@to_json")
        if arg.byte_length() > 0:
            raise self.err("InvalidSquirrelSyntax: '@@@to_json' takes no arguments")

    def parse_name_ref(mut self) raises -> NameRef:
        """Requires `self.pos` at the `@@` of a bare `@@name`."""
        if not self.try_consume("@@"):
            raise self.err("InvalidSquirrelSyntax: expected '@@'")
        var name = self.scan_ident()
        if name.byte_length() == 0:
            raise self.err("InvalidSquirrelSyntax: expected name")
        return NameRef(name=name)

    def parse_for_entity_loop(mut self) raises -> String:
        """Requires `self.pos` at the `@@` of `for @@name in ...:`.
        Consumes through the `in` keyword, leaving `self.pos` right at the
        start of the iterated expression. Returns `name`."""
        if not self.try_consume("@@"):
            raise self.err("InvalidSquirrelSyntax: expected '@@'")
        var name = self.scan_ident()
        if name.byte_length() == 0:
            raise self.err("InvalidSquirrelSyntax: expected name")
        self.skip_trivia()
        if not self.try_consume("in") or is_ident_char(self.peek()):
            raise self.err("InvalidSquirrelSyntax: expected 'in' after 'for @@" + name + "'")
        return name
