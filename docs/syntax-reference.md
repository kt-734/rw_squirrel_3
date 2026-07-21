# Syntax reference

All examples below are drawn from real, compiling code in `examples/`
(mainly `kitchen_sink`, `friends`, and `container_fields`) — every method
name and behavior here is verified, not aspirational.

## Declaring an entity

```
@@struct @@Employee:
    unique email: String
    title: String
    ordered years_employed: UInt32
    stats salary: Float64
    indexed @@dept: @@Department
    profile: Profile
```

A `@@struct @@Name:` block declares an entity. Each field is
`[modifier] name: Type` (or `@@name: Type` for a relation field that should
be directly readable/chainable off an entity handle — see
[Relation fields](#relation-fields) below).

### Struct-level flags

```
@@struct equatable @@Department: ...
@@struct keepalive @@Group: ...
```

- `equatable` — adds `value_eq(other)`, a field-by-field comparison,
  distinct from the handle's own `==` (id-based identity — the same row is
  `==` with itself, never with a different row, however similar its
  fields). Every field's type needs `!=` support for this to compile;
  Mojo's own compiler is the one that checks that, not squirrelc.
- `keepalive` — the table itself holds a genuine strong reference to every
  row it creates, so an entity can live with no other handle anywhere
  pointing at it. This hold propagates *forward* along that entity's own
  relation fields (a live row's own fields hold real handles to their
  targets), never backward — a `keepalive @@Group` with `multi @@members:
  @@Person` also keeps every current member alive, but nothing about
  `Person` itself changes just because something else's `keepalive` field
  happens to point at it. See
  [World scope and keepalive](#world-scope-and-keepalive).

### Field modifiers

Exactly one of these per field (they're mutually exclusive):

| Modifier | Meaning | Generates |
|---|---|---|
| *(none)* | Plain field, no backward index | `get_<field>`/`set_<field>` only |
| `unique` | No two rows may share this value | `for_<field>(v)` (raises if not found), `count_<field>(v)`, `group_by_<field>()`, `count_by_<field>()`, `distinct_<field>()` |
| `indexed` | Ordinary backward index, many rows can share a value | `for_<field>(v)` (returns a `Set`), `count_<field>(v)`, `group_by_<field>()`, `count_by_<field>()`, `distinct_<field>()` |
| `multi` | One-member-at-a-time membership, many-to-many | `add_to_<field>(v) -> Bool`, `remove_from_<field>(v) -> Bool`, `for_<field>(v)`, `count_<field>(v)`, `group_by_<field>()`, `count_by_<field>()`, `distinct_<field>()` |
| `ordered` | Backward index plus range queries (`Comparable` field type) | everything `indexed` gives, plus `min_<field>()`, `max_<field>()`, `median_<field>()`, and `for_<field>_greater_than(v)`/`_less_than(v)`/`_at_least(v)`/`_at_most(v)`/`_between(lo, hi)` (each returning `List`, not `Set`) |

`stats` is a separate, independent flag — combines with any modifier
*except* `multi` (no sensible `+`-fold over set membership): adds
`sum_<field>()`/`avg_<field>()` on top of whatever `min_`/`max_`/`median_`
the field already has (from `ordered`) or newly earns (from `stats` alone,
on a field with no other modifier). Every aggregate also gets `_by_<other_
field>`/`_for_<other_field>` siblings against every other modified field
(`sum_salary_by_dept()`, `avg_salary_for_dept(sales)`). Full detail,
including exact return types and raise behavior, in
[method-reference.md](method-reference.md).

Every entity table also always has `create(...)`, `all() -> Set[Self]`, and
`count() -> Int` (O(1), doesn't build a handle per row).

## Relation fields

A field typed `@@Type`, or a container of one, is a relation — an edge to
another entity's table.

```
@@members: List[@@Person]        # ordinary field, container-shaped
@@backup: Set[@@Employee]
@@lead: Optional[@@Employee]
@@leads: Dict[String, @@Employee]   # relation in the *value* position
multi @@projects: @@Project          # multi: one-at-a-time membership
```

**Whether the field's own name needs `@@`:** a relation is *directly
reachable* through a wrapper's own iteration/indexing surface when it sits
in the first type argument (`List[@@T]`, `Set[@@T]`, `Optional[@@T]`) or,
for a two-argument wrapper, the second (`Dict[K, @@T]` — real indexing
reaches it even though iteration doesn't). A field whose relation is
reachable this way *must* mark its own name with `@@`; one that isn't
(nothing currently defines a "reachable" path past position 2) stays bare.
This is enforced by the compiler, not a matter of style — an over- or
under-marked field is a compile error.

A relation field's value is always a live handle, chainable and indexable
directly, no intermediate binding required:

```
print(@@platform_team.@@members[0].name)
for @@m in @@platform_team.@@members:
    print(@@m.name)
```

### `multi` fields are different

`multi` isn't Set/List-wrapped — it's managed one member at a time:

```
_ = @@eng.add_to_@@projects(@@website)
_ = @@eng.add_to_@@projects(@@onboarding)
for @@proj in @@eng.@@projects:      # direct iteration works too
    print(@@proj.name)
```

Use `multi` for the standard many-to-many join pattern: since a field can
never point back at its own struct (any relation cycle is rejected, however
many hops it takes — see [overview.md](overview.md)), model many-to-many as
its own entity with a `multi` field, not a direct self-relation:

```
@@struct keepalive @@Group:
    multi @@members: @@Person
```

(`keepalive` matters here too — a `@@Group`'s only strong reference would
otherwise be whatever local handle created it.)

## Plain struct locals

A hand-written plain struct's own relation field still works normally
through a local variable holding one — but the variable's own *name* is
never itself `@@`-marked (a plain struct has no table of its own to bind
an entity handle against; only a field *access* through its value can be
marked, never the value's own local name):

```
@fieldwise_init
struct Assignment(Copyable, Movable, ImplicitlyDeletable):
    var @@person: @@Person
    role: String

var assignment: Assignment = @@team.lead.copy()
print(assignment.@@person.name)      # marked access, resolves fine
assignment.@@person = @@new_lead     # writes too
```

This works off the variable's own explicit type annotation alone (`var
assignment: Assignment = ...`) — the right-hand side can be anything
Mojo accepts (a copy of an already-known relation field, a hand-written
constructor call, whatever), no `@@Type{...}` construct required. The one
thing to watch: a plain struct's own field-declaration marking still
governs its constructor's own keyword argument spelling too (`@fieldwise_
init`'s rule: keyword name always equals field name) — construct with
`Assignment(@@person=@@alice, role="Lead")`, not the bare `person=`
spelling, which would just be plain, unprefixed text colliding with
whatever the field's real generated name actually is (and, for a field
literally named `ref`, with a genuine Mojo keyword).

The same explicit-type-annotation requirement covers every other place a
bare plain-struct-typed name gets introduced, not just a local var-decl:

```
def show(a: Assignment) raises:      # a def parameter
    print(a.@@person.name)

var team: List[Assignment] = ...     # a container of one
print(team[0].@@person.name)

for a in team:                       # a bare for-loop variable over it
    print(a.@@person.name)

print(a.lead.@@person.name)          # multi-hop: `lead` an unmarked
                                      # nested plain-struct field of `a`
```

In every case, *some* explicit signal has to appear somewhere the
compiler can see it — this is a text-scanning tool, not a type checker.
A def parameter or a hand-written struct field always needs its
annotation regardless (Mojo requires one there anyway, no different from
any other parameter/field). A var-decl is more lenient in three ways:

- `var x: Type = ...` — the explicit annotation, always works.
- `var x = Type(...)` / `var x = List[Type]()` — no annotation at all,
  inferred from a constructor-call-shaped initializer, the same way the
  marked-entity system already infers a bare `var @@x = List[@@Type]()`
  from its own container constructor rather than requiring `@@Type`
  spelled out twice.
- `var x = some_function(...)` — also no annotation, inferred from the
  function/method's own *registered return type* (not its name) when
  it's one this project actually declares — `var addrs =
  make_addresses(@@bob)` infers `List[Address]`, `var addr = @@bob.
  get_home()` infers `Address` straight off a bound entity's own bare
  method, exactly as if each had been spelled out by hand.

None of these ever produce a false positive: a call to something that
*isn't* a project-declared function/method at all (an unrelated call, a
typo'd name, a plain scalar like `var x: Int = 5`) is harmless dead
data — nothing downstream ever succeeds in resolving a field through a
name that isn't actually a known struct, it just quietly goes unused.

**What still needs an explicit annotation: anything squirrelc can't read
a `def name(...) -> Type:` line for, in a `.mojo.sqrrl` file it's
actually compiling.** That includes a plain struct's own hand-written
methods too — `Address.relocated(self, city: String) -> Address:`
tracks the same way a bare top-level function/an entity's own bare
method already do, chainable straight off the call (`addr.relocated(
"Metropolis").@@owner.name`, no intermediate variable) or bound to a
plain var-decl with no annotation. What's genuinely invisible is
anything with *no such line for squirrelc to read at all*:

- A method Mojo **synthesizes** for you from trait conformance —
  `.copy()` (from `Copyable`/`ImplicitlyCopyable`), `__eq__`/`__hash__`
  (from `Equatable`/`Hashable`), and so on. There's no `def ... ->
  Type:` anywhere in your source for these; Mojo generates the
  implementation itself.
- Anything **imported from outside this project** — another Mojo
  module, an external package, the standard library. The signature
  exists, but not in a file squirrelc reads.

```
var h = @@bob.home.copy()            # `.copy()` is Mojo-synthesized
                                      # (from Copyable), not tracked at all
print(h.@@dept.name)                 # error: 'h' was never constructed

var h: Address = @@bob.home.copy()   # fixed: the explicit annotation
print(h.@@dept.name)                 # doesn't need any inference at all
```

This is the same boundary as any other call throughout this DSL whose
signature isn't declared anywhere squirrelc reads (a table-level call
chained off `sqrrl___world` needs the same kind of registered-return
tracking, external or synthesized calls generally) — nothing new, just
the one case where skipping the annotation actually tempts you to leave
it off.

A bare (never `@@`/`@@@`-marked) function or method that returns a plain
struct is the one case that doesn't need an explicit annotation at all —
its own call result can be chained or iterated directly, no intermediate
variable required, the same way a marked entity-returning function/method
already can:

```
def make_address(city: String, @@owner: @@Employee) raises -> Address:
    return Address(city=city, @@owner=@@owner)

print(make_address("Capital City", @@bob).@@owner.name)
for a in make_addresses(@@bob):          # a bare function, iterated directly
    print(a.@@owner.name)

print(@@bob.get_home().@@owner.name)     # same, off a bound entity's own
                                          # bare method

for a in @@bob.get_homes():               # a *bare* loop variable, off a
    print(a.@@owner.name)                 # bound entity's own bare method

var addr = @@bob.get_home()               # a *bare var-decl*, no
print(addr.@@owner.name)                  # annotation, same source
```

A hand-written method on a plain struct itself works the same way too,
chained directly off a *bare*-rooted value (not just a bound `@@entity`):

```
@fieldwise_init
struct Address(Copyable, Movable, ImplicitlyDeletable):
    var city: String
    var @@owner: @@Employee

    def relocated(self, new_city: String, @@owner: @@Employee) -> Address:
        return Address(city=new_city, @@owner=@@owner)

var addr2 = Address(city="Springfield", @@owner=@@bob)
print(addr2.relocated("Shelbyville", @@bob).@@owner.name)  # direct chain

var y = addr2.relocated("Shelbyville", @@bob)               # bare var-decl
print(y.@@owner.name)

for a in addr2.get_nearby(@@bob):                           # bare for-loop
    print(a.@@owner.name)
```

This one matches an enormous amount of completely ordinary, unrelated
Mojo too — calling *any* method on *any* local variable at all looks
identical syntactically (`some_string.upper()`, `some_list.append(...)`)
— so it's a silent, harmless no-op whenever the receiver isn't actually
a tracked bare local, exactly like every other "matches far more often
than it's acted on" case in this DSL.

A bare loop variable can also iterate directly off a bound entity's own
plain field or a marked function/method's call result referenced
directly (`for a in @@bob.homes:`, `for a in @@existing_container:`) --
in every case, the loop variable's own marking must match whether the
iterated result is actually entity-shaped: `for @@x in ...:` requires it,
`for x in ...:` forbids it, checked in both directions regardless of
*how* the chain resolves (a field, a method call, a top-level function
call, or an already-bound variable).

A bare var-decl works the same way off a bound entity's own plain field
too, not just a method call (`var h = @@bob.home`) — and the *opposite*
mismatch is checked here as well: binding a genuinely `@@`-marked result
(a real relation, not a plain value) to an unmarked `var x = ...` is
rejected, requiring `var @@x = ...` instead, the same direction
`enforce_entity_binding` already enforced for every other marked-call
binding — this is what stops `var x = @@bob.@@dept` (`dept` a real
relation) from silently compiling to a plain, unmarked handle.

## Custom containers

Any hand-written type shaped like a container — one or two type parameters,
with `__getitem__` (indexing) and/or `__iter__` matching real Mojo `Dict`'s
own owned-iteration protocol (`IterableOwned`, raising `StopIteration` on
exhaustion, not a separate has-more check) — gets exactly the same
`@@container` treatment as `List`/`Set`/`Dict`/`Optional`. See
`examples/container_fields/grid_module.mojo` for a complete, working
two-argument example (`Grid[K, V]`).

Import the custom type directly wherever it's used as a field type or
constructed:

```
from schema.grid_module import Grid

@@struct @@Team:
    @@directory: Grid[String, @@Employee]
```

## Functions and methods

A **top-level function** or **struct method** whose return type is (or
contains, in a reachable position) an `@@`-marked value must mark its own
name — `@@name` if it doesn't need the world, `@@@name` if it does (never
both):

```
def @@@make_vendor(name: String) -> @@Vendor:
    var @@v = @@@Vendor { .name = name }
    return @@v
```

Marking makes the call itself a real, walkable position — a marked call's
result can be bound to a variable, iterated directly (`for @@x in
func(...):`), or chained directly (`func(...)[0].field`), with no
intermediate variable required either way.

A bare, unmarked function/method must *not* return an `@@`-marked value —
both directions (over-marked, under-marked) are compile errors, checked at
the signature, not deferred to a confusing error at some call site.

## World scope and keepalive

```
def main() raises:
    @@@:
        var @@alice = @@@Person { .name = "Alice" }
        ...
```

`@@@:` brings `sqrrl___world` into scope — exactly once per project. Every
other function/method that needs the world receives it as a threaded
parameter instead (that's the whole reason `@@@`-marking on functions
exists). At the end of the block, every entity's liveness is checked: an
entity still alive that's reachable from *nothing* external (no local
handle, no relation field, and not `keepalive`) means something leaked —
this aborts loudly rather than silently doing nothing.

This check clears every `keepalive` struct's own hold *before* checking any
struct's liveness — never interleaved one struct at a time. Because a
`keepalive` hold propagates forward (see above), a struct declared earlier
in the project can still be kept alive transitively through a `keepalive`
struct declared *later* (a `keepalive @@Group` holding `@@Person` members,
with `Person` declared first) — checking `Person`'s liveness before
`Group`'s own hold gets cleared would falsely report it as leaked, one
struct away from being released correctly.

`dont_keepalive()` releases a single entity's own `keepalive` hold early
(useful for something that should eventually be reclaimable once nothing
else references it, without waiting for the whole struct's `keepalive` to
be dropped):

```
var released = @@old_entry.dont_keepalive()
```

## JSON

Any project that calls one of the four whole-world JSON entry points gets a
generated `sqrrl__json.mojo`:

```
var dump = @@@to_json()
...
@@@begin_init_from_json(dump)
# ... use freshly-reloaded entities ...
@@@end_init_from_json()
```

`@@@begin_init_from_json` rebuilds the world from a dump, temporarily
keeping every reloaded entity alive; `@@@end_init_from_json` drops that
temporary hold, so anything not independently referenced by then is
released, same as it would be for freshly-constructed entities.

A custom container needs two hand-written escape-hatch companions to
participate in JSON — `sqrrl__<Wrapper>_json_to_pairs`/`_from_pairs` for a
two-argument wrapper, `_to_list`/`_from_list` for a one-argument one (see
`grid_module.mojo`/`ring_module.mojo` for working examples). These are
resolved automatically wherever the wrapper type itself is imported from; if
they genuinely live somewhere else, an explicit import of the escape-hatch
function itself, anywhere in the project, overrides that.
