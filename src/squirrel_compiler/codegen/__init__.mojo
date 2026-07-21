from squirrel_compiler.codegen.helpers import (
    sqrrl_prefixed,
    is_relation_field,
    storage_field_name,
    storage_field_name_for_hop,
    storage_field_name_for_plain,
    rewritten_field_type,
    emit_field_type,
    emit_index_type,
    is_container_type,
    container_wrapper_of,
    container_element_of,
    container_index_result_of,
    is_entity_iterable_leaf,
    encode_container_type,
    scan_entity_return_shape,
    scan_bare_return_type_text,
)
from squirrel_compiler.codegen.entity import emit_entity_inner, emit_entity
from squirrel_compiler.codegen.table import emit_indexes, emit_table
from squirrel_compiler.codegen.rewrite_context import RewriteContext
from squirrel_compiler.codegen.rewrite import rewrite_markers
from squirrel_compiler.codegen.transform import transform_source
