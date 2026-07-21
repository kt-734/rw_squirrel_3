@fieldwise_init
struct FieldModifier(ImplicitlyCopyable, Movable, Equatable):
    """Which (if any) modifier keyword a `@@struct` field was declared
    with. Mojo has no `enum` keyword -- a struct wrapping a discriminant,
    with named `comptime` values. A `Field` holds exactly one
    `FieldModifier`, not one `Bool` per keyword -- `unique`/`indexed`/
    `multi`/`ordered` are structurally mutually exclusive.

    Redesigned from rw_squirrel_2: `FORWARD_ONLY` (the old opt-*out* of a
    default-on backward index) is replaced by `INDEXED` (the new opt-*in*
    for a plain field that wants today's default `for_<field>` behavior with
    no other constraint) -- see the plan's Context point 1. `NONE` now means
    "no backward index at all, and this field's own `set_<field>` never
    touches the table" rather than "gets the default `Rel`-backed index"."""

    var value: Int

    comptime NONE = Self(0)
    comptime UNIQUE = Self(1)
    comptime INDEXED = Self(2)
    comptime MULTI = Self(3)
    comptime ORDERED = Self(4)

    def __eq__(self, other: Self) -> Bool:
        return self.value == other.value

    def __ne__(self, other: Self) -> Bool:
        return self.value != other.value


@fieldwise_init
struct Field(Copyable, Movable):
    """A single `name: Type` entry inside a `@@struct` body. `type_str` is
    left as raw, untouched text -- whether it's a plain Mojo type or a
    `@@`-marked relation is for codegen to interpret, not this parser.

    `is_stats` is set by a leading `stats` keyword, independent of
    `modifier` -- see rw_squirrel_2's own `Field` doc comment for the full
    reasoning (unchanged by the storage redesign)."""

    var name: String
    var type_str: String
    var modifier: FieldModifier
    var is_stats: Bool


@fieldwise_init
struct TypeParam(Copyable, Movable):
    """One entry in a hand-written plain struct's own `[T: Bound, ...]`
    type-parameter list (plain-structs milestone -- an `@@struct` is never
    generic, only a hand-written struct discovered by `Scanner.parse_hand_
    written_plain_struct` can have one). `bound` defaults to `"Copyable &
    Movable & ImplicitlyDeletable"` when the source writes no `: Bound` at
    all -- confirmed via a live spike to be a sufficient bound for a
    generic plain struct's own field storage/`__init__`/move-based
    reassignment shape against this project's pinned Mojo nightly.

    Ported from rw_squirrel_2's own `TypeParam` (same name/purpose,
    confirmed by reading it)."""

    var name: String
    var bound: String


struct ParsedStruct(Copyable, Movable):
    """One `@@struct [keepalive] [equatable] @@Name[(Trait1, Trait2, ...)]:
    <indented fields, then optional methods>` declaration -- or, reused for
    the plain-structs milestone, a hand-written `struct Name[T: Bound](...):
    <var-declared fields>` a real struct in its own right, discovered
    structurally by `Scanner.parse_hand_written_plain_struct` rather than
    parsed as a `@@`-marked declaration.

    `trait_list`/`method_body` are captured by the parser regardless of
    milestone (the grammar is stable), even though codegen doesn't splice
    them into the generated entity wrapper until M3 -- see the plan's
    Milestones section.

    `type_params` (only ever non-empty for a hand-written plain struct --
    an `@@struct` is never generic) is its own `[T: Bound, ...]` list, if
    any -- see `TypeParam`'s own doc comment. Mirrors rw_squirrel_2's own
    `ParsedStruct.type_params`, confirmed by reading it."""

    var name: String
    var fields: List[Field]
    var is_keepalive: Bool
    var is_equatable: Bool
    var trait_list: List[String]
    var method_body: String
    var type_params: List[TypeParam]

    def __init__(
        out self,
        var name: String,
        var fields: List[Field],
        is_keepalive: Bool = False,
        is_equatable: Bool = False,
        var trait_list: List[String] = List[String](),
        var method_body: String = String(),
        var type_params: List[TypeParam] = List[TypeParam](),
    ):
        self.name = name^
        self.fields = fields^
        self.is_keepalive = is_keepalive
        self.is_equatable = is_equatable
        self.trait_list = trait_list^
        self.method_body = method_body^
        self.type_params = type_params^


@fieldwise_init
struct ConstructField(Copyable, Movable):
    """One `.name = value` (or, for a relation field, `.@@name = value`)
    segment inside a `@@TypeName { ... }` construct body."""

    var name: String
    var is_relation: Bool
    var value: String


@fieldwise_init
struct Construct(Copyable, Movable):
    """A `@@TypeName { .field = expr, ... }` construction use site."""

    var type_name: String
    var fields: List[ConstructField]


@fieldwise_init
struct AccessStep(Copyable, Movable):
    """One `.field`/`.@@field`/`.@@@field`/`[index]` segment inside a
    `@@entity<steps...>` access chain (plain-structs milestone's general
    recursive access-chain redesign -- see the plan's Revision 3). A chain
    is just `List[AccessStep]`; there is no fixed depth and no special-
    cased "bare indexed reference" shape any more -- `@@matches[0]` is
    simply `steps == [AccessStep(kind=INDEX, ...)]`.

    `kind` is `FIELD` or `INDEX`. For `FIELD`, `name` is the identifier
    (a compound marked-call suffix like `add_to_@@projects` is still
    combined into one segment/one step here, exactly as today -- that
    stays a same-segment scanning concern, not a separate step kind).
    `marked`/`marked_world` are `FIELD`-only, meaning `.@@name`/`.@@@name`
    respectively (mutually exclusive, both false for a plain `.name`).
    For `INDEX`, `name` holds the raw, unparsed bracket-interior text, and
    `marked`/`marked_world` are always false.

    `end_pos` is pure scan-time bookkeeping -- the byte offset in the
    source immediately after this step's own token. It is never compared
    or rendered; `handle_field_access`'s walk uses it only to roll `sc.pos`
    back to a known-good boundary when the scanner's greedy chain-parsing
    turns out to have over-consumed past a plain (non-struct, non-
    container) leaf field -- see "premature-leaf rollback" in the plan."""

    comptime FIELD = 0
    comptime INDEX = 1

    var kind: Int
    var name: String
    var marked: Bool
    var marked_world: Bool
    var end_pos: Int

    def is_field(self) -> Bool:
        return self.kind == Self.FIELD

    def is_index(self) -> Bool:
        return self.kind == Self.INDEX


@fieldwise_init
struct FieldAccess(Copyable, Movable):
    """A `@@entity<steps...>` use-site access -- a read, or (if
    `write_value` is set) a write from `@@entity<steps...> = expr;`.
    `steps` is the full chain of `.field`/`[index]` segments, in source
    order, replacing the old fixed-depth `hops`/`field`/`field_marked`/
    `field_marked_world`/`index_expr`/`post_index_expr`/`post_field`/
    `post_field_marked` fields -- see the plan's Revision 3 for the full
    rationale (arbitrary-depth chaining, direct indexing, writing through
    an index).

    `is_call` is set instead when the chain is immediately followed by
    `(` -- a call (table-level, or an instance method on the walked
    terminal type) rather than a field/index access. A chain whose last
    step is an `INDEX` can never also be `is_call` -- rejected explicitly
    in the walk ("can't call directly on an indexed container element").

    `entity_marked_world` is true when `entity` was reached via `@@@`
    (three `@`s) rather than plain `@@` -- the M3 addendum's marker for
    "this reference needs `sqrrl___world`". The scanner can't yet tell
    whether `entity` is a bound variable (requiring plain `@@`) or a
    struct type name doing a table-level call (requiring `@@@`) -- that's
    resolved later in `rewrite_field_access.mojo`, which validates this
    flag against `ctx.entity_to_type` once it knows which case it is.

    `entity_is_bare` is true when `entity` carried no `@@` marker at all
    -- a plain-struct-typed local variable's own name (`n.@@ref`, `Scanner.
    bare_root_before_dot`'s own shape). `entity` itself is never rewritten
    for this case (no `sqrrl__` prefix -- the name was never marked, so
    the generated name is identical to the source one); only marked
    *steps* further down the chain still go through the usual rewriting."""

    var entity: String
    var entity_marked_world: Bool
    var entity_is_bare: Bool
    var steps: List[AccessStep]
    var is_call: Bool
    var write_value: Optional[String]


@fieldwise_init
struct AccessChainTail(Copyable, Movable):
    """What `Scanner.scan_call_or_write_tail` found immediately after a
    `.field`/`[index]` step chain -- shared between `parse_field_access`
    (a chain rooted at a bound `@@entity`) and `Scanner.scan_trailing_
    chain` (a chain rooted at the *return value* of an `@@`/`@@@`-marked
    function call, e.g. `@@get_dept(@@alice).name` -- mandatory-marking
    milestone). Mirrors `FieldAccess.is_call`/`.write_value` exactly, just
    without an `entity` of its own to carry them on."""

    var is_call: Bool
    var write_value: Optional[String]


@fieldwise_init
struct NameRef(Copyable, Movable):
    """A bare `@@name` -- covers both a declaration (`var @@alice = ...`)
    and a plain reference; both rewrite the same way (strip the `@@`). Also
    what `MarkerKind.RETURN_TYPE` parses."""

    var name: String


@fieldwise_init
struct EntityParam(Copyable, Movable):
    """A `@@name: <type>` declaration -- used in a `def`'s own parameter
    list, a local variable declaration whose right-hand side isn't itself
    a bare `@@`-marked expression, or (plain-structs milestone) a hand-
    written struct's own field declaration. `type_text` is the full, raw
    type text with `@@` markers still embedded exactly as written --
    `@@Type`, `Container[@@Type]`, or (mandatory-marking-era generalized
    scan, `Scanner.scan_entity_param_type_text`) any nested/multi-
    argument shape a `@@struct`'s own field declaration already supports
    (`Dict[String, @@Type]`, `List[Dict[String, @@Type]]`, ...). `parse_
    type_expr`/`rewritten_field_type` (the same general machinery a
    struct field's own type already goes through) resolve it, not a
    bespoke single-wrapper-single-argument grammar of this struct's own."""

    var name: String
    var type_text: String


@fieldwise_init
struct PlainVarDecl(Copyable, Movable):
    """`[var ]<name>: <Type>` -- a *bare* (never `@@`-marked) local
    variable, def-parameter, or hand-written-struct-field name with an
    explicit type annotation, `type_text` either a single identifier
    (`Note`) or a container of one (`List[Note]`), raw and un-rewritten
    -- `type_text` can still itself embed a genuine `@@`-marked relation
    reference even though `name` never carries `@@` at all (`members:
    List[Dict[String, @@Employee]]`, a relation confined to a position
    that doesn't require the *field's* own name to be marked): the
    caller must run `type_text` through `rewritten_field_type` before
    emitting it, the same general function `EntityParam`'s own hand-
    written-struct-field branch already relies on for the identical
    purpose -- never copy `type_text` through raw. `prefix_text` is
    everything from the marker's own start through the declaration's `:`
    and its trailing whitespace, captured verbatim (preserving whether
    `var ` was actually present, and the source's own original spacing)
    for the caller to re-emit unchanged ahead of the rewritten type.

    Unlike `EntityParam`, `name` is never itself `@@`-prefixed (a plain
    struct's own value never carries `@@` on the variable holding it --
    only a field *access* through it can be marked, e.g. `n.@@ref`) --
    this exists purely so a later marked field-access chain rooted at
    `name` can resolve `type_text` as its starting type, the same way a
    `@@Type{...}` construct or an `EntityParam` already lets a *marked*
    name do.

    `type_is_inferred` is True for the one remaining shape that needs no
    explicit annotation at all: a var-decl whose initializer is itself a
    constructor-call-shaped expression (`var addresses = List[Address]
    ()`, `type_text` = `List[Address]`, inferred from the constructor's
    own head rather than a written-out `: List[Address]`) -- the plain-
    struct-local analogue of `handle_name_ref`'s own marked-var-decl
    fallback (`var @@x = List[@@Type]()`, no explicit `@@Type` needed
    either). When True, `type_text` is for *registration only*: the
    constructor call itself is left unconsumed for the ordinary scan to
    re-discover and emit normally (any `@@`-marked argument inside it
    still needs that), so the caller must NOT also emit `type_text` --
    doing so would duplicate it, since the same text reappears right
    after `prefix_text` in the source, about to be scanned again."""

    var name: String
    var prefix_text: String
    var type_text: String
    var type_is_inferred: Bool


@fieldwise_init
struct PlainForLoop(Copyable, Movable):
    """`for [var/ref ]<loop_var> in <container>:` -- both the loop
    variable and the iterated expression bare (never `@@`-marked). The
    iterated expression is either a single name (`for n in notes:`,
    `container_name` alone, `is_call=False`) or a single bare function
    call (`for n in get_notes(@@b):`, `is_call=True`, `arg_text` the
    call's own raw, unrewritten argument-list text) -- not a full
    arbitrary expression either way (`for n in some_dict.values():`
    still isn't covered). Exists purely so `rewrite.mojo`'s own handler
    can look up `container_name` in `ctx.entity_to_type` (the variable
    case) or `ctx.bare_function_returns` (the call case) and, if it's a
    container type, register `loop_var` against its element type -- the
    bare-name/bare-call equivalent of `MarkerKind.FOR_ENTITY_LOOP`'s own
    `pending_for_loop_decl` mechanism, which only ever triggers for a
    `@@`-marked loop variable.

    `binding_prefix` is `"var"`/`"ref"` if the source wrote one before
    `loop_var`, else empty -- needed because the `is_call` case
    reconstructs its own output text from parsed pieces rather than
    copying the matched span verbatim (the non-call case's own `rewrite.
    mojo` handler just copies `source[start:end]`, `var`/`ref` included
    for free); without threading this through, the reconstruction
    silently dropped it -- confirmed via a real compile: `for ref a in
    get_addrs():` generated `for a in get_addrs():`, silently changing
    the loop binding's own mutability semantics from the source."""

    var loop_var: String
    var container_name: String
    var is_call: Bool
    var arg_text: String
    var binding_prefix: String


@fieldwise_init
struct BareForLoopHeader(Copyable, Movable):
    """`for [var/ref ]<loop_var> in` -- `Scanner.parse_bare_for_loop_
    over_marked_chain`'s own return value, split into pieces since its
    caller (`rewrite.mojo`'s `BARE_FOR_ENTITY_LOOP` handler) always
    reconstructs the output text (never copies verbatim -- the `@@`-
    marked chain that follows always needs the ordinary marker-scanning
    loop to continue from right after `in`, unlike `PLAIN_FOR_LOOP`'s own
    non-call case) and needs `binding_prefix` (`"var"`/`"ref"`/empty, see
    `PlainForLoop`'s own doc comment for why this matters) threaded back
    in alongside `loop_var` to avoid the same silent-drop bug."""

    var loop_var: String
    var binding_prefix: String


@fieldwise_init
struct MarkerKind(ImplicitlyCopyable, Movable, Equatable):
    """What `Scanner.find_next_marker` found. Mojo has no `enum` keyword --
    a struct wrapping a discriminant, with named `comptime` values.

    Slimmed from rw_squirrel_2 for M1's scope (see the plan's Milestones
    section): originally dropped `PLAIN_VAR_DECL` (plain-struct-typed
    locals, deferred alongside plain structs generally, M2+) -- since
    built (plain-structs milestone), see `Scanner.at_plain_var_decl`/
    `parse_plain_var_decl`. `BEGIN_INIT_FROM_JSON`/`END_INIT_FROM_JSON`/
    `INIT_FROM_JSON` (whole-world JSON serialization) and `TO_JSON` land in
    M5, filling the three gaps this struct's own numbering had already
    reserved for them plus one new value."""

    var value: Int

    comptime NONE = Self(0)
    comptime STRUCT = Self(1)
    comptime CONSTRUCT = Self(2)
    comptime FIELD_ACCESS = Self(3)
    comptime NAME_REF = Self(4)
    comptime INIT = Self(5)
    comptime WORLD_FUNC = Self(6)
    comptime ENTITY_PARAM = Self(7)
    comptime RETURN_TYPE = Self(8)
    comptime BEGIN_INIT_FROM_JSON = Self(9)
    comptime FOR_ENTITY_LOOP = Self(10)
    comptime END_INIT_FROM_JSON = Self(11)
    comptime INIT_FROM_JSON = Self(12)
    comptime WORLD_SCOPE = Self(13)
    comptime TO_JSON = Self(15)
    comptime ENTITY_FUNC = Self(16)
    comptime CONSTRUCT_KWARG = Self(17)
    comptime PLAIN_VAR_DECL = Self(18)
    comptime PLAIN_FOR_LOOP = Self(19)
    comptime BARE_CALL_CHAIN = Self(20)
    comptime BARE_FOR_ENTITY_LOOP = Self(21)
    comptime BARE_VAR_DECL_OVER_ENTITY = Self(22)
    comptime BARE_ROOTED_CHAIN = Self(23)
    comptime BARE_VAR_DECL_OVER_BARE_CHAIN = Self(24)
    comptime BARE_FOR_LOOP_OVER_BARE_CHAIN = Self(25)

    def __eq__(self, other: Self) -> Bool:
        return self.value == other.value

    def __ne__(self, other: Self) -> Bool:
        return self.value != other.value
