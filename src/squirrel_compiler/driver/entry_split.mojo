from squirrel_compiler.parser import Scanner, is_ident_char


def file_has_top_level_main(source: String) raises -> Bool:
    """True if `source` declares a literal, top-level `def main(` -- a
    line with no leading whitespace, since a nested one (inside a
    struct/method/function body) is always indented by construction, and
    `.mojo.sqrrl` never declares a real top-level `def main` any way but
    literally. This is the one thing that actually makes a generated
    file a valid `mojo run`/`mojo build` target at all (confirmed via a
    real compile: a file that only *imports* `main` via a wildcard,
    rather than declaring it directly, raises "module does not define a
    `main` function") -- see `struct_declaration_ranges`'s own doc
    comment for why that distinction is what this whole split hinges on.

    Line-oriented, not `Scanner`-based: `def main(` is always its own
    whole line by construction, so there's no need for `Scanner`'s own
    trivia/comment/string-literal awareness here."""
    var bytes = source.as_bytes()
    var line_start = 0
    while line_start <= len(bytes):
        var line_end = line_start
        while line_end < len(bytes) and bytes[line_end] != UInt8(ord("\n")):
            line_end += 1
        var line = String(from_utf8=bytes[line_start:line_end])
        if line.startswith("def main("):
            return True
        line_start = line_end + 1
    return False


@fieldwise_init
struct StructRange(Copyable, Movable, ImplicitlyCopyable):
    """One struct/plain-struct/trait declaration's own `[start, end)`
    byte span within its declaring file's raw source -- `start` where
    `@@struct`/the bare `struct`/`trait` keyword begins, `end` right
    after the declaration's own closing (`Scanner.parse_struct`/`parse_
    hand_written_plain_struct` leave `sc.pos` there; `trait_declaration_
    ranges` computes its own equivalent by hand, no `Scanner` support for
    trait declarations existing at all).

    `name` is only ever populated for a trait range (`"" ` for a struct
    or plain struct) -- `convert_directory.mojo` needs it, and only it,
    to register a moved trait into `entity_symbols` under its own name
    (a struct/plain struct already gets that from `discovery`/`plain_
    struct_discovery`'s own maps; nothing project-wide tracks a
    hand-written trait's own name at all otherwise, since until this
    split existed, a trait was pure pass-through text nothing ever
    needed to resolve cross-file)."""

    var start: Int
    var end: Int
    var name: String


def struct_declaration_ranges(source: String) raises -> List[StructRange]:
    """Every `@@struct`'s and every hand-written plain struct's own byte
    span in `source`, in file order -- the two scans are already
    mutually exclusive (`Scanner.at_bare_struct_keyword` explicitly
    excludes anything preceded by `@@`), so their results simply
    concatenate and sort; spans never nest or overlap (the DSL grammar
    has no way to declare a struct inside another struct's own body).

    Each span's own start is walked backward over any decorator line(s)
    immediately above the `struct`/`@@struct` keyword (`@fieldwise_init`,
    most commonly) via `_extend_start_over_decorators` -- `Scanner.skip_
    trivia` (used by both `find_next_struct_decl`/`find_next_hand_
    written_plain_struct_decl` to reach the keyword itself) only ever
    skips whitespace/comments, never a decorator line, so without this
    the decorator would land just *outside* the span -- confirmed as a
    real, silent bug via a real compile: `mask_source` then drops it from
    the impl half entirely, leaving a hand-written struct with no field-
    matching constructor at all (only the generic move/copy ones every
    struct always has), surfacing many call sites away as "no matching
    function in initialization".

    Used by `mask_source` to physically split a file's own struct/table
    declarations away from its top-level script -- see this module's own
    doc comment for why."""
    var ranges = List[StructRange]()

    var sc = Scanner(source)
    while sc.find_next_struct_decl():
        var start = _extend_start_over_decorators(source, sc.pos)
        _ = sc.parse_struct()
        ranges.append(StructRange(start, sc.pos, name=""))

    var psc = Scanner(source)
    while psc.find_next_hand_written_plain_struct_decl():
        var start = _extend_start_over_decorators(source, psc.pos)
        _ = psc.parse_hand_written_plain_struct()
        ranges.append(StructRange(start, psc.pos, name=""))

    for r in trait_declaration_ranges(source):
        ranges.append(r)

    sort_ranges(ranges)
    return ranges^


def trait_declaration_ranges(source: String) raises -> List[StructRange]:
    """Every top-level (column-0), hand-written `trait Name:`/`trait
    Name(Base, ...):` declaration's own `[start, end)` span, `end` being
    the end of its own last indented-or-blank body line. Mojo/DSL have no
    dedicated trait-declaration scanning today (a trait is otherwise pure
    pass-through text, never inspected the way a struct's own fields
    are) -- standalone, line-oriented, mirroring `file_has_top_level_
    main`'s own style rather than `Scanner`-based.

    Needed for the same reason `struct_declaration_ranges` itself
    exists: a struct moving to the impl half can conform to a trait
    declared in the very same file (`@@struct @@Person(HasId):`), so the
    trait has to move there too, or the impl half won't compile at all
    (confirmed via a real compile: "use of unknown declaration
    'HasId'"). Folded into `struct_declaration_ranges`'s own combined
    list -- a trait gets exactly the same treatment as a struct here,
    unlike a raw import line (`raw_import_line_ranges`), which needs to
    stay reachable from *both* halves rather than move to just one."""
    var ranges = List[StructRange]()
    var bytes = source.as_bytes()
    var n = len(bytes)
    var line_start = 0
    while line_start < n:
        var line_end = line_start
        while line_end < n and bytes[line_end] != UInt8(ord("\n")):
            line_end += 1
        var line = String(from_utf8=bytes[line_start:line_end])
        if line.startswith("trait ") or line.startswith("trait("):
            var after_keyword = String(line[byte=5 : line.byte_length()]).strip()
            var name_end = 0
            while name_end < after_keyword.byte_length() and is_ident_char(after_keyword.as_bytes()[name_end]):
                name_end += 1
            var name = String(after_keyword[byte=0:name_end])
            var block_end = line_end
            var next_start = line_end + 1
            while next_start < n:
                var next_end = next_start
                while next_end < n and bytes[next_end] != UInt8(ord("\n")):
                    next_end += 1
                var next_line = String(from_utf8=bytes[next_start:next_end])
                if next_line.strip().byte_length() == 0 or next_line.startswith(" ") or next_line.startswith("\t"):
                    block_end = next_end
                    next_start = next_end + 1
                    continue
                break
            ranges.append(StructRange(line_start, block_end, name=name))
            line_start = next_start
        else:
            line_start = line_end + 1
    return ranges^


def _extend_start_over_decorators(source: String, struct_start: Int) raises -> Int:
    """Walks `struct_start` (a `struct`/`@@struct` keyword's own
    position) backward over every decorator line stacked immediately
    above it (`@fieldwise_init`, `@always_inline`, ...) -- a decorator
    line here always starts with a bare `@` (never `@@`, which
    `at_bare_struct_keyword` already guarantees doesn't precede the
    hand-written-plain-struct case, and which a `@@struct` line itself
    never starts with either), so checking that one byte tells the two
    apart. Stops at the first line that isn't one, or the start of
    `source`."""
    var bytes = source.as_bytes()
    var pos = struct_start
    while True:
        # Skip the blank line(s) directly above `pos`, if any, to reach
        # the previous non-blank line's own end.
        var line_end = pos
        while line_end > 0 and (bytes[line_end - 1] == UInt8(ord("\n")) or bytes[line_end - 1] == UInt8(ord(" ")) or bytes[line_end - 1] == UInt8(ord("\t"))):
            line_end -= 1
        if line_end == 0:
            return pos
        var line_start = line_end
        while line_start > 0 and bytes[line_start - 1] != UInt8(ord("\n")):
            line_start -= 1
        var line = String(from_utf8=bytes[line_start:line_end]).strip()
        if not line.startswith("@") or line.startswith("@@"):
            return pos
        pos = line_start


def raw_import_line_ranges(source: String) raises -> List[StructRange]:
    """Every top-level (no leading whitespace), hand-written `from ... import
    ...`/`import ...` line's own `[start, end)` span -- a `.mojo.sqrrl` file
    is free to mix DSL declarations with plain pass-through import lines
    (`driver/misc_builders.mojo`'s `discover_raw_imports` docstring), most
    commonly a custom container wrapper's own type (`from ring_module
    import Ring`) that a struct's own field then references.

    Needed alongside `struct_declaration_ranges` specifically for the impl
    half of a split file: a struct's own field can reference one of these
    raw-imported types, but `mask_source(..., keep=True)` only preserves
    struct-declaration text on its own -- without also keeping these lines,
    the impl module would reference a type it never imports at all
    (confirmed via a real compile: `container_fields`'s own `Ring`/`Grid`
    fields, "use of unknown declaration"). The *entry* half needs no such
    extra treatment -- `mask_source(..., keep=False)` already preserves
    everything outside `struct_declaration_ranges` verbatim, imports
    included."""
    var ranges = List[StructRange]()
    var bytes = source.as_bytes()
    var n = len(bytes)
    var line_start = 0
    while line_start < n:
        var line_end = line_start
        while line_end < n and bytes[line_end] != UInt8(ord("\n")):
            line_end += 1
        var line = String(from_utf8=bytes[line_start:line_end])
        if line.startswith("from ") or line.startswith("import "):
            ranges.append(StructRange(line_start, line_end, name=""))
        line_start = line_end + 1
    return ranges^


def sort_ranges(mut ranges: List[StructRange]):
    """Insertion sort by `.start` -- `ranges` is never more than a
    handful of entries per file (one per struct declared there), so
    there's no need for anything fancier."""
    for i in range(1, len(ranges)):
        var j = i
        while j > 0 and ranges[j - 1].start > ranges[j].start:
            var tmp = ranges[j - 1]
            ranges[j - 1] = ranges[j]
            ranges[j] = tmp
            j -= 1


def mask_source(source: String, ranges_in: List[StructRange], keep: Bool) raises -> String:
    """Returns `source` with every byte outside (`keep=True`) or inside
    (`keep=False`) `ranges_in` replaced by a space -- length- and newline-
    preserving either way, so line numbers (and therefore every existing
    error message's own `source_location`-derived position) stay exactly
    accurate in both the struct-only and script-only halves this
    produces, even though each one is missing most of the original
    text.

    `ranges_in` doesn't need to already be sorted -- sorted here, on a
    copy, since a caller combining more than one range source (`entry_
    split.mojo`'s own `impl_ranges`, struct declarations plus raw import
    lines) has no reason to also track their combined order itself; the
    scan below relies on sorted, non-overlapping ranges to walk `source`
    in one pass via a single monotonic pointer."""
    var ranges = ranges_in.copy()
    sort_ranges(ranges)
    var bytes = source.as_bytes()
    var out_bytes = List[UInt8](capacity=len(bytes))
    var range_i = 0
    for i in range(len(bytes)):
        while range_i < len(ranges) and i >= ranges[range_i].end:
            range_i += 1
        var inside = range_i < len(ranges) and i >= ranges[range_i].start and i < ranges[range_i].end
        var b = bytes[i]
        if b == UInt8(ord("\n")) or inside == keep:
            out_bytes.append(b)
        else:
            out_bytes.append(UInt8(ord(" ")))
    return String(from_utf8=out_bytes)


def collapse_blank_runs(text: String, max_consecutive: Int = 1) raises -> String:
    """Collapses any run of more than `max_consecutive` blank (or
    whitespace-only) lines in `text` down to exactly `max_consecutive` --
    purely cosmetic, applied to `emit_file`'s own *final*, already-
    transformed output for a split file's own two halves, never to the
    masked source `transform_source` itself sees.

    That ordering matters: `mask_source` deliberately preserves every
    line (see its own doc comment) so a genuine `InvalidSquirrelSyntax`
    raised *during* transformation still reports the position a user's
    own `.mojo.sqrrl` editor agrees with. Once transformation has
    already succeeded, though, nothing downstream depends on the masked
    struct/script region's own line count anymore -- confirmed real
    otherwise: a split file's own generated output was dozens of blank
    lines longer than it needed to be, exactly the size of whichever
    half got masked out, hard to read for no benefit once past the point
    an error could still reference it."""
    var lines = List[String]()
    var bytes = text.as_bytes()
    var n = len(bytes)
    var line_start = 0
    while line_start <= n:
        var line_end = line_start
        while line_end < n and bytes[line_end] != UInt8(ord("\n")):
            line_end += 1
        lines.append(String(from_utf8=bytes[line_start:line_end]))
        line_start = line_end + 1

    var out = String()
    var blank_run = 0
    for i in range(len(lines)):
        var is_blank = lines[i].strip().byte_length() == 0
        if is_blank:
            blank_run += 1
            if blank_run > max_consecutive:
                continue
        else:
            blank_run = 0
        if i > 0:
            out += "\n"
        # A kept blank line is normalized to truly empty, not whatever
        # whitespace `mask_source` happened to leave it as (a lone
        # surviving one -- `blank_run <= max_consecutive` but still
        # `is_blank` -- would otherwise print as visible trailing spaces
        # instead of a clean blank line).
        out += "" if is_blank else lines[i]
    return out^
