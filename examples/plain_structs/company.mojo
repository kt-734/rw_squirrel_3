from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl___JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl___init, sqrrl___World
from sqrrl__json import sqrrl___begin_init_from_json, sqrrl___end_init_from_json, sqrrl___init_from_json, sqrrl___world_to_json
from company_impl import Address
from company_impl import Box
from company_impl import Tagged
from company_impl import sqrrl__Employee

from ext_module import ExternalCity, sqrrl__ExternalCity_from_json

def owner_name(a: Address) raises -> String:
    # A function parameter with a bare (never `@@`-marked) plain-struct
    # type -- its own explicit annotation alone is enough for a marked
    # relation-field access through it to resolve, no different from a
    # local variable's.
    return a.sqrrl__owner._inner[]._name

def make_address(city: String, sqrrl__owner: sqrrl__Employee) raises -> Address:
    # A bare (never `@@`/`@@@`-marked) function returning a plain-struct
    # value -- its own call result can be chained directly (`make_
    # address(...).@@owner.name`, no intermediate variable) or iterated
    # directly (`for x in make_addresses(...):`), the exact same way a
    # bare local variable's own value already can.
    return Address(city = city, sqrrl__owner = sqrrl__owner)

def make_addresses(sqrrl__owner: sqrrl__Employee) raises -> List[Address]:
    var out = List[Address]()
    out.append(Address(city = "Ogdenville", sqrrl__owner = sqrrl__owner))
    out.append(Address(city = "North Haverbrook", sqrrl__owner = sqrrl__owner))
    return out^

def main() raises:
    var sqrrl___world = sqrrl___init()
    try:
        var sqrrl__bob = sqrrl___world.Employee.create(name = "Bob")
        var addr: Address = Address(city = "Springfield", sqrrl__owner = sqrrl__bob)
        var meta = Tagged[String](label = "vip", count = 1)
        var sqrrl__alice = sqrrl___world.Person.create(name = "Alice", home = addr^, meta = meta^, hometown = ExternalCity(name = "Ogdenville"), sqrrl__box = Box(sqrrl__bob))

        print(sqrrl__alice._inner[]._home.city)
        print(sqrrl__alice._inner[]._home.sqrrl__owner._inner[]._name)
        print(sqrrl__alice._inner[]._meta.label, sqrrl__alice._inner[]._meta.count)
        print(sqrrl__alice._inner[]._hometown.name)
        print(sqrrl__alice._inner[]._sqrrl__box.value._inner[].get_name())

        sqrrl__alice._inner[]._home.city = "Shelbyville";
        sqrrl__alice._inner[]._home.sqrrl__owner = sqrrl__bob;

        print(sqrrl__alice._inner[]._home.city)
        print(sqrrl__alice._inner[]._home.sqrrl__owner._inner[]._name)

        # `addr2` itself is a bare local variable -- never `@@`-marked --
        # holding a plain-struct value directly (not reached through an
        # entity's own field this time). No explicit `: Address`
        # annotation needed here -- the constructor call on the right is
        # itself enough to infer it from, the same way a bare `var x =
        # List[@@Type]()` (a container constructor, always bare -- the
        # container itself is never the entity) already can.
        var addr2 = Address(city = "Ogdenville", sqrrl__owner = sqrrl__bob)
        print(addr2.sqrrl__owner._inner[]._name)
        addr2.sqrrl__owner = sqrrl__bob;
        print(addr2.sqrrl__owner._inner[]._name)

        # The same, through a function parameter, a container of the
        # bare-typed value, and a bare for-loop variable over one.
        print(owner_name(addr2))
        var addresses = List[Address]()
        addresses.append(addr2.copy())
        print(addresses[0].sqrrl__owner._inner[]._name)
        for a in addresses:
            print(a.sqrrl__owner._inner[]._name)

        # A bare function's own call result, chained directly (no
        # intermediate variable) or iterated directly (no intermediate
        # variable, no `for @@x in ...:` marked form) -- the bare-call
        # analogue of the local-variable/parameter/container cases above.
        print(make_address("Capital City", sqrrl__bob).sqrrl__owner._inner[]._name)
        for a in make_addresses(sqrrl__bob):
            print(a.sqrrl__owner._inner[]._name)

        # A bare *method*'s own call result, chained directly off a
        # bound `@@entity` receiver -- the method analogue of the two
        # bare-function cases just above.
        print(sqrrl__bob.get_home().sqrrl__owner._inner[]._name)

        # A bare `for` loop variable, iterating directly off a bare
        # method's own call result rooted at a bound `@@entity` receiver
        # -- no intermediate variable, no `for @@x in ...:` marked form
        # (the element is a plain struct, not an entity).
        for a in sqrrl__bob.get_homes():
            print(a.sqrrl__owner._inner[]._name)

        # A bare *var-decl*, no annotation, initialized straight from a
        # bound `@@entity`'s own bare method call -- no explicit `:
        # Address` needed (unlike a call whose own name isn't itself
        # `@@`-rooted, which `PLAIN_VAR_DECL`'s own inferred branch
        # handles instead), the entity-rooted analogue of the direct-
        # chain/for-loop cases just above.
        var addr3 = sqrrl__bob.get_home()
        print(addr3.sqrrl__owner._inner[]._name)

        # A hand-written method on a plain struct itself (`Address.
        # relocated`, not an entity/entity-method), chained directly off
        # a bare-rooted plain-struct value -- no intermediate variable.
        print(addr2.relocated("Shelbyville", sqrrl__bob).sqrrl__owner._inner[]._name)

        var box_a = Box(42)
        var box_b = Box("hello")
        print(box_a.value)
        print(box_b.value)

        var dump = sqrrl___world_to_json(sqrrl___world)
        print("dump:", dump)

        var bob_id = sqrrl__bob.id()
        var alice_id = sqrrl__alice.id()

        var sqrrl___temp_keep_alives = sqrrl___begin_init_from_json(sqrrl___world, dump)
        var sqrrl__bob2 = sqrrl___world.Employee.for_name("Bob")
        var sqrrl__alice2 = sqrrl___world.Person.for_name("Alice")

        if sqrrl__bob2.id() != bob_id:
            raise Error("id mismatch: bob")
        if sqrrl__alice2.id() != alice_id:
            raise Error("id mismatch: alice")

        print(sqrrl__alice2._inner[]._home.city)
        print(sqrrl__alice2._inner[]._home.sqrrl__owner._inner[]._name)
        print(sqrrl__alice2._inner[]._meta.label, sqrrl__alice2._inner[]._meta.count)
        print(sqrrl__alice2._inner[]._hometown.name)
        print(sqrrl__alice2._inner[]._sqrrl__box.value._inner[].get_name())
        print(
            "reload OK: ids, plain-struct field, generic plain-struct field, undiscovered"
            " external plain-value field, and a generic plain-struct field whose own"
            " bare type parameter resolves to a relation, all preserved"
        )
        sqrrl___end_init_from_json(sqrrl___temp_keep_alives^)
    finally:
        sqrrl___world.sqrrl__check_no_leaks()
