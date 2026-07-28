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


def _field_getter_calls(fields: List[Field], receiver: String) -> List[String]:
    """The ordered list of `<receiver>.get_<field>()` accessor-call
    strings for every field in `fields` -- shared by the value-based
    `__eq__`/`__hash__` generation below, replacing what used to be a
    near-identical copy of the same per-field loop (the old, now-removed
    `value_eq` had its own)."""
    var out = List[String]()
    for f in fields:
        out.append(receiver + ".get_" + param_name(f) + "()")
    return out^


def _inner_name(struct_name: String) -> String:
    return sqrrl_prefixed(struct_name) + "Inner"


def _indexes_name(struct_name: String) -> String:
    return sqrrl_prefixed(struct_name) + "Indexes"


def _value_key_name(struct_name: String) -> String:
    return sqrrl_prefixed(struct_name) + "ValueKey"


def _build_key_ctor_args_from_inner(fields: List[Field], plain_struct_names: Dict[String, Bool]) -> String:
    """Shared by `_build_value_key_ctor_args_from_inner` (whole-entity,
    `fields=parsed.fields`) and `emit_entity_inner`'s own per-key-group
    `__del__` eviction (a `key(...)` line's own field subset) -- builds a
    key struct's own constructor args from `Inner`'s own `__del__`. Reads
    straight off `self.<storage_field_name>` (never moves: `__del__` only
    ever borrows a field, since Mojo's own field-wise destructor cascade
    still needs every field intact after the explicit `__del__` body
    returns), `.copy()`-ing exactly the same fields `table.mojo`'s own
    `_build_value_key_ctor_args`/`_build_key_group_ctor_args` do for the
    identical reason -- `Set`/`List`/plain-struct storage isn't guaranteed
    `ImplicitlyCopyable`."""
    var out = String()
    var first = True
    for f in fields:
        if not first:
            out += ", "
        out += param_name(f) + "=self." + storage_field_name(f)
        if needs_move_assignment(f, plain_struct_names):
            out += ".copy()"
        first = False
    return out^


def _build_value_key_ctor_args_from_inner(parsed: ParsedStruct, plain_struct_names: Dict[String, Bool]) -> String:
    return _build_key_ctor_args_from_inner(parsed.fields, plain_struct_names)


def _collect_keyed_field_names(key_groups: List[List[String]]) -> Dict[String, Bool]:
    """The union of every field name appearing in *any* `key(...)` group --
    used to suppress `set_<field>`/`add_to_<field>`/`remove_from_<field>`
    for exactly those fields (`emit_entity_inner`), regardless of how many
    different groups a given field happens to belong to (counted once
    either way)."""
    var out = Dict[String, Bool]()
    for group in key_groups:
        for name in group:
            out[name] = True
    return out^


def _emit_key_struct(key_name: String, fields: List[Field], plain_struct_names: Dict[String, Bool]) -> String:
    """Shared by `emit_entity_value_key` (Part B's whole-entity key,
    `fields=parsed.fields`) and `emit_entity_key_groups` (a `key(...)`
    line's own field subset) -- both emit a small, independent value type
    with no reference back to `Wrapper`/`Inner`/`Indexes`/`EntityStorage`
    at all, differing only in *which* fields they cover. Field-by-field
    `__eq__`/`__hash__`, same shape as the wrapper's own (Part A,
    `emit_entity`) but reading straight off `self.<field>` -- there's no
    `Inner`/`get_<field>()` indirection here, just the bare field values
    themselves."""
    var out = String("@fieldwise_init\nstruct " + key_name + "(Copyable, Movable, Hashable, Equatable):\n")
    for f in fields:
        out += "    var " + param_name(f) + ": " + emit_field_type(f, plain_struct_names) + "\n"
    out += "\n"
    out += "    def __eq__(self, other: Self) -> Bool:\n"
    if len(fields) == 0:
        out += "        return True\n"
    else:
        for f in fields:
            out += "        if self." + param_name(f) + " != other." + param_name(f) + ":\n"
            out += "            return False\n"
        out += "        return True\n"
    out += "\n"
    out += "    def __ne__(self, other: Self) -> Bool:\n"
    out += "        return not (self == other)\n"
    out += "\n"
    out += "    def __hash__[H: Hasher](self, mut hasher: H):\n"
    if len(fields) == 0:
        out += "        pass\n"
    else:
        for f in fields:
            out += "        hasher.update(self." + param_name(f) + ")\n"
    return out^


def emit_entity_value_key(parsed: ParsedStruct, plain_struct_names: Dict[String, Bool] = Dict[String, Bool]()) -> String:
    """Emits `sqrrl__<Name>ValueKey` -- only for a `value`-flagged struct
    (Part B): the whole-entity key type used as `sqrrl__<Name>Indexes`'s
    own `UniqueIndex[...]` key type so `create()` can enforce "no two live
    rows ever hold equal field values" (get-or-create semantics,
    `table.mojo`) without the self-referential generic cycle a naive
    `UniqueIndex[sqrrl__<Name>]` would create (`Wrapper -> Inner ->
    EntityStorage[Indexes, Inner] -> Indexes -> UniqueIndex[Wrapper] ->
    Wrapper`) -- confirmed non-cyclic and buildable via a standalone spike
    before writing this."""
    return _emit_key_struct(_value_key_name(parsed.name), parsed.fields, plain_struct_names)


def _key_group_name(struct_name: String, i: Int) -> String:
    """`sqrrl__<Name>Key<i>` -- one per `key(...)` line, 0-indexed in
    declaration order. Deliberately distinct from `sqrrl__<Name>ValueKey`
    (the *whole-entity* key from the unrelated `value` feature) so the two
    never collide and read as clearly different concepts in generated
    output."""
    return sqrrl_prefixed(struct_name) + "Key" + String(i)


def _field_by_name(fields: List[Field], name: String) raises -> Field:
    """Resolves one of a `key(...)` line's own field *names* (all the
    parser records, `Scanner.parse_struct` -- `ParsedStruct.key_groups`)
    back to its real `Field` (type, modifier, ...). The parser has
    already validated every name refers to a real field before this ever
    runs (`scanner.mojo`'s own `key(...)` validation, right after
    `parse_struct_body` returns) -- raising here is purely defensive,
    should that invariant ever be violated, rather than a real expected
    path."""
    for f in fields:
        if f.name == name:
            return f.copy()
    raise Error("InternalError: key(...) referenced unknown field '" + name + "' -- parser should have already rejected this")


def emit_entity_key_groups(parsed: ParsedStruct, plain_struct_names: Dict[String, Bool] = Dict[String, Bool]()) raises -> String:
    """Emits one independent `sqrrl__<Name>Key<i>` struct per `key(...)`
    line in `parsed.key_groups` -- a struct with no `key(...)` lines emits
    nothing at all; one with several emits one fully independent struct
    per line, each covering only that line's own field subset (mirroring
    `emit_entity_value_key`'s shape via the shared `_emit_key_struct`, just
    scoped rather than whole-entity)."""
    var out = String()
    for i in range(len(parsed.key_groups)):
        var group_fields = List[Field]()
        for name in parsed.key_groups[i]:
            group_fields.append(_field_by_name(parsed.fields, name))
        if i > 0:
            out += "\n\n"
        out += _emit_key_struct(_key_group_name(parsed.name, i), group_fields, plain_struct_names)
    return out^


def emit_entity_inner(parsed: ParsedStruct, plain_struct_names: Dict[String, Bool] = Dict[String, Bool]()) raises -> String:
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
    if parsed.is_value_type:
        # Part B's own value-key index needs eviction too, exactly like
        # every other indexed-family field above -- otherwise a stale
        # entry (pointing at this now-dead id) would linger forever,
        # permanently blocking any future `create()` call for the same
        # field values (`get_bwd_or_none` would keep finding it) and
        # leaking the `Dict` entry itself.
        out += (
            "        self._table[].indexes._sqrrl__value_key.remove(self._id, "
            + _value_key_name(parsed.name)
            + "("
            + _build_value_key_ctor_args_from_inner(parsed, plain_struct_names)
            + "))\n"
        )
    for i in range(len(parsed.key_groups)):
        # Each `key(...)` line's own value-key index needs eviction too,
        # for the identical reason the whole-entity one above does -- a
        # stale entry pointing at this now-dead id would otherwise linger
        # forever, permanently blocking a later, genuinely-new `create()`
        # call for the same field values.
        var group_fields = List[Field]()
        for name in parsed.key_groups[i]:
            group_fields.append(_field_by_name(parsed.fields, name))
        out += (
            "        self._table[].indexes._sqrrl__key" + String(i) + ".remove(self._id, "
            + _key_group_name(parsed.name, i)
            + "("
            + _build_key_ctor_args_from_inner(group_fields, plain_struct_names)
            + "))\n"
        )
    out += "        self._table[].free_id(self._id)\n"
    out += "        self._table[].clear_weak_ref(self._id)\n"

    # A `value`-flagged struct (`parsed.is_value_type`) uses its own field
    # values as its hash/equality basis everywhere it's used as a key
    # elsewhere (Set/Dict membership, another struct's own `unique`/
    # `indexed`/`ordered` backward index). Mutating a field after that
    # would change the hash out from under whatever index already stored
    # it as a key, silently corrupting that index (confirmed via a real
    # debug trace: a Department mutated after being indexed by an
    # `indexed @@dept` field never got evicted, leaking it and everything
    # it referenced). No setter/`add_to_`/`remove_from_` is generated at
    # all for such a struct -- field-immutable once `create()`d -- closing
    # that corruption class at its root rather than tracking it down
    # per-index. `get_<field>` below is unaffected; read access stays fine.
    #
    # The identical reasoning applies field-by-field to a `key(...)` line's
    # own fields, on any struct (`value`-flagged or not): each is itself a
    # live key in one of `Indexes`'s own `UniqueIndex[Key<i>]`s the moment
    # `create()` runs, so mutating it afterward would corrupt that index
    # exactly the same way. `_collect_keyed_field_names` unions every
    # `key(...)` group's fields (a field in two different groups is still
    # only ever suppressed once) -- this set is checked per-field below
    # regardless of `is_value_type`, since a non-`value` struct can still
    # have `key(...)` groups of its own.
    var keyed_field_names = _collect_keyed_field_names(parsed.key_groups)
    if not parsed.is_value_type:
        for f in parsed.fields:
            if f.name in keyed_field_names:
                continue
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
                # Pre-existing bug, fixed while researching a related feature:
                # the new value was never actually registered in this field's
                # own UniqueIndex after a write -- check_unique/remove/assign
                # alone leaves `_bwd` with no entry at all for `v`, so a later
                # for_<field>(v)/contains(v) would never find this row again,
                # and a genuinely different row could `create()` with the same
                # `v` afterward without ever tripping UniqueConstraintViolation.
                out += "        self._table[].indexes." + f.name + ".add(self._id, self." + sf + ")\n"
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


def emit_entity(parsed: ParsedStruct, rewritten_method_body: String, json_used: Bool = False) -> String:
    """Emits `sqrrl__<Name>` -- the thin wrapper a script actually holds
    and passes around (Architecture: "Where user-declared `@@`-marked
    methods/traits splice in" -- onto this type, not `Inner`, since it's
    the concrete type used as a `Dict`/`Set` key and the one a trait list
    has to attach to). Method/trait splicing itself lands in M3;
    `rewritten_method_body` is accepted now so the call site doesn't need
    to change shape when that happens, but M1 never passes anything
    non-empty.

    `sqrrl___JsonSerializable` conformance (and the `sqrrl__to_json`
    method satisfying it) is now conditional on `json_used` -- the
    JSON-container-dispatch rearchitecture special-cased a *relation*
    field's own dump to call `.id()` directly everywhere the compiler
    already knows a field is a relation, so the trait's only remaining
    consumer is `sqrrl__to_json_default`'s own `reflect[T]`-based
    fallback recursing into a *plain struct's* own embedded relation
    field generically (reflection has no other way to tell "this nested
    field is an entity handle, dump its id" without it) -- needed only
    when the project touches JSON at all (`driver/misc_builders.mojo`'s
    `project_uses_json`, computed early enough in `driver/convert_
    directory.mojo` to reach here, unlike the per-file `uses_json_entry_
    point` check)."""
    var entity_name = sqrrl_prefixed(parsed.name)
    var inner_name = _inner_name(parsed.name)
    var traits = String("Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable")
    if json_used:
        traits += ", sqrrl___JsonSerializable"
    for t in parsed.trait_list:
        # `Equatable` is already in the base list above unconditionally
        # (every entity handle needs *some* Equatable/Hashable
        # conformance for Set/Dict/multi-relation storage to work,
        # regardless of `parsed.is_value_type`, which is now signaled by
        # the dedicated `value` keyword, not by anything in the trait
        # list -- see `scanner.mojo`'s `parse_struct`) -- skip re-adding
        # it if the user's own trait list happens to mention it anyway
        # (redundant, but harmless to allow), or Mojo would see it listed
        # twice.
        if t != "Equatable":
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
    # differently from the table-level `count()` (`sqrrl___world.Person.
    # count()`, "how many Person entities exist in total"), which means
    # something completely different despite the shared word. Renamed from
    # a plain `count()` here (M1-era, matching rw_squirrel_2's own naming)
    # after the collision caused real confusion reading generated output.
    out += "    def ref_count(self) -> Int:\n"
    out += "        return Int(self._inner.count())\n"
    out += "\n"
    # The `value` struct-level flag (`parsed.is_value_type` -- see
    # `scanner.mojo`'s `parse_struct`) means this type's *whole* notion of
    # equality is value-based: `__eq__`/`__ne__`/`__hash__` themselves
    # compare/hash field-by-field, not by id -- which every entity
    # handle's `Set`/`Dict`/`multi`-relation storage then automatically
    # inherits too, since they all consume this exact conformance.
    # Write-time uniqueness (so two live rows can never actually hold
    # equal field values, keeping `all()`/`group_by`/etc. safe under this
    # widened `Set`/`Dict` semantics) is handled separately, in
    # `table.mojo`'s `create()` -- this block is purely about the
    # comparison/hash methods themselves.
    if parsed.is_value_type:
        out += "    def __hash__[H: Hasher](self, mut hasher: H):\n"
        if len(parsed.fields) == 0:
            out += "        pass\n"
        else:
            for call in _field_getter_calls(parsed.fields, "self._inner[]"):
                out += "        hasher.update(" + call + ")\n"
        out += "\n"
        out += "    def __eq__(self, other: Self) -> Bool:\n"
        if len(parsed.fields) == 0:
            out += "        return True\n"
        else:
            var self_calls = _field_getter_calls(parsed.fields, "self._inner[]")
            var other_calls = _field_getter_calls(parsed.fields, "other._inner[]")
            for i in range(len(parsed.fields)):
                out += "        if " + self_calls[i] + " != " + other_calls[i] + ":\n"
                out += "            return False\n"
            out += "        return True\n"
        out += "\n"
        out += "    def __ne__(self, other: Self) -> Bool:\n"
        out += "        return not (self == other)\n"
        out += "\n"
    else:
        out += "    def __hash__[H: Hasher](self, mut hasher: H):\n"
        out += "        hasher.update(self.id())\n"
        out += "\n"
        out += "    def __eq__(self, other: Self) -> Bool:\n"
        out += "        return self.id() == other.id()\n"
        out += "\n"
        out += "    def __ne__(self, other: Self) -> Bool:\n"
        out += "        return self.id() != other.id()\n"
        out += "\n"
    if json_used:
        # sqrrl___JsonSerializable conformance (M5): a relation field's own
        # to_json is always just its target's bare id -- the target row
        # itself is serialized separately, once, as part of its own
        # table's dump (driver/json_module.mojo's emit_json_module),
        # never inline at every place it's referenced from.
        out += "    def sqrrl__to_json(self) -> String:\n"
        out += "        return String(self.id())\n"
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
