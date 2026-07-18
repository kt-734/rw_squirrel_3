from std.memory import ArcPointer
from std.os import abort

from squirrel_runtime.id_allocator import IdAllocator


struct EntityStorage[
    Indexes: Movable & ImplicitlyDeletable,
    Inner: Movable & ImplicitlyDeletable,
](Movable, ImplicitlyDeletable):
    """The payload behind every entity's `ArcPointer`, shared once per table:
    an `IdAllocator` (identical logic for every table) plus `Indexes` -- the
    generated per-struct `sqrrl__<Name>Indexes`, one field per backward-
    indexed field only (see codegen/table.mojo). Unlike rw_squirrel_2's
    `TableStorage[State]`, `Indexes` carries no cleanup contract of its own
    (no `TableStateLike`-equivalent trait) -- a field's forward value now
    lives as a real field on `Inner` (the generated per-struct
    `sqrrl__<Name>Inner`), so cleanup happens directly in `Inner.__del__`,
    not through a shared generic dispatch.

    `weak_refs` (one `WeakPointer` per id, to that id's own `Inner`) is what
    makes `handle_for` (looking up a live entity from a bare id, e.g. for a
    generated `for_<field>`) safe -- ported unchanged from rw_squirrel_2's
    own `TableStorage`, whose doc comment traces the exact double-free bug
    in the original rw_squirrel this exists to prevent: a `WeakPointer`
    doesn't keep anything alive, so `try_upgrade` lets a later lookup share
    a real reference to a still-live row without ever fabricating an
    independent, uncoordinated second owner.

    This is the *only* generic runtime layer between an `ArcPointer` and a
    generated `sqrrl__<Name>Table` -- there's no separate `EntityTable`
    wrapper on top of it the way an earlier draft had. That extra layer
    would have held nothing of its own beyond a single `ArcPointer[
    EntityStorage[...]]` field, with every one of its own methods just
    forwarding to `self.storage[].something()` -- pure indirection with no
    behavior or state that couldn't live directly here instead. A generated
    `sqrrl__<Name>Table` holds `ArcPointer[EntityStorage[Indexes, Inner]]`
    itself; `create()`/`for_<field>()` still have to be generated
    per-struct (only codegen knows a concrete `Inner`'s real field list),
    but everything mechanically identical across every struct --
    allocation, weak-ref-based handle reconstruction, the whole-table
    `all`/`count` walk -- lives here, once.

    `keepalive` (M4) lives here too, not on `Table` -- `Inner._table`
    already points *here*, never at `Table` itself (which only ever holds
    an `ArcPointer[EntityStorage]` pointing the other way), so this is the
    only place a real strong hold reachable from *both* an instance
    (`dont_keepalive`) and the table (`create`) can live without giving
    `Inner` a second pointer back to `Table`. Present unconditionally for
    every struct (an empty, unused `Dict` for a non-`keepalive`-tagged
    one) -- a small, real but non-functional cost, deliberately accepted
    over a `Table`-level field that a bare `Inner` could never reach."""

    var ids: IdAllocator
    var indexes: Self.Indexes
    var weak_refs: List[Optional[ArcPointer[Self.Inner].WeakPointer]]
    var keepalive: Dict[UInt32, ArcPointer[Self.Inner]]

    def __init__(out self, var indexes: Self.Indexes):
        self.ids = IdAllocator()
        self.indexes = indexes^
        self.weak_refs = List[Optional[ArcPointer[Self.Inner].WeakPointer]]()
        self.keepalive = Dict[UInt32, ArcPointer[Self.Inner]]()

    def alloc_id(mut self) -> UInt32:
        return self.ids.alloc()

    def alloc_specific_id(mut self, id: UInt32) raises:
        self.ids.alloc_specific(id)

    def free_id(mut self, id: UInt32):
        self.ids.free(id)

    def is_live(self, id: UInt32) -> Bool:
        return self.ids.is_live(id)

    def id_count(self) -> Int:
        return self.ids.id_count()

    def live_count(self) -> Int:
        return self.ids.live_count()

    def store_weak_ref(mut self, id: UInt32, w: ArcPointer[Self.Inner].WeakPointer):
        while Int(id) >= len(self.weak_refs):
            self.weak_refs.append(None)
        self.weak_refs[Int(id)] = w

    def clear_weak_ref(mut self, id: UInt32):
        if Int(id) < len(self.weak_refs):
            self.weak_refs[Int(id)] = None

    def try_upgrade(self, id: UInt32) -> Optional[ArcPointer[Self.Inner]]:
        if Int(id) >= len(self.weak_refs) or not self.weak_refs[Int(id)]:
            return None
        return self.weak_refs[Int(id)].value().try_upgrade()

    def register_weak(mut self, id: UInt32, inner: ArcPointer[Self.Inner]):
        """Stores a `WeakPointer` to `inner` under `id`, so a later bare-id
        lookup (`handle_for`, from a generated `for_<field>`) can share a
        real reference to this exact row instead of fabricating a second,
        uncoordinated owner."""
        var w = ArcPointer[Self.Inner].WeakPointer(downgrade=inner)
        self.store_weak_ref(id, w)

    def handle_for(self, id: UInt32) -> ArcPointer[Self.Inner]:
        """A safe alternative to fabricating a fresh `ArcPointer[Inner]` for
        an id you don't already hold a reference to -- upgrades the id's
        stored `WeakPointer` instead. Aborts rather than raises if the id is
        no longer live: every current caller (a generated `for_<field>`)
        only ever passes an id fresh out of an index's own backward lookup,
        kept in sync with which ids are currently live -- a dead id
        reaching here would mean that invariant broke, not realistic bad
        input a caller could meaningfully recover from."""
        var upgraded = self.try_upgrade(id)
        if not upgraded:
            abort("EntityStorage.handle_for: id is no longer live")
        return upgraded.value()

    def keepalive_add(mut self, id: UInt32, var inner: ArcPointer[Self.Inner]):
        """A real strong hold (M4's `keepalive`) -- lives here, on the
        shared runtime layer, rather than on the generated `sqrrl__<Name>
        Table` struct: `Inner._table` already points *here*, not at
        `Table` (which itself just holds `ArcPointer[EntityStorage]`), so
        this is the only place reachable from *both* an instance
        (`dont_keepalive`, `Inner._table[]...`) and the table (`create`)
        without giving `Inner` a second pointer back to `Table` itself."""
        self.keepalive[id] = inner^

    def keepalive_remove(mut self, id: UInt32) -> Bool:
        """`True` if `id` was actually removed (was actually held)."""
        try:
            _ = self.keepalive.pop(id)
            return True
        except:
            return False

    def keepalive_clear(mut self):
        self.keepalive = Dict[UInt32, ArcPointer[Self.Inner]]()

    def all(self) -> List[UInt32]:
        """Every currently-live id -- a single pass over every id ever
        handed out, checking `is_live`. Finds an entity regardless of what's
        actually keeping it alive (a relation elsewhere, a local handle,
        `keepalive`, ...) -- ground truth is the id allocator, not any one
        field's own index."""
        var out = List[UInt32]()
        for i in range(self.id_count()):
            var id = UInt32(i)
            if self.is_live(id):
                out.append(id)
        return out^
