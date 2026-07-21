from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl___JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl___init, sqrrl___World
from sqrrl__json import sqrrl___begin_init_from_json, sqrrl___end_init_from_json, sqrrl___init_from_json, sqrrl___world_to_json


from ring_module import Ring
from grid_module import Grid

@fieldwise_init
struct sqrrl__EmployeeInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__EmployeeIndexes, sqrrl__EmployeeInner]]
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


struct sqrrl__Employee(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl___JsonSerializable):
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

    def sqrrl__to_json(self) -> String:
        return String(self.id())


struct sqrrl__EmployeeIndexes(Movable, ImplicitlyDeletable):
    var name: UniqueIndex[String]

    def __init__(out self):
        self.name = UniqueIndex[String]()


struct sqrrl__EmployeeTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__EmployeeIndexes, sqrrl__EmployeeInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__EmployeeIndexes, sqrrl__EmployeeInner](sqrrl__EmployeeIndexes()))

    def create(mut self, *, name: String) raises -> sqrrl__Employee:
        if self.storage[].indexes.name.contains(name):
            raise Error("UniqueConstraintViolation: 'name' already in use by another entity")
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__EmployeeInner(_id=id, _table=self.storage, _name=name))
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

    def for_name(self, value: String) raises -> sqrrl__Employee:
        var id = self.storage[].indexes.name.get_bwd(value)
        return sqrrl__Employee(self.storage[].handle_for(id))

    def count_name(self, value: String) -> Int:
        return 1 if self.storage[].indexes.name.contains(value) else 0

    def group_by_name(self) -> Dict[String, sqrrl__Employee]:
        ref ids = self.storage[].indexes.name.all_bwd()
        var out = Dict[String, sqrrl__Employee]()
        for entry in ids.items():
            out[entry.key] = sqrrl__Employee(self.storage[].handle_for(entry.value))
        return out^

    def distinct_name(self) -> Set[String]:
        var out = Set[String]()
        ref ids = self.storage[].indexes.name.all_bwd()
        for key in ids.keys():
            out.add(key.copy())
        return out^

@fieldwise_init
struct sqrrl__DepartmentInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__DepartmentIndexes, sqrrl__DepartmentInner]]
    var _name: String
    var _sqrrl__members: List[sqrrl__Employee]
    var _sqrrl__backup: Set[sqrrl__Employee]
    var _sqrrl__lead: Optional[sqrrl__Employee]
    var _tags: List[String]
    var _sqrrl__scores: Dict[sqrrl__Employee, String]
    var _sqrrl__leads: Dict[String, sqrrl__Employee]
    var _groups: List[List[String]]
    var _ring: Ring[String]
    var _grid: Grid[String, Int]

    def __del__(deinit self):
        self._table[].indexes.name.remove(self._id, self._name)
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_name(mut self, v: String) raises:
        self._table[].indexes.name.check_unique(v, self._id)
        self._table[].indexes.name.remove(self._id, self._name)
        self._name = v

    def set_sqrrl__members(mut self, var v: List[sqrrl__Employee]):
        self._sqrrl__members = v^

    def set_sqrrl__backup(mut self, var v: Set[sqrrl__Employee]):
        self._sqrrl__backup = v^

    def set_sqrrl__lead(mut self, var v: Optional[sqrrl__Employee]):
        self._sqrrl__lead = v^

    def set_tags(mut self, var v: List[String]):
        self._tags = v^

    def set_sqrrl__scores(mut self, var v: Dict[sqrrl__Employee, String]):
        self._sqrrl__scores = v^

    def set_sqrrl__leads(mut self, var v: Dict[String, sqrrl__Employee]):
        self._sqrrl__leads = v^

    def set_groups(mut self, var v: List[List[String]]):
        self._groups = v^

    def set_ring(mut self, var v: Ring[String]):
        self._ring = v^

    def set_grid(mut self, var v: Grid[String, Int]):
        self._grid = v^

    @always_inline
    def get_name(self) -> ref [self._name] String:
        return self._name

    @always_inline
    def get_sqrrl__members(self) -> ref [self._sqrrl__members] List[sqrrl__Employee]:
        return self._sqrrl__members

    @always_inline
    def get_sqrrl__backup(self) -> ref [self._sqrrl__backup] Set[sqrrl__Employee]:
        return self._sqrrl__backup

    @always_inline
    def get_sqrrl__lead(self) -> ref [self._sqrrl__lead] Optional[sqrrl__Employee]:
        return self._sqrrl__lead

    @always_inline
    def get_tags(self) -> ref [self._tags] List[String]:
        return self._tags

    @always_inline
    def get_sqrrl__scores(self) -> ref [self._sqrrl__scores] Dict[sqrrl__Employee, String]:
        return self._sqrrl__scores

    @always_inline
    def get_sqrrl__leads(self) -> ref [self._sqrrl__leads] Dict[String, sqrrl__Employee]:
        return self._sqrrl__leads

    @always_inline
    def get_groups(self) -> ref [self._groups] List[List[String]]:
        return self._groups

    @always_inline
    def get_ring(self) -> ref [self._ring] Ring[String]:
        return self._ring

    @always_inline
    def get_grid(self) -> ref [self._grid] Grid[String, Int]:
        return self._grid


struct sqrrl__Department(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl___JsonSerializable):
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

    def sqrrl__to_json(self) -> String:
        return String(self.id())


struct sqrrl__DepartmentIndexes(Movable, ImplicitlyDeletable):
    var name: UniqueIndex[String]

    def __init__(out self):
        self.name = UniqueIndex[String]()


struct sqrrl__DepartmentTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__DepartmentIndexes, sqrrl__DepartmentInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__DepartmentIndexes, sqrrl__DepartmentInner](sqrrl__DepartmentIndexes()))

    def create(mut self, *, name: String, var sqrrl__members: List[sqrrl__Employee], var sqrrl__backup: Set[sqrrl__Employee], var sqrrl__lead: Optional[sqrrl__Employee], var tags: List[String], var sqrrl__scores: Dict[sqrrl__Employee, String], var sqrrl__leads: Dict[String, sqrrl__Employee], var groups: List[List[String]], var ring: Ring[String], var grid: Grid[String, Int]) raises -> sqrrl__Department:
        if self.storage[].indexes.name.contains(name):
            raise Error("UniqueConstraintViolation: 'name' already in use by another entity")
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__DepartmentInner(_id=id, _table=self.storage, _name=name, _sqrrl__members=sqrrl__members^, _sqrrl__backup=sqrrl__backup^, _sqrrl__lead=sqrrl__lead^, _tags=tags^, _sqrrl__scores=sqrrl__scores^, _sqrrl__leads=sqrrl__leads^, _groups=groups^, _ring=ring^, _grid=grid^))
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

def main() raises:
    var sqrrl___world = sqrrl___init()
    try:
        var sqrrl__alice = sqrrl___world.Employee.create(name = "Alice")
        var sqrrl__bob = sqrrl___world.Employee.create(name = "Bob")
        var scores_dict = Dict[sqrrl__Employee, String]()
        scores_dict[sqrrl__alice] = "lead"
        scores_dict[sqrrl__bob] = "member"
        var leads_dict = Dict[String, sqrrl__Employee]()
        leads_dict["primary"] = sqrrl__alice
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
