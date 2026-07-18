from std.memory import UnsafePointer


trait sqrrl__JsonSerializable:
    """Conformance marker for a generated entity wrapper (`sqrrl__<Name>`,
    added to its trait list by `codegen/entity.mojo`'s `emit_entity`) --
    `sqrrl__to_json(self)` is always just the row's own bare id (the row
    itself is serialized once, separately, as part of its own table's dump
    in `sqrrl__json.mojo` -- never inline at every place a relation field
    references it)."""

    def sqrrl__to_json(self) -> String:
        ...


def sqrrl__escape_json_string(s: String) -> String:
    """Escapes '"'/'\\' and the control characters JSON requires escaped
    (newline/tab/carriage-return) -- deliberately narrow, matching this
    module's own known limitation (no `\\uXXXX` support on the parse side
    either, see `sqrrl__JsonScanner.parse_json_string`'s own doc comment):
    any other control byte passes through unescaped rather than being
    silently misrepresented."""
    var out = String()
    var bytes = s.as_bytes()
    var run_start = 0
    for i in range(len(bytes)):
        var b = bytes[i]
        if b != UInt8(ord('"')) and b != UInt8(ord("\\")) and b != UInt8(ord("\n")) and b != UInt8(ord("\t")) and b != UInt8(ord("\r")):
            continue
        var escape: String
        if b == UInt8(ord('"')):
            escape = '\\"'
        elif b == UInt8(ord("\\")):
            escape = "\\\\"
        elif b == UInt8(ord("\n")):
            escape = "\\n"
        elif b == UInt8(ord("\t")):
            escape = "\\t"
        else:
            escape = "\\r"
        out += String(s[byte = run_start : i]) + escape
        run_start = i + 1
    out += String(s[byte = run_start : len(bytes)])
    return out^


def sqrrl__json_string_literal(v: String) -> String:
    """A JSON string literal for `v`, quoted and escaped -- the shape every
    `String`-typed field's own `sqrrl__to_json` emits a call to."""
    return '"' + sqrrl__escape_json_string(v) + '"'


def sqrrl__json_bool_literal(v: Bool) -> String:
    """`Bool`'s own JSON spelling is lowercase (`true`/`false`) -- distinct
    from `String(Bool)`'s Python-style `True`/`False`, so every `Bool`-typed
    field's own `sqrrl__to_json` routes through this instead of a bare
    `String(...)` the way every numeric leaf type can."""
    return "true" if v else "false"


def _is_json_digit(b: UInt8) -> Bool:
    return b >= UInt8(ord("0")) and b <= UInt8(ord("9"))


struct sqrrl__JsonScanner(Movable):
    """A cursor over a whole-world JSON dump's source text -- `sqrrl__<Name>
    _from_json_with_id`/`sqrrl__world_from_json` (generated, `sqrrl__json.
    mojo`) drive it directly rather than through any parsed intermediate
    tree, mirroring the DSL parser's own `Scanner` (`squirrel_compiler.
    parser.scanner`) in spirit -- a purpose-built cursor over exactly the
    grammar this one format needs, not a general JSON library."""

    var source: String
    var pos: Int

    def __init__(out self, var source: String):
        self.source = source^
        self.pos = 0

    def at_end(self) -> Bool:
        return self.pos >= self.source.byte_length()

    def peek(self) -> UInt8:
        if self.at_end():
            return 0
        return self.source.as_bytes()[self.pos]

    def skip_ws(mut self):
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

    def expect_byte(mut self, b: UInt8) raises:
        """Skips whitespace, then requires `b` next -- for the fixed
        structural bytes (`{`/`}`/`[`/`]`/`:`/`,`) generated code splices
        directly around every recursive `parse_*` call."""
        self.skip_ws()
        if self.at_end() or self.peek() != b:
            raise Error(
                "InvalidJson: expected byte "
                + String(b)
                + " at byte "
                + String(self.pos)
            )
        self.pos += 1

    def try_consume_byte(mut self, b: UInt8) -> Bool:
        """Like `expect_byte`, but reports success instead of raising --
        what a `,`-separated loop's own "is there another element" check
        uses."""
        self.skip_ws()
        if not self.at_end() and self.peek() == b:
            self.pos += 1
            return True
        return False

    def try_consume_literal(mut self, literal: String) -> Bool:
        """Skips whitespace, then consumes `literal` verbatim if it's next
        -- what `parse_json_bool` uses for `true`/`false`."""
        self.skip_ws()
        var end = self.pos + literal.byte_length()
        if end > self.source.byte_length():
            return False
        if self.source[byte = self.pos : end] == literal:
            self.pos = end
            return True
        return False

    def parse_json_string(mut self) raises -> String:
        """No `\\uXXXX` escape support (known limitation, matching this
        module's own doc comment) -- every other standard escape
        (`\\"`/`\\\\`/`\\/`/`\\n`/`\\t`/`\\r`) is handled. Slices unescaped
        runs directly out of the source rather than rebuilding byte-by-byte,
        which also means a multi-byte UTF-8 sequence in the source passes
        through a run untouched (every byte of it is >= 0x80, so it can
        never be mistaken for the ASCII '\"'/'\\\\' bytes this scans for)."""
        self.skip_ws()
        if self.at_end() or self.peek() != UInt8(ord('"')):
            raise Error("InvalidJson: expected string at byte " + String(self.pos))
        self.pos += 1
        var out = String()
        var run_start = self.pos
        while True:
            if self.at_end():
                raise Error("InvalidJson: unterminated string")
            var b = self.peek()
            if b == UInt8(ord('"')):
                out += String(self.source[byte = run_start : self.pos])
                self.pos += 1
                break
            if b == UInt8(ord("\\")):
                out += String(self.source[byte = run_start : self.pos])
                self.pos += 1
                if self.at_end():
                    raise Error("InvalidJson: unterminated escape in string")
                var e = self.peek()
                if e == UInt8(ord('"')):
                    out += '"'
                elif e == UInt8(ord("\\")):
                    out += "\\"
                elif e == UInt8(ord("/")):
                    out += "/"
                elif e == UInt8(ord("n")):
                    out += "\n"
                elif e == UInt8(ord("t")):
                    out += "\t"
                elif e == UInt8(ord("r")):
                    out += "\r"
                else:
                    raise Error(
                        "InvalidJson: unsupported escape sequence at byte "
                        + String(self.pos)
                        + " (no '\\uXXXX' support)"
                    )
                self.pos += 1
                run_start = self.pos
            else:
                self.pos += 1
        return out^

    def parse_json_int(mut self) raises -> Int:
        self.skip_ws()
        var start = self.pos
        if not self.at_end() and self.peek() == UInt8(ord("-")):
            self.pos += 1
        var digit_start = self.pos
        while not self.at_end() and _is_json_digit(self.peek()):
            self.pos += 1
        if self.pos == digit_start:
            raise Error("InvalidJson: expected integer at byte " + String(start))
        var text = String(self.source[byte = start : self.pos])
        try:
            return Int(text)
        except:
            raise Error("InvalidJson: malformed integer '" + text + "'")

    def parse_json_float(mut self) raises -> Float64:
        self.skip_ws()
        var start = self.pos
        if not self.at_end() and self.peek() == UInt8(ord("-")):
            self.pos += 1
        while not self.at_end() and (
            _is_json_digit(self.peek())
            or self.peek() == UInt8(ord("."))
            or self.peek() == UInt8(ord("e"))
            or self.peek() == UInt8(ord("E"))
            or self.peek() == UInt8(ord("+"))
            or self.peek() == UInt8(ord("-"))
        ):
            self.pos += 1
        var text = String(self.source[byte = start : self.pos])
        try:
            return Float64(text)
        except:
            raise Error("InvalidJson: malformed number '" + text + "'")

    def parse_json_bool(mut self) raises -> Bool:
        if self.try_consume_literal("true"):
            return True
        if self.try_consume_literal("false"):
            return False
        raise Error("InvalidJson: expected 'true'/'false' at byte " + String(self.pos))


def sqrrl__to_json[T: AnyType](value: T) -> String:
    """Generic, reflection-based JSON serializer for *any* value -- a leaf
    scalar, a real entity wrapper (`conforms_to(T, sqrrl__JsonSerializable)`
    -- always just its own bare id, the row itself dumped once, separately,
    by its own table), or (plain-structs milestone) a plain struct at any
    nesting depth, discovered by the compiler or not: `reflect[T]` walks its
    field names/types/byte offsets at comptime, recursing back into this
    same function per field. Matches rw_squirrel_1/2's own promise that a
    plain struct's `to_json` needs no generated code and no DSL-side
    declaration at all -- unlike rw_squirrel_2's own version of this
    dispatcher, this one needs no per-project generation either (no way to
    ask "is T a container of anything" generically is fine here, since
    rw_squirrel_3 doesn't route a wrapped/container relation field through
    this function at all -- `driver/json_module.mojo` handles `multi`'s own
    `Set[@@Target]` iteration separately, calling this function once per
    *element*, never on the container itself).

    Live-spiked and confirmed compiling against this project's pinned
    nightly before being wired in here."""
    comptime if T == String:
        return sqrrl__json_string_literal(rebind[String](value))
    elif T == Bool:
        return sqrrl__json_bool_literal(rebind[Bool](value))
    elif T == Int:
        return String(rebind[Int](value))
    elif T == Int8:
        return String(rebind[Int8](value))
    elif T == Int16:
        return String(rebind[Int16](value))
    elif T == Int32:
        return String(rebind[Int32](value))
    elif T == Int64:
        return String(rebind[Int64](value))
    elif T == UInt8:
        return String(rebind[UInt8](value))
    elif T == UInt16:
        return String(rebind[UInt16](value))
    elif T == UInt32:
        return String(rebind[UInt32](value))
    elif T == UInt64:
        return String(rebind[UInt64](value))
    elif T == Float64:
        return String(rebind[Float64](value))
    elif T == Float32:
        return String(rebind[Float32](value))
    elif conforms_to(T, sqrrl__JsonSerializable):
        return rebind[T](value).sqrrl__to_json()
    else:
        comptime r = reflect[T]
        comptime names = r.field_names()
        comptime ts = r.field_types()
        var p = UnsafePointer(to=value).bitcast[UInt8]()
        var out = String("{")
        comptime for i in range(r.field_count()):
            comptime Ti = ts[i]
            comptime off = r.field_offset[index=i]()
            var field_ptr = (p + off).bitcast[Ti]()
            if i > 0:
                out += ","
            out += '"' + String(names[i]) + '":' + sqrrl__to_json(field_ptr[])
        out += "}"
        return out^
