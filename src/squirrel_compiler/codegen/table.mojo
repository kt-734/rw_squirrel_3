from squirrel_compiler.parser import ParsedStruct, Field, FieldModifier
from squirrel_compiler.codegen.helpers import (
    sqrrl_prefixed,
    storage_field_name,
    param_name,
    needs_move_assignment,
    emit_field_type,
    emit_multi_element_type,
    emit_index_type,
)


def _inner_name(struct_name: String) -> String:
    return sqrrl_prefixed(struct_name) + "Inner"


def _indexes_name(struct_name: String) -> String:
    return sqrrl_prefixed(struct_name) + "Indexes"


def _table_name(struct_name: String) -> String:
    return sqrrl_prefixed(struct_name) + "Table"


def _has_any_unique(parsed: ParsedStruct) -> Bool:
    for f in parsed.fields:
        if f.modifier == FieldModifier.UNIQUE:
            return True
    return False


def _emit_count_field(f: Field, key_type: String) -> String:
    """`count_<field>(value) -> Int` -- `len(for_<field>(value))` without
    building an entity for every matching one just to throw it away right
    after. Shared by every non-`unique` indexed-family modifier; `unique`
    needs its own non-raising `contains`-based shape instead (`for_<field>`
    on a `unique` field already raises when `value` is unused, so this is
    genuinely new information there, not just a cheaper `len`)."""
    var out = String("\n")
    out += "    def count_" + param_name(f) + "(self, value: " + key_type + ") -> Int:\n"
    out += "        return len(self.storage[].indexes." + f.name + ".get_bwd(value))\n"
    return out^


def _emit_group_by_count_by_distinct(
    f: Field, entity_name: String, key_type: String, binding: String, distinct_returns_list: Bool
) -> String:
    """`group_by_<field>`/`count_by_<field>`/`distinct_<field>` -- shared
    shape for every indexed-family modifier except `unique` (whose
    `group_by_<field>` has no `Set` wrapping and earns no `count_by_<field>`
    at all -- every group is exactly 1 by construction, carrying zero
    information beyond what `unique` already guarantees -- so `unique` is
    emitted separately, not through this helper). `binding` is `ref` for
    indexed/multi (`PlainIndex`/`MultiIndex.all_bwd` borrow `_bwd`
    directly) and `var` for ordered (`OrderedIndex.all_bwd` builds a fresh
    owned `Dict` each call, walking `_sorted`'s already-ascending order --
    no `_bwd` dict exists there to borrow). `distinct_returns_list` is set
    only for `ordered`, whose ascending order is worth making explicit in
    the return type itself, same reason its range-query methods stay
    `List`-returning rather than `Set`."""
    var out = String("\n")
    out += "    def group_by_" + param_name(f) + "(self) -> Dict[" + key_type + ", Set[" + entity_name + "]]:\n"
    out += "        " + binding + " buckets = self.storage[].indexes." + f.name + ".all_bwd()\n"
    out += "        var out = Dict[" + key_type + ", Set[" + entity_name + "]]()\n"
    out += "        for entry in buckets.items():\n"
    out += "            var handles = Set[" + entity_name + "]()\n"
    out += "            for id in entry.value:\n"
    out += "                handles.add(" + entity_name + "(self.storage[].handle_for(id)))\n"
    out += "            out[entry.key] = handles^\n"
    out += "        return out^\n"
    out += "\n"
    out += "    def count_by_" + param_name(f) + "(self) -> Dict[" + key_type + ", Int]:\n"
    out += "        " + binding + " buckets = self.storage[].indexes." + f.name + ".all_bwd()\n"
    out += "        var out = Dict[" + key_type + ", Int]()\n"
    out += "        for entry in buckets.items():\n"
    out += "            out[entry.key] = len(entry.value)\n"
    out += "        return out^\n"
    out += "\n"
    var container = "List" if distinct_returns_list else "Set"
    out += "    def distinct_" + param_name(f) + "(self) -> " + container + "[" + key_type + "]:\n"
    out += "        var out = " + container + "[" + key_type + "]()\n"
    out += "        " + binding + " buckets = self.storage[].indexes." + f.name + ".all_bwd()\n"
    out += "        for key in buckets.keys():\n"
    out += "            out." + ("append" if distinct_returns_list else "add") + "(key.copy())\n"
    out += "        return out^\n"
    return out^


def emit_indexes(parsed: ParsedStruct, plain_struct_names: Dict[String, Bool] = Dict[String, Bool]()) -> String:
    """Emits `sqrrl__<Name>Indexes` -- one field per indexed-family field
    only (point 6 of the plan: no entry at all for a plain, `NONE`-modifier
    field). Field names stay bare, unlike `Inner`'s own -- point 4's last
    sentence: `Indexes` is pure table-internal bookkeeping, never touched
    by DSL-generated reads/writes or external code, so there's no
    external-facing surface to signal "private" against."""
    var indexes_name = _indexes_name(parsed.name)
    var out = String("struct " + indexes_name + "(Movable, ImplicitlyDeletable):\n")
    var any_indexed = False
    for f in parsed.fields:
        if f.modifier != FieldModifier.NONE:
            out += "    var " + f.name + ": " + emit_index_type(f, plain_struct_names) + "\n"
            any_indexed = True
    if any_indexed:
        out += "\n"
    out += "    def __init__(out self):\n"
    var any_init = False
    for f in parsed.fields:
        if f.modifier != FieldModifier.NONE:
            out += "        self." + f.name + " = " + emit_index_type(f, plain_struct_names) + "()\n"
            any_init = True
    if not any_init:
        out += "        pass\n"
    return out^


def emit_table(parsed: ParsedStruct, plain_struct_names: Dict[String, Bool] = Dict[String, Bool]()) -> String:
    """Emits `sqrrl__<Name>Table` -- genuine whole-table operations only
    (point 6): `create`, `all`/`count`, and `for_<field>` for every
    indexed-family field. No `get_*`/`set_*` here at all any more --
    those live entirely on `sqrrl__<Name>Inner` (see `entity.mojo`),
    regardless of a field's own indexed-ness.

    Holds `ArcPointer[EntityStorage[Indexes, Inner]]` directly -- no
    separate `EntityTable` middle layer (see `entity_storage.mojo`'s own
    doc comment for why that would've been pure indirection with nothing
    of its own)."""
    var entity_name = sqrrl_prefixed(parsed.name)
    var inner_name = _inner_name(parsed.name)
    var indexes_name = _indexes_name(parsed.name)
    var table_name = _table_name(parsed.name)
    var storage_type = String("EntityStorage[" + indexes_name + ", " + inner_name + "]")

    var out = String("struct " + table_name + "(Movable):\n")
    out += "    var storage: ArcPointer[" + storage_type + "]\n"
    out += "\n"
    out += "    def __init__(out self):\n"
    out += "        self.storage = ArcPointer(" + storage_type + "(" + indexes_name + "()))\n"

    # create() -- parameter names carry sqrrl__ for a relation field (mirrors
    # the DSL's own construction-site label, point 3 -- no exceptions). Every
    # UNIQUE field is validated for availability *before* allocating an id or
    # constructing anything, so a rejected create() leaves no partial state
    # needing cleanup. A `multi` field is just another field with a
    # `Set`-typed value -- an ordinary default parameter value (`= Set[...]()`)
    # covers "no initial membership supplied", so a construct site can either
    # populate it inline (`.@@projects = Set(@@website, @@app)`) or omit it
    # and populate it afterward one element at a time via
    # add_to_<field>/remove_from_<field> (see entity.mojo) -- both paths work
    # unchanged, no special-casing needed beyond the default value itself.
    out += "\n"
    var params = String()
    var first = True
    for f in parsed.fields:
        if not first:
            params += ", "
        if needs_move_assignment(f, plain_struct_names):
            # Set[T] (multi) / a wrapped relation (List[T] included -- not
            # ImplicitlyCopyable either, verified directly) / a
            # hand-written plain struct -- none is guaranteed
            # ImplicitlyCopyable, so all need `var` (owned) so the
            # ctor_args assignment below can move rather than copy.
            params += "var "
        params += param_name(f) + ": " + emit_field_type(f, plain_struct_names)
        if f.modifier == FieldModifier.MULTI:
            params += " = " + emit_field_type(f, plain_struct_names) + "()"
        first = False
    var has_unique = _has_any_unique(parsed)
    out += "    def create(mut self, " + params + ")"
    if has_unique:
        out += " raises"
    out += " -> " + entity_name + ":\n"
    for f in parsed.fields:
        if f.modifier == FieldModifier.UNIQUE:
            out += (
                "        if self.storage[].indexes."
                + f.name
                + ".contains("
                + param_name(f)
                + "):\n"
            )
            out += (
                '            raise Error("UniqueConstraintViolation: \''
                + f.name
                + "' already in use by another entity\")\n"
            )
    out += "        var id = self.storage[].alloc_id()\n"
    var ctor_args = String("_id=id, _table=self.storage")
    for f in parsed.fields:
        ctor_args += ", " + storage_field_name(f) + "=" + param_name(f)
        if needs_move_assignment(f, plain_struct_names):
            # Same set as the parameter-list check above -- none of these
            # is guaranteed ImplicitlyCopyable, and the parameter's only
            # use is this exact assignment, so move it rather than copy.
            ctor_args += "^"
    out += "        var inner = ArcPointer(" + inner_name + "(" + ctor_args + "))\n"
    out += "        self.storage[].register_weak(id, inner)\n"
    for f in parsed.fields:
        if f.modifier == FieldModifier.MULTI:
            # Element-keyed index: whatever initial membership was supplied
            # (possibly none -- the default value above) needs one add per
            # element, not a single .add(id, value) the way every other
            # indexed-family field's own value maps directly onto its
            # index -- MultiIndex.add_many does that bulk-add internally.
            out += (
                "        self.storage[].indexes."
                + f.name
                + ".add_many(id, inner[]."
                + storage_field_name(f)
                + ")\n"
            )
        elif f.modifier != FieldModifier.NONE:
            out += (
                "        self.storage[].indexes."
                + f.name
                + ".add(id, inner[]."
                + storage_field_name(f)
                + ")\n"
            )
    if parsed.is_keepalive:
        # Clone the ArcPointer (cheap -- refcount bump, not a deep copy)
        # before moving `inner` itself into the returned wrapper below --
        # `keepalive_add` needs its own owned strong hold, independent of
        # the one the caller's own returned handle carries.
        out += "        self.storage[].keepalive_add(id, inner.copy())\n"
    out += "        return " + entity_name + "(inner^)\n"

    out += "\n"
    out += "    def all(self) -> Set[" + entity_name + "]:\n"
    out += "        var out = Set[" + entity_name + "]()\n"
    out += "        for id in self.storage[].all():\n"
    out += "            out.add(" + entity_name + "(self.storage[].handle_for(id)))\n"
    out += "        return out^\n"

    out += "\n"
    out += "    def count(self) -> Int:\n"
    out += "        return self.storage[].live_count()\n"

    for f in parsed.fields:
        if f.modifier == FieldModifier.UNIQUE:
            out += "\n"
            out += "    def for_" + param_name(f) + "(self, value: " + emit_field_type(f, plain_struct_names) + ") raises -> " + entity_name + ":\n"
            out += "        var id = self.storage[].indexes." + f.name + ".get_bwd(value)\n"
            out += "        return " + entity_name + "(self.storage[].handle_for(id))\n"
        elif f.modifier == FieldModifier.MULTI:
            # Element-keyed: takes the bare element type, not the field's
            # own Set[...] type -- "which owners' membership set contains
            # this one element", matching add_to_<field>/remove_from_<field>'s
            # own parameter shape.
            out += "\n"
            out += "    def for_" + param_name(f) + "(self, value: " + emit_multi_element_type(f, plain_struct_names) + ") -> Set[" + entity_name + "]:\n"
            out += "        var out = Set[" + entity_name + "]()\n"
            out += "        for id in self.storage[].indexes." + f.name + ".get_bwd(value):\n"
            out += "            out.add(" + entity_name + "(self.storage[].handle_for(id)))\n"
            out += "        return out^\n"
        elif f.modifier == FieldModifier.ORDERED:
            # Exact match stays Set-returning, same shape as INDEXED (order
            # doesn't matter for a single value's own bucket, matches
            # all()'s own convention). Range queries return List[Entity]
            # instead, preserving ascending order -- OrderedIndex's own
            # range methods already return List[UInt32] for exactly this
            # reason (a Set here would throw the order away, the entire
            # reason `ordered` exists over plain `indexed`).
            out += "\n"
            out += "    def for_" + param_name(f) + "(self, value: " + emit_field_type(f, plain_struct_names) + ") -> Set[" + entity_name + "]:\n"
            out += "        var out = Set[" + entity_name + "]()\n"
            out += "        for id in self.storage[].indexes." + f.name + ".get_bwd(value):\n"
            out += "            out.add(" + entity_name + "(self.storage[].handle_for(id)))\n"
            out += "        return out^\n"
            for comparator in ["greater_than", "less_than", "at_least", "at_most"]:
                out += "\n"
                out += "    def for_" + param_name(f) + "_" + comparator + "(self, value: " + emit_field_type(f, plain_struct_names) + ") -> List[" + entity_name + "]:\n"
                out += "        var out = List[" + entity_name + "]()\n"
                out += "        for id in self.storage[].indexes." + f.name + "." + comparator + "(value):\n"
                out += "            out.append(" + entity_name + "(self.storage[].handle_for(id)))\n"
                out += "        return out^\n"
            out += "\n"
            out += (
                "    def for_" + param_name(f) + "_between(self, low: " + emit_field_type(f, plain_struct_names)
                + ", high: " + emit_field_type(f, plain_struct_names) + ") -> List[" + entity_name + "]:\n"
            )
            out += "        var out = List[" + entity_name + "]()\n"
            out += "        for id in self.storage[].indexes." + f.name + ".between(low, high):\n"
            out += "            out.append(" + entity_name + "(self.storage[].handle_for(id)))\n"
            out += "        return out^\n"
        elif f.modifier != FieldModifier.NONE:
            # INDEXED -- Set-returning: matches PlainIndex's own
            # Set[UInt32]-backed bucket directly (no List conversion
            # needed) and all()'s own convention, rather than preserving
            # rw_squirrel_2's plain-field List/indexable ergonomics.
            out += "\n"
            out += "    def for_" + param_name(f) + "(self, value: " + emit_field_type(f, plain_struct_names) + ") -> Set[" + entity_name + "]:\n"
            out += "        var out = Set[" + entity_name + "]()\n"
            out += "        for id in self.storage[].indexes." + f.name + ".get_bwd(value):\n"
            out += "            out.add(" + entity_name + "(self.storage[].handle_for(id)))\n"
            out += "        return out^\n"

    # count_<field>/group_by_<field>/count_by_<field>/distinct_<field> (M4)
    # -- every indexed-family field (any modifier but NONE), same
    # eligibility as for_<field> above.
    for f in parsed.fields:
        if f.modifier == FieldModifier.UNIQUE:
            out += "\n"
            out += "    def count_" + param_name(f) + "(self, value: " + emit_field_type(f, plain_struct_names) + ") -> Int:\n"
            out += "        return 1 if self.storage[].indexes." + f.name + ".contains(value) else 0\n"
            out += "\n"
            out += "    def group_by_" + param_name(f) + "(self) -> Dict[" + emit_field_type(f, plain_struct_names) + ", " + entity_name + "]:\n"
            out += "        ref ids = self.storage[].indexes." + f.name + ".all_bwd()\n"
            out += "        var out = Dict[" + emit_field_type(f, plain_struct_names) + ", " + entity_name + "]()\n"
            out += "        for entry in ids.items():\n"
            out += "            out[entry.key] = " + entity_name + "(self.storage[].handle_for(entry.value))\n"
            out += "        return out^\n"
            out += "\n"
            out += "    def distinct_" + param_name(f) + "(self) -> Set[" + emit_field_type(f, plain_struct_names) + "]:\n"
            out += "        var out = Set[" + emit_field_type(f, plain_struct_names) + "]()\n"
            out += "        ref ids = self.storage[].indexes." + f.name + ".all_bwd()\n"
            out += "        for key in ids.keys():\n"
            out += "            out.add(key.copy())\n"
            out += "        return out^\n"
        elif f.modifier == FieldModifier.MULTI:
            out += _emit_count_field(f, emit_multi_element_type(f, plain_struct_names))
            out += _emit_group_by_count_by_distinct(f, entity_name, emit_multi_element_type(f, plain_struct_names), "ref", False)
        elif f.modifier == FieldModifier.ORDERED:
            out += _emit_count_field(f, emit_field_type(f, plain_struct_names))
            out += _emit_group_by_count_by_distinct(f, entity_name, emit_field_type(f, plain_struct_names), "var", True)
        elif f.modifier != FieldModifier.NONE:
            out += _emit_count_field(f, emit_field_type(f, plain_struct_names))
            out += _emit_group_by_count_by_distinct(f, entity_name, emit_field_type(f, plain_struct_names), "ref", False)

    return out^
