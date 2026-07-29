from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl___init, sqrrl___World

def main() raises:
    var sqrrl___world = sqrrl___init()
    try:
        var sqrrl__eng = sqrrl___world.Department.create(name = "Engineering")
        var sqrrl__alice = sqrrl___world.Person.create(name = "alice", age = 30, sqrrl__dept = sqrrl__eng)
        var sqrrl__bob = sqrrl___world.Person.create(name = "bob", age = 25, sqrrl__dept = sqrrl__eng)
        sqrrl__alice._inner[].set_age(31);
        print(sqrrl__alice._inner[]._name, sqrrl__alice._inner[]._age, sqrrl__alice._inner[]._sqrrl__dept._inner[]._name)

        var sqrrl__team = sqrrl___world.Person.for_name("alice")
        print("found by index:", len(sqrrl__team))

        # Regression coverage for a real, once-present bug: a `unique`
        # field's own `set_<field>` used to check_unique/remove/assign
        # but never re-add the new value to its own backward index --
        # `for_<field>` on the *new* value would then wrongly raise
        # "no entity currently holds this value" even though the field
        # itself already held it.
        var sqrrl__ops = sqrrl___world.Department.create(name = "Operations")
        sqrrl__ops._inner[].set_name("Ops Renamed");
        var sqrrl__found_ops = sqrrl___world.Department.for_name("Ops Renamed")
        print("found renamed department by its new name:", sqrrl__found_ops._inner[]._name)

        print("count:", sqrrl___world.Person.count(), sqrrl__alice._inner[]._name, sqrrl__bob._inner[]._name, sqrrl__ops._inner[]._name)
    finally:
        sqrrl___world.sqrrl__check_no_leaks()
