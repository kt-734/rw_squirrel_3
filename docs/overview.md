# What squirrel is

squirrel (this project, `rw_squirrel_3`) is a small DSL, embedded directly in
Mojo source, for declaring an in-memory entity/relationship model and getting
a full storage layer generated for it: tables, indexes, relation lookups,
aggregates, keepalive semantics, JSON serialization, and safe cross-file
references — without hand-writing any of that plumbing.

A `.mojo.sqrrl` file is ordinary Mojo with extra syntax mixed in (`@@struct`,
`@@`-marked identifiers, a handful of field modifiers). `squirrelc` transforms
each one into a plain `.mojo` file sitting right next to it — the DSL never
survives past compile time; everything downstream is real, readable,
generated Mojo.

## Why model data this way

- **Single-copy storage, shared handles.** An entity lives once, in its own
  table; every handle to it (`sqrrl__<Name>`) is a cheap, reference-counted
  view onto that one copy, not an independent snapshot. Mutating through
  any handle is visible through every other handle to the same row.
- **No dangling references.** A handle that outlives the row it points at
  is a real failure mode in most hand-rolled versions of this pattern —
  here it's structurally impossible: `EntityStorage` tracks liveness and
  weak references itself, and a leaked-but-unreachable entity is caught
  and aborted on loudly at the end of world scope, rather than silently
  read as garbage.
- **Reverse lookups for free.** `for_dept(@@eng)`, `count_by_dept()`,
  `group_by_dept()` — one keyword on a field declaration (`indexed`) is the
  whole cost of getting every one of these, backed by a real index, not a
  linear scan hidden behind a convenient name.
- **Relation cycles caught before they become a runtime problem.** A schema
  that can never construct its own first entity (a genuine cycle) is
  rejected at compile time, project-wide, including through nested plain
  structs and any container argument position — not discovered later as a
  deadlock or a permanently-unreachable `ArcPointer` cycle.
- **Whole-project JSON for the cost of calling four functions.** Every
  entity, every relation, every custom container (via a small two-function
  escape hatch) participates in a whole-world dump/reload with no
  per-struct serialization code to maintain by hand.

## Core concepts

**Entity.** A `@@struct` declaration. Every entity gets its own table
(`sqrrl__<Name>Table`), a lightweight reference-counted handle type
(`sqrrl__<Name>`), and backing storage (`EntityStorage`) that hands out
opaque ids, tracks liveness, and supports weak references so a handle never
outlives the row it points at.

**World.** `sqrrl___World` holds one table per entity, project-wide. A script
brings it into scope once, at the top level, with `@@@:` — everything
indented under that block can construct entities and call table-level
methods. There is exactly one `@@:`/`@@@:` per project; every other function
that needs the world receives it as a threaded parameter (that's what a
`@@@`-marked function/method means — see [syntax-reference.md](syntax-reference.md)).

**Relation field.** A field typed `@@Type` (or a container of one,
`List[@@Type]`/`Set[@@Type]`/`Dict[String, @@Type]`/...) is an edge to
another entity's table, not a plain value — reading it gives you a live
handle, not a copy. Relation fields can't be cyclic: `create()` needs every
relation field's target to already exist, so a cycle would have no valid
first entity to construct. The compiler checks this project-wide and rejects
a cyclic schema before it ever gets to Mojo.

**keepalive.** By default an entity's only real ownership is whatever local
handle created it — nothing else. `keepalive` on a `@@struct` gives its table
a genuine strong hold on every row, so an entity can live purely by existing
in the table (an audit log, a lookup registry) with no handle anywhere else
keeping it alive.

This hold propagates *forward*, along whatever relation fields that entity
itself declares — not backward. A live row's own relation fields hold real
handles to their targets, so a `keepalive @@Group` with `multi @@members:
@@Person` also keeps every current member `Person` alive, for as long as
that membership lasts (dropping a member, or clearing the whole `Group`,
releases its share of that hold). It does *not* work the other way: nothing
about `Person` itself changes just because some other struct's `keepalive`
field happens to point at it, and a struct with no `keepalive` and no
relation field pointing *at* it from anywhere still disappears the moment
its last direct handle does, regardless of what it itself points at.

**Plain struct.** An ordinary hand-written Mojo struct (no `@@`) can still
have entity-typed fields (`@@owner: @@Employee`) and nested plain structs of
its own — it's a value type, never gets its own table, but the compiler still
tracks what it reaches for cycle detection, JSON, and marking purposes.

## A minimal example

```
@@struct @@Department:
    unique name: String
    multi @@projects: @@Project

@@struct @@Project:
    name: String

def main() raises:
    @@@:
        var @@eng = @@@Department { .name = "Engineering" }
        var @@website = @@@Project { .name = "Website" }
        _ = @@eng.add_to_@@projects(@@website)
        print(len(@@eng.@@projects))
```

See `examples/` in the repo root for much larger, real, compiling programs —
`kitchen_sink` in particular exercises nearly every feature at once.

## Where to go next

- [syntax-reference.md](syntax-reference.md) — every DSL construct, with the
  method surface each field modifier generates.
- [architecture.md](architecture.md) — how `squirrelc` itself is built: the
  compiler pipeline from source text to generated Mojo.
