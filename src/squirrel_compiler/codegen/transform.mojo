from squirrel_compiler.codegen.rewrite import rewrite_markers
from squirrel_compiler.codegen.rewrite_context import RewriteContext
from squirrel_compiler.parser import Field


def transform_source(
    source: String,
    relation_schema: Dict[String, Dict[String, String]],
    struct_names: Dict[String, Bool],
    unique_fields: Dict[String, List[String]],
    indexed_fields: Dict[String, List[String]],
    multi_fields: Dict[String, List[String]] = Dict[String, List[String]](),
    ordered_fields: Dict[String, List[String]] = Dict[String, List[String]](),
    world_methods: Dict[String, List[String]] = Dict[String, List[String]](),
    stats_fields: Dict[String, List[String]] = Dict[String, List[String]](),
    key_group_lookup_names: Dict[String, List[String]] = Dict[String, List[String]](),
    struct_fields: Dict[String, List[Field]] = Dict[String, List[Field]](),
    struct_key_groups: Dict[String, List[List[String]]] = Dict[String, List[List[String]]](),
    struct_method_body: Dict[String, String] = Dict[String, String](),
    plain_struct_names: Dict[String, Bool] = Dict[String, Bool](),
    plain_value_fields: Dict[String, Dict[String, String]] = Dict[String, Dict[String, String]](),
    json_used: Bool = False,
    bare_function_returns: Dict[String, String] = Dict[String, String](),
    bare_method_returns: Dict[String, Dict[String, String]] = Dict[String, Dict[String, String]](),
) raises -> String:
    """Entry point for converting one whole `.mojo.sqrrl` file: builds a
    fresh `RewriteContext` and hands off to `rewrite_markers`. `json_used`
    (whether the whole project touches JSON at all -- `driver/misc_
    builders.mojo`'s `project_uses_json`, computed *before* any file gets
    transformed, unlike `uses_json_entry_point`) gates `codegen/entity.
    mojo`'s own `sqrrl___JsonSerializable` conformance -- consumed only by
    JSON codegen (`driver/json_module.mojo`'s own module doc comment), so
    a project that never touches JSON at all shouldn't carry it on every
    entity unconditionally."""
    var ctx = RewriteContext(
        relation_schema=relation_schema.copy(),
        struct_names=struct_names.copy(),
        unique_fields=unique_fields.copy(),
        indexed_fields=indexed_fields.copy(),
        multi_fields=multi_fields.copy(),
        ordered_fields=ordered_fields.copy(),
        world_methods=world_methods.copy(),
        stats_fields=stats_fields.copy(),
        key_group_lookup_names=key_group_lookup_names.copy(),
        struct_fields=struct_fields.copy(),
        struct_key_groups=struct_key_groups.copy(),
        struct_method_body=struct_method_body.copy(),
        plain_struct_names=plain_struct_names.copy(),
        plain_value_fields=plain_value_fields.copy(),
        bare_function_returns=bare_function_returns.copy(),
        bare_method_returns=bare_method_returns.copy(),
        entity_to_type=Dict[String, String](),
        world_declared=False,
        temp_keep_alives_declared=False,
        json_used=json_used,
    )
    return rewrite_markers(source, ctx)
