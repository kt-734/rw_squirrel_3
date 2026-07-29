from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl___init, sqrrl___World
from people_impl import HasId

def print_entity_id[T: HasId](x: T):
    print("id:", x.entity_id())

def sqrrl__greet_everyone(mut sqrrl___world: sqrrl___World) raises -> String:
    var out = String("")
    for sqrrl__p in sqrrl___world.Person.all():
        out += sqrrl__p._inner[]._name + " "
    return out

def main() raises:
    var sqrrl___world = sqrrl___init()
    try:
        var sqrrl__alice = sqrrl___world.Person.create(name = "alice")
        var sqrrl__bob = sqrrl___world.Person.create(name = "bob")

        print(sqrrl__alice.greeting(sqrrl___world))
        print(sqrrl__bob.greeting(sqrrl___world))

        print("direct call:", sqrrl__alice.entity_id())
        print_entity_id(sqrrl__alice)
        print_entity_id(sqrrl__bob)

        print("top-level @@@ function:", sqrrl__greet_everyone(sqrrl___world))
        print("count:", sqrrl___world.Person.count(), sqrrl__alice._inner[]._name, sqrrl__bob._inner[]._name)
    finally:
        sqrrl___world.sqrrl__check_no_leaks()
