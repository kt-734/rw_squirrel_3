from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl___JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from schema.address import Address


@fieldwise_init
struct ContactInfo(Copyable, Movable, ImplicitlyDeletable):
    var home: Address
    var emails: List[String]
