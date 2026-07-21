from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl___JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from schema.person import sqrrl__Person


@fieldwise_init
struct Assignment(Copyable, Movable, ImplicitlyDeletable):
    var sqrrl__person: sqrrl__Person
    var role: String
