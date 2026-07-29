from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl___init, sqrrl___World

trait HasId:
    def entity_id(self) -> UInt32:
        ...

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

struct sqrrl__Person(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, HasId):
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

    def entity_id(self) -> UInt32:
        return self.id()

    def greeting(self, mut sqrrl___world: sqrrl___World) -> String:
        return "Hello, " + self._inner[]._name + "! Total people: " + String(sqrrl___world.Person.count())

struct sqrrl__PersonIndexes(Movable, ImplicitlyDeletable):
    def __init__(out self):
        pass

struct sqrrl__PersonTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__PersonIndexes, sqrrl__PersonInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__PersonIndexes, sqrrl__PersonInner](sqrrl__PersonIndexes()))

    def create(mut self, *, name: String) -> sqrrl__Person:
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
