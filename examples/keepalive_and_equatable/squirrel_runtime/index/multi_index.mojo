from std.os import abort
from std.collections import Set


struct MultiIndex[T: KeyElement & ImplicitlyDeletable & Copyable](Movable, ImplicitlyDeletable):
    """Backward index for a `multi`-tagged field: `Dict[T, Set[id]]`, keyed
    by each *element* of the field's own membership set rather than the
    field's whole value (what `PlainIndex` does for an ordinary field).
    `T` is the element type (`Project` for `multi @@projects: @@Project`),
    not `Set[Project]`.

    Forward-keeps-alive policy (settled 2026-07-16): the forward value --
    `Set[sqrrl__Project]` on the owning `Inner`'s own real field -- holds
    the actual strong references; this index only ever stores bare ids as
    bucket members, a lookup structure, never an owner. Same "pop the key
    entirely once its bucket empties" rule as `PlainIndex` applies here too
    (see its own doc comment) -- `T` being a relation entity type means the
    dict *key* itself is a strong reference, and leaving an empty bucket
    behind would leak it."""

    var _bwd: Dict[Self.T, Set[UInt32]]

    def __init__(out self):
        self._bwd = Dict[Self.T, Set[UInt32]]()

    def add(mut self, id: UInt32, value: Self.T):
        try:
            if value not in self._bwd:
                self._bwd[value.copy()] = Set[UInt32]()
            self._bwd[value].add(id)
        except:
            abort("MultiIndex.add: unreachable Dict operation failure")

    def remove(mut self, id: UInt32, value: Self.T):
        try:
            if value not in self._bwd:
                return
            # Mutate the bucket in place through a `ref` -- see
            # PlainIndex.remove's own comment for why this avoids a
            # copy-then-write-back.
            ref bucket = self._bwd[value]
            if id in bucket:
                try:
                    bucket.remove(id)
                except:
                    abort("MultiIndex.remove: unreachable Set.remove failure")
            var now_empty = len(bucket) == 0
            if now_empty:
                _ = self._bwd.pop(value)
        except:
            abort("MultiIndex.remove: unreachable Dict operation failure")

    def get_bwd(self, value: Self.T) -> Set[UInt32]:
        """All owner ids whose own membership set currently contains
        `value` (empty if none)."""
        try:
            return self._bwd[value].copy()
        except:
            return Set[UInt32]()

    def all_bwd(self) -> ref [self._bwd] Dict[Self.T, Set[UInt32]]:
        return self._bwd

    def add_many(mut self, id: UInt32, values: Set[Self.T]):
        """Bulk `add(id, elem)` for every element in `values` -- used by
        `create()`'s index population and as the "add new" half of a
        wholesale `set_<field>` replacement (paired with `remove_many` for
        the "evict old" half first, same unconditional evict-then-add
        shape every other field's `set_<field>` already uses -- it doesn't
        check whether the value actually changed either)."""
        for value in values:
            self.add(id, value)

    def remove_many(mut self, id: UInt32, values: Set[Self.T]):
        """Bulk `remove(id, elem)` for every element in `values` -- used by
        `__del__`'s eviction and as the "evict old" half of `set_<field>`."""
        for value in values:
            self.remove(id, value)
