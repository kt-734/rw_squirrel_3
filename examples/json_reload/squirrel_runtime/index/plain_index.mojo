from std.os import abort
from std.collections import Set


struct PlainIndex[T: KeyElement & ImplicitlyDeletable & Copyable](Movable, ImplicitlyDeletable):
    """Backward index for an `indexed`-tagged field: `Dict[T, Set[id]]`,
    every value currently in use mapped to every id currently holding it.

    Unlike rw_squirrel_2's `Rel[T]`, there is no `_fwd` half here at all --
    the forward value lives as a real field on the generated `Inner` struct
    now (see squirrel_compiler/codegen/entity.mojo), so this only ever needs
    to answer the *reverse* question. A generated `set_<field>` reads the old
    value directly off `Inner`'s own real field before calling `remove`, so
    there's nothing to fetch here either."""

    var _bwd: Dict[Self.T, Set[UInt32]]

    def __init__(out self):
        self._bwd = Dict[Self.T, Set[UInt32]]()

    def add(mut self, id: UInt32, value: Self.T):
        try:
            if value not in self._bwd:
                self._bwd[value.copy()] = Set[UInt32]()
            self._bwd[value].add(id)
        except:
            abort("PlainIndex.add: unreachable Dict operation failure")

    def remove(mut self, id: UInt32, value: Self.T):
        try:
            if value not in self._bwd:
                return
            # Mutate the bucket in place through a `ref` into the dict's own
            # storage -- no copy-then-write-back needed, `pop` only ever
            # runs after this reference's own last use (confirmed: Mojo
            # accepts mutating `self._bwd` itself once `bucket` is no
            # longer read).
            ref bucket = self._bwd[value]
            if id in bucket:
                try:
                    bucket.remove(id)
                except:
                    abort("PlainIndex.remove: unreachable Set.remove failure")
            var now_empty = len(bucket) == 0
            if now_empty:
                # Delete the key itself, not just empty its set -- when T is
                # a relation entity type, the key's own copy is a real
                # strong reference, and leaving an empty entry behind would
                # keep that reference alive forever.
                _ = self._bwd.pop(value)
        except:
            abort("PlainIndex.remove: unreachable Dict operation failure")

    def get_bwd(self, value: Self.T) -> Set[UInt32]:
        """All ids currently holding `value` (empty if none)."""
        try:
            return self._bwd[value].copy()
        except:
            return Set[UInt32]()

    def all_bwd(self) -> ref [self._bwd] Dict[Self.T, Set[UInt32]]:
        """Every value currently in use, each mapped to every id holding it
        -- a borrowed reference straight into `_bwd`, not a copy, since every
        caller (`group_by_<field>`) immediately builds its own fresh `Dict`
        from this one anyway."""
        return self._bwd
