from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl___JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort


@fieldwise_init
struct Pair[A: Copyable & ImplicitlyDeletable, B: Copyable & ImplicitlyDeletable](Copyable, Movable, ImplicitlyDeletable):
    var first: Self.A
    var second: Self.B
