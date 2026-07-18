from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl__JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort


@fieldwise_init
struct sqrrl__VendorInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__VendorIndexes, sqrrl__VendorInner]]
    var _name: String

    def __del__(deinit self):
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_name(mut self, v: String):
        self._name = v

    @always_inline
    def get_name(self) -> ref [self._name] String:
        return self._name


struct sqrrl__Vendor(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl__JsonSerializable):
    var _inner: ArcPointer[sqrrl__VendorInner]

    def __init__(out self, var inner: sqrrl__VendorInner):
        self._inner = ArcPointer(inner^)

    def __init__(out self, var inner: ArcPointer[sqrrl__VendorInner]):
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


struct sqrrl__VendorIndexes(Movable, ImplicitlyDeletable):
    def __init__(out self):
        pass


struct sqrrl__VendorTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__VendorIndexes, sqrrl__VendorInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__VendorIndexes, sqrrl__VendorInner](sqrrl__VendorIndexes()))

    def create(mut self, *, name: String) -> sqrrl__Vendor:
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__VendorInner(_id=id, _table=self.storage, _name=name))
        self.storage[].register_weak(id, inner)
        return sqrrl__Vendor(inner^)

    def all(self) -> Set[sqrrl__Vendor]:
        var out = Set[sqrrl__Vendor]()
        for id in self.storage[].all():
            out.add(sqrrl__Vendor(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

