# JSON and custom containers

## Whole-world JSON

A project only gets a generated `sqrrl__json.mojo` if some file actually
calls one of the four entry points — `@@@to_json()`, `@@@begin_init_from_
json(...)`, `@@@init_from_json(...)`, `@@@end_init_from_json()`. A project
that never touches JSON carries none of the associated code or trait
conformance; this is checked by scanning raw source for these markers
*before* any file gets transformed, since it also gates whether entity
structs get `sqrrl___JsonSerializable` conformance while they're being
emitted.

```
var dump = @@@to_json()
...
@@@begin_init_from_json(dump)
# ... every entity is temporarily kept alive (TempKeepAlives) ...
var @@x = @@@Employee.for_email("alice@example.com")   # a real, independent handle now
...
@@@end_init_from_json()   # drops the temporary hold; unreferenced entities go
```

Take the dump *before* anything you still need has had its last textual
use — Mojo drops a local as soon as its last use passes (ASAP/last-use
destruction, not scope-based), so `to_json()` called after that point would
serialize whatever's still alive at that moment, which may already be less
than you expect.

## The escape hatch, in full

A container that isn't `List`/`Set`/`Optional`/`Dict` gets JSON support
through two hand-written companion functions instead of generated
reflection:

```
def sqrrl__Grid_json_to_pairs[K: ..., V: ...](container: Grid[K, V]) -> List[Tuple[K, V]]:
    return container.pairs.copy()

def sqrrl__Grid_json_from_pairs[K: ..., V: ...](var pairs: List[Tuple[K, V]]) -> Grid[K, V]:
    return Grid[K, V](pairs=pairs^)
```

One-argument wrapper: `_to_list`/`_from_list`, converting to/from `List[T]`
instead of `List[Tuple[K, V]]`. That's the entire contract — squirrelc
never inspects the wrapper's own real implementation, just trusts these two
functions exist with the right name and shape.

### Where the import comes from

The generated `sqrrl__json.mojo` needs `Grid` and both companions imported
into itself. squirrelc resolves that import in priority order:

1. **An explicit import of the companion function itself**, anywhere in the
   project (`from wherever import sqrrl__Grid_json_to_pairs, sqrrl__Grid_
   json_from_pairs`) — the escape valve for when the companions genuinely
   don't live alongside the wrapper.
2. **Wherever the wrapper type itself is imported from** — the common case:
   trusting the convention that a wrapper and its own JSON companions live
   in the same hand-written file, and something in the project already
   needs the type imported directly regardless (to declare a field of that
   type, or construct one).
3. **The old fallback**: whichever real struct's own field first referenced
   the wrapper's module — kept only so this never hard-fails when neither
   of the above applies.

squirrelc never verifies any of this — it's a compile-time text scan of
every file's raw `from X import Y` lines, not real Mojo import resolution.
If the companions genuinely aren't where step 2 assumes, real Mojo fails on
the generated import line itself with a precise, if one-hop-removed, error:

```
sqrrl__json.mojo:8:31: error: module 'grid_module' does not contain 'sqrrl__Grid_json_to_pairs'
```

— which is exactly what step 1's override exists to fix.

## Iteration and indexing, independent of JSON

A custom container's *runtime* container semantics (does `.field[key]`
work? does `for x in .field:` work?) are unrelated to JSON support — they
come from the type's own `__getitem__`/`__iter__`, checked structurally
(does this type look like a container the DSL already understands), not
from any hand-written companion. See
[architecture.md](architecture.md#the-rewrite-engine-codegen) for
`is_directly_entity_reachable`. A container can have working
indexing/iteration with no JSON support at all (if the project never
serializes it), or vice versa in principle — though in practice, if a
field's ever going through a whole-world dump, it needs both.

The one subtlety specific to iteration: `Dict` (and anything shaped like
it) only ever yields *keys* when iterated directly, never values — the same
is true for a custom two-argument wrapper. A relation confined to the
*value* position (`Grid[String, @@Employee]`) is still directly indexable
(`.field["key"]`), but a direct `for @@x in .field:` must use a bare loop
variable (`for key in .field:`) — the compiler rejects a marked one, since
the loop would actually only ever bind a key, never the entity itself.
