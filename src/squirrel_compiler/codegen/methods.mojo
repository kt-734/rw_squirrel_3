from squirrel_compiler.parser import Scanner, is_ident_char
from squirrel_compiler.codegen.rewrite_context import RewriteContext


def _leading_indent(text: String) -> String:
    var bytes = text.as_bytes()
    var i = 0
    while i < len(bytes) and (bytes[i] == UInt8(ord(" ")) or bytes[i] == UInt8(ord("\t"))):
        i += 1
    return String(text[byte = 0 : i])


def _line_indent(text: String, line_start: Int) -> Int:
    var bytes = text.as_bytes()
    var i = line_start
    while i < len(bytes) and (bytes[i] == UInt8(ord(" ")) or bytes[i] == UInt8(ord("\t"))):
        i += 1
    return i - line_start


def _split_method_spans(method_body: String) -> List[String]:
    """Splits `method_body` (every user-declared method concatenated, as
    captured verbatim by `parse_struct_body`) into one span per method --
    a top-level `def `/`fn ` line at the *first* method's own indentation
    starts a new span; anything more deeply indented (a nested def, a
    multi-line body, ...) belongs to whichever method's span is currently
    open."""
    var bytes = method_body.as_bytes()
    var n = len(bytes)
    var header_indent = _line_indent(method_body, 0)
    var spans = List[String]()
    var span_start = 0
    var pos = 0
    while pos < n:
        var line_start = pos
        var indent = _line_indent(method_body, line_start)
        var content_start = line_start + indent
        var line_end = content_start
        while line_end < n and bytes[line_end] != UInt8(ord("\n")):
            line_end += 1
        var next_pos = line_end + 1 if line_end < n else line_end
        var is_blank = content_start == line_end
        if not is_blank and indent == header_indent and pos != 0:
            var line_text = String(method_body[byte = content_start : line_end])
            if line_text.startswith("def ") or line_text.startswith("fn "):
                spans.append(String(method_body[byte = span_start : line_start]))
                span_start = line_start
        pos = next_pos
    spans.append(String(method_body[byte = span_start : n]))
    return spans^


@fieldwise_init
struct _MethodHeader(Copyable, Movable):
    """One method's own parsed signature line, split from its body.
    `after_paren` is everything on the header line right after the method
    name's own `(` -- e.g. `self, x: Int) -> String:`."""

    var indent: String
    var keyword: String
    var is_world_marked: Bool
    var method_name: String
    var after_paren: String
    var body: String


def _parse_method_span(span: String, struct_name: String) raises -> _MethodHeader:
    """Splits one method's own `span` (as sliced by `_split_method_spans`)
    into its signature pieces, without rewriting anything -- shared by
    `world_marked_method_names` (which only needs the name/marking) and
    `rewrite_method_body` (which needs the rest too)."""
    var bytes = span.as_bytes()
    var n = len(bytes)
    var header_end = 0
    while header_end < n and bytes[header_end] != UInt8(ord("\n")):
        header_end += 1
    var body_start = header_end + 1 if header_end < n else header_end
    var header = String(span[byte = 0 : header_end])
    var body = String(span[byte = body_start : n])

    var indent = _leading_indent(header)
    var rest = String(header[byte = indent.byte_length() : header.byte_length()])

    var keyword: String
    if rest.startswith("def "):
        keyword = "def "
    elif rest.startswith("fn "):
        keyword = "fn "
    else:
        raise Error(
            "InvalidSquirrelSyntax: expected a method definition ('def' or"
            " 'fn') in '@@struct @@" + struct_name + "'"
        )
    rest = String(rest[byte = keyword.byte_length() : rest.byte_length()])

    var is_world_marked = rest.startswith("@@@")
    if is_world_marked:
        rest = String(rest[byte = 3 : rest.byte_length()])
    elif rest.startswith("@@"):
        raise Error(
            "InvalidSquirrelSyntax: method '"
            + rest
            + "' on '@@struct @@"
            + struct_name
            + "' -- a spliced method that needs 'sqrrl__world' is marked"
            " '@@@', not plain '@@' (a method's own name is never"
            " '@@'-marked otherwise)"
        )

    var paren = rest.find("(")
    if paren < 0:
        raise Error(
            "InvalidSquirrelSyntax: expected '(' after method name in"
            " '@@struct @@" + struct_name + "'"
        )
    var method_name = String(rest[byte = 0 : paren])
    var after_paren = String(rest[byte = paren + 1 : rest.byte_length()])

    return _MethodHeader(
        indent=indent,
        keyword=keyword,
        is_world_marked=is_world_marked,
        method_name=method_name,
        after_paren=after_paren,
        body=body,
    )


def _mark_self_field_access(body: String) raises -> String:
    """Auto-`@@`-marks every bare `self` reference in a spliced method's
    own body, so the DSL surface can write ordinary-looking `self.field`/
    `self.@@dept.name`/`self.method()` (no marker on `self` itself) instead
    of spelling out `@@self.field` -- `self` is the one identifier a method
    body can always unambiguously resolve to the enclosing struct, so
    there's no ambiguity a marker would need to disambiguate. This is a
    narrow, scoped preprocessing pass (only ever called on a method's own
    body, never general script text) that inserts the marker and then
    hands off entirely to the existing `@@`-driven machinery -- reuses
    `rewrite_markers`/`handle_field_access` unchanged, same as an
    explicitly-written `@@self.field` already did, rather than a parallel
    field-access path. Skips comments/string literals (the same
    `skip_non_code` convention every other scan in this codebase uses) and
    identifiers that merely contain "self" (`myself`, `self2`) via
    word-boundary checks on both sides; an already-`@@`-marked `@@self` is
    left untouched (idempotent)."""
    var sc = Scanner(body)
    var out = String()
    var pos = 0
    while not sc.at_end():
        var before = sc.pos
        sc.skip_non_code()
        if sc.pos != before:
            continue
        if sc.starts_with("self") and not is_ident_char(sc.peek_at(4)):
            var word_start = sc.pos
            var preceded_by_marker = word_start >= 2 and String(body[byte = word_start - 2 : word_start]) == "@@"
            var preceded_by_ident = word_start > 0 and is_ident_char(sc.byte_at(word_start - 1))
            if not preceded_by_marker and not preceded_by_ident:
                out += String(body[byte = pos : word_start]) + "@@self"
                sc.pos += 4
                pos = sc.pos
                continue
        sc.pos += 1
    out += String(body[byte = pos : body.byte_length()])
    return out^


def world_marked_method_names(method_body: String, struct_name: String) raises -> List[String]:
    """Names of every `@@@`-marked method declared in `method_body` --
    what `build_world_methods` (`driver/discovery.mojo`) scans project-wide,
    so the rewrite engine's instance-call dispatch
    (`rewrite_field_access.mojo`) can tell whether calling a spliced user
    method needs `sqrrl__world` threaded as its own first argument, without
    needing to see the declaring file itself (same cross-file reasoning as
    M2's relation-schema resolution)."""
    var out = List[String]()
    if method_body.strip().byte_length() == 0:
        return out^
    for span in _split_method_spans(method_body):
        var header = _parse_method_span(span, struct_name)
        if header.is_world_marked:
            out.append(header.method_name)
    return out^


def rewrite_method_body(method_body: String, struct_name: String, ctx: RewriteContext) raises -> String:
    """Splits `method_body` into per-method spans, rewrites each through
    the ordinary `rewrite_markers` machinery with its own fresh scope
    (`self` pre-seeded as a bound variable of type `struct_name`, so
    `self.field`/`self.@@dept.name` resolve exactly like any other
    bound-variable access once `_mark_self_field_access` inserts the `@@`
    marker `self` itself is never written with), and splices `mut
    sqrrl__world: sqrrl__World` into any method whose own name was
    `@@@`-marked (mirrors `MarkerKind.WORLD_FUNC`'s own def-signature
    insertion). A method's own name is never `sqrrl__`-prefixed -- only the
    `@@@` marker itself is stripped -- since it has to match exactly for
    trait conformance (`HasId.entity_id` must generate literally
    `entity_id`, not `sqrrl__entity_id`)."""
    from squirrel_compiler.codegen.rewrite import rewrite_markers

    if method_body.strip().byte_length() == 0:
        return String()

    var out = String()
    for span in _split_method_spans(method_body):
        var header = _parse_method_span(span, struct_name)
        var new_header = header.indent + header.keyword + header.method_name + "("
        if header.is_world_marked:
            var ab = header.after_paren.as_bytes()
            var starts_with_self = header.after_paren.startswith("self") and (
                len(ab) == 4 or not is_ident_char(ab[4])
            )
            if not starts_with_self:
                raise Error(
                    "InvalidSquirrelSyntax: '@@@"
                    + header.method_name
                    + "' on '@@struct @@"
                    + struct_name
                    + "' needs 'self' as its first parameter to use"
                    " 'sqrrl__world'"
                )
            var after_self = String(header.after_paren[byte = 4 : header.after_paren.byte_length()])
            var asb = after_self.as_bytes()
            var k = 0
            while k < len(asb) and (asb[k] == UInt8(ord(" ")) or asb[k] == UInt8(ord("\t"))):
                k += 1
            new_header += "self, mut sqrrl__world: sqrrl__World"
            if k < len(asb) and asb[k] == UInt8(ord(",")):
                var k2 = k + 1
                while k2 < len(asb) and (asb[k2] == UInt8(ord(" ")) or asb[k2] == UInt8(ord("\t"))):
                    k2 += 1
                new_header += ", " + String(after_self[byte = k2 : after_self.byte_length()])
            else:
                new_header += String(after_self[byte = k : after_self.byte_length()])
        else:
            new_header += header.after_paren

        var method_ctx = ctx.fresh_function_scope()
        method_ctx.entity_to_type["self"] = struct_name
        method_ctx.world_declared = header.is_world_marked

        var rewritten_body = rewrite_markers(_mark_self_field_access(header.body), method_ctx)

        out += new_header
        if not out.endswith("\n"):
            out += "\n"
        out += rewritten_body
        if not out.endswith("\n"):
            out += "\n"
    return out^
