from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl__init, sqrrl__World


@fieldwise_init
struct sqrrl__DepartmentInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__DepartmentIndexes, sqrrl__DepartmentInner]]
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


struct sqrrl__Department(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable):
    var _inner: ArcPointer[sqrrl__DepartmentInner]

    def __init__(out self, var inner: sqrrl__DepartmentInner):
        self._inner = ArcPointer(inner^)

    def __init__(out self, var inner: ArcPointer[sqrrl__DepartmentInner]):
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



struct sqrrl__DepartmentIndexes(Movable, ImplicitlyDeletable):
    var name: UniqueIndex[String]

    def __init__(out self):
        self.name = UniqueIndex[String]()


struct sqrrl__DepartmentTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__DepartmentIndexes, sqrrl__DepartmentInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__DepartmentIndexes, sqrrl__DepartmentInner](sqrrl__DepartmentIndexes()))

    def create(mut self, *, name: String) raises -> sqrrl__Department:
        if self.storage[].indexes.name.contains(name):
            raise Error("UniqueConstraintViolation: 'name' already in use by another entity")
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__DepartmentInner(_id=id, _table=self.storage, _name=name))
        self.storage[].register_weak(id, inner)
        self.storage[].indexes.name.add(id, inner[]._name)
        return sqrrl__Department(inner^)

    def all(self) -> Set[sqrrl__Department]:
        var out = Set[sqrrl__Department]()
        for id in self.storage[].all():
            out.add(sqrrl__Department(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

    def for_name(self, value: String) raises -> sqrrl__Department:
        var id = self.storage[].indexes.name.get_bwd(value)
        return sqrrl__Department(self.storage[].handle_for(id))

    def count_name(self, value: String) -> Int:
        return 1 if self.storage[].indexes.name.contains(value) else 0

    def group_by_name(self) -> Dict[String, sqrrl__Department]:
        ref ids = self.storage[].indexes.name.all_bwd()
        var out = Dict[String, sqrrl__Department]()
        for entry in ids.items():
            out[entry.key] = sqrrl__Department(self.storage[].handle_for(entry.value))
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
    var _sqrrl__dept: sqrrl__Department

    def __del__(deinit self):
        self._table[].indexes.name.remove(self._id, self._name)
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_name(mut self, v: String):
        self._table[].indexes.name.remove(self._id, self._name)
        self._name = v
        self._table[].indexes.name.add(self._id, self._name)

    def set_age(mut self, v: UInt32):
        self._age = v

    def set_sqrrl__dept(mut self, v: sqrrl__Department):
        self._sqrrl__dept = v

    @always_inline
    def get_name(self) -> ref [self._name] String:
        return self._name

    @always_inline
    def get_age(self) -> ref [self._age] UInt32:
        return self._age

    @always_inline
    def get_sqrrl__dept(self) -> ref [self._sqrrl__dept] sqrrl__Department:
        return self._sqrrl__dept


struct sqrrl__Person(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable):
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



struct sqrrl__PersonIndexes(Movable, ImplicitlyDeletable):
    var name: PlainIndex[String]

    def __init__(out self):
        self.name = PlainIndex[String]()


struct sqrrl__PersonTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__PersonIndexes, sqrrl__PersonInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__PersonIndexes, sqrrl__PersonInner](sqrrl__PersonIndexes()))

    def create(mut self, *, name: String, age: UInt32, sqrrl__dept: sqrrl__Department) -> sqrrl__Person:
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__PersonInner(_id=id, _table=self.storage, _name=name, _age=age, _sqrrl__dept=sqrrl__dept))
        self.storage[].register_weak(id, inner)
        self.storage[].indexes.name.add(id, inner[]._name)
        return sqrrl__Person(inner^)

    def all(self) -> Set[sqrrl__Person]:
        var out = Set[sqrrl__Person]()
        for id in self.storage[].all():
            out.add(sqrrl__Person(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

    def for_name(self, value: String) -> Set[sqrrl__Person]:
        var out = Set[sqrrl__Person]()
        for id in self.storage[].indexes.name.get_bwd(value):
            out.add(sqrrl__Person(self.storage[].handle_for(id)))
        return out^

    def count_name(self, value: String) -> Int:
        return len(self.storage[].indexes.name.get_bwd(value))

    def group_by_name(self) -> Dict[String, Set[sqrrl__Person]]:
        ref buckets = self.storage[].indexes.name.all_bwd()
        var out = Dict[String, Set[sqrrl__Person]]()
        for entry in buckets.items():
            var handles = Set[sqrrl__Person]()
            for id in entry.value:
                handles.add(sqrrl__Person(self.storage[].handle_for(id)))
            out[entry.key] = handles^
        return out^

    def count_by_name(self) -> Dict[String, Int]:
        ref buckets = self.storage[].indexes.name.all_bwd()
        var out = Dict[String, Int]()
        for entry in buckets.items():
            out[entry.key] = len(entry.value)
        return out^

    def distinct_name(self) -> Set[String]:
        var out = Set[String]()
        ref buckets = self.storage[].indexes.name.all_bwd()
        for key in buckets.keys():
            out.add(key.copy())
        return out^

def main() raises:
    var sqrrl__world = sqrrl__init()
    try:
        var sqrrl__eng = sqrrl__world.Department.create(name = "Engineering")
        var sqrrl__alice = sqrrl__world.Person.create(name = "alice", age = 30, sqrrl__dept = sqrrl__eng)
        var sqrrl__bob = sqrrl__world.Person.create(name = "bob", age = 25, sqrrl__dept = sqrrl__eng)
        sqrrl__alice._inner[].set_age(31);
        print(sqrrl__alice._inner[]._name, sqrrl__alice._inner[]._age, sqrrl__alice._inner[]._sqrrl__dept._inner[]._name)

        var sqrrl__team = sqrrl__world.Person.for_name("alice")
        print("found by index:", len(sqrrl__team))

        print("count:", sqrrl__world.Person.count(), sqrrl__alice._inner[]._name, sqrrl__bob._inner[]._name)
    finally:
        sqrrl__world.sqrrl__check_no_leaks()
