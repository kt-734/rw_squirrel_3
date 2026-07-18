from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl__JsonSerializable, sqrrl__to_json
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl__init, sqrrl__World


trait HasId:
    def entity_id(self) -> UInt32:
        ...


def print_entity_id[T: HasId](x: T):
    print("id:", x.entity_id())


def sqrrl__greet_everyone(mut sqrrl__world: sqrrl__World) raises -> String:
    var out = String("")
    for sqrrl__p in  sqrrl__world.Person.all():
        out += sqrrl__p._inner[]._name + " "
    return out


@fieldwise_init
struct sqrrl__PersonInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__PersonIndexes, sqrrl__PersonInner]]
    var _name: String

    def __del__(deinit self):
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_name(mut self, v: String):
        self._name = v

    @always_inline
    def get_name(self) -> ref [self._name] String:
        return self._name


struct sqrrl__Person(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl__JsonSerializable, HasId):
    var _inner: ArcPointer[sqrrl__PersonInner]

    def __init__(out self, var inner: sqrrl__PersonInner):
        self._inner = ArcPointer(inner^)

    def __init__(out self, var inner: ArcPointer[sqrrl__PersonInner]):
        self._inner = inner^

    def id(self) -> UInt32:
        return self._inner[]._id

    def ref_count(self) -> Int:
        return Int(self._inner.count())

    def __hash__[H: Hasher](self, mut hasher: H):
        hasher.update(self.id())

    def __eq__(self, other: Self) -> Bool:
        return self.id() == other.id()

    def __ne__(self, other: Self) -> Bool:
        return self.id() != other.id()

    def sqrrl__to_json(self) -> String:
        return String(self.id())

    def entity_id(self) -> UInt32:
        return self.id()

    def greeting(self, mut sqrrl__world: sqrrl__World) -> String:
        return "Hello, " + self._inner[]._name + "! Total people: " + String(sqrrl__world.Person.count())




struct sqrrl__PersonIndexes(Movable, ImplicitlyDeletable):
    def __init__(out self):
        pass


struct sqrrl__PersonTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__PersonIndexes, sqrrl__PersonInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__PersonIndexes, sqrrl__PersonInner](sqrrl__PersonIndexes()))

    def create(mut self, name: String) -> sqrrl__Person:
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__PersonInner(_id=id, _table=self.storage, _name=name))
        self.storage[].register_weak(id, inner)
        return sqrrl__Person(inner^)

    def all(self) -> Set[sqrrl__Person]:
        var out = Set[sqrrl__Person]()
        for id in self.storage[].all():
            out.add(sqrrl__Person(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

def main() raises:
    var sqrrl__world = sqrrl__init()
    try:
        var sqrrl__alice = sqrrl__world.Person.create(name = "alice")
        var sqrrl__bob = sqrrl__world.Person.create(name = "bob")

        print(sqrrl__alice.greeting(sqrrl__world))
        print(sqrrl__bob.greeting(sqrrl__world))

        print("direct call:", sqrrl__alice.entity_id())
        print_entity_id(sqrrl__alice)
        print_entity_id(sqrrl__bob)

        print("top-level @@@ function:", sqrrl__greet_everyone(sqrrl__world))
        print("count:", sqrrl__world.Person.count(), sqrrl__alice._inner[]._name, sqrrl__bob._inner[]._name)
    finally:
        sqrrl__world.sqrrl__check_no_leaks()
