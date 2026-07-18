from std.memory import ArcPointer


@fieldwise_init
struct TypeExpr(Copyable, Movable, ImplicitlyDeletable):
    """A parsed field-type expression -- "is this a container / what's its
    element / what's this generic instantiation's base name" parses into
    this tree once instead of ad hoc bracket-depth string scanning at every
    call site.

    - `LEAF`: a bare, unparameterized identifier with no `@@` and no
      `[...]` -- `String`, `UInt32`, or a plain type name used directly.
    - `RELATION`: `@@Employee` -- a relation field's target. `name` is the
      target's bare name (`@@` already stripped).
    - `PARAMETERIZED`: `Ident[arg1, arg2, ...]` -- a real container
      (`List`/`Set`/`Optional`/`Dict`), or (plain-structs milestone) a
      plain struct's own generic instantiation (`Box[String]`/`Box[
      @@Employee]` -- the wrapper itself is never `@@`-marked, only an
      individual argument might be). `args` is each comma-separated piece,
      parsed recursively either way -- a relation-typed argument
      (`@@Employee`) already resolves correctly via the same recursion,
      no special-casing needed.

    Verbatim port from rw_squirrel_2 -- type-expression parsing is
    unaffected by the storage redesign."""

    comptime LEAF = 0
    comptime RELATION = 1
    comptime PARAMETERIZED = 2

    var kind: Int
    var name: String
    var args: List[ArcPointer[TypeExpr]]

    def is_relation(self) -> Bool:
        return self.kind == Self.RELATION

    def is_parameterized(self) -> Bool:
        return self.kind == Self.PARAMETERIZED

    def arg_count(self) -> Int:
        return len(self.args)

    def arg(self, i: Int) -> ref [self.args[i][]] TypeExpr:
        return self.args[i][]

    def render(self) -> String:
        if self.kind == Self.RELATION:
            return "@@" + self.name
        if self.kind == Self.LEAF:
            return self.name
        var out = self.name + "["
        for i in range(len(self.args)):
            if i > 0:
                out += ", "
            out += self.args[i][].render()
        out += "]"
        return out^

    def render_relation_stripped(self) -> String:
        """Like `render()`, but a `RELATION` node renders its bare `name`
        (no `@@`) instead of `"@@" + name` -- what `relation_schema` (and
        `plain_value_fields`) should actually store for a (possibly nested)
        container relation type: `List[@@Employee]` -> `"List[Employee]"`,
        `List[List[@@Employee]]` -> `"List[List[Employee]]"`, plain
        `@@Employee` -> `"Employee"` (plain-structs milestone: `@@container`
        field support, general recursive access chain -- see the plan's
        Revision 3)."""
        if self.kind == Self.RELATION or self.kind == Self.LEAF:
            return self.name
        var out = self.name + "["
        for i in range(len(self.args)):
            if i > 0:
                out += ", "
            out += self.args[i][].render_relation_stripped()
        out += "]"
        return out^


def _split_top_level_commas(s: String) -> List[String]:
    """Splits `s` on every top-level `,` -- ignoring one nested inside
    further brackets."""
    var out = List[String]()
    var depth = 0
    var start = 0
    var bytes = s.as_bytes()
    var n = len(bytes)
    for i in range(n):
        var b = bytes[i]
        if b == UInt8(ord("[")) or b == UInt8(ord("(")) or b == UInt8(ord("{")):
            depth += 1
        elif b == UInt8(ord("]")) or b == UInt8(ord(")")) or b == UInt8(ord("}")):
            depth -= 1
        elif b == UInt8(ord(",")) and depth == 0:
            out.append(String(String(s[byte = start : i]).strip()))
            start = i + 1
    out.append(String(String(s[byte = start : n]).strip()))
    return out^


def parse_type_expr(type_str: String) -> TypeExpr:
    """Parses `type_str` (a field's raw type text -- `@@Employee`,
    `List[String]`, `Box[@@Employee]`, `Dict[String, Int]`, ...) into a
    `TypeExpr` tree."""
    var t = type_str.strip()
    if t.startswith("@@"):
        return TypeExpr(
            kind=TypeExpr.RELATION,
            name=String(t[byte=2 : t.byte_length()]),
            args=List[ArcPointer[TypeExpr]](),
        )
    var bracket = t.find("[")
    if bracket < 0:
        return TypeExpr(kind=TypeExpr.LEAF, name=String(t), args=List[ArcPointer[TypeExpr]]())
    var name = String(t[byte=0 : bracket])
    var inner = String(t[byte = bracket + 1 : t.byte_length() - 1])
    var args = List[ArcPointer[TypeExpr]]()
    for arg_str in _split_top_level_commas(inner):
        args.append(ArcPointer(parse_type_expr(arg_str)))
    return TypeExpr(kind=TypeExpr.PARAMETERIZED, name=name, args=args^)
