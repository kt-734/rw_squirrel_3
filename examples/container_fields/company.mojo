from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl___JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl___init, sqrrl___World
from sqrrl__json import sqrrl___begin_init_from_json, sqrrl___end_init_from_json, sqrrl___init_from_json, sqrrl___world_to_json
from company_impl import sqrrl__Employee

from ring_module import Ring
from grid_module import Grid

def main() raises:
    var sqrrl___world = sqrrl___init()
    try:
        var sqrrl__alice = sqrrl___world.Employee.create(name = "Alice")
        var sqrrl__bob = sqrrl___world.Employee.create(name = "Bob")
        var scores_dict = Dict[sqrrl__Employee, String]()
        scores_dict[sqrrl__alice] = "lead";
        scores_dict[sqrrl__bob] = "member";
        var leads_dict = Dict[String, sqrrl__Employee]()
        leads_dict["primary"] = sqrrl__alice;
        var sqrrl__eng = sqrrl___world.Department.create(name = "Engineering", sqrrl__members = [sqrrl__alice, sqrrl__bob], sqrrl__backup = Set(sqrrl__alice), sqrrl__lead = Optional(sqrrl__alice), tags = ["urgent", "core"], sqrrl__scores = scores_dict^, sqrrl__leads = leads_dict^, groups = [["a", "b"], ["c"]], ring = Ring[String](items=["x", "y"]), grid = Grid[String, Int](pairs=[("p", 1), ("q", 2)]))

        print(sqrrl__eng._inner[]._sqrrl__members[0]._inner[]._name)
        print(sqrrl__eng._inner[]._sqrrl__members[1]._inner[]._name)
        print(len(sqrrl__eng._inner[]._sqrrl__backup))
        if sqrrl__eng._inner[]._sqrrl__lead:
            print(sqrrl__eng._inner[]._sqrrl__lead.value()._inner[].get_name())
        print(sqrrl__eng._inner[]._tags[0], sqrrl__eng._inner[]._tags[1])
        print(sqrrl__eng._inner[]._sqrrl__scores[sqrrl__alice])
        print(sqrrl__eng._inner[]._sqrrl__leads["primary"]._inner[]._name)
        print(sqrrl__eng._inner[]._groups[0][0], sqrrl__eng._inner[]._groups[0][1], sqrrl__eng._inner[]._groups[1][0])
        print(sqrrl__eng._inner[]._ring[0], sqrrl__eng._inner[]._ring[1])
        print(sqrrl__eng._inner[]._grid["p"], sqrrl__eng._inner[]._grid["q"])

        sqrrl__eng._inner[]._sqrrl__members[0]._inner[].set_name("Alicia");
        print(sqrrl__eng._inner[]._sqrrl__members[0]._inner[]._name)

        var dump = sqrrl___world_to_json(sqrrl___world)
        print("dump:", dump)

        var alice_id = sqrrl__alice.id()
        var bob_id = sqrrl__bob.id()
        var eng_id = sqrrl__eng.id()

        var sqrrl___temp_keep_alives = sqrrl___begin_init_from_json(sqrrl___world, dump)
        var sqrrl__alice2 = sqrrl___world.Employee.for_name("Alicia")
        var sqrrl__bob2 = sqrrl___world.Employee.for_name("Bob")
        var sqrrl__eng2 = sqrrl___world.Department.for_name("Engineering")

        if sqrrl__alice2.id() != alice_id:
            raise Error("id mismatch: alice")
        if sqrrl__bob2.id() != bob_id:
            raise Error("id mismatch: bob")
        if sqrrl__eng2.id() != eng_id:
            raise Error("id mismatch: eng")

        print(sqrrl__eng2._inner[]._sqrrl__members[0]._inner[]._name)
        print(sqrrl__eng2._inner[]._sqrrl__members[1]._inner[]._name)
        print(len(sqrrl__eng2._inner[]._sqrrl__backup))
        if sqrrl__eng2._inner[]._sqrrl__lead:
            print(sqrrl__eng2._inner[]._sqrrl__lead.value()._inner[].get_name())
        print(sqrrl__eng2._inner[]._tags[0], sqrrl__eng2._inner[]._tags[1])
        print(sqrrl__eng2._inner[]._sqrrl__scores[sqrrl__alice2])
        print(sqrrl__eng2._inner[]._sqrrl__leads["primary"]._inner[]._name)
        print(sqrrl__eng2._inner[]._groups[0][0], sqrrl__eng2._inner[]._groups[0][1], sqrrl__eng2._inner[]._groups[1][0])
        print(sqrrl__eng2._inner[]._ring[0], sqrrl__eng2._inner[]._ring[1])
        print(sqrrl__eng2._inner[]._grid["p"], sqrrl__eng2._inner[]._grid["q"])
        print(
            "reload OK: List/Set/Optional/Dict relations (key or value position), a nested"
            " List, and custom one- and two-argument containers all preserved"
        )
        sqrrl___end_init_from_json(sqrrl___temp_keep_alives^)
    finally:
        sqrrl___world.sqrrl__check_no_leaks()
