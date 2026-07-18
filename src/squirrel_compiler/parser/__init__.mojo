from squirrel_compiler.parser.text_utils import (
    source_location,
    line_indent_of,
    is_ident_char,
    is_after_arrow,
    is_after_for_keyword,
    is_after_container_bracket,
    find_end_of_indented_block,
)
from squirrel_compiler.parser.ast import (
    FieldModifier,
    Field,
    TypeParam,
    ParsedStruct,
    ConstructField,
    Construct,
    AccessStep,
    FieldAccess,
    AccessChainTail,
    NameRef,
    EntityParam,
    MarkerKind,
)
from squirrel_compiler.parser.scanner import Scanner, parse_construct_fields
from squirrel_compiler.parser.relation_type_text import (
    is_wrapped_relation_type,
    relation_target_of,
    relation_wrapper_of,
    _is_relation_shaped,
)
from squirrel_compiler.parser.field_parsing import parse_struct_body, parse_hand_written_struct_fields
from squirrel_compiler.parser.type_expr import TypeExpr, parse_type_expr
