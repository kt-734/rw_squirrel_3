from sqrrl__world import sqrrl___World
from squirrel_runtime.json import sqrrl___JsonScanner
from sqrrl__json import sqrrl__to_json, sqrrl__from_json


@fieldwise_init
struct Ring[T: Copyable & ImplicitlyDeletable](Movable, ImplicitlyDeletable):
    """A hand-written custom container -- not List/Set/Optional/Dict --
    used to demonstrate the `_to_json`/`_from_json` contract every wrapper
    (built-in or custom) implements: a fresh no-arg constructor and a
    guessable build-up method are never assumed for a custom wrapper (a
    @fieldwise_init struct's own synthesized __init__ takes every field,
    not zero of them), so JSON support goes through the two hand-written
    companions below instead."""

    var items: List[Self.T]

    def __getitem__(self, i: Int) -> ref [self.items[i]] Self.T:
        return self.items[i]


def sqrrl__Ring_to_json[T: Copyable & ImplicitlyDeletable](value: Ring[T], world: sqrrl___World) -> String:
    """The complete JSON text for `value` directly -- an ordinary array,
    recursing through `sqrrl__to_json` per element so a relation in `T`
    dumps correctly too."""
    var out = String("[")
    for i in range(len(value.items)):
        if i > 0:
            out += ","
        out += sqrrl__to_json(value.items[i], world)
    out += "]"
    return out^


def sqrrl__Ring_from_json[
    T: Copyable & ImplicitlyDeletable
](mut sc: sqrrl___JsonScanner, world: sqrrl___World) raises -> Ring[T]:
    """Parses `sqrrl__Ring_to_json`'s own array text directly off `sc` --
    no known no-arg constructor plus per-element append method to rely on
    instead."""
    var items = List[T]()
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            items.append(sqrrl__from_json[T](sc, world))
            if sc.try_consume_byte(UInt8(ord(","))):
                continue
            sc.expect_byte(UInt8(ord("]")))
            break
    return Ring[T](items=items^)
