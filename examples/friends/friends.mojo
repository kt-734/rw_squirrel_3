from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl___init, sqrrl___World
from friends_impl import sqrrl__Person

def sqrrl__are_friends(mut sqrrl___world: sqrrl___World, sqrrl__one: sqrrl__Person, sqrrl__two: sqrrl__Person) raises -> Bool:
    if sqrrl__one == sqrrl__two:
        return False
    for sqrrl__g in sqrrl___world.Group.for_sqrrl__members(sqrrl__one):
        if sqrrl__two in sqrrl__g._inner[]._sqrrl__members:
            return True
    return False

def sqrrl__all_friends(mut sqrrl___world: sqrrl___World, sqrrl__person: sqrrl__Person) raises -> Set[sqrrl__Person]:
    var result = Set[sqrrl__Person]()
    for sqrrl__g in sqrrl___world.Group.for_sqrrl__members(sqrrl__person):
        for sqrrl__p in sqrrl__g._inner[]._sqrrl__members:
            if sqrrl__p != sqrrl__person:
                result.add(sqrrl__p)
    return result^

def main() raises:
    var sqrrl___world = sqrrl___init()
    try:
        var sqrrl__alice = sqrrl___world.Person.create(name = "Alice")
        var sqrrl__bob = sqrrl___world.Person.create(name = "Bob")
        var sqrrl__carol = sqrrl___world.Person.create(name = "Carol")
        var sqrrl__dave = sqrrl___world.Person.create(name = "Dave")

        # A "friend group" is modeled as its own entity rather than a
        # field directly on @@Person -- a field on @@Person pointing at
        # @@Person is a self-relation cycle no matter what wrapper it's
        # given (List/Set/multi all still count as an edge back to where
        # it started), so a real many-to-many friendship instead goes
        # through a join struct that only points *at* @@Person, never
        # the reverse. `keepalive` matters here too: a @@Group's only
        # strong reference is otherwise whatever local handle created
        # it, so without `keepalive` a group can silently stop existing
        # the moment nothing still holds that handle.
        _ = sqrrl___world.Group.create(sqrrl__members = Set(sqrrl__alice, sqrrl__bob))
        _ = sqrrl___world.Group.create(sqrrl__members = Set(sqrrl__alice, sqrrl__carol))

        print("alice and bob:", sqrrl__are_friends(sqrrl___world, sqrrl__alice, sqrrl__bob))
        print("alice and dave:", sqrrl__are_friends(sqrrl___world, sqrrl__alice, sqrrl__dave))
        print("alice and alice:", sqrrl__are_friends(sqrrl___world, sqrrl__alice, sqrrl__alice))

        print("alice's friends:")
        for sqrrl__f in sqrrl__all_friends(sqrrl___world, sqrrl__alice):
            print(" -", sqrrl__f._inner[]._name)
    finally:
        sqrrl___world.sqrrl__check_no_leaks()
