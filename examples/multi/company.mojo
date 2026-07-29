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
        var sqrrl__website = sqrrl___world.Project.create(name = "Website")
        var sqrrl__app = sqrrl___world.Project.create(name = "App")
        var sqrrl__eng = sqrrl___world.Department.create(name = "Engineering", sqrrl__projects = Set(sqrrl__website, sqrrl__app))
        var sqrrl__sales = sqrrl___world.Department.create(name = "Sales", sqrrl__projects = Set(sqrrl__website))

        print("eng has", len(sqrrl__eng._inner[]._sqrrl__projects), "projects")
        print("website is used by", len(sqrrl___world.Department.for_sqrrl__projects(sqrrl__website)), "departments")

        _ = sqrrl__eng._inner[].remove_from_sqrrl__projects(sqrrl__app)
        print("eng has", len(sqrrl__eng._inner[]._sqrrl__projects), "projects after removal")
        print("app is used by", len(sqrrl___world.Department.for_sqrrl__projects(sqrrl__app)), "departments after removal")

        print("website users:", len(sqrrl___world.Department.for_sqrrl__projects(sqrrl__website)))

        sqrrl__sales._inner[].set_sqrrl__projects(Set(sqrrl__app));
        print("website users after sales switches to app:", len(sqrrl___world.Department.for_sqrrl__projects(sqrrl__website)))
        print("app users after sales switches to app:", len(sqrrl___world.Department.for_sqrrl__projects(sqrrl__app)))
        print("sales projects:", len(sqrrl__sales._inner[]._sqrrl__projects), "eng projects:", len(sqrrl__eng._inner[]._sqrrl__projects))
    finally:
        sqrrl___world.sqrrl__check_no_leaks()
