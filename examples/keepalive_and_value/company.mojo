from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl___init, sqrrl___World

def main() raises:
    var sqrrl___world = sqrrl___init()
    try:
        _ = sqrrl___world.Project.create(name = "Website Revamp")
        _ = sqrrl___world.Project.create(name = "Onboarding Redesign")
        print("all projects:", len(sqrrl___world.Project.all()))

        var sqrrl__handle = sqrrl___world.Project.for_name("Website Revamp")
        var released = sqrrl__handle.dont_keepalive()
        print("released website revamp:", released)

        var sqrrl__alice = sqrrl___world.Person.create(name = "alice", age = 30)
        var sqrrl__alice_twin = sqrrl___world.Person.create(name = "alice", age = 30)
        var sqrrl__bob = sqrrl___world.Person.create(name = "bob", age = 25)

        print("alice equals alice_twin:", sqrrl__alice == sqrrl__alice_twin)
        print("alice equals bob:", sqrrl__alice == sqrrl__bob)

        # `@@Person` is flagged `value`, so `create()` (what `@@@Person {
        # ... }` compiles down to) gets get-or-create semantics: a value-duplicate
        # doesn't insert a second, separate row -- it hands back the
        # *existing* one. `@@alice_twin` isn't a distinct entity at all;
        # it's the very same row `@@alice` already is, confirmed here by
        # comparing `id()` directly (not just `==`, which field-by-field
        # equality would already guarantee even for two genuinely distinct
        # rows) and by the whole table's own count staying at 2 (alice,
        # bob), not 3.
        print("alice id equals alice_twin id:", sqrrl__alice.id() == sqrrl__alice_twin.id())
        print("person count (alice_twin was not a new row):", sqrrl___world.Person.count())

        # Mojo's own ASAP destruction drops a local right after its last
        # textual use -- `@@bob`'s was the `==` comparison above, so
        # without this line it (and, once `Person.count()` above no
        # longer needs them either, `@@alice`/`@@alice_twin` too) could
        # already be gone by the time `count()` ran, undercounting.
        print("keep alive:", sqrrl__alice._inner[]._name, sqrrl__alice_twin._inner[]._name, sqrrl__bob._inner[]._name)
    finally:
        sqrrl___world.sqrrl__check_no_leaks()
