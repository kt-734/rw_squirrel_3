from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl___JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from schema.project import sqrrl__Project
from schema.vendor import sqrrl__Vendor


@fieldwise_init
struct sqrrl__DepartmentInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__DepartmentIndexes, sqrrl__DepartmentInner]]
    var _name: String
    var _tags: List[String]
    var _sqrrl__projects: Set[sqrrl__Project]
    var _sqrrl__vendors: Set[sqrrl__Vendor]
    var _skills: Set[String]

    def __del__(deinit self):
        self._table[].indexes.projects.remove_many(self._id, self._sqrrl__projects)
        self._table[].indexes.skills.remove_many(self._id, self._skills)
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_name(mut self, v: String):
        self._name = v

    def set_tags(mut self, var v: List[String]):
        self._tags = v^

    def set_sqrrl__projects(mut self, var v: Set[sqrrl__Project]):
        self._table[].indexes.projects.remove_many(self._id, self._sqrrl__projects)
        self._sqrrl__projects = v^
        self._table[].indexes.projects.add_many(self._id, self._sqrrl__projects)

    def add_to_sqrrl__projects(mut self, value: sqrrl__Project) -> Bool:
        if value in self._sqrrl__projects:
            return False
        self._sqrrl__projects.add(value)
        self._table[].indexes.projects.add(self._id, value)
        return True

    def remove_from_sqrrl__projects(mut self, value: sqrrl__Project) -> Bool:
        try:
            self._sqrrl__projects.remove(value)
        except:
            return False
        self._table[].indexes.projects.remove(self._id, value)
        return True

    def set_sqrrl__vendors(mut self, var v: Set[sqrrl__Vendor]):
        self._sqrrl__vendors = v^

    def set_skills(mut self, var v: Set[String]):
        self._table[].indexes.skills.remove_many(self._id, self._skills)
        self._skills = v^
        self._table[].indexes.skills.add_many(self._id, self._skills)

    def add_to_skills(mut self, value: String) -> Bool:
        if value in self._skills:
            return False
        self._skills.add(value)
        self._table[].indexes.skills.add(self._id, value)
        return True

    def remove_from_skills(mut self, value: String) -> Bool:
        try:
            self._skills.remove(value)
        except:
            return False
        self._table[].indexes.skills.remove(self._id, value)
        return True

    @always_inline
    def get_name(self) -> ref [self._name] String:
        return self._name

    @always_inline
    def get_tags(self) -> ref [self._tags] List[String]:
        return self._tags

    @always_inline
    def get_sqrrl__projects(self) -> ref [self._sqrrl__projects] Set[sqrrl__Project]:
        return self._sqrrl__projects

    @always_inline
    def get_sqrrl__vendors(self) -> ref [self._sqrrl__vendors] Set[sqrrl__Vendor]:
        return self._sqrrl__vendors

    @always_inline
    def get_skills(self) -> ref [self._skills] Set[String]:
        return self._skills


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

    def value_eq(self, other: Self) -> Bool:
        if self._inner[].get_name() != other._inner[].get_name():
            return False
        if self._inner[].get_tags() != other._inner[].get_tags():
            return False
        if self._inner[].get_sqrrl__projects() != other._inner[].get_sqrrl__projects():
            return False
        if self._inner[].get_sqrrl__vendors() != other._inner[].get_sqrrl__vendors():
            return False
        if self._inner[].get_skills() != other._inner[].get_skills():
            return False
        return True


struct sqrrl__DepartmentIndexes(Movable, ImplicitlyDeletable):
    var projects: MultiIndex[sqrrl__Project]
    var skills: MultiIndex[String]

    def __init__(out self):
        self.projects = MultiIndex[sqrrl__Project]()
        self.skills = MultiIndex[String]()


struct sqrrl__DepartmentTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__DepartmentIndexes, sqrrl__DepartmentInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__DepartmentIndexes, sqrrl__DepartmentInner](sqrrl__DepartmentIndexes()))

    def create(mut self, *, name: String, var tags: List[String], var sqrrl__projects: Set[sqrrl__Project] = Set[sqrrl__Project](), var sqrrl__vendors: Set[sqrrl__Vendor], var skills: Set[String] = Set[String]()) -> sqrrl__Department:
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__DepartmentInner(_id=id, _table=self.storage, _name=name, _tags=tags^, _sqrrl__projects=sqrrl__projects^, _sqrrl__vendors=sqrrl__vendors^, _skills=skills^))
        self.storage[].register_weak(id, inner)
        self.storage[].indexes.projects.add_many(id, inner[]._sqrrl__projects)
        self.storage[].indexes.skills.add_many(id, inner[]._skills)
        return sqrrl__Department(inner^)

    def all(self) -> Set[sqrrl__Department]:
        var out = Set[sqrrl__Department]()
        for id in self.storage[].all():
            out.add(sqrrl__Department(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

    def for_sqrrl__projects(self, value: sqrrl__Project) -> Set[sqrrl__Department]:
        var out = Set[sqrrl__Department]()
        for id in self.storage[].indexes.projects.get_bwd(value):
            out.add(sqrrl__Department(self.storage[].handle_for(id)))
        return out^

    def for_skills(self, value: String) -> Set[sqrrl__Department]:
        var out = Set[sqrrl__Department]()
        for id in self.storage[].indexes.skills.get_bwd(value):
            out.add(sqrrl__Department(self.storage[].handle_for(id)))
        return out^

    def count_sqrrl__projects(self, value: sqrrl__Project) -> Int:
        return len(self.storage[].indexes.projects.get_bwd(value))

    def group_by_sqrrl__projects(self) -> Dict[sqrrl__Project, Set[sqrrl__Department]]:
        ref buckets = self.storage[].indexes.projects.all_bwd()
        var out = Dict[sqrrl__Project, Set[sqrrl__Department]]()
        for entry in buckets.items():
            var handles = Set[sqrrl__Department]()
            for id in entry.value:
                handles.add(sqrrl__Department(self.storage[].handle_for(id)))
            out[entry.key] = handles^
        return out^

    def count_by_sqrrl__projects(self) -> Dict[sqrrl__Project, Int]:
        ref buckets = self.storage[].indexes.projects.all_bwd()
        var out = Dict[sqrrl__Project, Int]()
        for entry in buckets.items():
            out[entry.key] = len(entry.value)
        return out^

    def distinct_sqrrl__projects(self) -> Set[sqrrl__Project]:
        var out = Set[sqrrl__Project]()
        ref buckets = self.storage[].indexes.projects.all_bwd()
        for key in buckets.keys():
            out.add(key.copy())
        return out^

    def count_skills(self, value: String) -> Int:
        return len(self.storage[].indexes.skills.get_bwd(value))

    def group_by_skills(self) -> Dict[String, Set[sqrrl__Department]]:
        ref buckets = self.storage[].indexes.skills.all_bwd()
        var out = Dict[String, Set[sqrrl__Department]]()
        for entry in buckets.items():
            var handles = Set[sqrrl__Department]()
            for id in entry.value:
                handles.add(sqrrl__Department(self.storage[].handle_for(id)))
            out[entry.key] = handles^
        return out^

    def count_by_skills(self) -> Dict[String, Int]:
        ref buckets = self.storage[].indexes.skills.all_bwd()
        var out = Dict[String, Int]()
        for entry in buckets.items():
            out[entry.key] = len(entry.value)
        return out^

    def distinct_skills(self) -> Set[String]:
        var out = Set[String]()
        ref buckets = self.storage[].indexes.skills.all_bwd()
        for key in buckets.keys():
            out.add(key.copy())
        return out^

