from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl___init, sqrrl___World
from schema.department import sqrrl__Department


@fieldwise_init
struct sqrrl__EmployeeInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__EmployeeIndexes, sqrrl__EmployeeInner]]
    var _name: String
    var _sqrrl__dept: sqrrl__Department

    def __del__(deinit self):
        self._table[].indexes.name.remove(self._id, self._name)
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_name(mut self, v: String):
        self._table[].indexes.name.remove(self._id, self._name)
        self._name = v
        self._table[].indexes.name.add(self._id, self._name)

    def set_sqrrl__dept(mut self, v: sqrrl__Department):
        self._sqrrl__dept = v

    @always_inline
    def get_name(self) -> ref [self._name] String:
        return self._name

    @always_inline
    def get_sqrrl__dept(self) -> ref [self._sqrrl__dept] sqrrl__Department:
        return self._sqrrl__dept


struct sqrrl__Employee(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable):
    var _inner: ArcPointer[sqrrl__EmployeeInner]

    def __init__(out self, var inner: sqrrl__EmployeeInner):
        self._inner = ArcPointer(inner^)

    def __init__(out self, var inner: ArcPointer[sqrrl__EmployeeInner]):
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



struct sqrrl__EmployeeIndexes(Movable, ImplicitlyDeletable):
    var name: PlainIndex[String]

    def __init__(out self):
        self.name = PlainIndex[String]()


struct sqrrl__EmployeeTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__EmployeeIndexes, sqrrl__EmployeeInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__EmployeeIndexes, sqrrl__EmployeeInner](sqrrl__EmployeeIndexes()))

    def create(mut self, *, name: String, sqrrl__dept: sqrrl__Department) -> sqrrl__Employee:
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__EmployeeInner(_id=id, _table=self.storage, _name=name, _sqrrl__dept=sqrrl__dept))
        self.storage[].register_weak(id, inner)
        self.storage[].indexes.name.add(id, inner[]._name)
        return sqrrl__Employee(inner^)

    def all(self) -> Set[sqrrl__Employee]:
        var out = Set[sqrrl__Employee]()
        for id in self.storage[].all():
            out.add(sqrrl__Employee(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

    def for_name(self, value: String) -> Set[sqrrl__Employee]:
        var out = Set[sqrrl__Employee]()
        for id in self.storage[].indexes.name.get_bwd(value):
            out.add(sqrrl__Employee(self.storage[].handle_for(id)))
        return out^

    def count_name(self, value: String) -> Int:
        return len(self.storage[].indexes.name.get_bwd(value))

    def group_by_name(self) -> Dict[String, Set[sqrrl__Employee]]:
        ref buckets = self.storage[].indexes.name.all_bwd()
        var out = Dict[String, Set[sqrrl__Employee]]()
        for entry in buckets.items():
            var handles = Set[sqrrl__Employee]()
            for id in entry.value:
                handles.add(sqrrl__Employee(self.storage[].handle_for(id)))
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
