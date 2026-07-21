def source_location(source: String, byte_pos: Int) -> String:
    """1-indexed "line:col" for `byte_pos` within `source` -- spliced into
    every raised error so a message says exactly where in a `.mojo.sqrrl` file
    it happened.

    Verbatim port from rw_squirrel_2 -- pure lexical scanning, unaffected by
    the storage redesign."""
    var line = 1
    var col = 1
    var bytes = source.as_bytes()
    var limit = byte_pos if byte_pos < len(bytes) else len(bytes)
    for i in range(limit):
        if bytes[i] == UInt8(ord("\n")):
            line += 1
            col = 1
        else:
            col += 1
    return String(line) + ":" + String(col)


def line_indent_of(source: String, pos: Int) -> Int:
    """Number of leading space/tab bytes on the line containing byte offset
    `pos` -- the baseline `scan_indented_block`/`find_end_of_indented_block`
    compare every following line's own indentation against."""
    var bytes = source.as_bytes()
    var line_start = pos
    while line_start > 0 and bytes[line_start - 1] != UInt8(ord("\n")):
        line_start -= 1
    var i = line_start
    while i < len(bytes) and (bytes[i] == UInt8(ord(" ")) or bytes[i] == UInt8(ord("\t"))):
        i += 1
    return i - line_start


def find_end_of_indented_block(source: String, header_end: Int, header_indent: Int) -> Int:
    """Computes where an indented block ends, without consuming anything --
    used for `@@:`'s own body: unlike a `@@struct`'s field body (extracted
    whole and parsed structurally), `@@:`'s body is ordinary code that still
    needs the normal, continuous top-to-bottom marker-scanning pass, so
    `Scanner.pos` is left right at the body's start; this just tells the
    caller where the block ends, so it knows where to splice in the leak
    check once the ordinary scan reaches that point."""
    var bytes = source.as_bytes()
    var pos = header_end
    while pos < len(bytes) and bytes[pos] != UInt8(ord("\n")):
        pos += 1
    if pos < len(bytes):
        pos += 1
    while pos < len(bytes):
        var line_start = pos
        var i = line_start
        while i < len(bytes) and (bytes[i] == UInt8(ord(" ")) or bytes[i] == UInt8(ord("\t"))):
            i += 1
        var is_blank = i >= len(bytes) or bytes[i] == UInt8(ord("\n"))
        if not is_blank and (i - line_start) <= header_indent:
            break
        while pos < len(bytes) and bytes[pos] != UInt8(ord("\n")):
            pos += 1
        if pos < len(bytes):
            pos += 1
    return pos


def is_ident_char(b: UInt8) -> Bool:
    return (
        (b >= UInt8(ord("a")) and b <= UInt8(ord("z")))
        or (b >= UInt8(ord("A")) and b <= UInt8(ord("Z")))
        or (b >= UInt8(ord("0")) and b <= UInt8(ord("9")))
        or b == UInt8(ord("_"))
    )


def is_after_arrow(source: String, pos: Int) -> Bool:
    """True if, scanning backward from byte offset `pos` (skipping spaces
    and tabs), the two bytes immediately before are `-` then `>` -- i.e.
    `pos` sits right after `->` (Mojo's return-type arrow), modulo
    whitespace. Tells a return-type marking (`-> @@Type:`) apart from any
    other bare `@@name:` shape."""
    var bytes = source.as_bytes()
    var i = pos
    while i > 0 and (bytes[i - 1] == UInt8(ord(" ")) or bytes[i - 1] == UInt8(ord("\t"))):
        i -= 1
    return i >= 2 and bytes[i - 1] == UInt8(ord(">")) and bytes[i - 2] == UInt8(ord("-"))


def is_after_for_keyword(source: String, pos: Int) -> Bool:
    """True if, scanning backward from byte offset `pos` (skipping spaces/
    tabs, and one optional `var`/`ref` keyword in between), the preceding
    text is `for` with a word boundary before it too -- `pos` sits right
    after `for `, `for var `, or `for ref ` (mod whitespace)."""
    var bytes = source.as_bytes()
    var i = pos
    while i > 0 and (bytes[i - 1] == UInt8(ord(" ")) or bytes[i - 1] == UInt8(ord("\t"))):
        i -= 1
    if i >= 3 and (
        String(source[byte = i - 3 : i]) == "var" or String(source[byte = i - 3 : i]) == "ref"
    ) and (i == 3 or not is_ident_char(bytes[i - 4])):
        i -= 3
        while i > 0 and (bytes[i - 1] == UInt8(ord(" ")) or bytes[i - 1] == UInt8(ord("\t"))):
            i -= 1
    if i < 3:
        return False
    if String(source[byte = i - 3 : i]) != "for":
        return False
    return i == 3 or not is_ident_char(bytes[i - 4])


def is_after_open_paren_or_comma(source: String, pos: Int) -> Bool:
    """True if, scanning backward from byte offset `pos` (skipping spaces/
    tabs), the immediately preceding byte is `(` or `,` -- `pos` sits at
    the start of a call's own argument list, or right after a comma
    separating two arguments. Tells a plain-struct constructor's own
    keyword argument name (`Note(@@owner=...)`) apart from any other bare
    `@@name=` shape -- a var-decl's own initializer (`var @@x = ...`) is
    never preceded by `(`/`,` this way (`var`'s own trailing space is
    neither)."""
    var bytes = source.as_bytes()
    var i = pos
    while i > 0 and (bytes[i - 1] == UInt8(ord(" ")) or bytes[i - 1] == UInt8(ord("\t"))):
        i -= 1
    return i > 0 and (bytes[i - 1] == UInt8(ord("(")) or bytes[i - 1] == UInt8(ord(",")))


def is_after_dot(source: String, pos: Int) -> Bool:
    """True if, scanning backward from byte offset `pos` (skipping spaces/
    tabs), the immediately preceding byte is `.` -- `pos` sits right after
    a chain's own `.` continuation. Lets `find_next_marker` recognize a
    *write* through a bare-rooted chain's own marked field (`addr2.@@
    owner = @@bob`) as `FIELD_ACCESS` too, not just a read (`addr2.@@
    owner.name`, already found via the `.`/`[` *following* the marked
    step): a write's own marked field is always the chain's *last* step,
    so nothing ever follows it with `.`/`[` for that existing check to
    catch -- this is the same check from the *other* side, confirming
    there's a chain to rewind through at all before attempting `bare_
    root_before_dot` (without this guard, a genuinely root-level `var @@x
    = ...`/`@@x = ...` -- never preceded by `.` -- would wrongly be
    treated as a field write instead of an ordinary name reference)."""
    var bytes = source.as_bytes()
    var i = pos
    while i > 0 and (bytes[i - 1] == UInt8(ord(" ")) or bytes[i - 1] == UInt8(ord("\t"))):
        i -= 1
    return i > 0 and bytes[i - 1] == UInt8(ord("."))


def bare_root_before_dot(source: String, pos: Int) -> Int:
    """If byte offset `pos` (the start of an `@@`-marked token, e.g.
    `@@ref` in `n.@@ref`, `notes[0].@@ref`, or `foo.bar.@@ref`) is
    immediately preceded by `.` then a chain of one or more `ident[...]`
    segments (each own bracket span balanced, each pair joined by a
    further `.`) -- returns that outermost identifier's own start offset
    once the chain stops (the byte right before it is no longer `.`).
    Returns `-1` if there's no real identifier there at all (`).@@ref`/
    `].@@ref` immediately, with nothing bracket-balanced behind it, or
    the source's own start).

    Deliberately doesn't also gate on what comes *before* that outermost
    identifier (no allowlist of "valid" preceding characters/keywords) --
    tried that first and it was wrong: `return a.@@ref`/`x + a.@@ref`
    both genuinely root the chain at `a`, and enumerating every keyword/
    operator that can precede a fresh expression is an open-ended list
    with no natural end, the opposite of general. The one real thing
    that disqualifies an identifier from being the root -- it's actually
    a deeper hop in some *other* chain -- is already fully handled by
    this function's own loop (continuing backward through `.` for as
    long as the chain keeps going); once that loop stops, whatever
    identifier it lands on genuinely is the start of its own expression,
    full stop.

    Lets `n.@@ref`/`notes[0].@@ref`/`foo.bar.@@ref` (`n`/`notes`/`foo` a
    bare local variable holding a plain-struct value or a container of
    one, `bar`/`@@ref` a further unmarked/marked field hop) be recognized
    as a single field-access chain rooted at `n`/`notes`/`foo`, not a
    stray `@@ref` reference the scanner would otherwise stop at on its
    own -- the root itself carries no `@@` at all, so nothing about
    scanning forward from it ever finds a marker until `@@ref`."""
    var bytes = source.as_bytes()
    if pos == 0 or bytes[pos - 1] != UInt8(ord(".")):
        return -1
    var i = pos - 1
    while True:
        var j = i
        while j > 0 and bytes[j - 1] == UInt8(ord("]")):
            var depth = 0
            var k = j - 1
            while k >= 0:
                if bytes[k] == UInt8(ord("]")):
                    depth += 1
                elif bytes[k] == UInt8(ord("[")):
                    depth -= 1
                    if depth == 0:
                        break
                k -= 1
            if k < 0:
                return -1
            j = k
        var ident_end = j
        while j > 0 and is_ident_char(bytes[j - 1]):
            j -= 1
        if j == ident_end:
            return -1
        if j > 0 and bytes[j - 1] == UInt8(ord(".")):
            i = j - 1
            continue
        return j


def is_after_container_bracket(source: String, pos: Int) -> Bool:
    """True if byte offset `pos` sits inside `Ident[...]`'s bracket list, at
    *any* parameter position -- `List[@@Type`, `Dict[@@Type, V]`'s second
    slot, `Dict[K, @@Type]`'s own -- wherever that container appears.
    Bounded to the current line."""
    var bytes = source.as_bytes()
    var i = pos
    var depth = 0
    while i > 0:
        var b = bytes[i - 1]
        if b == UInt8(ord("\n")):
            return False
        if b == UInt8(ord("]")) or b == UInt8(ord(")")) or b == UInt8(ord("}")):
            depth += 1
        elif b == UInt8(ord("[")):
            if depth == 0:
                var j = i - 1
                while j > 0 and (bytes[j - 1] == UInt8(ord(" ")) or bytes[j - 1] == UInt8(ord("\t"))):
                    j -= 1
                var ident_end = j
                while j > 0 and is_ident_char(bytes[j - 1]):
                    j -= 1
                return j != ident_end
            depth -= 1
        elif b == UInt8(ord("(")) or b == UInt8(ord("{")):
            if depth == 0:
                return False
            depth -= 1
        i -= 1
    return False
