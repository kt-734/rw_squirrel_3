from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl__JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from schema.money import Money
from schema.vendor import sqrrl__Vendor


@fieldwise_init
struct sqrrl__ProjectInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__ProjectIndexes, sqrrl__ProjectInner]]
    var _name: String
    var _priority: UInt32
    var _sqrrl__vendor: sqrrl__Vendor
    var _budget: Money

    def __del__(deinit self):
        self._table[].indexes.priority.remove(self._id, self._priority)
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_name(mut self, v: String):
        self._name = v

    def set_priority(mut self, v: UInt32):
        self._table[].indexes.priority.remove(self._id, self._priority)
        self._priority = v
        self._table[].indexes.priority.add(self._id, self._priority)

    def set_sqrrl__vendor(mut self, v: sqrrl__Vendor):
        self._sqrrl__vendor = v

    def set_budget(mut self, var v: Money):
        self._budget = v^

    @always_inline
    def get_name(self) -> ref [self._name] String:
        return self._name

    @always_inline
    def get_priority(self) -> ref [self._priority] UInt32:
        return self._priority

    @always_inline
    def get_sqrrl__vendor(self) -> ref [self._sqrrl__vendor] sqrrl__Vendor:
        return self._sqrrl__vendor

    @always_inline
    def get_budget(self) -> ref [self._budget] Money:
        return self._budget


struct sqrrl__Project(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl__JsonSerializable):
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
    var priority: OrderedIndex[UInt32]

    def __init__(out self):
        self.priority = OrderedIndex[UInt32]()


struct sqrrl__ProjectTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__ProjectIndexes, sqrrl__ProjectInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__ProjectIndexes, sqrrl__ProjectInner](sqrrl__ProjectIndexes()))

    def create(mut self, *, name: String, priority: UInt32, sqrrl__vendor: sqrrl__Vendor, var budget: Money) -> sqrrl__Project:
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__ProjectInner(_id=id, _table=self.storage, _name=name, _priority=priority, _sqrrl__vendor=sqrrl__vendor, _budget=budget^))
        self.storage[].register_weak(id, inner)
        self.storage[].indexes.priority.add(id, inner[]._priority)
        return sqrrl__Project(inner^)

    def all(self) -> Set[sqrrl__Project]:
        var out = Set[sqrrl__Project]()
        for id in self.storage[].all():
            out.add(sqrrl__Project(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

    def for_priority(self, value: UInt32) -> Set[sqrrl__Project]:
        var out = Set[sqrrl__Project]()
        for id in self.storage[].indexes.priority.get_bwd(value):
            out.add(sqrrl__Project(self.storage[].handle_for(id)))
        return out^

    def for_priority_greater_than(self, value: UInt32) -> List[sqrrl__Project]:
        var out = List[sqrrl__Project]()
        for id in self.storage[].indexes.priority.greater_than(value):
            out.append(sqrrl__Project(self.storage[].handle_for(id)))
        return out^

    def for_priority_less_than(self, value: UInt32) -> List[sqrrl__Project]:
        var out = List[sqrrl__Project]()
        for id in self.storage[].indexes.priority.less_than(value):
            out.append(sqrrl__Project(self.storage[].handle_for(id)))
        return out^

    def for_priority_at_least(self, value: UInt32) -> List[sqrrl__Project]:
        var out = List[sqrrl__Project]()
        for id in self.storage[].indexes.priority.at_least(value):
            out.append(sqrrl__Project(self.storage[].handle_for(id)))
        return out^

    def for_priority_at_most(self, value: UInt32) -> List[sqrrl__Project]:
        var out = List[sqrrl__Project]()
        for id in self.storage[].indexes.priority.at_most(value):
            out.append(sqrrl__Project(self.storage[].handle_for(id)))
        return out^

    def for_priority_between(self, low: UInt32, high: UInt32) -> List[sqrrl__Project]:
        var out = List[sqrrl__Project]()
        for id in self.storage[].indexes.priority.between(low, high):
            out.append(sqrrl__Project(self.storage[].handle_for(id)))
        return out^

    def count_priority(self, value: UInt32) -> Int:
        return len(self.storage[].indexes.priority.get_bwd(value))

    def group_by_priority(self) -> Dict[UInt32, Set[sqrrl__Project]]:
        var buckets = self.storage[].indexes.priority.all_bwd()
        var out = Dict[UInt32, Set[sqrrl__Project]]()
        for entry in buckets.items():
            var handles = Set[sqrrl__Project]()
            for id in entry.value:
                handles.add(sqrrl__Project(self.storage[].handle_for(id)))
            out[entry.key] = handles^
        return out^

    def count_by_priority(self) -> Dict[UInt32, Int]:
        var buckets = self.storage[].indexes.priority.all_bwd()
        var out = Dict[UInt32, Int]()
        for entry in buckets.items():
            out[entry.key] = len(entry.value)
        return out^

    def distinct_priority(self) -> List[UInt32]:
        var out = List[UInt32]()
        var buckets = self.storage[].indexes.priority.all_bwd()
        for key in buckets.keys():
            out.append(key.copy())
        return out^

    def min_priority(self) raises -> UInt32:
        var sqrrl__ids = self.storage[].all()
        if len(sqrrl__ids) == 0:
            raise Error("min_priority: table has no entities")
        var sqrrl__acc: Optional[UInt32] = None
        for sqrrl__id in sqrrl__ids:
            var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._priority
            if not sqrrl__acc or sqrrl__v < sqrrl__acc.value():
                sqrrl__acc = sqrrl__v
        return sqrrl__acc.value()

    def max_priority(self) raises -> UInt32:
        var sqrrl__ids = self.storage[].all()
        if len(sqrrl__ids) == 0:
            raise Error("max_priority: table has no entities")
        var sqrrl__acc: Optional[UInt32] = None
        for sqrrl__id in sqrrl__ids:
            var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._priority
            if not sqrrl__acc or sqrrl__v > sqrrl__acc.value():
                sqrrl__acc = sqrrl__v
        return sqrrl__acc.value()

    def median_priority(self) raises -> UInt32:
        ref sqrrl__sorted = self.storage[].indexes.priority.entries()
        if len(sqrrl__sorted) == 0:
            raise Error("median_priority: table has no entities")
        return sqrrl__sorted[len(sqrrl__sorted) // 2].value

