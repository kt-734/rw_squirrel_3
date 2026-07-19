from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl___JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort


@fieldwise_init
struct Box[T: Copyable & ImplicitlyDeletable](Copyable, Movable, ImplicitlyDeletable):
    var value: Self.T
