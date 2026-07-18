@fieldwise_init
struct Ring[T: Copyable & ImplicitlyDeletable](Movable, ImplicitlyDeletable):
    """A hand-written custom container -- not List/Set/Optional/Dict --
    used to demonstrate the @@container JSON escape hatch: a fresh no-arg
    constructor and a guessable build-up method are never assumed for a
    custom wrapper (a @fieldwise_init struct's own synthesized __init__
    takes every field, not zero of them), so JSON support goes through
    the two hand-written companions below instead."""

    var items: List[Self.T]

    def __getitem__(self, i: Int) -> ref [self.items] Self.T:
        return self.items[i]


def sqrrl__Ring_json_to_list[T: Copyable & ImplicitlyDeletable](container: Ring[T]) -> List[T]:
    """Dump-direction escape hatch -- Ring isn't guaranteed `__iter__`, so
    `@@@to_json()` converts to an ordinary List first."""
    return container.items.copy()


def sqrrl__Ring_json_from_list[T: Copyable & ImplicitlyDeletable](var items: List[T]) -> Ring[T]:
    """Reload-direction escape hatch -- the whole, already-populated List
    is handed over in one shot, since there's no known no-arg constructor
    plus per-element append method to rely on instead."""
    return Ring[T](items=items^)
