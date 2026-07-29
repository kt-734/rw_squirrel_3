from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl___init, sqrrl___World

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
        self._table[].indexes.name.add(self._id, self._name)

    @always_inline
    def get_name(self) -> ref [self._name] String:
        return self._name

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

    def count_for_name(self, value: String) -> Int:
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
    var _sqrrl__lead: sqrrl__Employee
    var _sqrrl__team: List[sqrrl__Employee]
    var _sqrrl__ranks: Dict[sqrrl__Employee, String]
    var _sqrrl__groups: List[List[sqrrl__Employee]]
    var _sqrrl__scores: Dict[String, sqrrl__Employee]
    var _sqrrl__rosters: List[Dict[String, sqrrl__Employee]]

    def __del__(deinit self):
        self._table[].indexes.name.remove(self._id, self._name)
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_name(mut self, v: String) raises:
        self._table[].indexes.name.check_unique(v, self._id)
        self._table[].indexes.name.remove(self._id, self._name)
        self._name = v
        self._table[].indexes.name.add(self._id, self._name)

    def set_sqrrl__lead(mut self, v: sqrrl__Employee):
        self._sqrrl__lead = v

    def set_sqrrl__team(mut self, var v: List[sqrrl__Employee]):
        self._sqrrl__team = v^

    def set_sqrrl__ranks(mut self, var v: Dict[sqrrl__Employee, String]):
        self._sqrrl__ranks = v^

    def set_sqrrl__groups(mut self, var v: List[List[sqrrl__Employee]]):
        self._sqrrl__groups = v^

    def set_sqrrl__scores(mut self, var v: Dict[String, sqrrl__Employee]):
        self._sqrrl__scores = v^

    def set_sqrrl__rosters(mut self, var v: List[Dict[String, sqrrl__Employee]]):
        self._sqrrl__rosters = v^

    @always_inline
    def get_name(self) -> ref [self._name] String:
        return self._name

    @always_inline
    def get_sqrrl__lead(self) -> ref [self._sqrrl__lead] sqrrl__Employee:
        return self._sqrrl__lead

    @always_inline
    def get_sqrrl__team(self) -> ref [self._sqrrl__team] List[sqrrl__Employee]:
        return self._sqrrl__team

    @always_inline
    def get_sqrrl__ranks(self) -> ref [self._sqrrl__ranks] Dict[sqrrl__Employee, String]:
        return self._sqrrl__ranks

    @always_inline
    def get_sqrrl__groups(self) -> ref [self._sqrrl__groups] List[List[sqrrl__Employee]]:
        return self._sqrrl__groups

    @always_inline
    def get_sqrrl__scores(self) -> ref [self._sqrrl__scores] Dict[String, sqrrl__Employee]:
        return self._sqrrl__scores

    @always_inline
    def get_sqrrl__rosters(self) -> ref [self._sqrrl__rosters] List[Dict[String, sqrrl__Employee]]:
        return self._sqrrl__rosters

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

    def lead_name(self) -> String:
        return self._inner[]._sqrrl__lead._inner[]._name

    def contains(self, sqrrl__e: sqrrl__Employee) -> Bool:
        for sqrrl__m in self._inner[]._sqrrl__team:
            if sqrrl__m == sqrrl__e:
                return True
        return False

    def greet_team(self, extra: List[sqrrl__Employee]) -> String:
        var out = String("")
        for sqrrl__m in self._inner[]._sqrrl__team:
            out += sqrrl__m._inner[]._name + " "
        for sqrrl__m in extra:
            out += sqrrl__m._inner[]._name + " "
        return String(out.strip())

    def promote_to_lead(self, sqrrl__e: sqrrl__Employee):
        self._inner[].set_sqrrl__lead(sqrrl__e);

    # -- methods: mandatory marking on a method's own name is gone -- a
    # bare method can return anything now, single relation or a
    # container of one, and stays bare either way. Its call is still
    # tracked project-wide (`ctx.bare_method_returns`, the same map a
    # bare top-level function's own call already goes through), so
    # bind-then-use, direct for-loop, and direct chain all still work
    # off it, no intermediate variable required (see main() below) --
    # only binding an entity-shaped result to a variable/loop var that's
    # meant to persist still needs `@@` on *that* name, same as it does
    # for a top-level function's call (see `scores_for`'s own call sites
    # below).
    def team_lead(self) -> sqrrl__Employee:
        return self._inner[]._sqrrl__lead

    def roster(self) -> List[sqrrl__Employee]:
        return self._inner[]._sqrrl__team.copy()

    # a value-position (second-argument) return works exactly the same
    # way -- direct indexing/chaining off the call works (see main()
    # below), but a for-loop over it would need a bare loop variable,
    # since iterating only ever yields the key
    def scores_by_role(self) -> Dict[String, sqrrl__Employee]:
        return self._inner[]._sqrrl__scores.copy()

    def headcount(self, mut sqrrl___world: sqrrl___World) raises -> String:
        return self._inner[]._name + ": " + String(sqrrl___world.Employee.count())

    def rename(self, mut sqrrl___world: sqrrl___World, new_name: String) raises:
        if sqrrl___world.Department.count() > 0:
            self._inner[].set_name(new_name);

struct sqrrl__DepartmentIndexes(Movable, ImplicitlyDeletable):
    var name: UniqueIndex[String]

    def __init__(out self):
        self.name = UniqueIndex[String]()

struct sqrrl__DepartmentTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__DepartmentIndexes, sqrrl__DepartmentInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__DepartmentIndexes, sqrrl__DepartmentInner](sqrrl__DepartmentIndexes()))

    def create(mut self, *, name: String, sqrrl__lead: sqrrl__Employee, var sqrrl__team: List[sqrrl__Employee], var sqrrl__ranks: Dict[sqrrl__Employee, String], var sqrrl__groups: List[List[sqrrl__Employee]], var sqrrl__scores: Dict[String, sqrrl__Employee], var sqrrl__rosters: List[Dict[String, sqrrl__Employee]]) raises -> sqrrl__Department:
        if self.storage[].indexes.name.contains(name):
            raise Error("UniqueConstraintViolation: 'name' already in use by another entity")
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__DepartmentInner(_id=id, _table=self.storage, _name=name, _sqrrl__lead=sqrrl__lead, _sqrrl__team=sqrrl__team^, _sqrrl__ranks=sqrrl__ranks^, _sqrrl__groups=sqrrl__groups^, _sqrrl__scores=sqrrl__scores^, _sqrrl__rosters=sqrrl__rosters^))
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

    def count_for_name(self, value: String) -> Int:
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
