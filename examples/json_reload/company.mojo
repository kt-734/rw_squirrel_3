from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl___JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl___init, sqrrl___World
from sqrrl__json import sqrrl___begin_init_from_json, sqrrl___end_init_from_json, sqrrl___init_from_json, sqrrl___world_to_json


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


struct sqrrl__Project(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl___JsonSerializable):
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


struct sqrrl__ProjectIndexes(Movable, ImplicitlyDeletable):
    var name: UniqueIndex[String]

    def __init__(out self):
        self.name = UniqueIndex[String]()


struct sqrrl__ProjectTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__ProjectIndexes, sqrrl__ProjectInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__ProjectIndexes, sqrrl__ProjectInner](sqrrl__ProjectIndexes()))

    def create(mut self, *, name: String) raises -> sqrrl__Project:
        if self.storage[].indexes.name.contains(name):
            raise Error("UniqueConstraintViolation: 'name' already in use by another entity")
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__ProjectInner(_id=id, _table=self.storage, _name=name))
        self.storage[].register_weak(id, inner)
        self.storage[].indexes.name.add(id, inner[]._name)
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
struct sqrrl__DepartmentInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__DepartmentIndexes, sqrrl__DepartmentInner]]
    var _name: String
    var _sqrrl__projects: Set[sqrrl__Project]

    def __del__(deinit self):
        self._table[].indexes.name.remove(self._id, self._name)
        self._table[].indexes.projects.remove_many(self._id, self._sqrrl__projects)
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_name(mut self, v: String) raises:
        self._table[].indexes.name.check_unique(v, self._id)
        self._table[].indexes.name.remove(self._id, self._name)
        self._name = v

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

    @always_inline
    def get_name(self) -> ref [self._name] String:
        return self._name

    @always_inline
    def get_sqrrl__projects(self) -> ref [self._sqrrl__projects] Set[sqrrl__Project]:
        return self._sqrrl__projects


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
    var projects: MultiIndex[sqrrl__Project]

    def __init__(out self):
        self.name = UniqueIndex[String]()
        self.projects = MultiIndex[sqrrl__Project]()


struct sqrrl__DepartmentTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__DepartmentIndexes, sqrrl__DepartmentInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__DepartmentIndexes, sqrrl__DepartmentInner](sqrrl__DepartmentIndexes()))

    def create(mut self, *, name: String, var sqrrl__projects: Set[sqrrl__Project] = Set[sqrrl__Project]()) raises -> sqrrl__Department:
        if self.storage[].indexes.name.contains(name):
            raise Error("UniqueConstraintViolation: 'name' already in use by another entity")
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__DepartmentInner(_id=id, _table=self.storage, _name=name, _sqrrl__projects=sqrrl__projects^))
        self.storage[].register_weak(id, inner)
        self.storage[].indexes.name.add(id, inner[]._name)
        self.storage[].indexes.projects.add_many(id, inner[]._sqrrl__projects)
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

    def for_sqrrl__projects(self, value: sqrrl__Project) -> Set[sqrrl__Department]:
        var out = Set[sqrrl__Department]()
        for id in self.storage[].indexes.projects.get_bwd(value):
            out.add(sqrrl__Department(self.storage[].handle_for(id)))
        return out^

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

@fieldwise_init
struct sqrrl__TagInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__TagIndexes, sqrrl__TagInner]]
    var _label: String

    def __del__(deinit self):
        self._table[].indexes.label.remove(self._id, self._label)
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_label(mut self, v: String) raises:
        self._table[].indexes.label.check_unique(v, self._id)
        self._table[].indexes.label.remove(self._id, self._label)
        self._label = v

    @always_inline
    def get_label(self) -> ref [self._label] String:
        return self._label


struct sqrrl__Tag(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl___JsonSerializable):
    var _inner: ArcPointer[sqrrl__TagInner]

    def __init__(out self, var inner: sqrrl__TagInner):
        self._inner = ArcPointer(inner^)

    def __init__(out self, var inner: ArcPointer[sqrrl__TagInner]):
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


struct sqrrl__TagIndexes(Movable, ImplicitlyDeletable):
    var label: UniqueIndex[String]

    def __init__(out self):
        self.label = UniqueIndex[String]()


struct sqrrl__TagTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__TagIndexes, sqrrl__TagInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__TagIndexes, sqrrl__TagInner](sqrrl__TagIndexes()))

    def create(mut self, *, label: String) raises -> sqrrl__Tag:
        if self.storage[].indexes.label.contains(label):
            raise Error("UniqueConstraintViolation: 'label' already in use by another entity")
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__TagInner(_id=id, _table=self.storage, _label=label))
        self.storage[].register_weak(id, inner)
        self.storage[].indexes.label.add(id, inner[]._label)
        self.storage[].keepalive_add(id, inner.copy())
        return sqrrl__Tag(inner^)

    def all(self) -> Set[sqrrl__Tag]:
        var out = Set[sqrrl__Tag]()
        for id in self.storage[].all():
            out.add(sqrrl__Tag(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

    def for_label(self, value: String) raises -> sqrrl__Tag:
        var id = self.storage[].indexes.label.get_bwd(value)
        return sqrrl__Tag(self.storage[].handle_for(id))

    def count_label(self, value: String) -> Int:
        return 1 if self.storage[].indexes.label.contains(value) else 0

    def group_by_label(self) -> Dict[String, sqrrl__Tag]:
        ref ids = self.storage[].indexes.label.all_bwd()
        var out = Dict[String, sqrrl__Tag]()
        for entry in ids.items():
            out[entry.key] = sqrrl__Tag(self.storage[].handle_for(entry.value))
        return out^

    def distinct_label(self) -> Set[String]:
        var out = Set[String]()
        ref ids = self.storage[].indexes.label.all_bwd()
        for key in ids.keys():
            out.add(key.copy())
        return out^

def main() raises:
    var sqrrl___world = sqrrl___init()
    try:
        var sqrrl__website = sqrrl___world.Project.create(name = "Website")
        var sqrrl__app = sqrrl___world.Project.create(name = "App")
        var sqrrl__eng = sqrrl___world.Department.create(name = "Engineering", sqrrl__projects = Set(sqrrl__website, sqrrl__app))
        var sqrrl__t1 = sqrrl___world.Tag.create(label = "urgent")

        var dump = sqrrl___world_to_json(sqrrl___world)
        print("dump:", dump)

        # Captured after to_json() -- these calls are each variable's true
        # last use, so ASAP destruction doesn't free them until here, well
        # after to_json() has already walked every table (see the project's
        # own documented ASAP-destruction-vs-weakly-referenced-entities
        # pitfall: capturing these ids *before* to_json() would make that
        # capture their true last use instead, destroying them -- and
        # emptying every table -- before to_json() ever ran).
        var website_id = sqrrl__website.id()
        var app_id = sqrrl__app.id()
        var eng_id = sqrrl__eng.id()
        var t1_id = sqrrl__t1.id()

        var sqrrl___temp_keep_alives = sqrrl___begin_init_from_json(sqrrl___world, dump)
        var sqrrl__website2 = sqrrl___world.Project.for_name("Website")
        var sqrrl__app2 = sqrrl___world.Project.for_name("App")
        var sqrrl__eng2 = sqrrl___world.Department.for_name("Engineering")
        var sqrrl__t1_2 = sqrrl___world.Tag.for_label("urgent")

        if sqrrl__website2.id() != website_id:
            raise Error("id mismatch: website")
        if sqrrl__app2.id() != app_id:
            raise Error("id mismatch: app")
        if sqrrl__eng2.id() != eng_id:
            raise Error("id mismatch: eng")
        if sqrrl__t1_2.id() != t1_id:
            raise Error("id mismatch: t1")

        var sqrrl__members = sqrrl___world.Department.for_sqrrl__projects(sqrrl__website2)
        if len(sqrrl__members) != 1:
            raise Error("reloaded multi index broken: website2 membership")

        print("reload OK: ids preserved, multi index intact")
        sqrrl___end_init_from_json(sqrrl___temp_keep_alives^)
    finally:
        sqrrl___world.sqrrl__check_no_leaks()
