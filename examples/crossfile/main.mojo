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
        var sqrrl__alice = sqrrl___world.Employee.create(name = "alice", sqrrl__dept = sqrrl__eng)
        var sqrrl__bob = sqrrl___world.Employee.create(name = "bob", sqrrl__dept = sqrrl__eng)

        print(sqrrl__alice._inner[]._name, sqrrl__alice._inner[]._sqrrl__dept._inner[]._name)

        var sqrrl__matches = sqrrl___world.Employee.for_name("alice")
        print("found by index:", len(sqrrl__matches))

        print("count:", sqrrl___world.Employee.count(), sqrrl__alice._inner[]._name, sqrrl__bob._inner[]._name)
    finally:
        sqrrl___world.sqrrl__check_no_leaks()
