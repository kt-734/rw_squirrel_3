# Pitfalls and errors

A guide to the specific errors you'll actually hit, what they mean, and how
to fix them — distilled from real gaps found and fixed during this
project's own development, not a hypothetical list.

## `InvalidSquirrelSyntax: '<Type>.<field>' is a relation field -- read it as '.@@<field>', not '.<field>'`

You wrote `.field` where `field` is declared `@@field: @@Type` (or a
container of one). A relation field's own access must be marked to match
its declaration — `declare unmarked, access unmarked` / `declare marked,
access marked` is enforced symmetrically. Fix: add the `@@` at the access
site (`.@@field`), or check whether the field should even be marked in the
first place (see [syntax-reference.md](syntax-reference.md#relation-fields)
— a relation only needs `@@` when it's *directly reachable* through
iteration/indexing; one confined to a position with no such path stays
bare).

## `InvalidSquirrelSyntax: '@@<x>' -- iterating this only ever yields a plain value here ...`

You wrote `for @@x in <something>:` where iterating that value only ever
exposes a *key*, never the entity itself — e.g. any `Dict`-shaped value
(built-in or custom), even one with a relation genuinely reachable by
*indexing*. Iteration and indexing are different questions: a value/field
whose only relation is in a `Dict`'s value position supports
`.field["key"]` directly, but a direct `for` loop over it only ever binds
the key. Fix: drop the `@@` — `for x in <something>:` — and index
separately if you need the entity.

## `CyclicRelation: A (module) -> B (module) -> A`

The project's relation graph has a cycle — `create()` needs every relation
field's target to already exist, so a cycle has no valid first entity to
construct, and `ArcPointer` has no cycle collector to fall back on either.
This is checked project-wide, including through hand-written plain
structs' own nested relation fields, at *any* container argument position
(a relation reachable only through a `Dict`'s value position is just as
much an edge as one in the key or a bare field). If this fires
unexpectedly, look for a relation field you didn't think of as
"pointing back" — often a plain struct embedded in one direction that
itself, several hops deep, reaches back the other way.

There's no way around a genuine cycle other than removing it from the
schema — typically by modeling a many-to-many relationship as its own
`keepalive` join entity instead of a direct field
(see [syntax-reference.md](syntax-reference.md#multi-fields-are-different)).

## `LeakedEntities: '<Name>' still has N live entities outside sqrrl___world -- something external still references them`

Raised at the end of `@@@:`'s own scope (or the next `@@init()`/reload)
when an entity of struct `<Name>` is still alive but unreachable from
anything the leak-checker considers legitimate: no local handle, no
relation field pointing at it, and the struct itself isn't `keepalive`.
Two common causes:

1. **You meant it to survive with no local handle**, and forgot
   `keepalive` on the struct declaration.
2. **A genuine leak** — something is holding a handle you didn't account
   for (often: a container built earlier in the function that never got
   cleared, or a field on some *other* still-live entity that references
   this one).

If you added `keepalive` and are still seeing this for an entity that
should legitimately be reachable only *through* a keepalive struct's own
relation field, remember the hold propagates forward, not backward — the
entity holding the reference needs `keepalive`, not the one being
referenced. See
[syntax-reference.md](syntax-reference.md#world-scope-and-keepalive).

## `... is marked '@@' but doesn't return an '@@'-marked value` / `... returns an '@@'-marked value but isn't itself marked`

A top-level function's or method's own `@@`/`@@@` marking doesn't match
what it actually returns — checked at the signature, both directions.
Over-marked: drop the `@@`. Under-marked: add `@@` (if the function doesn't
need `sqrrl___world`) or `@@@` (if it does — never both). This is checked
independently of whether the function needs the world; a function can
return an entity without touching the world (e.g. re-returning a parameter
unchanged), and one that needs the world doesn't necessarily return
anything entity-shaped at all (in which case it stays bare — `@@@` is
about parameter-threading, not really about the return type).

## A custom container's own `__iter__` crashes the *compiler*, not just fails to compile

If a hand-written container's `__iter__` uses `Iterable`/`__has_next__`
instead of the real Mojo `Dict` protocol (`IterableOwned`,
`IteratorOwnedType`, `__next__` raising `StopIteration` on exhaustion, no
separate has-more check), expect an outright compiler crash with no
diagnostic — confirmed unrelated to squirrelc or generics specifically;
it's simply the wrong protocol for the current Mojo version. See
`examples/container_fields/grid_module.mojo`'s own doc comment for the
exact, working shape to copy.

## `sqrrl__json.mojo:N: error: module '<X>' does not contain 'sqrrl__<Wrapper>_json_to_pairs'`

A custom container's JSON escape-hatch companions aren't where squirrelc
assumed they'd be (alongside the wrapper type's own import). See
[json-and-custom-containers.md](json-and-custom-containers.md#where-the-import-comes-from)
for the resolution order and the fix (an explicit import of the companion
function itself, anywhere in the project).
