from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl___JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort


struct Money(Copyable, Movable, ImplicitlyDeletable):
    var cents: Int64

    def __init__(out self, var cents: Int64):
        self.cents = cents
