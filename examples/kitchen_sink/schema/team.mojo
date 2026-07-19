from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl___JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from schema.assignment import Assignment
from schema.employee import sqrrl__Employee
from schema.person import sqrrl__Person


@fieldwise_init
struct sqrrl__TeamInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__TeamIndexes, sqrrl__TeamInner]]
    var _name: String
    var _lead: Assignment
    var _sqrrl__members: List[sqrrl__Person]
    var _sqrrl__advisor: Optional[sqrrl__Employee]

    def __del__(deinit self):
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_name(mut self, v: String):
        self._name = v

    def set_lead(mut self, var v: Assignment):
        self._lead = v^

    def set_sqrrl__members(mut self, var v: List[sqrrl__Person]):
        self._sqrrl__members = v^

    def set_sqrrl__advisor(mut self, var v: Optional[sqrrl__Employee]):
        self._sqrrl__advisor = v^

    @always_inline
    def get_name(self) -> ref [self._name] String:
        return self._name

    @always_inline
    def get_lead(self) -> ref [self._lead] Assignment:
        return self._lead

    @always_inline
    def get_sqrrl__members(self) -> ref [self._sqrrl__members] List[sqrrl__Person]:
        return self._sqrrl__members

    @always_inline
    def get_sqrrl__advisor(self) -> ref [self._sqrrl__advisor] Optional[sqrrl__Employee]:
        return self._sqrrl__advisor


struct sqrrl__Team(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl___JsonSerializable):
    var _inner: ArcPointer[sqrrl__TeamInner]

    def __init__(out self, var inner: sqrrl__TeamInner):
        self._inner = ArcPointer(inner^)

    def __init__(out self, var inner: ArcPointer[sqrrl__TeamInner]):
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


struct sqrrl__TeamIndexes(Movable, ImplicitlyDeletable):
    def __init__(out self):
        pass


struct sqrrl__TeamTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__TeamIndexes, sqrrl__TeamInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__TeamIndexes, sqrrl__TeamInner](sqrrl__TeamIndexes()))

    def create(mut self, *, name: String, var lead: Assignment, var sqrrl__members: List[sqrrl__Person], var sqrrl__advisor: Optional[sqrrl__Employee]) -> sqrrl__Team:
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__TeamInner(_id=id, _table=self.storage, _name=name, _lead=lead^, _sqrrl__members=sqrrl__members^, _sqrrl__advisor=sqrrl__advisor^))
        self.storage[].register_weak(id, inner)
        return sqrrl__Team(inner^)

    def all(self) -> Set[sqrrl__Team]:
        var out = Set[sqrrl__Team]()
        for id in self.storage[].all():
            out.add(sqrrl__Team(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

