from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl___JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort


@fieldwise_init
struct sqrrl__AuditLogInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__AuditLogIndexes, sqrrl__AuditLogInner]]
    var _message: String

    def __del__(deinit self):
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_message(mut self, v: String):
        self._message = v

    @always_inline
    def get_message(self) -> ref [self._message] String:
        return self._message


struct sqrrl__AuditLog(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl___JsonSerializable):
    var _inner: ArcPointer[sqrrl__AuditLogInner]

    def __init__(out self, var inner: sqrrl__AuditLogInner):
        self._inner = ArcPointer(inner^)

    def __init__(out self, var inner: ArcPointer[sqrrl__AuditLogInner]):
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


struct sqrrl__AuditLogIndexes(Movable, ImplicitlyDeletable):
    def __init__(out self):
        pass


struct sqrrl__AuditLogTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__AuditLogIndexes, sqrrl__AuditLogInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__AuditLogIndexes, sqrrl__AuditLogInner](sqrrl__AuditLogIndexes()))

    def create(mut self, *, message: String) -> sqrrl__AuditLog:
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__AuditLogInner(_id=id, _table=self.storage, _message=message))
        self.storage[].register_weak(id, inner)
        self.storage[].keepalive_add(id, inner.copy())
        return sqrrl__AuditLog(inner^)

    def all(self) -> Set[sqrrl__AuditLog]:
        var out = Set[sqrrl__AuditLog]()
        for id in self.storage[].all():
            out.add(sqrrl__AuditLog(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

