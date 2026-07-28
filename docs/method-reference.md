# Method reference

Every method a `@@struct` declaration generates, precisely — verified
against the actual codegen (`codegen/table.mojo`, `codegen/entity.mojo`,
`codegen/aggregates.mojo`), not approximated. `Entity` below stands for the
struct's own handle type (`sqrrl__<Name>`).

## Every struct, unconditionally

| Method | Signature |
|---|---|
| `create(...)` | one keyword parameter per field, declared order; raises if any parameter violates a `unique` field or a `key(...)` group (see below) — *except* for a `value` struct (see below), where a whole-entity value-duplicate returns the existing handle instead of raising |
| `all()` | `() -> Set[Entity]` |
| `count()` | `() -> Int` — O(1), doesn't construct a handle per row |

Plus, only if the struct itself is tagged:

| Tag | Effect |
|---|---|
| `value` (`@@struct value @@Name:`) | `==`/`!=`/`Hashable` on the handle become field-by-field (value-based), not id-based — see its own section below |
| `keepalive` | adds `dont_keepalive(mut self) -> Bool`, also on the handle |

`dont_keepalive` isn't table-level — called as `@@handle.dont_keepalive()`.

## Every field

`get_<field>(self) -> FieldType` — always present, regardless of modifier.

`set_<field>(mut self, v: FieldType)` — present for every field on an
ordinary struct, **except** on a `value`-flagged struct (see below), or on
a field that appears in any `key(...)` group (see below) — both get none
at all.

## `key(field1, field2, ...)`: composite (multi-field) uniqueness

A struct-body line, `key(field1, field2, ...)` — not a per-field modifier,
since it spans more than one field. Declares that no two live rows may
share the same combination of values across exactly those fields. A struct
may write `key(...)` more than once; each line is its own fully
independent constraint with its own backing index, own `create()` check,
and own lookup method:

| Per `key(...)` line | Effect |
|---|---|
| `create(...)` | raises `UniqueConstraintViolation: key(f1, f2, ...) already in use by another entity` on a collision for *this* group specifically — checked independently of every other group and of any individual `unique` field |
| `for_<f1>_<f2>_...(v1, v2, ...)` | `raises -> Entity` — the one row matching this exact combination, mirroring a single `unique` field's own `for_<field>` |
| every field named in the group | loses `set_<field>`/`add_to_<field>`/`remove_from_<field>` — field-immutable, for the identical reason a `value` struct's fields are (mutating a live composite key would corrupt its own backing index) |

Not generated for a composite key group: `count_for_<...>`/`group_by_<...>`/
`distinct_<...>` — a deliberate scope boundary, lower value for a
multi-field tuple than the lookup itself.

A field not named in any `key(...)` group on the same struct is
unaffected. Every field's own type still needs `!=`/`Hashable`/`Copyable`
support to compile. See `docs/syntax-reference.md` and
`examples/composite_keys/` for worked examples, including the two-group
case.

## `< @@Other`: struct inheritance

`@@struct @@Name < @@Other:` copies `Other`'s entire field list — every
field, every modifier, every `key(...)` group, and every spliced method —
into `Name`, which still gets its own completely independent generated
type, table, storage, id space, and indexes. Every method/field-shape
table in this reference applies to an inheriting struct exactly as if its
*merged* field list and method text had been declared directly — codegen
never treats it as a special case once the merge has happened (`driver/
discovery.mojo`'s `resolve_struct_inheritance`, which runs before every
other project-wide analysis pass). Purely structural, not virtual/
polymorphic: no shared table, no runtime dispatch, separate `count()`s.
`keepalive`/`value`/the target's own trait list are **not** inherited —
those stay independently declared on each struct. No chaining (`<`'s own
target may not itself use `<`); the inheriting struct may add its own
fields/`key(...)` groups but may not redeclare one of the target's own
field names. See `docs/syntax-reference.md` and `examples/absolute_db/`
for a worked example.

## `value`-flagged structs: field-immutable, value-based identity

A struct flagged `value` (`@@struct value @@Name:`) gets a fundamentally
different contract, not just an extra method:

- `==`/`!=`/`Hashable` on the handle compare/hash **every field**, not the
  entity's id — which every `Set`/`Dict`/`multi`-relation elsewhere that
  stores this type as a member/key then automatically inherits too (they
  all consume the same conformance).
- **No `set_<field>`/`add_to_<field>`/`remove_from_<field>` is generated
  at all, for any field, regardless of modifier** — field-immutable once
  `create()`d. Mutating a field after this entity has been stored as a
  key elsewhere (e.g. another struct's own `indexed`/`unique`/`ordered`
  backward index) would change its hash out from under that index,
  silently corrupting it — a real, confirmed failure mode, not a
  theoretical one. Removing every setter closes it at the root: a value
  that can never change after construction is always safe to use as a
  key anywhere.
- `create()` gets **get-or-create** semantics: if a row with exactly
  these field values already exists, `create()` returns *that* handle
  (same `id()`) instead of inserting a second, separate row — safe and
  lossless, since every field already matches by definition. This keeps
  `all()`/`group_by_<field>()`/etc. on the struct's own table honest (no
  two live rows can ever silently collapse into one Set/Dict entry from
  a *different* struct's perspective, since duplicates never coexist in
  the first place). An individual `unique`-tagged field on the same
  struct still raises `UniqueConstraintViolation` for a genuine
  conflict (same field, different overall values) — get-or-create only
  fires for a full-value match, checked first.
- Every field's own type needs `!=`/`Hashable`/`Copyable` to compile
  (never checked ahead of time — same "let the real Mojo compiler catch
  it" stance the rest of this reference already takes for `!=`).

See `docs/syntax-reference.md` and `examples/keepalive_and_value/`,
`examples/kitchen_sink/` for worked examples.

## `for_<field>`, `count_for_<field>`, `group_by_<field>`, `count_by_<field>`, `distinct_<field>`

Only generated for a field with a modifier (`is_groupable` — anything but a
plain, unmodified field; a plain field gets *only* `get_`/`set_`, no
backward index at all). `count_for_<field>` is named to mirror `for_
<field>` deliberately — it's "count of what `for_<field>` would return,"
not an unrelated name that happens to share a prefix.

| Modifier | `for_<field>(value)` | `count_for_<field>(value)` |
|---|---|---|
| `unique` | `raises -> Entity` (the one match, or raises) | `-> Int` (0 or 1 — the non-raising way to check "is this value taken") |
| `indexed` | `-> Set[Entity]` | `-> Int` |
| `multi` | `(value: ElementType) -> Set[Entity]` | `(value: ElementType) -> Int` |
| `ordered` | `-> Set[Entity]` (same base shape as `indexed`) | `-> Int` |

| Modifier | `group_by_<field>()` | `count_by_<field>()` | `distinct_<field>()` |
|---|---|---|---|
| `unique` | `-> Dict[FieldType, Entity]` (no `Set` — exactly one per key) | *not generated* — `count_for_<field>` is already 0-or-1, so this would add nothing | `-> Set[FieldType]` |
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
