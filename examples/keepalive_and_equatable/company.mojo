from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl__JsonSerializable, sqrrl__to_json
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl__init, sqrrl__World


@fieldwise_init
struct sqrrl__ProjectInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__ProjectIndexes, sqrrl__ProjectInner]]
    var _name: String

    def __del__(deinit self):
        self._table[].indexes.name.remove(self._id, self._name)
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_name(mut self, v: String) raises:
        self._table[].indexes.name.check_unique(v, self._id)
        self._table[].indexes.name.remove(self._id, self._name)
        self._name = v

    @always_inline
    def get_name(self) -> ref [self._name] String:
        return self._name


struct sqrrl__Project(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl__JsonSerializable):
    var _inner: ArcPointer[sqrrl__ProjectInner]

    def __init__(out self, var inner: sqrrl__ProjectInner):
        self._inner = ArcPointer(inner^)

    def __init__(out self, var inner: ArcPointer[sqrrl__ProjectInner]):
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

    def dont_keepalive(mut self) -> Bool:
        return self._inner[]._table[].keepalive_remove(self.id())


struct sqrrl__ProjectIndexes(Movable, ImplicitlyDeletable):
    var name: UniqueIndex[String]

    def __init__(out self):
        self.name = UniqueIndex[String]()


struct sqrrl__ProjectTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__ProjectIndexes, sqrrl__ProjectInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__ProjectIndexes, sqrrl__ProjectInner](sqrrl__ProjectIndexes()))

    def create(mut self, name: String) raises -> sqrrl__Project:
        if self.storage[].indexes.name.contains(name):
            raise Error("UniqueConstraintViolation: 'name' already in use by another entity")
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__ProjectInner(_id=id, _table=self.storage, _name=name))
        self.storage[].register_weak(id, inner)
        self.storage[].indexes.name.add(id, inner[]._name)
        self.storage[].keepalive_add(id, inner.copy())
        return sqrrl__Project(inner^)

    def all(self) -> Set[sqrrl__Project]:
        var out = Set[sqrrl__Project]()
        for id in self.storage[].all():
            out.add(sqrrl__Project(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

    def for_name(self, value: String) raises -> sqrrl__Project:
        var id = self.storage[].indexes.name.get_bwd(value)
        return sqrrl__Project(self.storage[].handle_for(id))

    def count_name(self, value: String) -> Int:
        return 1 if self.storage[].indexes.name.contains(value) else 0

    def group_by_name(self) -> Dict[String, sqrrl__Project]:
        ref ids = self.storage[].indexes.name.all_bwd()
        var out = Dict[String, sqrrl__Project]()
        for entry in ids.items():
            out[entry.key] = sqrrl__Project(self.storage[].handle_for(entry.value))
        return out^

    def distinct_name(self) -> Set[String]:
        var out = Set[String]()
        ref ids = self.storage[].indexes.name.all_bwd()
        for key in ids.keys():
            out.add(key.copy())
        return out^

@fieldwise_init
struct sqrrl__PersonInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__PersonIndexes, sqrrl__PersonInner]]
    var _name: String
    var _age: UInt32

    def __del__(deinit self):
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_name(mut self, v: String):
        self._name = v

    def set_age(mut self, v: UInt32):
        self._age = v

    @always_inline
    def get_name(self) -> ref [self._name] String:
        return self._name

    @always_inline
    def get_age(self) -> ref [self._age] UInt32:
        return self._age


struct sqrrl__Person(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl__JsonSerializable):
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

    def value_eq(self, other: Self) -> Bool:
        if self._inner[].get_name() != other._inner[].get_name():
            return False
        if self._inner[].get_age() != other._inner[].get_age():
            return False
        return True


struct sqrrl__PersonIndexes(Movable, ImplicitlyDeletable):
    def __init__(out self):
        pass


struct sqrrl__PersonTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__PersonIndexes, sqrrl__PersonInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__PersonIndexes, sqrrl__PersonInner](sqrrl__PersonIndexes()))

    def create(mut self, name: String, age: UInt32) -> sqrrl__Person:
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__PersonInner(_id=id, _table=self.storage, _name=name, _age=age))
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
        _ = sqrrl__world.Project.create(name = "Website Revamp")
        _ = sqrrl__world.Project.create(name = "Onboarding Redesign")
        print("all projects:", len(sqrrl__world.Project.all()))

        var sqrrl__handle = sqrrl__world.Project.for_name("Website Revamp")
        var released = sqrrl__handle.dont_keepalive()
        print("released website revamp:", released)

        var sqrrl__alice = sqrrl__world.Person.create(name = "alice", age = 30)
        var sqrrl__alice_twin = sqrrl__world.Person.create(name = "alice", age = 30)
        var sqrrl__bob = sqrrl__world.Person.create(name = "bob", age = 25)

        print("alice equals alice_twin (value):", sqrrl__alice.value_eq(sqrrl__alice_twin))
        print("alice equals bob (value):", sqrrl__alice.value_eq(sqrrl__bob))
        print("alice equals alice_twin (identity):", sqrrl__alice == sqrrl__alice_twin)
    finally:
        sqrrl__world.sqrrl__check_no_leaks()
