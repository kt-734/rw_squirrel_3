from squirrel_compiler.parser import Scanner, ParsedStruct, Field, FieldModifier, parse_type_expr, TypeParam
from squirrel_compiler.driver.file_paths import module_path_for
from squirrel_compiler.codegen import sqrrl_prefixed, is_relation_field
from squirrel_compiler.codegen.methods import world_marked_method_names


struct DiscoveredStruct(Copyable, Movable, ImplicitlyDeletable):
    """One `@@struct` found during the directory walk, tagged with the
    dotted module path of the file that declared it."""

    var module_path: String
    var parsed: ParsedStruct

    def __init__(out self, var module_path: String, var parsed: ParsedStruct):
        self.module_path = module_path^
        self.parsed = parsed^


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
                discovered.append(DiscoveredStruct(module_path, parsed^))
        except e:
            raise Error(path + ": " + String(e))

    return DiscoveryResult(discovered^, module_of^)


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
    nested, e.g. `"List[List[Employee]]"`), for every relation field in
    `fields` -- a `multi` field's own `type_str` is already the bare,
    `@@`-marked element type (`multi @@projects: @@Project`'s is
    `@@Project`, same shape a bare relation field's is), so it's registered
    here identically, no separate case needed. Plain-structs milestone:
    `is_relation_field`/`render_relation_stripped` now also recognize a
    (possibly nested) container-wrapped relation field (`@@container`
    support -- see the plan's Revision 3), not just a bare `@@Type`."""
    var out = Dict[String, String]()
    for field in fields:
        if is_relation_field(field):
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
    """Field name -> declared plain type, for every *non*-relation field in
    `fields` -- `RewriteContext.plain_value_fields`'s own per-struct entry
    (plain-structs milestone): the general access-chain walk's
    `owner_is_real`/`owner_is_plain` dispatch validates a FIELD step's
    `marked` flag against `relation_schema`/`plain_value_fields` uniformly,
    regardless of which kind of struct declares the field."""
    var out = Dict[String, String]()
    for field in fields:
        if not is_relation_field(field):
            out[field.name] = field.type_str
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
    kept as a separate struct since nothing else needs this pairing)."""

    var fields: Dict[String, List[Field]]
    var module_of: Dict[String, String]
    var is_generic: Dict[String, Bool]
    var type_params: Dict[String, List[TypeParam]]

    def __init__(
        out self,
        var fields: Dict[String, List[Field]],
        var module_of: Dict[String, String],
        var is_generic: Dict[String, Bool] = Dict[String, Bool](),
        var type_params: Dict[String, List[TypeParam]] = Dict[String, List[TypeParam]](),
    ):
        self.fields = fields^
        self.module_of = module_of^
        self.is_generic = is_generic^
        self.type_params = type_params^


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
        except e:
            raise Error(path + ": " + String(e))
    return PlainStructDiscovery(fields^, module_of^, is_generic^, type_params^)


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
    whether calling a spliced user method needs `sqrrl__world` threaded as
    its own first argument, even when the call site is in a different file
    than the one declaring the method (same cross-file reasoning M2's
    relation-schema resolution already needs)."""
    var world_methods = Dict[String, List[String]]()
    for ds in discovery.structs:
        world_methods[ds.parsed.name] = world_marked_method_names(ds.parsed.method_body, ds.parsed.name)
    return world_methods^


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
