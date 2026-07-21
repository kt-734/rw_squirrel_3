# Method reference

Every method a `@@struct` declaration generates, precisely — verified
against the actual codegen (`codegen/table.mojo`, `codegen/entity.mojo`,
`codegen/aggregates.mojo`), not approximated. `Entity` below stands for the
struct's own handle type (`sqrrl__<Name>`).

## Every struct, unconditionally

| Method | Signature |
|---|---|
| `create(...)` | one keyword parameter per field, declared order; raises if any parameter violates a `unique` field |
| `all()` | `() -> Set[Entity]` |
| `count()` | `() -> Int` — O(1), doesn't construct a handle per row |

Plus, only if the struct itself is tagged:

| Tag | Method | Signature |
|---|---|---|
| `equatable` | `value_eq` | `(self, other: Self) -> Bool` — field-by-field comparison, on the *handle* |
| `keepalive` | `dont_keepalive` | `(mut self) -> Bool` — also on the handle |

Neither `value_eq` nor `dont_keepalive` are table-level — both are called as
`@@handle.value_eq(@@other)` / `@@handle.dont_keepalive()`.

## Every field

`get_<field>(self) -> FieldType` / `set_<field>(mut self, v: FieldType)` —
always present, regardless of modifier.

## `for_<field>`, `count_<field>`, `group_by_<field>`, `count_by_<field>`, `distinct_<field>`

Only generated for a field with a modifier (`is_groupable` — anything but a
plain, unmodified field; a plain field gets *only* `get_`/`set_`, no
backward index at all).

| Modifier | `for_<field>(value)` | `count_<field>(value)` |
|---|---|---|
| `unique` | `raises -> Entity` (the one match, or raises) | `-> Int` (0 or 1 — the non-raising way to check "is this value taken") |
| `indexed` | `-> Set[Entity]` | `-> Int` |
| `multi` | `(value: ElementType) -> Set[Entity]` | `(value: ElementType) -> Int` |
| `ordered` | `-> Set[Entity]` (same base shape as `indexed`) | `-> Int` |

| Modifier | `group_by_<field>()` | `count_by_<field>()` | `distinct_<field>()` |
|---|---|---|---|
| `unique` | `-> Dict[FieldType, Entity]` (no `Set` — exactly one per key) | *not generated* — `count_<field>` is already 0-or-1, so this would add nothing | `-> Set[FieldType]` |
| `indexed`/`ordered` | `-> Dict[FieldType, Set[Entity]]` | `-> Dict[FieldType, Int]` | `-> Set[FieldType]` |
| `multi` | `-> Dict[ElementType, Set[Entity]]` | `-> Dict[ElementType, Int]` | `-> Set[ElementType]` |

### `ordered`-only range queries

An `ordered` field additionally gets, on top of everything `indexed` gives:

```
for_<field>_greater_than(value) -> List[Entity]
for_<field>_less_than(value)    -> List[Entity]
for_<field>_at_least(value)     -> List[Entity]
for_<field>_at_most(value)      -> List[Entity]
for_<field>_between(low, high)  -> List[Entity]
```

Note the return type: `List`, not `Set`, for every range-query variant —
different from the base `for_<field>(value) -> Set[Entity]` these sit
alongside.

## `multi`-only

```
add_to_<field>(mut self, value: ElementType) -> Bool     # True if newly added
remove_from_<field>(mut self, value: ElementType) -> Bool  # True if actually removed
```

## Aggregates: `sum_`/`avg_`/`min_`/`max_`/`median_`

A field is **aggregatable** (`y`, the value being aggregated) if it's
`stats`-tagged (any modifier — but see the `multi` exclusion below), or
`ordered` (earns `min`/`max`/`median` for free, since `ordered` already
requires `Comparable`; `sum`/`avg` still need `stats` for the `+` they
additionally promise). A `multi` field is **never** aggregatable, even if
`stats`-tagged — its storage is `Set[ElementType]`, and there's no
sensible `+`-fold over set membership.

A field is **groupable** (`x`, the field results get bucketed by) if it has
*any* modifier at all — independent of `stats`.

For every aggregatable `y`, three shapes, each against every groupable
`x` where `x.name != y.name` (grouping by itself is meaningless):

```
{kind}_<y>() raises -> ResultType                    # whole table; raises if empty
{kind}_<y>_by_<x>() -> Dict[XKeyType, ResultType]     # per group; never raises, empty groups just absent
{kind}_<y>_for_<x>(value) raises -> ResultType        # one group; raises if that group is empty
```

`kind` is one of `sum`/`avg`/`min`/`max`/`median`. `ResultType` is
`Float64` for `avg` regardless of `y`'s own declared type (an integer
average silently truncating would lose information); every other kind
stays in `y`'s own declared type. `XKeyType` is `x`'s own element type for
a `multi` `x`, its declared field type otherwise.

```
print(@@@Employee.sum_salary())                    # whole table
print(@@@Employee.avg_salary_for_@@dept(@@sales))    # one department
for @@d in @@@Employee.sum_salary_by_@@dept():       # every department at once
    ...
```

## What's deliberately *not* here

`squirrelc` never scans the project to see which of these combinations are
actually used anywhere before generating them — every valid combination is
emitted unconditionally (one deliberate simplification over an earlier
design that tracked usage: Mojo's own compiler already dead-strips whatever
never gets called, so there's no real cost to generating the full surface
every time).
