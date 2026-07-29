from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl___JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl___init, sqrrl___World
from sqrrl__json import sqrrl___begin_init_from_json, sqrrl___end_init_from_json, sqrrl___init_from_json, sqrrl___world_to_json

def main() raises:
    var sqrrl___world = sqrrl___init()
    try:
        var sqrrl__website = sqrrl___world.Project.create(name = "Website")
        var sqrrl__app = sqrrl___world.Project.create(name = "App")
        var sqrrl__eng = sqrrl___world.Department.create(name = "Engineering", sqrrl__projects = Set(sqrrl__website, sqrrl__app))
        var sqrrl__t1 = sqrrl___world.Tag.create(label = "urgent")

        var dump = sqrrl___world_to_json(sqrrl___world)
        print("dump:", dump)

        # Captured after to_json() -- these calls are each variable's true
        # last use, so ASAP destruction doesn't free them until here, well
        # after to_json() has already walked every table (see the project's
        # own documented ASAP-destruction-vs-weakly-referenced-entities
        # pitfall: capturing these ids *before* to_json() would make that
        # capture their true last use instead, destroying them -- and
        # emptying every table -- before to_json() ever ran).
        var website_id = sqrrl__website.id()
        var app_id = sqrrl__app.id()
        var eng_id = sqrrl__eng.id()
        var t1_id = sqrrl__t1.id()

        var sqrrl___temp_keep_alives = sqrrl___begin_init_from_json(sqrrl___world, dump)
        var sqrrl__website2 = sqrrl___world.Project.for_name("Website")
        var sqrrl__app2 = sqrrl___world.Project.for_name("App")
        var sqrrl__eng2 = sqrrl___world.Department.for_name("Engineering")
        var sqrrl__t1_2 = sqrrl___world.Tag.for_label("urgent")

        if sqrrl__website2.id() != website_id:
            raise Error("id mismatch: website")
        if sqrrl__app2.id() != app_id:
            raise Error("id mismatch: app")
        if sqrrl__eng2.id() != eng_id:
            raise Error("id mismatch: eng")
        if sqrrl__t1_2.id() != t1_id:
            raise Error("id mismatch: t1")

        var sqrrl__members = sqrrl___world.Department.for_sqrrl__projects(sqrrl__website2)
        if len(sqrrl__members) != 1:
            raise Error("reloaded multi index broken: website2 membership")

        print("reload OK: ids preserved, multi index intact")
        sqrrl___end_init_from_json(sqrrl___temp_keep_alives^)
    finally:
        sqrrl___world.sqrrl__check_no_leaks()
