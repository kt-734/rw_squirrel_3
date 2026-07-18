@fieldwise_init
struct Grid[K: Copyable & ImplicitlyDeletable & Hashable & Equatable, V: Copyable & ImplicitlyDeletable](Movable, ImplicitlyDeletable):
    """A hand-written custom two-argument container -- not Dict -- used
    to demonstrate the @@container JSON escape hatch generalized to
    two-argument wrappers: a fresh no-arg constructor is never assumed
    for a custom wrapper, so JSON support goes through the two
    hand-written companions below instead, mirroring the one-argument
    Ring[T] example exactly."""

    var pairs: List[Tuple[Self.K, Self.V]]

    def get(self, key: Self.K) raises -> Self.V:
        for i in range(len(self.pairs)):
            if self.pairs[i][0] == key:
                return self.pairs[i][1].copy()
        raise Error("key not found")


def sqrrl__Grid_json_to_pairs[
    K: Copyable & ImplicitlyDeletable & Hashable & Equatable, V: Copyable & ImplicitlyDeletable
](container: Grid[K, V]) -> List[Tuple[K, V]]:
    return container.pairs.copy()


def sqrrl__Grid_json_from_pairs[
    K: Copyable & ImplicitlyDeletable & Hashable & Equatable, V: Copyable & ImplicitlyDeletable
](var pairs: List[Tuple[K, V]]) -> Grid[K, V]:
    return Grid[K, V](pairs=pairs^)
