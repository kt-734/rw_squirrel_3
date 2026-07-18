from std.memory import UnsafePointer
from std.collections import Set


def sqrrl__movable_rebind[Src: Movable & ImplicitlyDeletable, Dst: Movable & ImplicitlyDeletable](var src: Src) -> Dst:
    """Moves `src` out as `Dst`, for exactly one situation: a generic
    function bound only by `Movable` (not `Copyable`) needs to return a
    value it just built at a *concrete* type (inside a `comptime if T ==
    ConcreteType:` branch) as its own abstract `T`. `rebind[T](src)`
    alone can't do this -- confirmed via two separate real-compiler
    spikes: `rebind[T](src)` (no `^`) demands `T: ImplicitlyCopyable`
    (never guaranteed generically); appending `^` directly to `rebind`'s
    own call expression fails outright ("expression does not designate a
    value with an origin"); and `.copy()` after `rebind[T](src)` -- the
    one combination confirmed to work elsewhere in this file -- requires
    `T: Copyable`, which a custom, Movable-only container wrapper (no
    guaranteed copy constructor at all) doesn't have.

    Goes through a real, tracked move instead of a raw pointer trick:
    `List[Dst](unsafe_uninit_length=1)` reserves one *uninitialized* slot
    (Mojo's own list-growth primitive, not a hand-rolled allocation),
    `init_pointee_move` placement-constructs `src` into it bitcast as
    `Src` (same underlying representation as `Dst` -- guaranteed by the
    caller's own `T == ConcreteType` check, never asserted here), and
    `.pop()` moves the now-valid `Dst` back out, decrementing the list's
    own tracked length to zero so nothing double-destroys it. Confirmed
    via a direct spike this is actually necessary, not just cautious:
    reinterpreting a *stack* local's own address via `UnsafePointer(to=
    src).bitcast[Dst]().take_pointee()` compiles fine but crashes at
    runtime the moment `Src` owns a heap allocation (a double-free) --
    `src`'s own scope-exit destructor still runs, because nothing told
    Mojo's move-tracking `src`'s bytes were already stolen. Going through
    `List`'s own tracked length instead avoids that: the list -- not a
    bare stack slot with its own independent destructor -- is what owns
    the slot's lifetime, and popping it updates that tracked length
    directly."""
    var buf = List[Dst](unsafe_uninit_length=1)
    var raw = buf.unsafe_ptr().bitcast[UInt8]()
    raw.bitcast[Src]().init_pointee_move(src^)
    return buf.pop()


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


def sqrrl__to_json_default[T: AnyType](value: T) -> String:
    """Generic, reflection-based JSON serializer for *any* value -- a leaf
    scalar, a real entity wrapper (`conforms_to(T, sqrrl__JsonSerializable)`
    -- always just its own bare id, the row itself dumped once, separately,
    by its own table), or (plain-structs milestone) a plain struct at any
    nesting depth, discovered by the compiler or not: `reflect[T]` walks its
    field names/types/byte offsets at comptime, recursing back into this
    same function per field. Matches rw_squirrel_1/2's own promise that a
    plain struct's `to_json` needs no generated code and no DSL-side
    declaration at all.

    This is *not* the function generated/spliced code calls directly any
    more (that's the per-project-generated `sqrrl__to_json[T]` in `sqrrl__
    json.mojo`, one dispatch-table branch per concrete container type the
    schema actually uses, falling through to this exact function for
    everything else) -- split out under this name (rather than staying
    `sqrrl__to_json` and living with a naming collision against the
    generated function) so the leaf/`JsonSerializable`/reflect-fallback
    core stays a static, directly unit-testable function on its own,
    matching rw_squirrel_2's own equivalent split (`container_types`-driven
    generation layered in front of a fixed core) -- confirmed by reading
    their real source, not assumed. `reflect[T]` genuinely can't walk a
    `List`/`Set`/`Dict`/`Optional`'s own internal representation (no named
    fields to introspect), which is why a container reaching *this*
    function's own final `else` would fail outright -- the per-project
    dispatcher's whole job is to intercept exactly that case first, via an
    exact `T == ConcreteContainerType` comptime match (the only kind of
    check available: there's no way to ask Mojo's own type system "is `T`
    a container of anything" generically, confirmed via a direct spike
    that `List`/`Set`/`Optional`/`Dict` can't be given a new trait
    conformance from outside their own stdlib declaration either -- no
    `extension`-style mechanism exists in this Mojo build)."""
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
            out += '"' + String(names[i]) + '":' + sqrrl__to_json_default(field_ptr[])
        out += "}"
        return out^


def sqrrl__from_json_default[T: Movable & ImplicitlyDeletable](mut sc: sqrrl__JsonScanner) raises -> T:
    """The reload-direction counterpart to `sqrrl__to_json_default` -- but
    with no reflect-based fallback at all: writing a value back into a
    reflected field requires `Ti` to prove `Movable` as an explicit type
    argument to `UnsafePointer.init_pointee_move`, and `reflect[T].field_
    types()` only ever hands back `AnyType`-bounded types, with no way to
    widen that to satisfy a trait bound generically -- confirmed via two
    independent real-compiler spikes (a direct call, and one gated behind
    `conforms_to(Ti, Movable)`, which still fails to unify two separately-
    computed "Movable-narrowed" views of the same `Ti`). So every leaf
    branch here is the only thing this function can offer; anything else
    (a container, a plain struct, a genuinely undiscovered type) needs the
    per-project-generated `sqrrl__from_json[T]` (`sqrrl__json.mojo`) to
    recognize it via an exact `T == ConcreteType` match and route to
    generated/hand-written reconstruction code instead -- this function is
    that dispatcher's own final fallback, for the plain leaf case.

    Bound by `Movable`, not `Copyable` -- widened once a custom, Movable-
    only container wrapper (no guaranteed copy constructor at all) turned
    out to reach this same dispatch mechanism too (`driver/json_module.
    mojo`'s own doc comment has the full story) -- so every branch here
    goes through `sqrrl__movable_rebind` (this file's own doc comment on
    it explains exactly why `rebind[T](v).copy()` alone doesn't work
    generically) instead of `rebind[T](v).copy()`."""
    comptime if T == String:
        var v = sc.parse_json_string()
        return sqrrl__movable_rebind[String, T](v^)
    elif T == Bool:
        var v = sc.parse_json_bool()
        return sqrrl__movable_rebind[Bool, T](v)
    elif T == Int:
        var v = sc.parse_json_int()
        return sqrrl__movable_rebind[Int, T](v)
    elif T == Int8:
        var v = Int8(sc.parse_json_int())
        return sqrrl__movable_rebind[Int8, T](v)
    elif T == Int16:
        var v = Int16(sc.parse_json_int())
        return sqrrl__movable_rebind[Int16, T](v)
    elif T == Int32:
        var v = Int32(sc.parse_json_int())
        return sqrrl__movable_rebind[Int32, T](v)
    elif T == Int64:
        var v = Int64(sc.parse_json_int())
        return sqrrl__movable_rebind[Int64, T](v)
    elif T == UInt8:
        var v = UInt8(sc.parse_json_int())
        return sqrrl__movable_rebind[UInt8, T](v)
    elif T == UInt16:
        var v = UInt16(sc.parse_json_int())
        return sqrrl__movable_rebind[UInt16, T](v)
    elif T == UInt32:
        var v = UInt32(sc.parse_json_int())
        return sqrrl__movable_rebind[UInt32, T](v)
    elif T == UInt64:
        var v = UInt64(sc.parse_json_int())
        return sqrrl__movable_rebind[UInt64, T](v)
    elif T == Float64:
        var v = sc.parse_json_float()
        return sqrrl__movable_rebind[Float64, T](v)
    elif T == Float32:
        var v = Float32(sc.parse_json_float())
        return sqrrl__movable_rebind[Float32, T](v)
    else:
        raise Error("sqrrl__from_json: unsupported type -- structs/containers use their own generated from_json")


# `list_to_json`/`list_from_json`/`pairs_to_json`/`pairs_from_json` -- the
# shared "dump/parse a List[T]/List[Tuple[K, V]] as a JSON array" helpers
# every 1-/2-type-argument wrapper's own adapter (below) feeds into -- are
# deliberately generated per-project into `sqrrl__json.mojo` instead of
# living here as static code (unlike rw_squirrel_2's own identical
# helpers, confirmed by reading their real source): they recurse via
# `sqrrl__to_json`/`sqrrl__from_json`, which are themselves per-project
# generated (one dispatch-table branch per concrete container/plain-
# struct-instantiation type the schema actually needs) -- and `sqrrl__
# json.mojo` is only generated *at all* when some file in the project
# actually touches JSON (`driver/convert_directory.mojo`'s lazy-generation
# fix), while this file (`squirrel_runtime/json.mojo`) is copied into
# *every* project unconditionally, JSON-using or not (`sqrrl__
# JsonSerializable`'s conformance is added to every entity regardless).
# A static top-level `from sqrrl__json import sqrrl__to_json, sqrrl__
# from_json` here would make this file fail to parse for any project that
# doesn't generate one -- confirmed this constraint doesn't apply to
# rw_squirrel_2 the same way (no lazy-generation feature there, `sqrrl__
# json.mojo` always exists), so their exact file-layout choice doesn't
# carry over unmodified.


def sqrrl__List_json_to_list[T: Copyable](container: List[T]) -> List[T]:
    """Built-in-wrapper adapter for `List` itself -- the identity, since
    `List` already *is* the generic shape every 1-argument wrapper's own
    JSON dump converts to first. Exists (rather than special-casing `List`
    out of the dispatch table entirely) so `List`/`Set`/`Optional`/a custom
    wrapper all go through the exact same generated dispatch-table shape,
    with zero special cases for the three built-in ones -- see `driver/
    json_module.mojo`'s own doc comment for why this matters."""
    return container.copy()


def sqrrl__List_json_from_list[T: Movable & ImplicitlyDeletable](var items: List[T]) -> List[T]:
    return items^


def sqrrl__Set_json_to_list[T: Copyable & ImplicitlyDeletable & Hashable & Equatable](container: Set[T]) -> List[T]:
    var out = List[T]()
    for elem in container:
        out.append(elem.copy())
    return out^


def sqrrl__Set_json_from_list[
    T: Copyable & ImplicitlyDeletable & Hashable & Equatable
](var items: List[T]) -> Set[T]:
    var out = Set[T]()
    for item in items:
        out.add(item.copy())
    return out^


def sqrrl__Optional_json_to_list[T: Copyable](container: Optional[T]) -> List[T]:
    var out = List[T]()
    if container:
        out.append(container.value().copy())
    return out^


def sqrrl__Optional_json_from_list[T: Movable & ImplicitlyDeletable](var items: List[T]) raises -> Optional[T]:
    if len(items) == 0:
        return None
    if len(items) > 1:
        raise Error("InvalidJson: Optional field has more than one value")
    return items.pop()


def sqrrl__Dict_json_to_pairs[
    K: Copyable & ImplicitlyDeletable & Hashable & Equatable, V: Copyable & ImplicitlyDeletable
](container: Dict[K, V]) -> List[Tuple[K, V]]:
    var out = List[Tuple[K, V]]()
    for entry in container.items():
        out.append((entry.key.copy(), entry.value.copy()))
    return out^


def sqrrl__Dict_json_from_pairs[
    K: Copyable & ImplicitlyDeletable & Hashable & Equatable, V: Copyable & ImplicitlyDeletable
](var pairs: List[Tuple[K, V]]) -> Dict[K, V]:
    var out = Dict[K, V]()
    for pair in pairs:
        out[pair[0].copy()] = pair[1].copy()
    return out^
