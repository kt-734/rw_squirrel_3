from squirrel_compiler.codegen.rewrite import rewrite_markers
from squirrel_compiler.codegen.rewrite_context import RewriteContext


def transform_source(
    source: String,
    relation_schema: Dict[String, Dict[String, String]],
    struct_names: Dict[String, Bool],
    function_returns: Dict[String, String],
    unique_fields: Dict[String, List[String]],
    indexed_fields: Dict[String, List[String]],
    multi_fields: Dict[String, List[String]] = Dict[String, List[String]](),
    ordered_fields: Dict[String, List[String]] = Dict[String, List[String]](),
    world_methods: Dict[String, List[String]] = Dict[String, List[String]](),
    stats_fields: Dict[String, List[String]] = Dict[String, List[String]](),
    plain_struct_names: Dict[String, Bool] = Dict[String, Bool](),
    plain_value_fields: Dict[String, Dict[String, String]] = Dict[String, Dict[String, String]](),
) raises -> String:
    """Entry point for converting one whole `.mojo.sqrrl` file: builds a
    fresh `RewriteContext` and hands off to `rewrite_markers`."""
    var ctx = RewriteContext(
        relation_schema=relation_schema.copy(),
        struct_names=struct_names.copy(),
        function_returns=function_returns.copy(),
        unique_fields=unique_fields.copy(),
        indexed_fields=indexed_fields.copy(),
        multi_fields=multi_fields.copy(),
        ordered_fields=ordered_fields.copy(),
        world_methods=world_methods.copy(),
        stats_fields=stats_fields.copy(),
        plain_struct_names=plain_struct_names.copy(),
        plain_value_fields=plain_value_fields.copy(),
        entity_to_type=Dict[String, String](),
        world_declared=False,
        temp_keep_alives_declared=False,
    )
    return rewrite_markers(source, ctx)
