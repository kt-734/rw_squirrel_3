from squirrel_compiler.parser.ast import (
    Field,
    TypeParam,
    ParsedStruct,
    ConstructField,
    Construct,
    AccessStep,
    FieldAccess,
    AccessChainTail,
    NameRef,
    EntityParam,
    PlainVarDecl,
    PlainForLoop,
    BareForLoopHeader,
    MarkerKind,
)
from squirrel_compiler.parser.text_utils import (
    is_ident_char,
    source_location,
    line_indent_of,
    is_after_arrow,
    is_after_for_keyword,
    is_after_container_bracket,
    is_after_open_paren_or_comma,
    is_after_dot,
    bare_root_before_dot,
    find_end_of_indented_block,
)
from squirrel_compiler.parser.field_parsing import parse_struct_body, parse_hand_written_struct_fields
from squirrel_compiler.parser.relation_type_text import is_directly_entity_reachable


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

    def scan_balanced_span_body(
        mut self, open_char: UInt8, close_char: UInt8, unterminated_msg: String
    ) raises -> String:
        """Requires `self.pos` already just past the relevant single open
        bracket (the caller consumes/validates it themselves, since the
        right "expected '...'" wording varies per caller). Returns the
        body up to the matching `close_char` (exclusive), and advances
        `self.pos` past the closing byte -- the shared shape `scan_
        braced_span` (`{}`), `scan_bracketed_span` (`[]`), `scan_call_
        args_to_close`/`_parse_json_call_arg` (`()`), and a hand-written
        struct's own trait-list skip (also `()`) all used to duplicate as
        separate, near-identical loops, differing only in which single
        bracket pair they tracked and their own error wording.

        `scan_call_args_to_close`'s own previous version tracked *all
        three* bracket kinds as one combined depth counter (any opener
        increments, any closer decrements, regardless of kind) rather
        than matching `(`/`)` specifically -- a trick that happens to
        find the same stopping point for well-formed Mojo (any nested
        `[...]`/`{...}` is itself already balanced before the outer `)`
        can appear), so single-kind tracking here gives it the identical
        result without needing that trick at all."""
        var body_start = self.pos
        var depth = 1
        while not self.at_end() and depth > 0:
            var before = self.pos
            self.skip_non_code()
            if self.pos != before:
                continue
            var b = self.peek()
            if b == open_char:
                depth += 1
            elif b == close_char:
                depth -= 1
            self.pos += 1
        if depth != 0:
            raise self.err(unterminated_msg)
        return String(self.source[byte = body_start : self.pos - 1])

    def scan_braced_span(mut self) raises -> String:
        """Requires `self.pos` at `{`. Returns the body between the matching
        braces (exclusive), and advances `self.pos` past the closing `}`."""
        if not self.try_consume("{"):
            raise self.err("InvalidSquirrelSyntax: expected '{'")
        return self.scan_balanced_span_body(
            UInt8(ord("{")), UInt8(ord("}")), "InvalidSquirrelSyntax: unterminated '{'"
        )

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
        if not self.try_consume("["):
            raise self.err("InvalidSquirrelSyntax: expected '['")
        return self.scan_balanced_span_body(
            UInt8(ord("[")), UInt8(ord("]")), "InvalidSquirrelSyntax: unterminated '['"
        )

    def scan_bracket_depth_aware_span(mut self, terminators: String) raises -> String:
        """The shared depth-aware "scan a type text span" shape `scan_type`
        (a `@@struct`/hand-written struct field's own type, terminated by
        `,`/newline), `scan_entity_param_type_text` (a def parameter or
        var-decl's own type, additionally terminated by `)`/`='), and
        `codegen/helpers.mojo`'s `scan_entity_return_shape` (a def/
        method's own return type, terminated by `:`) all share, instead
        of three near-identical copies -- scans from `self.pos` up to the
        first byte in `terminators` seen at top-level bracket depth
        (ignoring one nested inside `[]`/`()`/`{}`; an unbalanced closer
        at depth 0 belongs to an *enclosing* context, e.g. a def's own
        closing `)` right after its last parameter, and also ends the
        scan), skipping over comments/string literals via `skip_non_code`
        the same way every other scan in this codebase does.

        Leaves `self.pos` right after the scanned text's own last non-
        whitespace byte -- *not* at the terminator itself, and not
        through any trailing whitespace before it -- so the original
        source's own spacing between the type and whatever comes next is
        left unconsumed for a caller that splices generated output
        straight from source spacing (`scan_entity_param_type_text`'s own
        caller does -- confirmed missing via a real end-to-end compile:
        `sqrrl__senior: sqrrl__Employee= value`, the space before `=`
        gone; `scan_type`'s own caller never needs to, a struct field's
        declaration is always regenerated fresh, never copied through --
        but behaving the same way here regardless keeps all three
        callers consistent instead of leaving one a latent, currently-
        unhit special case)."""
        var start = self.pos
        var depth = 0
        var terminator_bytes = terminators.as_bytes()
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
                    break  # this closer belongs to an enclosing context
                depth -= 1
            elif depth == 0:
                var is_terminator = False
                for t in terminator_bytes:
                    if b == t:
                        is_terminator = True
                        break
                if is_terminator:
                    break
            self.pos += 1
        var end = self.pos
        while end > start and (
            self.byte_at(end - 1) == UInt8(ord(" "))
            or self.byte_at(end - 1) == UInt8(ord("\t"))
            or self.byte_at(end - 1) == UInt8(ord("\r"))
        ):
            end -= 1
        self.pos = end
        return String(self.source[byte = start : end])

    def scan_type(mut self) raises -> String:
        """Scans a field's type text: up to the next top-level `,` or `\\n`
        (ignoring either nested inside `[]`/`()`/`{}`) or end of input."""
        return self.scan_bracket_depth_aware_span(",\n")

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
        if self.try_consume("("):
            # A real Mojo trait list -- skip it (balanced parens), never
            # captured: nothing here needs its contents. Reuses `scan_
            # balanced_span_body`'s own shape -- previously a separate,
            # near-identical loop (and, unlike the others, one with no
            # unterminated-paren check at all, silently running to end-
            # of-input on malformed source instead of raising a clear
            # error; a strict improvement, not a behavior this project
            # ever relied on for a genuinely valid struct declaration).
            _ = self.scan_balanced_span_body(
                UInt8(ord("(")), UInt8(ord(")")), "InvalidSquirrelSyntax: unterminated '(' in trait list"
            )
            self.skip_trivia()
        if not self.try_consume(":"):
            raise self.err("InvalidSquirrelSyntax: expected ':' after struct name")
        var body = self.scan_indented_block(header_indent)
        var struct_fields = List[Field]()
        var method_body = parse_hand_written_struct_fields(body, struct_fields)
        return ParsedStruct(name=name, fields=struct_fields^, method_body=method_body^, type_params=type_params^)

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

    def at_plain_var_decl(mut self) raises -> Bool:
        """True if `self.pos` starts `[var ]<name>: <Type>` -- a *bare*
        local variable name (never `@@`-marked) with an explicit type
        annotation, `<Type>` either a single identifier (`Note`) or a
        container of one (`List[Note]`, `Dict[String, Note]`, any nesting
        `scan_bracketed_span` already handles generally). Matches with or
        without a leading `var ` and with or without a trailing ` = ...`
        -- covers a var-decl, a def's own parameter declaration, *and* a
        hand-written plain struct's own field declaration, the same three
        contexts `MarkerKind.ENTITY_PARAM` already covers for the marked
        equivalent (`@@name: @@Type`) -- disambiguating between them is
        `rewrite.mojo`'s own handler's job (`is_in_def_signature`/`at_
        assignment`, mirroring `ENTITY_PARAM`'s exact three-way split),
        not this lookahead's. A pure lookahead, restoring `self.pos`
        either way.

        Purely syntactic -- has no access to the project-wide `plain_
        struct_names` map (only a rewrite handler, via `RewriteContext`,
        does), so this matches far more often than `PLAIN_VAR_DECL` is
        actually acted on: `var x: Int = 5` and a struct's own `text:
        String` field both match this shape too. The handler checks
        `<Type>` semantically and, when it isn't actually a known plain
        struct (or a container of one), just copies the matched text
        straight through unchanged -- this lookahead only needs to be
        syntactically conservative enough that it never fires on `var
        @@x = ...`/`var @@x: @@Type = ...` (both already handled
        elsewhere, via the `@@`-triggered branches above in `find_next_
        marker`): `scan_ident` stops at `@`, so either name immediately
        returns empty the moment a `@@`-marked spelling is actually
        present, at either position.

        A second, `var`-only shape (no `:` at all) also matches: `var
        <name> = <CtorIdent>[<TypeArgs>]?(` -- a var-decl whose
        initializer is itself a constructor-call-shaped expression,
        letting `type_text` be inferred from the constructor's own head
        instead of a written-out annotation (`var addresses = List[
        Address]()`, no `: List[Address]` needed) -- the plain-struct-
        local analogue of `handle_name_ref`'s own marked-var-decl
        fallback for `var @@x = List[@@Type]()`. Requires the leading
        `var` keyword specifically (unlike the annotated shape, which
        allows omitting it for a def-parameter/struct-field): an ordinary
        reassignment of an already-declared bare var (`addr2 = Address(
        ...)`, no `var`) must never be reinterpreted as a fresh
        declaration."""
        var save = self.pos
        var had_var = self.try_consume("var")
        self.skip_trivia()
        var name = self.scan_ident()
        if name.byte_length() == 0:
            self.pos = save
            return False
        self.skip_trivia()
        if self.peek() == UInt8(ord(":")):
            self.pos += 1
            self.skip_trivia()
            var type_name = self.scan_ident()
            if type_name.byte_length() == 0:
                self.pos = save
                return False
            self.skip_trivia()
            if self.peek() == UInt8(ord("[")):
                _ = self.scan_bracketed_span()
            self.pos = save
            return True
        if not had_var or not self.at_assignment():
            self.pos = save
            return False
        self.pos += 1
        self.skip_trivia()
        var ctor_name = self.scan_ident()
        if ctor_name.byte_length() == 0:
            self.pos = save
            return False
        if self.peek() == UInt8(ord("[")):
            _ = self.scan_bracketed_span()
        var matched = self.peek() == UInt8(ord("("))
        self.pos = save
        return matched

    def parse_plain_var_decl(mut self) raises -> PlainVarDecl:
        """Requires `self.pos` at the `var` token (or, with no leading
        `var` at all, straight at the name -- a def parameter or a
        struct field), already confirmed via `at_plain_var_decl`.

        For the annotated shape, leaves `self.pos` right after the type
        -- deliberately never consumes a trailing `=` itself (mirrors
        `parse_entity_param`'s own shape exactly): the caller (`rewrite.
        mojo`) needs `self.pos` sitting right there, unconsumed, to look
        ahead for `=` itself and decide `is_var_decl` the same way
        `MarkerKind.ENTITY_PARAM`'s own handler already does for the
        marked equivalent.

        For the inferred shape (`type_is_inferred=True`), leaves `self.
        pos` right after `= ` -- deliberately *before* the constructor
        call's own head, which stays unconsumed for the ordinary scan to
        re-discover and emit normally (any `@@`-marked argument inside
        it still needs that); `type_text` here is captured via a lookahead
        that restores `self.pos` afterward, since it's for registration
        only, never emitted by this marker itself."""
        var start = self.pos
        _ = self.try_consume("var")
        self.skip_trivia()
        var name = self.scan_ident()
        self.skip_trivia()
        if self.peek() == UInt8(ord(":")):
            self.pos += 1
            self.skip_trivia()
            var prefix_text = String(self.source[byte = start : self.pos])
            var type_start = self.pos
            _ = self.scan_ident()
            if self.peek() == UInt8(ord("[")):
                _ = self.scan_bracketed_span()
            var type_text = String(self.source[byte = type_start : self.pos])
            return PlainVarDecl(
                name=name, prefix_text=prefix_text, type_text=type_text, type_is_inferred=False
            )
        _ = self.at_assignment()
        self.pos += 1
        self.skip_trivia()
        var prefix_text = String(self.source[byte = start : self.pos])
        var type_lookahead = self.pos
        var type_start = self.pos
        _ = self.scan_ident()
        if self.peek() == UInt8(ord("[")):
            _ = self.scan_bracketed_span()
        var type_text = String(self.source[byte = type_start : self.pos])
        self.pos = type_lookahead
        return PlainVarDecl(name=name, prefix_text=prefix_text, type_text=type_text, type_is_inferred=True)

    def at_plain_for_loop(mut self) raises -> Bool:
        """True if `self.pos` starts `for [var/ref ]<loop_var> in
        <container>[(...)]:` -- both the loop variable and the iterated
        expression bare (never `@@`-marked); the iterated expression is
        a single name, optionally followed by one balanced call (`for n
        in get_notes(@@b):`), never a full arbitrary expression. A pure
        lookahead, restoring `self.pos` either way. Purely syntactic
        (whether `<container>` is actually a known, container-typed
        local/function is `rewrite.mojo`'s own handler's job) --
        conservative enough to never misfire on `for @@x in ...:`
        (`MarkerKind.FOR_ENTITY_LOOP`'s own shape, found via the `@@`-
        triggered branches above, never reaching this fallback at
        all)."""
        var save = self.pos
        if not (self.starts_with("for") and not is_ident_char(self.peek_at(3))):
            self.pos = save
            return False
        self.pos += 3
        self.skip_trivia()
        _ = self.try_consume("var")
        _ = self.try_consume("ref")
        self.skip_trivia()
        var loop_var = self.scan_ident()
        if loop_var.byte_length() == 0:
            self.pos = save
            return False
        self.skip_trivia()
        if not (self.starts_with("in") and not is_ident_char(self.peek_at(2))):
            self.pos = save
            return False
        self.pos += 2
        self.skip_trivia()
        var container_name = self.scan_ident()
        if container_name.byte_length() == 0:
            self.pos = save
            return False
        if self.peek() == UInt8(ord("(")):
            self.pos += 1
            _ = self.scan_call_args_to_close()
        self.skip_trivia()
        var matched = self.peek() == UInt8(ord(":"))
        self.pos = save
        return matched

    def parse_plain_for_loop(mut self) raises -> PlainForLoop:
        """Requires `self.pos` at the `for` token, already confirmed via
        `at_plain_for_loop`. Leaves `self.pos` right after the container
        name/call (before `:`) -- the caller copies `source[marker_start
        : self.pos]` straight through verbatim for the non-call case
        (preserving original spacing exactly, no hardcoded space
        reconstruction, which caused a real cosmetic double-space bug for
        `FOR_ENTITY_LOOP`'s own analogous case); the call case instead
        needs its own argument list run through `rewrite_markers` (any
        `@@`-marked argument still needs rewriting), so the caller
        reconstructs that text itself rather than copying it raw."""
        _ = self.try_consume("for")
        self.skip_trivia()
        var binding_prefix = String()
        if self.try_consume("var"):
            binding_prefix = "var"
        elif self.try_consume("ref"):
            binding_prefix = "ref"
        self.skip_trivia()
        var loop_var = self.scan_ident()
        self.skip_trivia()
        _ = self.try_consume("in")
        self.skip_trivia()
        var container_name = self.scan_ident()
        var is_call = False
        var arg_text = String()
        if self.peek() == UInt8(ord("(")):
            is_call = True
            self.pos += 1
            arg_text = self.scan_call_args_to_close()
        return PlainForLoop(
            loop_var=loop_var, container_name=container_name, is_call=is_call, arg_text=arg_text,
            binding_prefix=binding_prefix,
        )

    def at_bare_for_loop_over_marked_chain(mut self) raises -> Bool:
        """True if `self.pos` starts `for [var/ref ]<loop_var> in @@` --
        a *bare* (never `@@`-marked) loop variable whose own iterated
        expression is rooted at a single `@@` (a bound entity's own
        field/method-call chain, a marked top-level function's own call,
        or a bound entity referenced directly) -- deliberately requires
        exactly one `@@`, not `@@@`: a table-level call's own result is
        always compiler-constructed and guaranteed entity-shaped (see
        `PendingForLoopDecl`'s own doc comment), never a legitimate case
        for a bare loop var, so excluded here at the syntax level rather
        than relying on downstream validation to catch it.

        The bare-loop-var mirror of `MarkerKind.FOR_ENTITY_LOOP`'s own
        `for @@x in ...:` shape (found via the `@@`-triggered branches in
        `find_next_marker`, never reaching this fallback) -- lives here,
        not there, because the loop variable itself carries no `@@` for
        the scanner to stop at; this has to be a forward, purely
        syntactic fallback check exactly like `at_plain_for_loop`/`at_
        bare_call_chain`, checked once nothing `@@`-triggered matched at
        the current position. Deliberately does *not* try to parse the
        chain itself -- that's the ordinary `@@`-triggered dispatch's own
        job once the outer scanning loop reaches the `@@` on its own; this
        only confirms a single `@@` immediately follows `in`. A pure
        lookahead, restoring `self.pos` either way."""
        var save = self.pos
        if not (self.starts_with("for") and not is_ident_char(self.peek_at(3))):
            self.pos = save
            return False
        self.pos += 3
        self.skip_trivia()
        _ = self.try_consume("var")
        _ = self.try_consume("ref")
        self.skip_trivia()
        var loop_var = self.scan_ident()
        if loop_var.byte_length() == 0:
            self.pos = save
            return False
        self.skip_trivia()
        if not (self.starts_with("in") and not is_ident_char(self.peek_at(2))):
            self.pos = save
            return False
        self.pos += 2
        self.skip_trivia()
        var matched = self.starts_with("@@") and not self.starts_with("@@@")
        self.pos = save
        return matched

    def parse_bare_for_loop_prefix(mut self) raises -> BareForLoopHeader:
        """Requires `self.pos` at the `for` token, already confirmed via
        `at_bare_for_loop_over_marked_chain`. Consumes through `in`,
        leaving `self.pos` right at the `@@` of the iterated expression --
        mirrors `parse_for_entity_loop`'s own contract exactly (no
        trailing-space handling here either, same reasoning: the source's
        own original space between `in` and the `@@` is left for the
        outer loop's own ordinary "between text" copy to reproduce
        verbatim). Returns the loop variable's own (bare) name plus
        whatever `var`/`ref` binding prefix preceded it (`PlainForLoop`'s
        own doc comment has the full "why" -- this handler reconstructs
        its own output text too, so dropping the prefix here would be the
        exact same silent bug)."""
        _ = self.try_consume("for")
        self.skip_trivia()
        var binding_prefix = String()
        if self.try_consume("var"):
            binding_prefix = "var"
        elif self.try_consume("ref"):
            binding_prefix = "ref"
        self.skip_trivia()
        var loop_var = self.scan_ident()
        self.skip_trivia()
        _ = self.try_consume("in")
        return BareForLoopHeader(loop_var=loop_var, binding_prefix=binding_prefix)

    def at_bare_var_decl_over_marked_chain(mut self) raises -> Bool:
        """True if `self.pos` starts `var <bare_name> = @@` (single `@@`,
        not `@@@` -- a table-level call's own result is always compiler-
        constructed and guaranteed entity-shaped, and can't be assigned to
        a bare name symmetrically for the same reason `at_bare_for_loop_
        over_marked_chain` excludes it) -- a *bare* (never `@@`-marked)
        var-decl whose initializer is rooted at a single `@@` (a bound
        entity's own field/method-call chain, a marked top-level
        function's own call, or a bound entity referenced directly).

        The var-decl mirror of `at_bare_for_loop_over_marked_chain`
        exactly, just for `pending_decl` instead of `pending_for_loop_
        decl` -- needed for the identical reason: `var addr = @@bob.get_
        home()` (a bare method returning a plain struct) has no `:
        Address` annotation and no bare-identifier-before-`(` shape
        either (`at_plain_var_decl`'s own inferred shape requires `scan_
        ident()` to succeed on the RHS, which stops dead at `@`), so
        nothing registers `addr` at all -- confirmed via a real compile
        ("was never constructed") before this existed. Requires the
        leading `var` keyword (an ordinary reassignment of an existing
        bare var, `addr = @@bob...`, no `var`, must never be mistaken for
        a fresh declaration)."""
        var save = self.pos
        if not self.try_consume("var"):
            self.pos = save
            return False
        self.skip_trivia()
        var name = self.scan_ident()
        if name.byte_length() == 0:
            self.pos = save
            return False
        self.skip_trivia()
        if not self.at_assignment():
            self.pos = save
            return False
        self.pos += 1
        self.skip_trivia()
        var matched = self.starts_with("@@") and not self.starts_with("@@@")
        self.pos = save
        return matched

    def parse_bare_var_decl_prefix(mut self) raises -> String:
        """Requires `self.pos` at the `var` token, already confirmed via
        `at_bare_var_decl_over_marked_chain`. Consumes through `=`,
        leaving `self.pos` right there (no trailing-space handling,
        same reasoning as `parse_for_entity_loop`/`parse_bare_for_loop_
        over_marked_chain`: the source's own original space between `=`
        and the `@@` is left for the outer loop's own ordinary "between
        text" copy to reproduce verbatim). Returns the variable's own
        (bare) name."""
        _ = self.try_consume("var")
        self.skip_trivia()
        var name = self.scan_ident()
        self.skip_trivia()
        _ = self.at_assignment()
        self.pos += 1
        return name

    def at_bare_rooted_chain(mut self) raises -> Bool:
        """True if `self.pos` starts `<bare_ident>.<ident>(` -- a bare
        (never `@@`-marked) receiver whose own chain's first hop is a
        method call, immediately followed by `(`. Neither the `@@`-
        triggered dispatch (nothing here is `@@`-marked at all) nor
        `bare_root_before_dot`'s own backward look (which can't rewind
        through a call's own closing `)`, only through `]`) can recognize
        this shape at all -- confirmed as a real, previously-silent gap:
        `addr2.relocated(...).@@owner.name`/`var x = addr2.get_thing()`/
        `for a in addr2.get_thing():` all left their own target
        completely unregistered before this existed (`var x =`/`for a
        in` need their own sibling markers too, `BARE_VAR_DECL_OVER_BARE_
        CHAIN`/`BARE_FOR_LOOP_OVER_BARE_CHAIN`, to set `pending_decl`/
        `pending_for_loop_decl` *before* the scanner reaches this one --
        this marker alone is what makes the *direct*-chain shape, with
        no intermediate variable, work).

        Requires the receiver itself not be preceded by `.` -- otherwise
        a deeper hop's own field name (`a.b.c(...)`, checked starting at
        `b` once nothing matches at `a`) could be mistaken for a fresh
        root, the same reasoning `bare_root_before_dot`'s own backward
        walk already encodes for *its* direction, just checked forward
        here instead.

        Purely syntactic -- doesn't check `ctx.entity_to_type` (the
        scanner has no access to it); the handler does, and silently
        no-ops (advances one byte, exactly as if nothing had matched at
        all) whenever the receiver isn't actually a tracked bare local --
        this shape matches an *enormous* amount of completely ordinary,
        unrelated Mojo (`some_string.upper()`, `some_list.append(...)`,
        any native method call on any untracked local at all), so unlike
        every other fallback check in this file, misfiring here is the
        common case by a wide margin, not the exception -- the handler's
        own silent, harmless no-op has to hold up under that, not just
        the occasional false match."""
        var save = self.pos
        if is_after_dot(self.source, save):
            return False
        var receiver = self.scan_ident()
        if receiver.byte_length() == 0:
            self.pos = save
            return False
        if self.peek() != UInt8(ord(".")):
            self.pos = save
            return False
        self.pos += 1
        var method_name = self.scan_ident()
        if method_name.byte_length() == 0:
            self.pos = save
            return False
        var matched = self.peek() == UInt8(ord("("))
        self.pos = save
        return matched

    def at_bare_var_decl_over_bare_chain(mut self) raises -> Bool:
        """True if `self.pos` starts `var <bare_name> = <bare_ident>.
        <ident>(` -- the bare-rooted mirror of `at_bare_var_decl_over_
        marked_chain`, for a chain whose own root carries no `@@` either
        (`var x = addr2.get_thing()`). Requires the *exact* same shape
        `at_bare_rooted_chain` itself requires (receiver, `.`, method
        name, `(`) -- not just `receiver.` -- on purpose: this marker's
        own job is only to set `pending_decl` a step early, and `BARE_
        ROOTED_CHAIN` is what actually consumes it (clearing it one way
        or another, every return path) once the scanner reaches the
        receiver's own position next. If this matched a *looser* shape
        (`var x = addr2.some_field`, a plain field with no call at all --
        `at_plain_var_decl`'s own inferred branch already covers `var
        <name> = <CtorIdent>(`, a direct call with no receiver, so this
        one only needs to worry about the receiver.something shape),
        `BARE_ROOTED_CHAIN` wouldn't fire there at all (it requires the
        call), and `pending_decl` would leak, unconsumed, into whatever
        marker the scanner finds next -- confirmed as a real risk while
        building this, not a hypothetical, hence matching the exact same
        precondition rather than a superficially simpler one. No
        explicit `not starts_with("@@")` guard needed -- `scan_ident()`
        stops dead at `@` on its own, self-excluding the marked-root
        sibling case exactly the way `at_plain_var_decl`'s own inferred
        branch already does."""
        var save = self.pos
        if not self.try_consume("var"):
            self.pos = save
            return False
        self.skip_trivia()
        var name = self.scan_ident()
        if name.byte_length() == 0:
            self.pos = save
            return False
        self.skip_trivia()
        if not self.at_assignment():
            self.pos = save
            return False
        self.pos += 1
        self.skip_trivia()
        var receiver = self.scan_ident()
        if receiver.byte_length() == 0:
            self.pos = save
            return False
        if self.peek() != UInt8(ord(".")):
            self.pos = save
            return False
        self.pos += 1
        var method_name = self.scan_ident()
        if method_name.byte_length() == 0:
            self.pos = save
            return False
        var matched = self.peek() == UInt8(ord("("))
        self.pos = save
        return matched

    def at_bare_for_loop_over_bare_chain(mut self) raises -> Bool:
        """True if `self.pos` starts `for [var/ref ]<loop_var> in
        <bare_ident>.<ident>(` -- the bare-rooted mirror of `at_bare_for_
        loop_over_marked_chain`, for an iterated chain whose own root
        carries no `@@` either (`for a in addr2.get_thing():`). Requires
        the exact same shape `at_bare_rooted_chain` itself requires
        (receiver, `.`, method name, `(`), for the identical "guarantee
        it's actually consumed, not leaked" reason `at_bare_var_decl_
        over_bare_chain`'s own doc comment explains in full."""
        var save = self.pos
        if not (self.starts_with("for") and not is_ident_char(self.peek_at(3))):
            self.pos = save
            return False
        self.pos += 3
        self.skip_trivia()
        _ = self.try_consume("var")
        _ = self.try_consume("ref")
        self.skip_trivia()
        var loop_var = self.scan_ident()
        if loop_var.byte_length() == 0:
            self.pos = save
            return False
        self.skip_trivia()
        if not (self.starts_with("in") and not is_ident_char(self.peek_at(2))):
            self.pos = save
            return False
        self.pos += 2
        self.skip_trivia()
        var receiver = self.scan_ident()
        if receiver.byte_length() == 0:
            self.pos = save
            return False
        if self.peek() != UInt8(ord(".")):
            self.pos = save
            return False
        self.pos += 1
        var method_name = self.scan_ident()
        if method_name.byte_length() == 0:
            self.pos = save
            return False
        var matched = self.peek() == UInt8(ord("("))
        self.pos = save
        return matched

    def at_bare_call_chain(mut self) raises -> Bool:
        """True if `self.pos` starts `<bare_ident>(...)` (a call, its own
        argument list balanced) immediately followed by `.` or `[` -- a
        bare (never `@@`-marked) function's own call result, chained
        directly with no intermediate variable (`make_note(@@b).@@ref.
        name`). A pure lookahead, restoring `self.pos` either way.

        Checked *forward*, at the function name's own position, before
        the scanner ever steps into the argument list at all -- not
        backward from whatever marked step eventually follows the way
        `bare_root_before_dot` works for a variable-rooted chain. This
        matters concretely: the argument list can itself contain a
        genuine `@@`-marked reference (`@@b` above), which the scanner's
        own left-to-right walk would otherwise find and process as its
        own independent marker *before* ever reaching a later marked
        step to look backward from -- confirmed via a real crash (a
        negative-length "between text" slice in `rewrite_markers`'s own
        loop) when this was first built as a backward look instead.

        Purely syntactic -- doesn't check whether the identifier is
        actually a known function in `bare_function_returns` (the
        scanner has no access to that project-wide map); `handle_bare_
        call_chain` checks semantically and, when it isn't, just copies
        the call through unchanged, letting the outer loop's own
        ordinary scan continue normally into the trailing `.`/`[` text
        from there -- the same "matches far more often than it's acted
        on" shape `PLAIN_VAR_DECL`/`PLAIN_FOR_LOOP` already use.

        Requires the identifier itself *not* be preceded by `.` -- a
        confirmed, real bug found while investigating a *different*
        bare-rooted-chain gap: without this guard, `addr2.relocated(...)
        .@@owner` matched here too (this check has no idea what preceded
        `relocated`, purely forward), looking `relocated` up in `ctx.
        bare_function_returns` -- the *flat*, receiver-unaware map
        `build_bare_plain_function_returns` populates from every `def `
        line project-wide regardless of indentation -- as if it were a
        genuinely bare top-level function. Two different structs each
        declaring their own same-named method (`Widget.clone() -> Widget`
        and `Address.clone(...) -> Address`) collided in that flat map
        (last one scanned wins); confirmed via a real compile that `w.
        clone().@@dept` (`w` a `Widget`, no `dept` field at all) silently
        compiled as if `.clone()` returned `Address` instead, surfacing
        only as a confusing Mojo-level `'Widget' value has no attribute
        'sqrrl__dept'` error. A method call on any receiver (`.name(`)
        must go through `BARE_ROOTED_CHAIN`'s own receiver-type-aware
        lookup instead (`ctx.bare_method_returns[receiver_type][name]`,
        already correctly struct-scoped) -- never this flat map."""
        var save = self.pos
        if is_after_dot(self.source, save):
            return False
        var name = self.scan_ident()
        if name.byte_length() == 0 or self.peek() != UInt8(ord("(")):
            self.pos = save
            return False
        self.pos += 1
        _ = self.scan_call_args_to_close()
        var matched = self.peek() == UInt8(ord(".")) or self.peek() == UInt8(ord("["))
        self.pos = save
        return matched

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
        `sqrrl___world`": world-scope (`@@@:`), a top-level function
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
                        " needs 'sqrrl___world' ('@@@func(...)'), or ':' to"
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
                    # A bare `@@:` -- world-scope now needs `sqrrl___world`
                    # marked explicitly via `@@@:`, no silent two-`@` form.
                    raise self.err(
                        "InvalidSquirrelSyntax: '@@:' needs 'sqrrl___world'"
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
                        + "' needs 'sqrrl___world' -- write '@@@"
                        + ident
                        + "{...}'"
                    )
                elif (
                    self.peek() == UInt8(ord(".")) or self.peek() == UInt8(ord("["))
                    or (self.at_assignment() and is_after_dot(self.source, marker_start))
                ):
                    kind = MarkerKind.FIELD_ACCESS
                    # `n.@@ref...` -- a chain rooted at a *bare*
                    # (never `@@`-marked) plain-struct-typed local
                    # variable, this marker sitting at its own first
                    # marked step, not the chain's true root. Widen
                    # `marker_start` back to `n` itself so `parse_
                    # field_access` (extended to accept a bare
                    # entity name too) parses the whole thing as one
                    # chain, rather than treating `@@ref` as some
                    # unrelated, freestanding reference.
                    #
                    # The `at_assignment() and is_after_dot(...)` half is
                    # the *write* mirror of the same shape: `n.@@ref =
                    # value` never has a trailing `.`/`[` (the marked
                    # field is always the chain's own last step for a
                    # write), so the read-only trigger above would never
                    # catch it -- confirmed as a real, silent gap via a
                    # real compile: `addr2.@@nonexistent = @@bob` (`addr2`
                    # bare, `nonexistent` not even a real field) fell
                    # through to plain `NAME_REF` entirely, which has no
                    # idea it's preceded by `addr2.` at all, and just
                    # blindly renamed it to `sqrrl__nonexistent` -- no
                    # error until Mojo's own compile stage, confusingly
                    # far from the actual cause. `is_after_dot` (not just
                    # `at_assignment()` alone) is required here so a
                    # genuine root-level `@@x = value`/`var @@x = value`
                    # (never preceded by `.`) still goes through `NAME_
                    # REF` exactly as before -- only a `.`-preceded write
                    # is redirected here.
                    #
                    # A bare *function call*'s own result chained the
                    # same way (`make_note(@@b).@@ref`) is deliberately
                    # NOT handled via an equivalent backward look here --
                    # by the time the scanner reaches `@@ref`, it has
                    # already independently found and processed any
                    # `@@`-marked argument *inside* the call (`@@b`) as
                    # its own separate marker, emitting it and advancing
                    # the outer loop's own position tracker past that
                    # point. Rewinding back to the call's own name at
                    # this point would try to re-process text the outer
                    # loop already consumed, producing a negative-length
                    # "between text" slice (confirmed via a real crash).
                    # `MarkerKind.BARE_CALL_CHAIN` (`at_bare_call_chain`,
                    # in the fallback chain below) instead detects this
                    # *forward*, at the function name's own position,
                    # before the scanner ever steps into the argument
                    # list at all -- the same reason `PLAIN_VAR_DECL`/
                    # `PLAIN_FOR_LOOP` are also forward, not backward,
                    # checks.
                    var bare_root_start = bare_root_before_dot(self.source, marker_start)
                    if bare_root_start >= 0:
                        marker_start = bare_root_start
                elif self.peek() == UInt8(ord("(")):
                    # `@@ident(...)` -- a function (definition or call site)
                    # that returns an '@@'-marked value but needs no
                    # 'sqrrl___world' of its own (mandatory marking: any
                    # function whose return type involves an '@@'-marked
                    # value must be marked, plain '@@' if it doesn't also
                    # need 'sqrrl___world', '@@@' -- never both -- if it
                    # does). The scanner can't yet tell whether `ident`
                    # actually returns such a value at all (that needs
                    # `function_returns`, a project-wide, build-time-only
                    # map) -- `rewrite.mojo`'s own handling validates that
                    # once rewriting reaches this point, same split every
                    # other semantic check in this file already uses.
                    kind = MarkerKind.ENTITY_FUNC
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
                elif self.at_assignment() and is_after_open_paren_or_comma(self.source, marker_start):
                    # `Note(@@owner=@@b)` -- a hand-written plain struct's
                    # own `@fieldwise_init`-derived constructor call, the
                    # keyword argument spelled the same marked way the
                    # field itself is declared (`var @@owner: @@Beta`)
                    # rather than the raw internal `sqrrl__owner` name.
                    # Preceded by `(`/`,` and followed by a real `=` (not
                    # `==`) is the one shape nothing else in the grammar
                    # already means -- `@@Type{...}`'s own construct-field
                    # syntax uses `.@@field = value` (a `.` precedes it,
                    # a completely different dispatch branch above), and a
                    # var-decl's own initializer is never preceded by `(`/
                    # `,` this way.
                    kind = MarkerKind.CONSTRUCT_KWARG
                else:
                    kind = MarkerKind.NAME_REF
                self.pos = marker_start
                return kind
            if self.at_plain_var_decl():
                return MarkerKind.PLAIN_VAR_DECL
            if self.at_bare_var_decl_over_marked_chain():
                return MarkerKind.BARE_VAR_DECL_OVER_ENTITY
            if self.at_bare_var_decl_over_bare_chain():
                return MarkerKind.BARE_VAR_DECL_OVER_BARE_CHAIN
            if self.at_plain_for_loop():
                return MarkerKind.PLAIN_FOR_LOOP
            if self.at_bare_for_loop_over_marked_chain():
                return MarkerKind.BARE_FOR_ENTITY_LOOP
            if self.at_bare_for_loop_over_bare_chain():
                return MarkerKind.BARE_FOR_LOOP_OVER_BARE_CHAIN
            if self.at_bare_rooted_chain():
                return MarkerKind.BARE_ROOTED_CHAIN
            if self.at_bare_call_chain():
                return MarkerKind.BARE_CALL_CHAIN
            self.pos += 1

    def at_wrapped_entity_param(mut self) raises -> Bool:
        """True if, from the current position, the text matches
        `Ident[...]` where the bracketed body contains an `@@`-marked
        argument *somewhere* -- immediately (`List[@@Person]`), in a
        non-first position of a multi-argument wrapper (`Dict[String,
        @@Employee]`), or nested inside a further container (`List[Dict[
        String, @@Employee]]`) -- not just `Ident[@@` (a single-wrapper,
        single-argument-only lookahead, the old, narrower version of this
        check). Restores `self.pos` before returning either way -- purely
        a lookahead; a genuinely unterminated `[` still raises (a real
        syntax error, not something a lookahead should silently swallow)."""
        var save = self.pos
        var wrapper = self.scan_ident()
        if wrapper.byte_length() == 0:
            self.pos = save
            return False
        self.skip_trivia()
        if self.peek() != UInt8(ord("[")):
            self.pos = save
            return False
        var body = self.scan_bracketed_span()
        var result = "@@" in body
        self.pos = save
        return result

    def scan_entity_param_type_text(mut self) raises -> String:
        """Scans an entity param's (or a hand-written struct's own field
        declaration's) raw type text -- from `self.pos` up to the next
        top-level `,`/`)`/`='/newline (ignoring any nested inside `[]`/
        `()`/`{}`), or end of input -- `scan_bracket_depth_aware_span`
        with a wider terminator set than `scan_type`'s own (a `@@struct`
        field is only ever terminated by `,`/newline; an entity param can
        also be the last one before a def's closing `)`, or a var-decl's
        own `= value`). `@@` markers, at any depth, are left exactly as
        written -- `parse_type_expr`/`rewritten_field_type` (the same
        general machinery a struct field's own type already goes
        through) resolve the whole shape uniformly downstream, arbitrary
        nesting and argument count included; this scan's only job is
        finding where the type text *ends*."""
        return self.scan_bracket_depth_aware_span(",)=\n")

    def parse_entity_param(mut self) raises -> EntityParam:
        """Requires `self.pos` at the `@@` of `@@name: <type>` -- `<type>`
        may be a bare relation (`@@Type`) or any container/argument shape
        a `@@struct`'s own field declaration already supports (`List[
        @@Type]`, `Dict[String, @@Type]`, `List[Dict[String, @@Type]]`,
        ...), scanned generally via `scan_entity_param_type_text` rather
        than the old single-wrapper, single-argument-only grammar.

        Marking symmetry (mandatory-marking-narrowing milestone, "or
        methods or functions" -- the same rule `field_parsing.mojo`
        already enforces for a struct's own fields applies equally to a
        `def`'s own parameter and a `var`-decl's own explicit type): the
        name is marked here by construction (the `@@` this method itself
        just consumed), so the type must actually be `is_directly_entity_
        iterable` too, or this raises -- `@@name: Dict[String, @@Type]`
        (a relation confined to the value position) is exactly as invalid
        here as an unmarked struct field naming a directly-iterable type
        would be; write the plain, unmarked form (`name: Dict[String,
        @@Type]`) instead, letting the embedded `@@Type` resolve via the
        ordinary type-position rewrite."""
        if not self.try_consume("@@"):
            raise self.err("InvalidSquirrelSyntax: expected '@@'")
        var name = self.scan_ident()
        if name.byte_length() == 0:
            raise self.err("InvalidSquirrelSyntax: expected entity parameter name")
        self.skip_trivia()
        if not self.try_consume(":"):
            raise self.err("InvalidSquirrelSyntax: expected ':' after entity parameter name")
        self.skip_trivia()
        var type_text = self.scan_entity_param_type_text()
        if type_text.byte_length() == 0:
            raise self.err("InvalidSquirrelSyntax: expected a type after ':'")
        if not is_directly_entity_reachable(type_text):
            raise self.err(
                "InvalidSquirrelSyntax: '@@"
                + name
                + "' -- '"
                + type_text
                + "' isn't directly reachable as an entity (a relation"
                " confined to a container's non-key/non-sole position, or"
                " nested too deep, never earns '@@' marking on the name"
                " itself) -- write '"
                + name
                + ": "
                + type_text
                + "' (no '@@' on the name)"
            )
        return EntityParam(name=name, type_text=type_text)

    def parse_construct(mut self) raises -> Construct:
        """Requires `self.pos` at the `@@@` of a `@@@TypeName { ... }`
        construct -- construction always needs `sqrrl___world` (M3 addendum),
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
        (`@@@Type.method(...)`, needs `sqrrl___world`); plain `@@` marks a
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
        var entity: String
        var entity_is_bare = False
        if entity_marked_world or self.try_consume("@@"):
            entity = self.scan_ident()
            if entity.byte_length() == 0:
                raise self.err("InvalidSquirrelSyntax: expected entity name")
        else:
            # A chain can also start at a *bare* (never `@@`-marked)
            # identifier -- a plain-struct-typed local variable's own
            # name, e.g. `n.@@ref.name` -- reachable only via `find_next_
            # marker`'s own backward look (`bare_root_before_dot`), which
            # rewinds `self.pos` to the identifier's start before this is
            # ever called; every *other* caller still always finds
            # '@@'/'@@@' here first, unchanged. `entity_marked_world`
            # stays `False` for this shape -- a bare-rooted chain can
            # never be a table-level call, always written with the
            # marked `@@@Type.method(...)` spelling instead.
            entity = self.scan_ident()
            if entity.byte_length() == 0:
                raise self.err("InvalidSquirrelSyntax: expected '@@'")
            entity_is_bare = True

        var steps = self.scan_access_steps()
        if len(steps) == 0:
            raise self.err(
                "InvalidSquirrelSyntax: expected '.' or '[' after"
                " entity/relation name"
            )
        var tail = self.scan_call_or_write_tail()
        return FieldAccess(
            entity=entity,
            entity_marked_world=entity_marked_world,
            entity_is_bare=entity_is_bare,
            steps=steps^,
            is_call=tail.is_call,
            write_value=tail.write_value,
        )

    def scan_access_steps(mut self) raises -> List[AccessStep]:
        """Scans a chain of `.field`/`.@@field`/`.@@@field`/`[index]`
        segments from `self.pos` for as long as one keeps following --
        the general recursive access-chain loop, factored out of `parse_
        field_access` so it's also usable rooted at something other than
        a bound `@@entity` (the return value of an `@@`/`@@@`-marked
        function call, `@@get_dept(@@alice).name` -- mandatory-marking
        milestone). May return an empty list -- whether that's valid is
        the caller's own concern (`parse_field_access` requires at least
        one step; a bare call's own trailing-chain scan doesn't)."""
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
                # own `@@@`-marked declaration (needs `sqrrl___world`).
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
        return steps^

    def scan_call_or_write_tail(mut self) raises -> AccessChainTail:
        """Requires `self.pos` right after the last step `scan_access_
        steps` produced (or right after an entity/call with zero steps).
        Classifies what follows: an immediate `(` is a call (table-level,
        or an instance method on the walked terminal type -- `is_call`),
        an `=` is a write (`write_value` holds the raw, unparsed
        right-hand side), anything else is an ordinary read. Factored out
        of `parse_field_access` for the same reuse reason `scan_access_
        steps` was."""
        var after_chain = self.pos
        self.skip_trivia()
        if self.peek() == UInt8(ord("(")):
            self.pos = after_chain
            return AccessChainTail(is_call=True, write_value=None)

        if not self.at_assignment():
            self.pos = after_chain
            return AccessChainTail(is_call=False, write_value=None)

        self.pos += 1  # consume '='
        self.skip_whitespace()
        var value = self._scan_write_value_span()
        return AccessChainTail(is_call=False, write_value=String(value))

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
        function that needs `sqrrl___world`, whether this is its own
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

    def parse_entity_func(mut self) raises -> String:
        """Requires `self.pos` at the `@@` (exactly two `@`s -- `@@@` is
        `parse_world_func`'s own case) of `@@name(` -- a top-level
        function that returns an `@@`-marked value but needs no
        `sqrrl___world` of its own (mandatory-marking milestone), whether
        this is its own definition or a call site. Consumes through the
        opening `(` and returns `name`. Mirrors `parse_world_func`
        exactly, minus the third `@`."""
        if not self.try_consume("@@"):
            raise self.err("InvalidSquirrelSyntax: expected '@@'")
        var name = self.scan_ident()
        if name.byte_length() == 0:
            raise self.err("InvalidSquirrelSyntax: expected function name")
        self.skip_trivia()
        if not self.try_consume("("):
            raise self.err("InvalidSquirrelSyntax: expected '(' after function name")
        return name

    def scan_call_args_to_close(mut self) raises -> String:
        """Requires `self.pos` already just past a call's own opening `(`
        (as `parse_world_func`/`parse_entity_func` both leave it). Returns
        the raw, untrimmed argument-list text and advances `self.pos` past
        the matching `)` -- mirrors `_parse_json_call_arg`'s own depth-
        tracking tail, minus the "consume the opening '(' myself" part
        (the caller already did, via one of the two `parse_*_func`s
        above, before it even knows yet whether this call needs a
        trailing-chain resolution or not)."""
        return self.scan_balanced_span_body(
            UInt8(ord("(")), UInt8(ord(")")), "InvalidSquirrelSyntax: unterminated '(' in function call"
        )

    def peek_trailing_chain_follows(mut self) -> Bool:
        """Pure lookahead (restores `self.pos` either way): true if,
        skipping trivia from `self.pos`, the next byte is `.` or `[` --
        i.e. a function call's return value continues into a `.field`/
        `[index]` access chain rather than ending there (mandatory-
        marking milestone)."""
        var save = self.pos
        self.skip_trivia()
        var b = self.peek()
        var follows = b == UInt8(ord(".")) or b == UInt8(ord("["))
        self.pos = save
        return follows

    def peek_marked_field_name(mut self) -> Optional[String]:
        """Pure lookahead (restores `self.pos` either way): if, skipping
        trivia from `self.pos`, the next thing is `.` immediately
        followed by `@@`, returns the marked field's own name; else
        `None`. Lets `_handle_instance_call`'s plain-struct-owner branch
        catch a marked field chained off an *untracked* call's own
        return value right at the call site (`addr.copy().@@dept`,
        `.copy()` never registered) instead of downstream, once the
        scanner rediscovers `@@dept` on its own and treats it as an
        unrelated, freestanding reference -- the same "confusing error
        two steps removed from the actual cause" `peek_trailing_chain_
        follows`'s own callers are built to avoid, just checking for a
        *marked* continuation specifically rather than any continuation
        at all."""
        var save = self.pos
        self.skip_trivia()
        var result: Optional[String] = None
        if self.peek() == UInt8(ord(".")):
            self.pos += 1
            self.skip_trivia()
            if self.starts_with("@@"):
                self.pos += 2
                var name = self.scan_ident()
                if name.byte_length() > 0:
                    result = Optional[String](name)
        self.pos = save
        return result

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
        var raw = self.scan_balanced_span_body(
            UInt8(ord("(")), UInt8(ord(")")), "InvalidSquirrelSyntax: unterminated '(' in '" + call_text + "(...)'"
        )
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
