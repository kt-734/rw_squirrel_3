from squirrel_compiler.parser import (
    Scanner,
    ParsedStruct,
    Field,
    FieldModifier,
    parse_type_expr,
    TypeParam,
    is_directly_entity_reachable,
)
from squirrel_compiler.driver.file_paths import module_path_for
from squirrel_compiler.codegen import sqrrl_prefixed, param_name
from squirrel_compiler.codegen.methods import world_marked_method_names, bare_method_returns


struct DiscoveredStruct(Copyable, Movable, ImplicitlyDeletable):
    """One `@@struct` found during the directory walk, tagged with the
    dotted module path of the file that declared it.

    `full_source`: the *entire* declaring file's own raw text (every
    struct from the same file carries its own copy -- same duplication
    `module_path` already has, one entry per struct, not deduplicated
    per file) -- `world_marked_method_names`/`bare_method_returns`
    (`codegen/methods.mojo`) need it, alongside `parsed.method_body_
    start_offset`, to report a real file location if a method's own
    header turns out malformed during this project-wide discovery pass,
    which runs well before the main per-file transform (and its own
    file-path-prefixing catch) even starts.

    `file_path`: the real `.mojo.sqrrl` path (not `module_path`, a
    dotted module name) -- `build_world_methods`/`build_bare_method_
    returns` use it to prefix a caught error the same way `discover_
    structs`'s own catch already does, since nothing wraps *their* own
    per-struct calls with a file path otherwise."""

    var module_path: String
    var parsed: ParsedStruct
    var full_source: String
    var file_path: String

    def __init__(
        out self,
        var module_path: String,
        var parsed: ParsedStruct,
        var full_source: String = String(),
        var file_path: String = String(),
    ):
        self.module_path = module_path^
        self.parsed = parsed^
        self.full_source = full_source^
        self.file_path = file_path^


struct DiscoveryResult(Movable):
    """The output of `discover_structs`' pass over every `.mojo.sqrrl` file:
    every struct found, and a `struct name -> declaring module` map."""

    var structs: List[DiscoveredStruct]
    var module_of: Dict[String, String]

    def __init__(out self, var structs: List[DiscoveredStruct], var module_of: Dict[String, String]):
        self.structs = structs^
        self.module_of = module_of^


def discover_structs(sqrrl_files: List[String], target_root: String) raises -> DiscoveryResult:
    """Pass 1: parses every `@@struct` in every `.mojo.sqrrl` file under
    `target_root`, without emitting anything yet."""
    var discovered = List[DiscoveredStruct]()
    var module_of = Dict[String, String]()

    for path in sqrrl_files:
        var module_path = module_path_for(path, target_root)
        var f = open(path, "r")
        var source = f.read()
        f.close()

        var sc = Scanner(source)
        try:
            while sc.find_next_struct_decl():
                var parsed = sc.parse_struct()
                module_of[parsed.name] = module_path
                discovered.append(DiscoveredStruct(module_path, parsed^, source, path))
        except e:
            raise Error(path + ": " + String(e))

    return DiscoveryResult(discovered^, module_of^)


def _same_field_set(a: List[String], b: List[String]) -> Bool:
    """Mirrors `scanner.mojo`'s own private `_same_field_set` exactly
    (order-independent set equality for two `key(...)` groups) -- not
    exported from the parser module, so duplicated here rather than
    imported, same convention this codebase already follows for other
    small private helpers shared across layers (e.g. `entity.mojo`/
    `table.mojo`'s own duplicated `_field_by_name`)."""
    if len(a) != len(b):
        return False
    for name in a:
        if name not in b:
            return False
    return True


def resolve_struct_inheritance(mut discovery: DiscoveryResult) raises:
    """Struct inheritance (`@@struct @@Name < @@Other:`): for every struct
    with `parsed.inherits_from != ""`, copies the target's own `fields`/
    `key_groups`/`method_body` in, mutating `discovery.structs` in place.
    Must run before *every* other discovery-level builder/check
    (`check_no_relation_cycles`, `build_relation_schema`, `build_unique_
    fields`, `build_key_group_lookup_names`, `check_key_groups_dont_
    collide_with_fields`, etc.) -- all of them iterate `discovery.structs`
    directly and read straight off `ds.parsed.fields`/`ds.parsed.key_
    groups`, so once this mutation has happened, literally none of them
    need to know inheritance exists at all; they see an inheriting
    struct's already-merged content exactly as if it had been declared
    directly.

    Fields: target's own first, then this struct's own additional ones,
    in that order -- `DuplicateFieldName` if this struct tries to
    redeclare one of the target's own field names (inheritance only ever
    adds, never overrides). Key groups: same order, simple concatenation
    (each group is independent regardless of which struct declared it).
    Method bodies: text concatenation (`target + "\\n" + own`, degrading
    to just whichever side is non-empty when the other is blank, so a
    struct that inherits fields but declares no methods of its own -- or
    a target with no methods -- doesn't pick up a stray leading/trailing
    blank line) -- this is what lets `build_world_methods`/`build_bare_
    method_returns` (both scan `ds.parsed.method_body` as raw text for
    method names, no position-awareness needed for that) see the *union*
    of both structs' own methods for call-site dispatch elsewhere in a
    script, same "no changes needed downstream" payoff as fields/key
    groups. (Byte-accurate position tracking for a rewrite *error*
    actually inside an inherited method body is a separate, later concern
    -- see `codegen/rewrite.mojo`'s own `STRUCT` branch and its doc
    comment on the accepted v1 imprecision there.)

    No chaining: raises if the target itself has its own `inherits_from`
    set. An unknown target name also raises here (rather than at parse
    time) since resolving it needs every struct project-wide to have been
    discovered first -- this is also where inheriting from a hand-written
    plain struct is naturally rejected for free, since plain structs are
    never part of `discovery.structs` at all (a separate discovery pass,
    `discover_plain_structs`), so the name lookup simply never finds
    them."""
    var index_of = Dict[String, Int]()
    for i in range(len(discovery.structs)):
        index_of[discovery.structs[i].parsed.name] = i

    for i in range(len(discovery.structs)):
        var own_name = discovery.structs[i].parsed.name
        var target_name = discovery.structs[i].parsed.inherits_from
        if target_name == "":
            continue
        if target_name not in index_of:
            raise Error(
                "InvalidSquirrelSyntax: '@@" + own_name + " < @@" + target_name
                + "' references unknown struct '" + target_name + "'"
            )
        var target_index = index_of[target_name]
        if discovery.structs[target_index].parsed.inherits_from != "":
            raise Error(
                "InvalidSquirrelSyntax: '@@" + own_name + " < @@" + target_name
                + "' -- '" + target_name + "' itself uses '<', and struct"
                " inheritance chaining isn't supported"
            )

        var merged_fields = discovery.structs[target_index].parsed.fields.copy()
        for f in discovery.structs[i].parsed.fields:
            for existing in merged_fields:
                if existing.name == f.name:
                    raise Error(
                        "DuplicateFieldName: '" + f.name + "' is already"
                        " inherited from '" + target_name + "' -- '"
                        + own_name + "' can't redeclare it"
                    )
            merged_fields.append(f.copy())

        var merged_key_groups = discovery.structs[target_index].parsed.key_groups.copy()
        for group in discovery.structs[i].parsed.key_groups:
            merged_key_groups.append(group.copy())

        var target_method_body = discovery.structs[target_index].parsed.method_body
        var own_method_body = discovery.structs[i].parsed.method_body
        var merged_method_body: String
        if target_method_body == "":
            merged_method_body = own_method_body
        elif own_method_body == "":
            merged_method_body = target_method_body
        else:
            merged_method_body = target_method_body + "\n" + own_method_body

        discovery.structs[i].parsed.fields = merged_fields^
        discovery.structs[i].parsed.key_groups = merged_key_groups^
        discovery.structs[i].parsed.method_body = merged_method_body^


def check_key_groups_after_inheritance(discovery: DiscoveryResult) raises:
    """`Scanner.parse_struct` defers its own `key(...)` field-name/
    duplicate validation for an inheriting struct (its own `key(...)`
    lines may legitimately reference fields that only become visible
    after `resolve_struct_inheritance` copies the target's fields in) --
    this re-runs that exact same validation (undeclared field name /
    duplicate field within one group / two groups with an identical field
    set), but only for structs with `inherits_from != ""` (an ordinary
    struct already got this at parse time, doesn't need it twice), against
    the now-fully-merged `ds.parsed.fields`/`ds.parsed.key_groups`. Must
    run after `resolve_struct_inheritance`. Same coarser "struct name, no
    line:col" error-reporting convention this file's other post-discovery
    checks already accept (`check_no_relation_cycles`/`check_key_groups_
    dont_collide_with_fields`)."""
    for ds in discovery.structs:
        if ds.parsed.inherits_from == "":
            continue
        for group in ds.parsed.key_groups:
            for field_name in group:
                var found = False
                for f in ds.parsed.fields:
                    if f.name == field_name:
                        found = True
                        break
                if not found:
                    raise Error(
                        "InvalidSquirrelSyntax: 'key(...)' on '" + ds.parsed.name
                        + "' references undeclared field '" + field_name + "'"
                    )
            for i in range(len(group)):
                for j in range(i + 1, len(group)):
                    if group[i] == group[j]:
                        raise Error(
                            "InvalidSquirrelSyntax: 'key(...)' on '" + ds.parsed.name
                            + "' lists field '" + group[i] + "' more than once"
                        )
        for i in range(len(ds.parsed.key_groups)):
            for j in range(i + 1, len(ds.parsed.key_groups)):
                if _same_field_set(ds.parsed.key_groups[i], ds.parsed.key_groups[j]):
                    raise Error(
                        "InvalidSquirrelSyntax: two 'key(...)' groups on '"
                        + ds.parsed.name + "' declare the exact same field set"
                    )


def build_struct_fields(discovery: DiscoveryResult) -> Dict[String, List[Field]]:
    """Struct name -> its own (post-inheritance-merge) field list --
    threaded into `RewriteContext` so `codegen/rewrite.mojo`'s own,
    independent re-parse of each struct (which never consults
    `DiscoveryResult` and so never sees an inheriting struct's copied-in
    fields) can be overridden with the authoritative, already-merged
    version. A no-op override for a non-inheriting struct -- its own
    fresh re-parse and this discovery-computed version are always
    identical."""
    var out = Dict[String, List[Field]]()
    for ds in discovery.structs:
        out[ds.parsed.name] = ds.parsed.fields.copy()
    return out^


def build_struct_key_groups(discovery: DiscoveryResult) -> Dict[String, List[List[String]]]:
    """`build_struct_fields`'s exact parallel for `key_groups`."""
    var out = Dict[String, List[List[String]]]()
    for ds in discovery.structs:
        out[ds.parsed.name] = ds.parsed.key_groups.copy()
    return out^


def build_struct_method_bodies(discovery: DiscoveryResult) -> Dict[String, String]:
    """`build_struct_fields`'s exact parallel for `method_body` -- lets
    `codegen/rewrite.mojo`'s `STRUCT` branch splice an inherited method in
    as this struct's own, using the same `rewrite_method_body(parsed.
    method_body, parsed.name, ctx, source, parsed.method_body_start_
    offset)` call it already makes; only `.method_body` itself needs
    overriding from here, not the offset/source (see that function's own
    doc comment for the accepted v1 imprecision this implies for an error
    specifically inside an *inherited* method body)."""
    var out = Dict[String, String]()
    for ds in discovery.structs:
        out[ds.parsed.name] = ds.parsed.method_body
    return out^


def build_struct_names(discovery: DiscoveryResult) -> Dict[String, Bool]:
    """The project-wide set of declared `@@struct` names -- what the
    rewrite engine's table-level-call dispatch uses to tell a known struct
    apart from an undeclared/mistyped one (`RewriteContext.struct_names`)."""
    var out = Dict[String, Bool]()
    for ds in discovery.structs:
        out[ds.parsed.name] = True
    return out^


def _relation_fields_of(fields: List[Field]) -> Dict[String, String]:
    """Field name -> target struct name (or, for a `@@container` field, its
    encoded container-of-target text, e.g. `"List[Employee]"` -- possibly
    nested, e.g. `"List[List[Employee]]"`), for every field whose own name
    is `@@`-marked in `fields` -- a `multi` field's own `type_str` is
    already the bare, `@@`-marked element type (`multi @@projects:
    @@Project`'s is `@@Project`, same shape a bare relation field's is),
    so it's registered here identically, no separate case needed.

    `is_directly_entity_reachable`, not the broader `is_relation_field` --
    a field's own *name* only ever ends up `@@`-marked when its type is
    directly entity-iterable (`field_parsing.mojo`'s own marking-symmetry
    check is the actual source of truth for this; a relation confined to
    a `Dict`'s value position, or nested too deep, never earns marking,
    so it's never a `relation_schema` entry -- it lands in `plain_value_
    fields` below instead, consistent with how it was actually declared)."""
    var out = Dict[String, String]()
    for field in fields:
        if is_directly_entity_reachable(field.type_str):
            out[field.name] = parse_type_expr(field.type_str).render_relation_stripped()
    return out^


def build_relation_schema(
    discovery: DiscoveryResult, plain_struct_fields: Dict[String, List[Field]] = Dict[String, List[Field]]()
) raises -> Dict[String, Dict[String, String]]:
    """Struct name -> relation field name -> target struct name, for every
    `@@struct` declared project-wide, plus (plain-structs milestone) every
    hand-written plain struct's own field list -- a plain struct's own
    relation field needs to reach this map too, since a `@@struct`'s own
    field might hop *through* one (`@@alice.home.@@owner`)."""
    var schema = Dict[String, Dict[String, String]]()
    for ds in discovery.structs:
        schema[ds.parsed.name] = _relation_fields_of(ds.parsed.fields)
    for name in plain_struct_fields.keys():
        var owned_name = String(name)
        schema[owned_name] = _relation_fields_of(plain_struct_fields[owned_name])
    return schema^


def _plain_value_fields_of(fields: List[Field]) -> Dict[String, String]:
    """Field name -> declared plain type, for every field whose own name
    is *not* `@@`-marked in `fields` (the `_relation_fields_of` complement
    -- see its own doc comment for exactly which fields that now
    excludes) -- `RewriteContext.plain_value_fields`'s own per-struct
    entry (plain-structs milestone): the general access-chain walk's
    `owner_is_real`/`owner_is_plain` dispatch validates a FIELD step's
    `marked` flag against `relation_schema`/`plain_value_fields`
    uniformly, regardless of which kind of struct declares the field.
    Stored `@@`-stripped (`render_relation_stripped`), same as `_relation_
    fields_of`'s own values -- a field can land here with a relation
    still buried in a non-directly-iterable position (`Dict[String,
    @@Employee]`), and every downstream consumer of this map expects a
    bare, already-rewritable-as-is type string, never one with a
    dangling `@@` a plain (unmarked) field could never otherwise have."""
    var out = Dict[String, String]()
    for field in fields:
        if not is_directly_entity_reachable(field.type_str):
            out[field.name] = parse_type_expr(field.type_str).render_relation_stripped()
    return out^


def build_plain_value_fields(
    discovery: DiscoveryResult, plain_struct_fields: Dict[String, List[Field]] = Dict[String, List[Field]]()
) raises -> Dict[String, Dict[String, String]]:
    """Struct name -> plain (non-relation) field name -> declared type, for
    every `@@struct` *and* every hand-written plain struct declared
    project-wide -- `relation_schema`'s parallel for a plain-value field
    (plain-structs milestone)."""
    var out = Dict[String, Dict[String, String]]()
    for ds in discovery.structs:
        out[ds.parsed.name] = _plain_value_fields_of(ds.parsed.fields)
    for name in plain_struct_fields.keys():
        var owned_name = String(name)
        out[owned_name] = _plain_value_fields_of(plain_struct_fields[owned_name])
    return out^


struct PlainStructDiscovery(Movable):
    """The output of `discover_plain_structs`' pass: every hand-written
    plain struct's own field list, plus (unlike `plain_struct_fields` alone
    -- everywhere else in the project only ever needs the field list) which
    module declared it, needed by `driver/json_module.mojo` to import the
    plain struct's own real Mojo type for its generated `from_json`
    companion (mirrors `DiscoveryResult`'s own `module_of`, same purpose,
    kept as a separate struct since nothing else needs this pairing).

    `method_body` is each plain struct's own raw method-body text (`""`
    for one with no methods at all) -- captured the same way `@@struct`'s
    own already is (`ParsedStruct.method_body`, via `parse_hand_written_
    struct_fields`'s own return-the-suffix behavior, mirroring `parse_
    struct_body`), letting `driver/discovery.mojo`'s `build_bare_method_
    returns`-equivalent for plain structs reuse `codegen/methods.mojo`'s
    `bare_method_returns` as-is."""

    var fields: Dict[String, List[Field]]
    var module_of: Dict[String, String]
    var is_generic: Dict[String, Bool]
    var type_params: Dict[String, List[TypeParam]]
    var method_body: Dict[String, String]

    def __init__(
        out self,
        var fields: Dict[String, List[Field]],
        var module_of: Dict[String, String],
        var is_generic: Dict[String, Bool] = Dict[String, Bool](),
        var type_params: Dict[String, List[TypeParam]] = Dict[String, List[TypeParam]](),
        var method_body: Dict[String, String] = Dict[String, String](),
    ):
        self.fields = fields^
        self.module_of = module_of^
        self.is_generic = is_generic^
        self.type_params = type_params^
        self.method_body = method_body^


def discover_plain_structs(sqrrl_files: List[String], target_root: String) raises -> PlainStructDiscovery:
    """A dedicated pass (plain-structs milestone) scanning for hand-written
    plain struct declarations (`Scanner.find_next_hand_written_plain_struct_
    decl`/`parse_hand_written_plain_struct`) instead of `@@struct` ones --
    the *only* source of plain-struct knowledge project-wide. A plain
    struct is never added to `discovery.structs` (the `@@struct`-only list)
    -- nothing that already iterates it (entity/table/world-module codegen)
    needs to learn to skip one; it was never in that list to begin with.
    `is_generic` (`len(parsed.type_params) > 0`) lets `driver/json_module.
    mojo` know when a plain struct's own generated `from_json` companion
    needs a `[T: Bound, ...]` parameter list of its own -- its field list
    has already been unqualified back to bare type-parameter names
    (`Self.T` -> `T`, `parser/field_parsing.mojo`'s `parse_hand_written_
    struct_fields`), which only mean something inside a free function that
    itself re-declares the same `T`. `type_params` carries the actual
    `[T: Bound, ...]` list (structurally extracted from the struct's own
    header, same pass) so `_emit_plain_struct_from_json` can re-declare it."""
    var fields = Dict[String, List[Field]]()
    var module_of = Dict[String, String]()
    var is_generic = Dict[String, Bool]()
    var type_params = Dict[String, List[TypeParam]]()
    var method_body = Dict[String, String]()
    for path in sqrrl_files:
        var module_path = module_path_for(path, target_root)
        var f = open(path, "r")
        var source = f.read()
        f.close()
        var sc = Scanner(source)
        try:
            while sc.find_next_hand_written_plain_struct_decl():
                var parsed = sc.parse_hand_written_plain_struct()
                module_of[parsed.name] = module_path
                is_generic[parsed.name] = len(parsed.type_params) > 0
                fields[parsed.name] = parsed.fields.copy()
                type_params[parsed.name] = parsed.type_params.copy()
                method_body[parsed.name] = parsed.method_body
        except e:
            raise Error(path + ": " + String(e))
    return PlainStructDiscovery(fields^, module_of^, is_generic^, type_params^, method_body^)


def build_plain_struct_names(plain_struct_fields: Dict[String, List[Field]]) -> Dict[String, Bool]:
    """The project-wide set of declared plain-struct names -- trivial,
    `plain_struct_fields.keys()`."""
    var out = Dict[String, Bool]()
    for name in plain_struct_fields.keys():
        out[name] = True
    return out^


def check_plain_struct_names_disjoint(struct_names: Dict[String, Bool], plain_struct_names: Dict[String, Bool]) raises:
    """The rewrite engine's `owner_is_real`/`owner_is_plain` dispatch
    (`rewrite_field_access.mojo`) depends on `struct_names`/`plain_struct_
    names` partitioning every struct name project-wide with no overlap --
    checked once, at discovery time, rather than trusted implicitly."""
    for name in plain_struct_names.keys():
        if name in struct_names:
            raise Error(
                "DuplicateStructName: '"
                + name
                + "' is declared both as a '@@struct' and as a hand-written"
                " plain struct -- these two namespaces must be disjoint"
            )


def build_unique_fields(discovery: DiscoveryResult) -> Dict[String, List[String]]:
    """Struct name -> names of its `unique`-marked fields, for every
    `@@struct` declared project-wide."""
    var unique_fields = Dict[String, List[String]]()
    for ds in discovery.structs:
        var names = List[String]()
        for field in ds.parsed.fields:
            if field.modifier == FieldModifier.UNIQUE:
                names.append(field.name)
        unique_fields[ds.parsed.name] = names^
    return unique_fields^


def build_indexed_fields(discovery: DiscoveryResult) -> Dict[String, List[String]]:
    """Struct name -> names of its `indexed`-marked fields, for every
    `@@struct` declared project-wide -- the M1 replacement for
    rw_squirrel_2's "every field defaults to a backward index" (see the
    plan's Context point 1): lets the rewrite engine's table-level-call
    dispatch tell whether a `@@Type.for_<field>(...)` call is valid at
    all, and if so that it's `List`-returning (unlike a `unique` field's
    own single-entity `for_<field>`)."""
    var indexed_fields = Dict[String, List[String]]()
    for ds in discovery.structs:
        var names = List[String]()
        for field in ds.parsed.fields:
            if field.modifier == FieldModifier.INDEXED:
                names.append(field.name)
        indexed_fields[ds.parsed.name] = names^
    return indexed_fields^


def build_multi_fields(discovery: DiscoveryResult) -> Dict[String, List[String]]:
    """Struct name -> names of its `multi`-marked fields, for every
    `@@struct` declared project-wide -- lets the rewrite engine's
    table-level-call dispatch recognize a multi field's own element-keyed
    `for_<field>`, and its instance-call dispatch recognize
    `add_to_<field>`/`remove_from_<field>` as a real, supported call rather
    than an unrecognized method."""
    var multi_fields = Dict[String, List[String]]()
    for ds in discovery.structs:
        var names = List[String]()
        for field in ds.parsed.fields:
            if field.modifier == FieldModifier.MULTI:
                names.append(field.name)
        multi_fields[ds.parsed.name] = names^
    return multi_fields^


def _join_key_group_field_names(group: List[String], fields: List[Field]) raises -> String:
    """The single joined lookup-method suffix for one `key(...)` group,
    e.g. `key(name, start_year)` -> `"name_start_year"` -- shared by
    `build_key_group_lookup_names` and `check_key_groups_dont_collide_
    with_fields`. Each field's own piece of the join uses `param_name`
    (`sqrrl__` prefix iff that field is a relation), exactly matching
    `codegen/table.mojo`'s own generated `for_<...>` method name. Raises
    only if the parser's own validation (every name in every group
    matches a real field, `scanner.mojo`'s `parse_struct`) were somehow
    violated, which should be unreachable in practice."""
    var joined = String()
    for i in range(len(group)):
        if i > 0:
            joined += "_"
        var found = False
        for f in fields:
            if f.name == group[i]:
                joined += param_name(f)
                found = True
                break
        if not found:
            raise Error(
                "InternalError: key(...) referenced unknown field '"
                + group[i] + "' -- parser should have already rejected this"
            )
    return joined^


def build_key_group_lookup_names(discovery: DiscoveryResult) raises -> Dict[String, List[String]]:
    """Struct name -> one joined lookup-method suffix per `key(...)` line
    it declares, in declaration order -- e.g. `key(name, start_year)`
    contributes `"name_start_year"`. Lets the rewrite engine's table-level
    -call dispatch (`rewrite_field_access.mojo`) recognize `@@@Type.
    for_name_start_year(...)` as valid *without* trying to split the
    joined text back apart at call-site parse time (impossible in
    general -- a field name can itself contain an underscore, so
    `"name_start_year"` is ambiguous as a *split target*, only
    unambiguous as a *whole-string comparison* against every group's own
    precomputed joined name, which is what this builds)."""
    var out = Dict[String, List[String]]()
    for ds in discovery.structs:
        var joined_names = List[String]()
        for group in ds.parsed.key_groups:
            joined_names.append(_join_key_group_field_names(group, ds.parsed.fields))
        out[ds.parsed.name] = joined_names^
    return out^


def check_key_groups_dont_collide_with_fields(discovery: DiscoveryResult) raises:
    """A `key(...)` group's own joined lookup-method name (`for_room_date`
    for `key(room, date)`) can coincide with a genuinely different field's
    own derived `for_<field>` name -- confirmed via a real repro: a
    struct with `key(room, date)` *and* a separate `indexed room_date:
    String` field generates two `def for_room_date` overloads on the same
    table (harmless to real Mojo -- it resolves them by arity), but the
    rewrite engine's own call-site dispatch (`rewrite_field_access.mojo`)
    matches purely on the method-name *text*, before any argument count is
    known, so a script calling the single-field lookup would get silently
    mis-registered as the composite one (wrong return shape -- a bare
    entity instead of a `Set`). Rejected here, at the source, rather than
    trying to disambiguate by arity downstream: raises a clear
    `InvalidSquirrelSyntax`-style error naming both the struct and the
    colliding method name.

    Checks every reserved `for_<field>`-family name a field with any
    modifier but `NONE` earns -- the plain `for_<field>` itself, plus
    (for an `ordered` field) its five range-query siblings
    (`_greater_than`/`_less_than`/`_at_least`/`_at_most`/`_between`) --
    since any of those could just as easily collide with a `key(...)`
    group's own joined name."""
    for ds in discovery.structs:
        if len(ds.parsed.key_groups) == 0:
            continue
        var reserved = Dict[String, Bool]()
        for f in ds.parsed.fields:
            if f.modifier == FieldModifier.NONE:
                continue
            var base = param_name(f)
            reserved[base] = True
            if f.modifier == FieldModifier.ORDERED:
                for comparator in ["greater_than", "less_than", "at_least", "at_most", "between"]:
                    reserved[base + "_" + comparator] = True
        for group in ds.parsed.key_groups:
            var joined = _join_key_group_field_names(group, ds.parsed.fields)
            if joined in reserved:
                raise Error(
                    "InvalidSquirrelSyntax: 'key(...)' on '" + ds.parsed.name
                    + "' generates a lookup method named 'for_" + joined
                    + "', which collides with a field on the same struct that"
                    " already earns that exact method name -- rename one of"
                    " them, or restructure the key(...) group, to avoid the"
                    " ambiguity"
                )


def build_entity_symbols(discovery: DiscoveryResult) -> Dict[String, String]:
    """`sqrrl__<Name>` (the concrete entity wrapper type -- the only
    generated identifier a *different* file's own output could ever need
    to reference, since a relation field's type is always this bare
    wrapper, never `...Inner`/`...Indexes`/`...Table`, which stay entirely
    internal to the file that declares them) -> the module that declares
    it, for every `@@struct` project-wide. `emit_file` scans its own
    transformed output text for whichever of these actually appear, rather
    than re-deriving "does this field need an import" from field-by-field
    inspection -- one general mechanism instead of one bespoke check per
    place a cross-file reference could show up (adapted from
    rw_squirrel_2's own `build_cross_file_symbols`, slimmed to the single
    symbol per struct this design actually needs)."""
    var symbol_of = Dict[String, String]()
    for ds in discovery.structs:
        symbol_of[sqrrl_prefixed(ds.parsed.name)] = ds.module_path
    return symbol_of^


def build_world_methods(discovery: DiscoveryResult) raises -> Dict[String, List[String]]:
    """Struct name -> names of its `@@@`-marked methods, scanned from every
    `@@struct` declared project-wide (`ds.parsed.method_body`, captured
    verbatim by the parser regardless of milestone) -- lets the rewrite
    engine's instance-call dispatch (`rewrite_field_access.mojo`) tell
    whether calling a spliced user method needs `sqrrl___world` threaded as
    its own first argument, even when the call site is in a different file
    than the one declaring the method (same cross-file reasoning M2's
    relation-schema resolution already needs)."""
    var world_methods = Dict[String, List[String]]()
    for ds in discovery.structs:
        try:
            world_methods[ds.parsed.name] = world_marked_method_names(
                ds.parsed.method_body, ds.parsed.name, ds.full_source, ds.parsed.method_body_start_offset
            )
        except e:
            raise Error(ds.file_path + ": " + String(e))
    return world_methods^


def build_bare_method_returns(discovery: DiscoveryResult) raises -> Dict[String, Dict[String, String]]:
    """Struct name -> bare method name -> its raw, unstripped return-type
    text, for every `@@struct` declared project-wide -- the method
    analogue of `driver/misc_builders.mojo`'s `build_bare_function_
    returns`, covering every non-world method unconditionally (plain,
    entity-shaped, or a container of either, since mandatory marking for
    a method's own return shape is gone): lets `_handle_instance_call`
    (`rewrite_field_access.mojo`) continue a trailing chain off a bare
    method's own call result (`@@own.get_note().@@ref.name`, no
    intermediate variable), the same way `ctx.bare_function_returns`/
    `handle_bare_call_chain` already lets one continue off a bare
    top-level function's own call result."""
    var bare_method_returns_out = Dict[String, Dict[String, String]]()
    for ds in discovery.structs:
        try:
            bare_method_returns_out[ds.parsed.name] = bare_method_returns(
                ds.parsed.method_body, ds.parsed.name, ds.full_source, ds.parsed.method_body_start_offset
            )
        except e:
            raise Error(ds.file_path + ": " + String(e))
    return bare_method_returns_out^


def build_plain_struct_bare_method_returns(
    plain_struct_discovery: PlainStructDiscovery,
) raises -> Dict[String, Dict[String, String]]:
    """`build_bare_method_returns`'s own counterpart for a hand-written
    plain struct's own methods -- struct name -> bare method name -> its
    raw, unstripped return-type text, for every plain struct declared
    project-wide. Reuses `codegen/methods.mojo`'s `bare_method_returns`
    completely unchanged (it's already generic text-splitting, with no
    `@@struct`-specific dependency beyond error-message wording, which
    never fires here since a plain struct's own method is never `@@`/
    `@@@`-marked in practice) -- the only missing piece was `PlainStruct
    Discovery.method_body` itself, which didn't exist until now (`parse_
    hand_written_struct_fields` used to discard a plain struct's own
    method text entirely, unlike `@@struct`'s `parse_struct_body`, which
    always captured it).

    Lets `_handle_instance_call`'s plain-struct-owner branch (`rewrite_
    field_access.mojo`, previously *always* a direct, untracked
    passthrough with no lookup at all) continue a trailing chain off a
    plain struct's own bare method call (`addr2.get_extra().@@dept.
    name`), the same way a bare method on a real `@@struct` already can
    -- merged into the very same `ctx.bare_method_returns` map at
    `convert_directory.mojo`'s own build step (struct names are disjoint
    by construction -- `check_plain_struct_names_disjoint` -- so there's
    no key collision to resolve, just a union of two already-generic
    "struct name -> bare method name -> return type" maps)."""
    var out = Dict[String, Dict[String, String]]()
    for struct_name in plain_struct_discovery.method_body.keys():
        # No real file offset available for a hand-written plain struct's
        # own method text (unlike `@@struct`'s `method_body_start_offset`)
        # -- `full_source=method_body, offset=0` is the same "line 1 of
        # the isolated text" resolution this path already had; no worse
        # than before, and `_parse_method_span`'s '@@'-marking migration
        # raise never fires here anyway (a plain struct's own method is
        # never `@@`/`@@@`-marked in practice, per this function's own
        # docstring above).
        var body = plain_struct_discovery.method_body[String(struct_name)]
        out[String(struct_name)] = bare_method_returns(body, String(struct_name), body, 0)
    return out^


def build_stats_fields(discovery: DiscoveryResult) -> Dict[String, List[String]]:
    """Struct name -> names of its `stats`-tagged fields, for every
    `@@struct` declared project-wide (M4) -- lets the rewrite engine's
    table-level-call dispatch (`rewrite_field_access.mojo`) recognize
    `sum_<field>`/`avg_<field>` (which need `is_stats`, unlike `min_`/
    `max_`/`median_`, which an `ordered` field earns for free -- see
    `analysis/field_shape.mojo`'s `is_aggregatable`)."""
    var stats_fields = Dict[String, List[String]]()
    for ds in discovery.structs:
        var names = List[String]()
        for field in ds.parsed.fields:
            if field.is_stats:
                names.append(field.name)
        stats_fields[ds.parsed.name] = names^
    return stats_fields^


def build_ordered_fields(discovery: DiscoveryResult) -> Dict[String, List[String]]:
    """Struct name -> names of its `ordered`-marked fields, for every
    `@@struct` declared project-wide -- lets the rewrite engine's
    table-level-call dispatch recognize an ordered field's own range-query
    calls (`for_<field>_greater_than`/`_less_than`/`_at_least`/`_at_most`/
    `_between`), distinguishing them from an ordinary `for_<field>` exact
    match by checking against the field's declared name directly rather
    than guessing a fixed suffix length (a field's own name can itself
    contain underscores, so blind slicing would be ambiguous)."""
    var ordered_fields = Dict[String, List[String]]()
    for ds in discovery.structs:
        var names = List[String]()
        for field in ds.parsed.fields:
            if field.modifier == FieldModifier.ORDERED:
                names.append(field.name)
        ordered_fields[ds.parsed.name] = names^
    return ordered_fields^
