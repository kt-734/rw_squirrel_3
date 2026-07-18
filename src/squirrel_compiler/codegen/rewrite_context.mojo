@fieldwise_init
struct RewriteContext(Copyable, Movable):
    """Bundles the read-only, project-wide analysis inputs plus the two
    cross-recursive mutable fields (`entity_to_type`/`world_declared`)
    `rewrite_markers` threads into a nested, recursive sub-scan (a
    construct field's own value, an index expression).

    Slimmed from rw_squirrel_2's own `RewriteContext`: drops
    `plain_struct_fields`/`relation_targets` (plain structs, M2+ but not
    yet built), `aggregate_usages` (M4). Adds `struct_names` (which
    identifiers name a known `@@struct`, needed for table-level call
    dispatch -- rw_squirrel_2 approximated this by checking
    `relation_schema` presence, which breaks for a struct with zero
    relation fields) and `indexed_fields` (which fields are
    `indexed`-tagged, the M1 replacement for rw_squirrel_2's "every field
    defaults to indexed unless `forwardonly`" -- see the plan's Context
    point 1). `multi_fields` (M2) lets `for_<field>` dispatch recognize a
    `multi` field's own element-keyed reverse lookup, and instance-call
    dispatch recognize `add_to_<field>`/`remove_from_<field>`.
    `world_methods` (M3) is `entity_methods`'s replacement -- struct name ->
    names of its `@@@`-marked methods (see `codegen/methods.mojo`'s
    `world_marked_method_names`/`discovery.mojo`'s `build_world_methods`),
    letting instance-call dispatch tell whether calling a spliced user
    method needs `sqrrl__world` threaded as its own first argument.
    `stats_fields` (M4) lets table-level-call dispatch recognize
    `sum_<field>`/`avg_<field>` (need `is_stats`, unlike `min_`/`max_`/
    `median_`, which an `ordered` field earns for free -- see
    `analysis/field_shape.mojo`). `temp_keep_alives_declared` (M5) is
    `world_declared`'s sibling for the JSON-reload local `sqrrl__
    temp_keep_alives`: set by `@@@begin_init_from_json(...)`, cleared by
    `@@@end_init_from_json()`, giving a repeat `begin` or a stray `end` a
    clean compile-time check instead of an opaque downstream Mojo error.

    `plain_struct_names`/`plain_value_fields` (plain-structs milestone) are
    the general access-chain walk's `owner_is_real`/`owner_is_plain`
    dispatch's own two project-wide maps: `plain_struct_names` says which
    struct names are hand-written plain structs (disjoint from
    `struct_names`, checked once at discovery time), `plain_value_fields`
    is `relation_schema`'s parallel for a *plain-value* field (unmarked, no
    relation content of its own -- `home: Address` on `@@Person`, or one of
    `Address`'s own plain fields) -- struct name -> field name -> declared
    plain type. Whichever of `relation_schema`/`plain_value_fields` a
    step's name is found in determines both its required `@@`-marking and
    its storage-name convention (`rewrite_field_access.mojo`)."""

    var relation_schema: Dict[String, Dict[String, String]]
    var struct_names: Dict[String, Bool]
    var function_returns: Dict[String, String]
    var unique_fields: Dict[String, List[String]]
    var indexed_fields: Dict[String, List[String]]
    var multi_fields: Dict[String, List[String]]
    var ordered_fields: Dict[String, List[String]]
    var world_methods: Dict[String, List[String]]
    var stats_fields: Dict[String, List[String]]
    var plain_struct_names: Dict[String, Bool]
    var plain_value_fields: Dict[String, Dict[String, String]]
    var entity_to_type: Dict[String, String]
    var world_declared: Bool
    var temp_keep_alives_declared: Bool
    var json_used: Bool

    def fresh_function_scope(self) -> Self:
        """A copy of this context with `entity_to_type`/`world_declared`/
        `temp_keep_alives_declared` reset -- what a new top-level `def`
        resets to, and what rewriting a `@@struct`'s own spliced method body
        needs too (M3). `json_used` (whether the whole project touches JSON
        at all -- `driver/misc_builders.mojo`'s `project_uses_json`) is a
        project-wide fact, not per-scope state, so it always carries over
        unchanged, same as every other read-only analysis input above it."""
        return Self(
            relation_schema=self.relation_schema.copy(),
            struct_names=self.struct_names.copy(),
            function_returns=self.function_returns.copy(),
            unique_fields=self.unique_fields.copy(),
            indexed_fields=self.indexed_fields.copy(),
            multi_fields=self.multi_fields.copy(),
            ordered_fields=self.ordered_fields.copy(),
            world_methods=self.world_methods.copy(),
            stats_fields=self.stats_fields.copy(),
            plain_struct_names=self.plain_struct_names.copy(),
            plain_value_fields=self.plain_value_fields.copy(),
            entity_to_type=Dict[String, String](),
            world_declared=False,
            temp_keep_alives_declared=False,
            json_used=self.json_used,
        )
