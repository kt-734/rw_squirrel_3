from squirrel_compiler.parser import ParsedStruct, Field, FieldModifier
from squirrel_compiler.codegen.helpers import (
    sqrrl_prefixed,
    storage_field_name,
    is_relation_field,
    needs_move_assignment,
    emit_field_type,
    emit_multi_element_type,
    param_name,
)


def _inner_name(struct_name: String) -> String:
    return sqrrl_prefixed(struct_name) + "Inner"


def _indexes_name(struct_name: String) -> String:
    return sqrrl_prefixed(struct_name) + "Indexes"


def emit_entity_inner(parsed: ParsedStruct, plain_struct_names: Dict[String, Bool] = Dict[String, Bool]()) -> String:
    """Emits `sqrrl__<Name>Inner` -- the concrete, per-struct payload behind
    every entity's `ArcPointer` (Architecture: "Two-layer entity"). Real,
    underscore-prefixed fields (point 4) for every declared field, a
    `set_<field>` (point 5) for every one of them (trivial passthrough for
    a `NONE`-modifier field, index-sync for an indexed one), an
    `@always_inline get_<field>` for every one too, and `__del__` (point 6:
    frees the id/weak-ref, and for each of its own indexed fields, evicts
    itself from that field's backward-index bucket -- a non-indexed field
    needs nothing there at all, Mojo's own field-wise destructor cascade
    already releases whatever it held)."""
    var inner_name = _inner_name(parsed.name)
    var indexes_name = _indexes_name(parsed.name)
    var storage_type = String("EntityStorage[" + indexes_name + ", " + inner_name + "]")

    var out = String("@fieldwise_init\nstruct " + inner_name + "(Movable, ImplicitlyDeletable):\n")
    out += "    var _id: UInt32\n"
    out += "    var _table: ArcPointer[" + storage_type + "]\n"
    for f in parsed.fields:
        out += "    var " + storage_field_name(f) + ": " + emit_field_type(f, plain_struct_names) + "\n"
    out += "\n"

    out += "    def __del__(deinit self):\n"
    for f in parsed.fields:
        if f.modifier == FieldModifier.MULTI:
            # A multi field's own backward index is keyed per *element*, not
            # per whole field value -- evicting this row means removing it
            # from every element's own bucket its current membership set
            # still touches. MultiIndex.remove_many does that bulk-remove
            # internally. The forward Set itself needs nothing further:
            # Mojo's own field-wise destructor cascade (below, implicitly)
            # decref's every element it holds.
            out += (
                "        self._table[].indexes."
                + f.name
                + ".remove_many(self._id, self."
                + storage_field_name(f)
                + ")\n"
            )
        elif f.modifier != FieldModifier.NONE:
            out += (
                "        self._table[].indexes."
                + f.name
                + ".remove(self._id, self."
                + storage_field_name(f)
                + ")\n"
            )
    out += "        self._table[].free_id(self._id)\n"
    out += "        self._table[].clear_weak_ref(self._id)\n"

    for f in parsed.fields:
        out += "\n"
        var sf = storage_field_name(f)
        var ft = emit_field_type(f, plain_struct_names)
        if f.modifier == FieldModifier.NONE:
            if needs_move_assignment(f, plain_struct_names):
                # A hand-written plain struct, or a wrapped relation
                # (`List[@@Employee]`/`@@container` -- `List[T]` turned out
                # NOT to be ImplicitlyCopyable in this Mojo build either,
                # verified directly), isn't guaranteed ImplicitlyCopyable
                # -- `var`+`^` (move) instead of a bare copy-assignment,
                # same reason `multi`'s Set[T] already needs it below.
                out += "    def set_" + param_name(f) + "(mut self, var v: " + ft + "):\n"
                out += "        self." + sf + " = v^\n"
            else:
                out += "    def set_" + param_name(f) + "(mut self, v: " + ft + "):\n"
                out += "        self." + sf + " = v\n"
        elif f.modifier == FieldModifier.UNIQUE:
            out += "    def set_" + param_name(f) + "(mut self, v: " + ft + ") raises:\n"
            out += "        self._table[].indexes." + f.name + ".check_unique(v, self._id)\n"
            out += "        self._table[].indexes." + f.name + ".remove(self._id, self." + sf + ")\n"
            out += "        self." + sf + " = v\n"
        elif f.modifier == FieldModifier.MULTI:
            # Membership normally changes one element at a time
            # (add_to_<field>/remove_from_<field>, below), but a wholesale
            # replacement is also available via the DSL's ordinary write
            # syntax (`.@@field = Set(...)`) -- same evict-old/assign-new/
            # add-new shape the INDEXED/ORDERED branch below has, just
            # Set-valued via MultiIndex's own bulk remove_many/add_many.
            # Evicting old membership *before* reassigning the field (not
            # copying it out first) -- same ordering UNIQUE's own
            # check_unique/remove/assign sequence already uses -- means
            # remove_many can just borrow the field directly, no copy
            # needed. `var` (owned) on the parameter is still required --
            # Set[T] isn't ImplicitlyCopyable, so the field assignment
            # itself moves it in.
            out += "    def set_" + param_name(f) + "(mut self, var v: " + ft + "):\n"
            out += "        self._table[].indexes." + f.name + ".remove_many(self._id, self." + sf + ")\n"
            out += "        self." + sf + " = v^\n"
            out += "        self._table[].indexes." + f.name + ".add_many(self._id, self." + sf + ")\n"
            out += "\n"
            var elem_t = emit_multi_element_type(f, plain_struct_names)
            out += "    def add_to_" + param_name(f) + "(mut self, value: " + elem_t + ") -> Bool:\n"
            out += "        if value in self." + sf + ":\n"
            out += "            return False\n"
            out += "        self." + sf + ".add(value)\n"
            out += "        self._table[].indexes." + f.name + ".add(self._id, value)\n"
            out += "        return True\n"
            out += "\n"
            # Set.remove's own signature raises unconditionally (whether or
            # not the value is present), but that failure mode *is* what
            # the Bool return already communicates -- catching it directly
            # instead of a separate membership check first both drops the
            # redundant `raises` on this method's own signature (the Bool
            # return already fully covers "did it happen") and avoids a
            # second Set lookup (membership check + remove, vs. just remove).
            out += "    def remove_from_" + param_name(f) + "(mut self, value: " + elem_t + ") -> Bool:\n"
            out += "        try:\n"
            out += "            self." + sf + ".remove(value)\n"
            out += "        except:\n"
            out += "            return False\n"
            out += "        self._table[].indexes." + f.name + ".remove(self._id, value)\n"
            out += "        return True\n"
        else:
            # INDEXED and ORDERED -- OrderedIndex deliberately exposes the
            # same add/remove method names PlainIndex does (see
            # emit_index_type), so this evict-old/add-new body works
            # unchanged for both. Evicting old *before* reassigning (not
            # copying it out first) lets remove() just borrow the field
            # directly -- same ordering UNIQUE's own set_<field> already
            # uses, no copy needed.
            out += "    def set_" + param_name(f) + "(mut self, v: " + ft + "):\n"
            out += "        self._table[].indexes." + f.name + ".remove(self._id, self." + sf + ")\n"
            out += "        self." + sf + " = v\n"
            out += "        self._table[].indexes." + f.name + ".add(self._id, self." + sf + ")\n"

    for f in parsed.fields:
        out += "\n"
        out += "    @always_inline\n"
        var gsf = storage_field_name(f)
        # A borrowed reference straight into the field, not a copy -- same
        # policy already applied to PlainIndex/MultiIndex.remove's bucket
        # mutation and PlainIndex.all_bwd's own return (see their doc
        # comments). Avoids a real cost for every field kind here, not just
        # Set (which additionally isn't ImplicitlyCopyable, so this also
        # replaces what used to need an explicit .copy() workaround).
        out += "    def get_" + param_name(f) + "(self) -> ref [self." + gsf + "] " + emit_field_type(f, plain_struct_names) + ":\n"
        out += "        return self." + gsf + "\n"

    return out^


def emit_entity(parsed: ParsedStruct, rewritten_method_body: String) -> String:
    """Emits `sqrrl__<Name>` -- the thin wrapper a script actually holds
    and passes around (Architecture: "Where user-declared `@@`-marked
    methods/traits splice in" -- onto this type, not `Inner`, since it's
    the concrete type used as a `Dict`/`Set` key and the one a trait list
    has to attach to). Method/trait splicing itself lands in M3;
    `rewritten_method_body` is accepted now so the call site doesn't need
    to change shape when that happens, but M1 never passes anything
    non-empty."""
    var entity_name = sqrrl_prefixed(parsed.name)
    var inner_name = _inner_name(parsed.name)
    var traits = String("Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl__JsonSerializable")
    for t in parsed.trait_list:
        traits += ", " + t

    var out = String("struct " + entity_name + "(" + traits + "):\n")
    out += "    var _inner: ArcPointer[" + inner_name + "]\n"
    out += "\n"
    out += "    def __init__(out self, var inner: " + inner_name + "):\n"
    out += "        self._inner = ArcPointer(inner^)\n"
    out += "\n"
    out += "    def __init__(out self, var inner: ArcPointer[" + inner_name + "]):\n"
    out += "        self._inner = inner^\n"
    out += "\n"
    out += "    def id(self) -> UInt32:\n"
    out += "        return self._inner[]._id\n"
    out += "\n"
    # ArcPointer refcount introspection ("how many live handles currently
    # point at this exact row"), not a DSL concept -- deliberately named
    # differently from the table-level `count()` (`sqrrl__world.Person.
    # count()`, "how many Person entities exist in total"), which means
    # something completely different despite the shared word. Renamed from
    # a plain `count()` here (M1-era, matching rw_squirrel_2's own naming)
    # after the collision caused real confusion reading generated output.
    out += "    def ref_count(self) -> Int:\n"
    out += "        return Int(self._inner.count())\n"
    out += "\n"
    out += "    def __hash__[H: Hasher](self, mut hasher: H):\n"
    out += "        hasher.update(self.id())\n"
    out += "\n"
    out += "    def __eq__(self, other: Self) -> Bool:\n"
    out += "        return self.id() == other.id()\n"
    out += "\n"
    out += "    def __ne__(self, other: Self) -> Bool:\n"
    out += "        return self.id() != other.id()\n"
    out += "\n"
    # sqrrl__JsonSerializable conformance (M5): a relation field's own
    # to_json is always just its target's bare id -- the target row itself
    # is serialized separately, once, as part of its own table's dump
    # (driver/json_module.mojo's emit_json_module), never inline at every
    # place it's referenced from.
    out += "    def sqrrl__to_json(self) -> String:\n"
    out += "        return String(self.id())\n"
    if parsed.is_equatable:
        # Instance method, not table-level (M4 correction): field-by-field
        # comparison never needs `sqrrl__world` or any table/index access
        # at all -- reads straight off two entities' own `Inner`, same
        # "delegate through self._inner[]" shape `id()` above already
        # uses. Deliberately distinct from `__eq__` (id-based, "same row")
        # -- this is "same field values, not necessarily the same row".
        out += "\n"
        out += "    def value_eq(self, other: Self) -> Bool:\n"
        if len(parsed.fields) == 0:
            out += "        return True\n"
        else:
            for f in parsed.fields:
                out += (
                    "        if self._inner[].get_"
                    + param_name(f)
                    + "() != other._inner[].get_"
                    + param_name(f)
                    + "():\n"
                )
                out += "            return False\n"
            out += "        return True\n"
    if parsed.is_keepalive:
        # Instance method too, for the same reason -- mutates shared state
        # reachable from an instance exactly the way `add_to_<field>`/
        # `remove_from_<field>` already reach shared index state from
        # Inner's own `_table` -- `keepalive` itself lives on
        # `EntityStorage` (`squirrel_runtime/entity_storage.mojo`), not on
        # the generated `Table` struct, specifically so it's reachable
        # here (`Inner._table` points at `EntityStorage` directly; `Table`
        # only ever points at `EntityStorage`, never the other way).
        out += "\n"
        out += "    def dont_keepalive(mut self) -> Bool:\n"
        out += "        return self._inner[]._table[].keepalive_remove(self.id())\n"
    if rewritten_method_body.strip().byte_length() > 0:
        out += "\n"
        out += rewritten_method_body
        if not rewritten_method_body.endswith("\n"):
            out += "\n"
    return out^
