from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl___JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort

from ext_module import ExternalCity, sqrrl__ExternalCity_from_json

@fieldwise_init
struct Address(Copyable, Movable, ImplicitlyDeletable):
    var city: String
    var sqrrl__owner: sqrrl__Employee

    def relocated(self, new_city: String, sqrrl__owner: sqrrl__Employee) -> Address:
        # A hand-written method on a plain (non-`@@struct`) struct,
        # returning another plain-struct value -- tracked the same way a
        # bare top-level function/an `@@struct`'s own bare method already
        # are, letting a trailing chain continue off its own call result
        # (`addr.relocated(...).@@owner.name`, no intermediate variable).
        # (Takes `@@owner` as its own parameter rather than reading `self.
        # @@owner` -- a plain struct's own method body is real, hand-
        # written Mojo the DSL never gives its own `self` a registered
        # type inside, unlike a spliced `@@struct` method's `self`, so a
        # marked field access directly on `self` doesn't resolve here.)
        return Address(city=new_city, sqrrl__owner=sqrrl__owner)

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

    def get_home(self) -> Address:
        # A bare (never `@@`/`@@@`-marked) method on an `@@struct`,
        # returning a plain-struct value -- the method analogue of a bare
        # top-level function's own call result: its own call can be
        # chained directly (`@@x.get_home().@@owner.name`, no
        # intermediate variable), no different from `make_address(...)`
        # above except the receiver is a bound `@@entity` instead of a
        # function's own parameters.
        return Address(city="Metropolis", sqrrl__owner=self)

    def get_homes(self) -> List[Address]:
        # Same, but returning a *container* of the plain struct -- lets a
        # bare (never `@@`-marked) `for` loop variable iterate directly
        # off the bare method's own call result, no intermediate
        # variable, the entity-rooted analogue of `for a in addresses:`/
        # `for a in make_addresses(...):` above.
        var out = List[Address]()
        out.append(Address(city="Smallville", sqrrl__owner=self))
        return out^

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
struct sqrrl__PersonInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__PersonIndexes, sqrrl__PersonInner]]
    var _name: String
    var _home: Address
    var _meta: Tagged[String]
    var _hometown: ExternalCity
    var _sqrrl__box: Box[sqrrl__Employee]

    def __del__(deinit self):
        self._table[].indexes.name.remove(self._id, self._name)
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_name(mut self, v: String) raises:
        self._table[].indexes.name.check_unique(v, self._id)
        self._table[].indexes.name.remove(self._id, self._name)
        self._name = v
        self._table[].indexes.name.add(self._id, self._name)

    def set_home(mut self, var v: Address):
        self._home = v^

    def set_meta(mut self, var v: Tagged[String]):
        self._meta = v^

    def set_hometown(mut self, var v: ExternalCity):
        self._hometown = v^

    def set_sqrrl__box(mut self, var v: Box[sqrrl__Employee]):
        self._sqrrl__box = v^

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

    @always_inline
    def get_sqrrl__box(self) -> ref [self._sqrrl__box] Box[sqrrl__Employee]:
        return self._sqrrl__box

struct sqrrl__Person(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl___JsonSerializable):
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

    def create(mut self, *, name: String, var home: Address, var meta: Tagged[String], var hometown: ExternalCity, var sqrrl__box: Box[sqrrl__Employee]) raises -> sqrrl__Person:
        if self.storage[].indexes.name.contains(name):
            raise Error("UniqueConstraintViolation: 'name' already in use by another entity")
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__PersonInner(_id=id, _table=self.storage, _name=name, _home=home^, _meta=meta^, _hometown=hometown^, _sqrrl__box=sqrrl__box^))
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

    def count_for_name(self, value: String) -> Int:
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
