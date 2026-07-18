from squirrel_compiler.parser import ParsedStruct, Field, FieldModifier
from squirrel_compiler.codegen.helpers import (
    sqrrl_prefixed,
    storage_field_name,
    param_name,
    emit_field_type,
    emit_multi_element_type,
)
from squirrel_compiler.analysis import is_groupable, is_aggregatable


def _x_key_type(x: Field) -> String:
    """The type a groupable field `x` is keyed/parameterized by in
    `_by_<x>`/`_for_<x>` -- the bare element type for `multi` (matching
    `for_<field>`'s/table.mojo's own convention), the field's own type
    otherwise."""
    if x.modifier == FieldModifier.MULTI:
        return emit_multi_element_type(x)
    return emit_field_type(x)


def _result_type(kind: String, y: Field) -> String:
    """`avg` always returns `Float64` regardless of `y`'s own declared type
    -- an integer average silently truncating would lose information a
    `Float64` promotion doesn't. `sum`/`min`/`max`/`median` stay in `y`'s
    own type, since those are exact either way."""
    if kind == "avg":
        return "Float64"
    return emit_field_type(y)


def _fold_body(kind: String, y: Field, ids_expr: String, indent: String, assign: String) -> String:
    """The loop that folds `kind` over every id in `ids_expr` (already
    known non-empty by the caller), reading each one's own `y` value
    directly off storage -- `self.storage[].handle_for(id)[].<field>`, no
    `Optional`/`.take()` dance (unlike rw_squirrel_2, which has no real
    forward field at all to read directly). `min`/`max`/`sum` track a
    running `Optional[T]` accumulator (avoids needing a type-generic
    "zero" value); `avg` sums the same way then divides by a running
    count. `median` alone collects into a fresh `List[T]`, sorts, and takes
    the *upper* of the two middle values for an even-sized group -- the
    only one of the five kinds that ever needs a sort at all."""
    var sf = storage_field_name(y)
    var yt = emit_field_type(y)
    var out = String()
    if kind == "median":
        out += indent + "var sqrrl__values = List[" + yt + "]()\n"
        out += indent + "for sqrrl__id in " + ids_expr + ":\n"
        out += indent + "    sqrrl__values.append(self.storage[].handle_for(sqrrl__id)[]." + sf + ")\n"
        out += indent + "sort(sqrrl__values)\n"
        out += indent + assign + "sqrrl__values[len(sqrrl__values) // 2]\n"
        return out^

    out += indent + "var sqrrl__acc: Optional[" + yt + "] = None\n"
    if kind == "avg":
        out += indent + "var sqrrl__count = 0\n"
    out += indent + "for sqrrl__id in " + ids_expr + ":\n"
    out += indent + "    var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]." + sf + "\n"
    if kind == "avg":
        out += indent + "    sqrrl__count += 1\n"
    if kind == "min":
        out += indent + "    if not sqrrl__acc or sqrrl__v < sqrrl__acc.value():\n"
        out += indent + "        sqrrl__acc = sqrrl__v\n"
    elif kind == "max":
        out += indent + "    if not sqrrl__acc or sqrrl__v > sqrrl__acc.value():\n"
        out += indent + "        sqrrl__acc = sqrrl__v\n"
    else:  # sum, avg
        out += indent + "    if sqrrl__acc:\n"
        out += indent + "        sqrrl__acc = sqrrl__acc.value() + sqrrl__v\n"
        out += indent + "    else:\n"
        out += indent + "        sqrrl__acc = sqrrl__v\n"
    if kind == "avg":
        out += indent + assign + "Float64(sqrrl__acc.value()) / Float64(sqrrl__count)\n"
    else:
        out += indent + assign + "sqrrl__acc.value()\n"
    return out^


def _emit_whole_table_variant(kind: String, y: Field) -> String:
    var method_name = kind + "_" + param_name(y)
    var result_type = _result_type(kind, y)
    var out = String("\n")
    out += "    def " + method_name + "(self) raises -> " + result_type + ":\n"
    if y.modifier == FieldModifier.ORDERED and kind == "median":
        # Read directly off the already-ascending sorted index -- no fresh
        # List/sort at all, the entire reason `ordered` exists.
        out += "        ref sqrrl__sorted = self.storage[].indexes." + y.name + ".entries()\n"
        out += "        if len(sqrrl__sorted) == 0:\n"
        out += '            raise Error("' + method_name + ': table has no entities")\n'
        out += "        return sqrrl__sorted[len(sqrrl__sorted) // 2].value\n"
        return out^
    out += "        var sqrrl__ids = self.storage[].all()\n"
    out += "        if len(sqrrl__ids) == 0:\n"
    out += '            raise Error("' + method_name + ': table has no entities")\n'
    out += _fold_body(kind, y, "sqrrl__ids", "        ", "return ")
    return out^


def _emit_by_variant(kind: String, y: Field, x: Field) -> String:
    var method_name = kind + "_" + param_name(y) + "_by_" + param_name(x)
    var result_type = _result_type(kind, y)
    var key_type = _x_key_type(x)
    var out = String("\n")
    out += "    def " + method_name + "(self) -> Dict[" + key_type + ", " + result_type + "]:\n"
    if x.modifier == FieldModifier.UNIQUE:
        # Exactly one id per key -- a direct read, no fold needed at all.
        out += "        ref sqrrl__ids = self.storage[].indexes." + x.name + ".all_bwd()\n"
        out += "        var out = Dict[" + key_type + ", " + result_type + "]()\n"
        out += "        for entry in sqrrl__ids.items():\n"
        out += "            var sqrrl__v = self.storage[].handle_for(entry.value)[]." + storage_field_name(y) + "\n"
        if kind == "avg":
            out += "            out[entry.key] = Float64(sqrrl__v)\n"
        else:
            out += "            out[entry.key] = sqrrl__v\n"
        out += "        return out^\n"
        return out^
    if y.modifier == FieldModifier.ORDERED and kind == "median" and x.modifier != FieldModifier.MULTI:
        # Walk y's own ascending sorted entries once, bucketing y's own
        # *values* (not ids -- rw_squirrel_3's OrderedEntry already carries
        # both together, no separate id->value lookup needed) by x's value
        # -- since the walk is already y-ascending, every bucket ends up
        # already sorted by y too, so the middle index is the median with
        # no per-bucket sort. Skipped when x is `multi`: one id could then
        # land in more than one bucket, breaking the single-pass grouping.
        out += "        var sqrrl__buckets = Dict[" + key_type + ", List[" + emit_field_type(y) + "]]()\n"
        out += "        try:\n"
        out += "            for sqrrl__entry in self.storage[].indexes." + y.name + ".entries():\n"
        out += "                var sqrrl__key = self.storage[].handle_for(sqrrl__entry.id)[]." + storage_field_name(x) + "\n"
        out += "                if sqrrl__key not in sqrrl__buckets:\n"
        out += "                    sqrrl__buckets[sqrrl__key.copy()] = List[" + emit_field_type(y) + "]()\n"
        out += "                sqrrl__buckets[sqrrl__key].append(sqrrl__entry.value)\n"
        out += "        except:\n"
        out += '            abort("' + method_name + ': unreachable Dict operation failure")\n'
        out += "        var out = Dict[" + key_type + ", " + result_type + "]()\n"
        out += "        for entry in sqrrl__buckets.items():\n"
        out += "            out[entry.key] = entry.value[len(entry.value) // 2]\n"
        out += "        return out^\n"
        return out^
    var binding = "var" if x.modifier == FieldModifier.ORDERED else "ref"
    out += "        " + binding + " sqrrl__buckets = self.storage[].indexes." + x.name + ".all_bwd()\n"
    out += "        var out = Dict[" + key_type + ", " + result_type + "]()\n"
    out += "        for entry in sqrrl__buckets.items():\n"
    out += _fold_body(kind, y, "entry.value", "            ", "out[entry.key] = ")
    out += "        return out^\n"
    return out^


def _emit_for_variant(kind: String, y: Field, x: Field) -> String:
    var method_name = kind + "_" + param_name(y) + "_for_" + param_name(x)
    var result_type = _result_type(kind, y)
    var value_type = _x_key_type(x)
    var out = String("\n")
    out += "    def " + method_name + "(self, value: " + value_type + ") raises -> " + result_type + ":\n"
    if x.modifier == FieldModifier.UNIQUE:
        out += "        var sqrrl__id = self.storage[].indexes." + x.name + ".get_bwd(value)\n"
        out += "        var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]." + storage_field_name(y) + "\n"
        if kind == "avg":
            out += "        return Float64(sqrrl__v)\n"
        else:
            out += "        return sqrrl__v\n"
        return out^
    # Always the generic fold, even when y is ordered -- sorting just the
    # one group asked about is cheaper than filtering the whole sorted
    # index down to it, so there's no fast path worth having here.
    out += "        var sqrrl__bucket = self.storage[].indexes." + x.name + ".get_bwd(value)\n"
    out += "        if len(sqrrl__bucket) == 0:\n"
    out += '            raise Error("' + method_name + ': no entities found for this value")\n'
    out += _fold_body(kind, y, "sqrrl__bucket", "        ", "return ")
    return out^


def emit_aggregate_methods(parsed: ParsedStruct) -> String:
    """`sum_<field>`/`avg_<field>`/`min_<field>`/`max_<field>`/
    `median_<field>` (M4) -- one whole-table form per aggregatable field
    `y` (unconditional, `O(fields)`), plus `_by_<x>`/`_for_<x>` paired
    forms against every *other* groupable field `x` (`x.name != y.name`,
    since aggregating a field grouped by itself is meaningless -- every
    group already holds exactly that one value). Generated unconditionally
    for every valid combination -- no demand-driven usage scanning (a
    deliberate simplification over rw_squirrel_2, which only emits the
    combinations actually referenced somewhere in the project; Mojo's own
    compiler dead-strips whatever's never called here instead)."""
    var out = String()
    for y in parsed.fields:
        if not is_aggregatable(y):
            continue
        var kinds = List[String]()
        kinds.append("min")
        kinds.append("max")
        kinds.append("median")
        if y.is_stats:
            kinds.append("sum")
            kinds.append("avg")
        for kind in kinds:
            out += _emit_whole_table_variant(kind, y)
            for x in parsed.fields:
                if x.name == y.name or not is_groupable(x):
                    continue
                out += _emit_by_variant(kind, y, x)
                out += _emit_for_variant(kind, y, x)
    return out^
