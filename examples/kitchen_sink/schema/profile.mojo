from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl__JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from schema.address import Address
from schema.box import Box
from schema.contact_info import ContactInfo
from schema.pair import Pair


@fieldwise_init
struct Profile(Copyable, Movable, ImplicitlyDeletable):
    var contact: ContactInfo
    var nicknames: Optional[List[String]]
    var scores: Dict[String, Int]
    var rating: Box[UInt32]
    var coordinates: Pair[Int, Int]
    var past_addresses: List[Address]
    var boxed_ratings: List[Box[UInt32]]
