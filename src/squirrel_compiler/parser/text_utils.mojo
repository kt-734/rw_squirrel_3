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


def is_ident_start_char(b: UInt8) -> Bool:
    """Like `is_ident_char`, but excludes digits -- a leading digit is
    never a real identifier's own first character (it's a numeric
    literal instead), unlike a *later* position in the same identifier
    (`x1`, `team2`), where a digit is completely ordinary. `scan_ident()`
    itself stays boundary-unaware on purpose (it's reused to scan a
    continuation from a mid-identifier position too, e.g. resuming after
    a partial match elsewhere) -- this is for a caller that specifically
    needs to reject a bare numeric run (`0`, `42`) masquerading as a
    name, confirmed as a real gap: `at_plain_var_decl`'s own "any bare
    name, anywhere" fallback previously accepted `0` (from an unrelated
    `if ... > 0:` comparison) as a var-decl/param name, harmless only by
    coincidence (the type that happened to follow could never actually
    resolve) until a later check made a stray `0: @@name` an accepted
    shape instead of a silently-declined one."""
    return (
        (b >= UInt8(ord("a")) and b <= UInt8(ord("z")))
        or (b >= UInt8(ord("A")) and b <= UInt8(ord("Z")))
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


def _skip_ws_backward(source: String, pos: Int) -> Int:
    """Walks backward from `pos` over spaces/tabs, returning the position
    right after the last non-whitespace byte (`pos` itself if there's
    none). Shared by `is_after_dot`'s own whitespace-tolerant `.` check
    and `bare_root_before_dot`'s matching check for a cast's own `.(`
    (`Scanner.scan_access_steps`'s own cast-step parsing tolerates
    trivia between the `.` and the `(` the same way it does everywhere
    else, so both backward checks have to tolerate it too)."""
    var bytes = source.as_bytes()
    var i = pos
    while i > 0 and (bytes[i - 1] == UInt8(ord(" ")) or bytes[i - 1] == UInt8(ord("\t"))):
        i -= 1
    return i


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
    var i = _skip_ws_backward(source, pos)
    return i > 0 and bytes[i - 1] == UInt8(ord("."))


def _skip_balanced_group_backward(source: String, pos: Int) -> Int:
    """If byte offset `pos` is immediately preceded by a closing `]`/`)`/
    `}`, returns the position of its own matching opener, skipping over
    any further same-kind nesting along the way (the backward mirror of
    `Scanner.scan_bracket_depth_aware_span`'s own forward depth-
    tracking). Returns `pos` unchanged if it isn't immediately preceded
    by a closer at all -- the common case, "no group here", handled the
    same way as an actual empty group so callers can loop until the
    position stops moving. Returns `-1` if the nesting never balances
    before the start of `source`."""
    var bytes = source.as_bytes()
    if pos == 0:
        return pos
    var closer = bytes[pos - 1]
    var opener: UInt8
    if closer == UInt8(ord("]")):
        opener = UInt8(ord("["))
    elif closer == UInt8(ord(")")):
        opener = UInt8(ord("("))
    elif closer == UInt8(ord("}")):
        opener = UInt8(ord("{"))
    else:
        return pos
    var depth = 0
    var k = pos - 1
    while k >= 0:
        if bytes[k] == closer:
            depth += 1
        elif bytes[k] == opener:
            depth -= 1
            if depth == 0:
                return k
        k -= 1
    return -1


def bare_root_before_dot(source: String, pos: Int) -> Int:
    """If byte offset `pos` (the start of an `@@`-marked token) sits at
    the front of a chain hop that continues an earlier bare-rooted
    chain, returns that chain's outermost identifier's own start offset.
    Returns `-1` if there's no such chain behind `pos` at all.

    Three entry shapes reach the same backward walk:
      - `pos` immediately preceded by `.` -- an ordinary field/method
        hop (`n.@@ref`, `notes[0].@@ref`, `foo.bar.@@ref`).
      - `pos` immediately preceded by `[` -- a generic method call's own
        type argument (`h.source.unsafe_get[@@Type]`), *if* the
        identifier right before that `[` is itself preceded by `.` (this
        second condition is what keeps an ordinary container type's own
        type argument, `Dict[@@Type, V]`/`Dict[K, @@Type]`, from ever
        matching here at all -- neither is ever preceded by an
        identifier-then-`.` in this specific shape).
      - `pos` immediately preceded by `(` (skipping trivia), itself
        preceded by `.` -- a cast's own opening (`.( @@Type )`, this
        chain's own cast-in-chain syntax -- the only DSL shape that ever
        puts a marked type directly after a bare `(` with no identifier
        in between, so this alone distinguishes it from an ordinary call
        argument like `foo(@@bar)`, where the identifier `foo` -- not
        `.` -- always sits directly before that same `(`).

    Once positioned at a `.` via any of the three, walks backward through
    a chain of one or more `ident[...]`/`ident(...)` segments (each own
    bracket/paren span balanced via `_skip_balanced_group_backward`, each
    pair joined by a further `.`) until the chain stops (the byte right
    before it is no longer `.`), returning that outermost identifier's
    own start offset. Returns `-1` if there's no real identifier there at
    all, or the source's own start.

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
    scanning forward from it ever finds a marker until `@@ref`. Also lets
    a generic method call's own type argument, and a cast immediately
    following one, be recognized the same way (`h.source.unsafe_get[@@
    Series]().( @@Series ).title`)."""
    var bytes = source.as_bytes()
    var i: Int
    if pos > 0 and bytes[pos - 1] == UInt8(ord(".")):
        i = pos - 1
    elif pos > 0 and bytes[pos - 1] == UInt8(ord("[")):
        var method_start = _ident_start_backward(source, pos - 1)
        if method_start == pos - 1 or method_start == 0 or bytes[method_start - 1] != UInt8(ord(".")):
            return -1
        i = method_start - 1
    elif pos > 0 and bytes[pos - 1] == UInt8(ord("(")):
        var before_paren = _skip_ws_backward(source, pos - 1)
        if before_paren == 0 or bytes[before_paren - 1] != UInt8(ord(".")):
            return -1
        i = before_paren - 1
    else:
        return -1
    while True:
        var j = i
        while True:
            var skipped = _skip_balanced_group_backward(source, j)
            if skipped == -1:
                return -1
            if skipped == j:
                break
            j = skipped
        var ident_end = j
        j = _ident_start_backward(source, j)
        if j == ident_end:
            return -1
        if j > 0 and bytes[j - 1] == UInt8(ord(".")):
            i = j - 1
            continue
        return j


def _ident_start_backward(source: String, pos: Int) -> Int:
    """Walks backward from `pos` over identifier characters, returning
    the start of that run -- `pos` itself if there's none. Shared by
    `bare_root_before_dot`'s own entry shapes (the identifier immediately
    before an opening `[` in the generic-call case) and its main
    backward-walk loop (each chain hop's own identifier) -- both are
    exactly this same "how far back does this identifier go" step, just
    starting from different positions."""
    var bytes = source.as_bytes()
    var j = pos
    while j > 0 and is_ident_char(bytes[j - 1]):
        j -= 1
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
