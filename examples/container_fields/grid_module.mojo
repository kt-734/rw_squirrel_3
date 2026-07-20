@fieldwise_init
struct _GridKeyIter[K: Copyable & ImplicitlyDeletable](IterableOwned, Iterator, Movable):
    """Grid's own `__iter__` companion -- an *owned* iterator (consumes a
    freshly-built `List[K]` of keys, never borrows from `Grid` itself),
    matching real Mojo `Dict`'s own `_DictKeyIterOwned` shape exactly:
    `IterableOwned` (not `Iterable`) needs `IteratorOwnedType` (here just
    `Self`) and `__iter__(var self) -> Self.IteratorOwnedType` (`return
    self^`); `Iterator` needs `Element` and `__next__(mut self) raises
    StopIteration -> Self.Element` -- exhaustion signaled by *raising*
    `StopIteration`, not a separate `__has_next__` check (confirmed
    against the real stdlib `Dict` source directly -- an `Iterable`/
    `__has_next__`-based attempt crashes this compiler outright, even
    for the simplest possible non-generic case with no `Grid` involved
    at all, since that's simply the wrong protocol for the current
    Mojo version)."""

    comptime Element = Self.K
    comptime IteratorOwnedType = Self

    var items: List[Self.K]
    var idx: Int

    def __iter__(var self) -> Self.IteratorOwnedType:
        return self^

    def __next__(mut self) raises StopIteration -> Self.Element:
        if self.idx >= len(self.items):
            raise StopIteration()
        var v = self.items[self.idx].copy()
        self.idx += 1
        return v^


@fieldwise_init
struct Grid[K: Copyable & ImplicitlyDeletable & Hashable & Equatable, V: Copyable & ImplicitlyDeletable](Movable, ImplicitlyDeletable):
    """A hand-written custom two-argument container -- not Dict -- used
    to demonstrate the @@container JSON escape hatch generalized to
    two-argument wrappers: a fresh no-arg constructor is never assumed
    for a custom wrapper, so JSON support goes through the two
    hand-written companions below instead, mirroring the one-argument
    Ring[T] example exactly.

    `__getitem__`/`__iter__` (key-yielding, matching real `Dict`
    iteration) make Grid a fully well-behaved two-argument wrapper for
    the DSL's own mandatory-marking/access-chain machinery: a `@@`-
    marked `Grid[K, @@V]` field's value-position relation is reachable
    by indexing (`.@@field[key]`), and a for-loop over the same field
    (`for key in .@@field:`, bare loop variable required -- iterating
    only ever yields keys, never the value/entity) works end to end,
    at any hop depth -- confirmed via a real multi-struct chain compile,
    the same way it already does for a real `Dict`."""

    var pairs: List[Tuple[Self.K, Self.V]]

    def get(self, key: Self.K) raises -> Self.V:
        for i in range(len(self.pairs)):
            if self.pairs[i][0] == key:
                return self.pairs[i][1].copy()
        raise Error("key not found")

    def __getitem__(self, key: Self.K) raises -> Self.V:
        return self.get(key)

    def keys(self) -> List[Self.K]:
        var out = List[Self.K]()
        for i in range(len(self.pairs)):
            out.append(self.pairs[i][0].copy())
        return out^

    def __iter__(self) -> _GridKeyIter[Self.K]:
        return _GridKeyIter[Self.K](items=self.keys(), idx=0)


def sqrrl__Grid_json_to_pairs[
    K: Copyable & ImplicitlyDeletable & Hashable & Equatable, V: Copyable & ImplicitlyDeletable
](container: Grid[K, V]) -> List[Tuple[K, V]]:
    return container.pairs.copy()


def sqrrl__Grid_json_from_pairs[
    K: Copyable & ImplicitlyDeletable & Hashable & Equatable, V: Copyable & ImplicitlyDeletable
](var pairs: List[Tuple[K, V]]) -> Grid[K, V]:
    return Grid[K, V](pairs=pairs^)
