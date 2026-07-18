from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl__JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl__init, sqrrl__World
from sqrrl__json import sqrrl__begin_init_from_json, sqrrl__end_init_from_json, sqrrl__init_from_json, sqrrl__world_to_json


from ext_module import ExternalCity, sqrrl__ExternalCity_from_json

@fieldwise_init
struct Address(Copyable, Movable, ImplicitlyDeletable):
    var city: String
    var owner: sqrrl__Employee


struct Box[T: Copyable & ImplicitlyDeletable](Movable, ImplicitlyDeletable):
    var value: Self.T

    def __init__(out self, var value: Self.T):
        self.value = value^


@fieldwise_init
struct Tagged[Kind: Copyable & ImplicitlyDeletable](Movable, ImplicitlyDeletable):
    # Unlike Box, no field is typed as the bare type parameter itself --
    # `Kind` only ever appears at the instantiation site (`Tagged[String]`
    # below), never as a field's own storage type. That's the dividing
    # line for JSON reload: a generic plain struct's `from_json` can only
    # be generated when every field has a concrete type at codegen time,
    # since there's no way to generate code that parses an abstract "T"
    # from JSON text without knowing what it concretely is.
    var label: String
    var count: UInt32


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


struct sqrrl__Employee(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl__JsonSerializable):
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

    def create(mut self, name: String) raises -> sqrrl__Employee:
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
struct sqrrl__PersonInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__PersonIndexes, sqrrl__PersonInner]]
    var _name: String
    var _home: Address
    var _meta: Tagged[String]
    var _hometown: ExternalCity

    def __del__(deinit self):
        self._table[].indexes.name.remove(self._id, self._name)
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_name(mut self, v: String) raises:
        self._table[].indexes.name.check_unique(v, self._id)
        self._table[].indexes.name.remove(self._id, self._name)
        self._name = v

    def set_home(mut self, var v: Address):
        self._home = v^

    def set_meta(mut self, var v: Tagged[String]):
        self._meta = v^

    def set_hometown(mut self, var v: ExternalCity):
        self._hometown = v^

    @always_inline
    def get_name(self) -> ref [self._name] String:
        return self._name

    @always_inline
    def get_home(self) -> ref [self._home] Address:
        return self._home

    @always_inline
    def get_meta(self) -> ref [self._meta] Tagged[String]:
        return self._meta

    @always_inline
    def get_hometown(self) -> ref [self._hometown] ExternalCity:
        return self._hometown


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


struct sqrrl__PersonIndexes(Movable, ImplicitlyDeletable):
    var name: UniqueIndex[String]

    def __init__(out self):
        self.name = UniqueIndex[String]()


struct sqrrl__PersonTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__PersonIndexes, sqrrl__PersonInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__PersonIndexes, sqrrl__PersonInner](sqrrl__PersonIndexes()))

    def create(mut self, name: String, var home: Address, var meta: Tagged[String], var hometown: ExternalCity) raises -> sqrrl__Person:
        if self.storage[].indexes.name.contains(name):
            raise Error("UniqueConstraintViolation: 'name' already in use by another entity")
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__PersonInner(_id=id, _table=self.storage, _name=name, _home=home^, _meta=meta^, _hometown=hometown^))
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

    def for_name(self, value: String) raises -> sqrrl__Person:
        var id = self.storage[].indexes.name.get_bwd(value)
        return sqrrl__Person(self.storage[].handle_for(id))

    def count_name(self, value: String) -> Int:
        return 1 if self.storage[].indexes.name.contains(value) else 0

    def group_by_name(self) -> Dict[String, sqrrl__Person]:
        ref ids = self.storage[].indexes.name.all_bwd()
        var out = Dict[String, sqrrl__Person]()
        for entry in ids.items():
            out[entry.key] = sqrrl__Person(self.storage[].handle_for(entry.value))
        return out^

    def distinct_name(self) -> Set[String]:
        var out = Set[String]()
        ref ids = self.storage[].indexes.name.all_bwd()
        for key in ids.keys():
            out.add(key.copy())
        return out^

def main() raises:
    var sqrrl__world = sqrrl__init()
    try:
        var sqrrl__bob = sqrrl__world.Employee.create(name = "Bob")
        var addr = Address(city = "Springfield", owner = sqrrl__bob)
        var meta = Tagged[String](label = "vip", count = 1)
        var sqrrl__alice = sqrrl__world.Person.create(name = "Alice", home = addr^, meta = meta^, hometown = ExternalCity(name = "Ogdenville"))

        print(sqrrl__alice._inner[]._home.city)
        print(sqrrl__alice._inner[]._home.owner._inner[]._name)
        print(sqrrl__alice._inner[]._meta.label, sqrrl__alice._inner[]._meta.count)
        print(sqrrl__alice._inner[]._hometown.name)

        sqrrl__alice._inner[]._home.city = "Shelbyville";
        sqrrl__alice._inner[]._home.owner = sqrrl__bob;

        print(sqrrl__alice._inner[]._home.city)
        print(sqrrl__alice._inner[]._home.owner._inner[]._name)

        var box_a = Box(42)
        var box_b = Box("hello")
        print(box_a.value)
        print(box_b.value)

        var dump = sqrrl__world_to_json(sqrrl__world)
        print("dump:", dump)

        var bob_id = sqrrl__bob.id()
        var alice_id = sqrrl__alice.id()

        var sqrrl__temp_keep_alives = sqrrl__begin_init_from_json(sqrrl__world, dump)
        var sqrrl__bob2 = sqrrl__world.Employee.for_name("Bob")
        var sqrrl__alice2 = sqrrl__world.Person.for_name("Alice")

        if sqrrl__bob2.id() != bob_id:
            raise Error("id mismatch: bob")
        if sqrrl__alice2.id() != alice_id:
            raise Error("id mismatch: alice")

        print(sqrrl__alice2._inner[]._home.city)
        print(sqrrl__alice2._inner[]._home.owner._inner[]._name)
        print(sqrrl__alice2._inner[]._meta.label, sqrrl__alice2._inner[]._meta.count)
        print(sqrrl__alice2._inner[]._hometown.name)
        print("reload OK: ids, plain-struct field, generic plain-struct field, and undiscovered external plain-value field preserved")
        sqrrl__end_init_from_json(sqrrl__temp_keep_alives^)
    finally:
        sqrrl__world.sqrrl__check_no_leaks()
