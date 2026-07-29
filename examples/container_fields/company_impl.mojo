from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl___JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort

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
        self._table[].indexes.name.add(self._id, self._name)

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
        self._table[].indexes.name.add(self._id, self._name)

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
