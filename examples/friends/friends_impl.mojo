from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort

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

@fieldwise_init
struct sqrrl__GroupInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__GroupIndexes, sqrrl__GroupInner]]
    var _sqrrl__members: Set[sqrrl__Person]

    def __del__(deinit self):
        self._table[].indexes.members.remove_many(self._id, self._sqrrl__members)
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_sqrrl__members(mut self, var v: Set[sqrrl__Person]):
        self._table[].indexes.members.remove_many(self._id, self._sqrrl__members)
        self._sqrrl__members = v^
        self._table[].indexes.members.add_many(self._id, self._sqrrl__members)

    def add_to_sqrrl__members(mut self, value: sqrrl__Person) -> Bool:
        if value in self._sqrrl__members:
            return False
        self._sqrrl__members.add(value)
        self._table[].indexes.members.add(self._id, value)
        return True

    def remove_from_sqrrl__members(mut self, value: sqrrl__Person) -> Bool:
        try:
            self._sqrrl__members.remove(value)
        except:
            return False
        self._table[].indexes.members.remove(self._id, value)
        return True

    @always_inline
    def get_sqrrl__members(self) -> ref [self._sqrrl__members] Set[sqrrl__Person]:
        return self._sqrrl__members

struct sqrrl__Group(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable):
    var _inner: ArcPointer[sqrrl__GroupInner]

    def __init__(out self, var inner: sqrrl__GroupInner):
        self._inner = ArcPointer(inner^)

    def __init__(out self, var inner: ArcPointer[sqrrl__GroupInner]):
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

    def dont_keepalive(mut self) -> Bool:
        return self._inner[]._table[].keepalive_remove(self.id())

struct sqrrl__GroupIndexes(Movable, ImplicitlyDeletable):
    var members: MultiIndex[sqrrl__Person]

    def __init__(out self):
        self.members = MultiIndex[sqrrl__Person]()

struct sqrrl__GroupTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__GroupIndexes, sqrrl__GroupInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__GroupIndexes, sqrrl__GroupInner](sqrrl__GroupIndexes()))

    def create(mut self, *, var sqrrl__members: Set[sqrrl__Person] = Set[sqrrl__Person]()) -> sqrrl__Group:
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__GroupInner(_id=id, _table=self.storage, _sqrrl__members=sqrrl__members^))
        self.storage[].register_weak(id, inner)
        self.storage[].indexes.members.add_many(id, inner[]._sqrrl__members)
        self.storage[].keepalive_add(id, inner.copy())
        return sqrrl__Group(inner^)

    def all(self) -> Set[sqrrl__Group]:
        var out = Set[sqrrl__Group]()
        for id in self.storage[].all():
            out.add(sqrrl__Group(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

    def for_sqrrl__members(self, value: sqrrl__Person) -> Set[sqrrl__Group]:
        var out = Set[sqrrl__Group]()
        for id in self.storage[].indexes.members.get_bwd(value):
            out.add(sqrrl__Group(self.storage[].handle_for(id)))
        return out^

    def count_for_sqrrl__members(self, value: sqrrl__Person) -> Int:
        return len(self.storage[].indexes.members.get_bwd(value))

    def group_by_sqrrl__members(self) -> Dict[sqrrl__Person, Set[sqrrl__Group]]:
        ref buckets = self.storage[].indexes.members.all_bwd()
        var out = Dict[sqrrl__Person, Set[sqrrl__Group]]()
        for entry in buckets.items():
            var handles = Set[sqrrl__Group]()
            for id in entry.value:
                handles.add(sqrrl__Group(self.storage[].handle_for(id)))
            out[entry.key] = handles^
        return out^

    def count_by_sqrrl__members(self) -> Dict[sqrrl__Person, Int]:
        ref buckets = self.storage[].indexes.members.all_bwd()
        var out = Dict[sqrrl__Person, Int]()
        for entry in buckets.items():
            out[entry.key] = len(entry.value)
        return out^

    def distinct_sqrrl__members(self) -> Set[sqrrl__Person]:
        var out = Set[sqrrl__Person]()
        ref buckets = self.storage[].indexes.members.all_bwd()
        for key in buckets.keys():
            out.add(key.copy())
        return out^
