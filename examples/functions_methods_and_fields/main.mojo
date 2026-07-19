from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl___init, sqrrl___World


# Every combination of "does this name need @@ marking?" for a struct
# field, a hand-written plain struct field, a def/method parameter, and
# a top-level function's own name -- all governed by one rule:
# is_directly_entity_reachable: a bare relation (@@Type), a wrapper's own
# *first* type parameter (recursively) satisfying the same rule, or --
# for a wrapper with at least two type parameters -- its *second* type
# parameter (recursively) satisfying it too. Not tied to any specific
# wrapper name (a custom two-argument wrapper like Grid[K, V] gets the
# same treatment Dict does). A relation is only ever unreachable, and
# therefore stays unmarked, when it's confined to a *third-or-later*
# type parameter -- no iteration or indexing operation this DSL
# generates ever reaches one, so marking there would promise a
# capability that doesn't exist.
#
# Position 1 and position 2 differ in *how* they're reached, though:
# iterating a container (`for x in container:`) only ever exposes
# position 1 -- Dict[K, V]'s own iteration only ever yields K, never V,
# the same restriction real Mojo Dict iteration has. Position 2 is only
# reachable by *indexing* (`container[key]`). A marked field/function/
# method whose only relation is in position 2 can still be indexed and
# chained off directly, but a `for @@x in ...:` over it is rejected --
# iterating it never yields an entity, so the loop variable must be
# bare (`for x in ...:`) instead.


@fieldwise_init
struct sqrrl__EmployeeInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__EmployeeIndexes, sqrrl__EmployeeInner]]
    var _name: String

    def __del__(deinit self):
        self._table[].indexes.name.remove(self._id, self._name)
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_name(mut self, v: String) raises:
        self._table[].indexes.name.check_unique(v, self._id)
        self._table[].indexes.name.remove(self._id, self._name)
        self._name = v

    @always_inline
    def get_name(self) -> ref [self._name] String:
        return self._name


struct sqrrl__Employee(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable):
    var _inner: ArcPointer[sqrrl__EmployeeInner]

    def __init__(out self, var inner: sqrrl__EmployeeInner):
        self._inner = ArcPointer(inner^)

    def __init__(out self, var inner: ArcPointer[sqrrl__EmployeeInner]):
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



struct sqrrl__EmployeeIndexes(Movable, ImplicitlyDeletable):
    var name: UniqueIndex[String]

    def __init__(out self):
        self.name = UniqueIndex[String]()


struct sqrrl__EmployeeTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__EmployeeIndexes, sqrrl__EmployeeInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__EmployeeIndexes, sqrrl__EmployeeInner](sqrrl__EmployeeIndexes()))

    def create(mut self, *, name: String) raises -> sqrrl__Employee:
        if self.storage[].indexes.name.contains(name):
            raise Error("UniqueConstraintViolation: 'name' already in use by another entity")
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__EmployeeInner(_id=id, _table=self.storage, _name=name))
        self.storage[].register_weak(id, inner)
        self.storage[].indexes.name.add(id, inner[]._name)
        return sqrrl__Employee(inner^)

    def all(self) -> Set[sqrrl__Employee]:
        var out = Set[sqrrl__Employee]()
        for id in self.storage[].all():
            out.add(sqrrl__Employee(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

    def for_name(self, value: String) raises -> sqrrl__Employee:
        var id = self.storage[].indexes.name.get_bwd(value)
        return sqrrl__Employee(self.storage[].handle_for(id))

    def count_name(self, value: String) -> Int:
        return 1 if self.storage[].indexes.name.contains(value) else 0

    def group_by_name(self) -> Dict[String, sqrrl__Employee]:
        ref ids = self.storage[].indexes.name.all_bwd()
        var out = Dict[String, sqrrl__Employee]()
        for entry in ids.items():
            out[entry.key] = sqrrl__Employee(self.storage[].handle_for(entry.value))
        return out^

    def distinct_name(self) -> Set[String]:
        var out = Set[String]()
        ref ids = self.storage[].indexes.name.all_bwd()
        for key in ids.keys():
            out.add(key.copy())
        return out^

@fieldwise_init
struct sqrrl__DepartmentInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__DepartmentIndexes, sqrrl__DepartmentInner]]
    var _name: String
    var _sqrrl__lead: sqrrl__Employee
    var _sqrrl__team: List[sqrrl__Employee]
    var _sqrrl__ranks: Dict[sqrrl__Employee, String]
    var _sqrrl__groups: List[List[sqrrl__Employee]]
    var _sqrrl__scores: Dict[String, sqrrl__Employee]
    var _sqrrl__rosters: List[Dict[String, sqrrl__Employee]]

    def __del__(deinit self):
        self._table[].indexes.name.remove(self._id, self._name)
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_name(mut self, v: String) raises:
        self._table[].indexes.name.check_unique(v, self._id)
        self._table[].indexes.name.remove(self._id, self._name)
        self._name = v

    def set_sqrrl__lead(mut self, v: sqrrl__Employee):
        self._sqrrl__lead = v

    def set_sqrrl__team(mut self, var v: List[sqrrl__Employee]):
        self._sqrrl__team = v^

    def set_sqrrl__ranks(mut self, var v: Dict[sqrrl__Employee, String]):
        self._sqrrl__ranks = v^

    def set_sqrrl__groups(mut self, var v: List[List[sqrrl__Employee]]):
        self._sqrrl__groups = v^

    def set_sqrrl__scores(mut self, var v: Dict[String, sqrrl__Employee]):
        self._sqrrl__scores = v^

    def set_sqrrl__rosters(mut self, var v: List[Dict[String, sqrrl__Employee]]):
        self._sqrrl__rosters = v^

    @always_inline
    def get_name(self) -> ref [self._name] String:
        return self._name

    @always_inline
    def get_sqrrl__lead(self) -> ref [self._sqrrl__lead] sqrrl__Employee:
        return self._sqrrl__lead

    @always_inline
    def get_sqrrl__team(self) -> ref [self._sqrrl__team] List[sqrrl__Employee]:
        return self._sqrrl__team

    @always_inline
    def get_sqrrl__ranks(self) -> ref [self._sqrrl__ranks] Dict[sqrrl__Employee, String]:
        return self._sqrrl__ranks

    @always_inline
    def get_sqrrl__groups(self) -> ref [self._sqrrl__groups] List[List[sqrrl__Employee]]:
        return self._sqrrl__groups

    @always_inline
    def get_sqrrl__scores(self) -> ref [self._sqrrl__scores] Dict[String, sqrrl__Employee]:
        return self._sqrrl__scores

    @always_inline
    def get_sqrrl__rosters(self) -> ref [self._sqrrl__rosters] List[Dict[String, sqrrl__Employee]]:
        return self._sqrrl__rosters


struct sqrrl__Department(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable):
    var _inner: ArcPointer[sqrrl__DepartmentInner]

    def __init__(out self, var inner: sqrrl__DepartmentInner):
        self._inner = ArcPointer(inner^)

    def __init__(out self, var inner: ArcPointer[sqrrl__DepartmentInner]):
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


    def lead_name(self) -> String:
        return self._inner[]._sqrrl__lead._inner[]._name

    def contains(self, sqrrl__e: sqrrl__Employee) -> Bool:
        for sqrrl__m in self._inner[]._sqrrl__team:
            if sqrrl__m == sqrrl__e:
                return True
        return False

    def greet_team(self, sqrrl__extra: List[sqrrl__Employee]) -> String:
        var out = String("")
        for sqrrl__m in self._inner[]._sqrrl__team:
            out += sqrrl__m._inner[]._name + " "
        for sqrrl__m in sqrrl__extra:
            out += sqrrl__m._inner[]._name + " "
        return String(out.strip())

    def promote_to_lead(self, sqrrl__e: sqrrl__Employee):
        self._inner[].set_sqrrl__lead(sqrrl__e);

    # -- methods: mandatory marking applies here too -- a method whose
    # return type is directly entity-reachable must mark its own name,
    # '@@' if it doesn't also need sqrrl___world, '@@@' if it does (the
    # exact same rule a top-level function's own name already follows).
    # Its call site is then a real marker position, same as a marked
    # function's -- bind-then-use, direct for-loop, and direct chain all
    # work off it, no intermediate variable required (see main() below).
    def team_lead(self) -> sqrrl__Employee:
        return self._inner[]._sqrrl__lead

    def roster(self) -> List[sqrrl__Employee]:
        return self._inner[]._sqrrl__team.copy()

    # a value-position (second-argument) return needs marking too, same
    # as a field of this shape does -- direct indexing/chaining off the
    # call works (see main() below), but a for-loop over it would need
    # a bare loop variable, since iterating only ever yields the key
    def scores_by_role(self) -> Dict[String, sqrrl__Employee]:
        return self._inner[]._sqrrl__scores.copy()

    def headcount(self, mut sqrrl___world: sqrrl___World) raises -> String:
        return self._inner[]._name + ": " + String(sqrrl___world.Employee.count())

    def rename(self, mut sqrrl___world: sqrrl___World, new_name: String) raises:
        if sqrrl___world.Department.count() > 0:
            self._inner[].set_name(new_name);




struct sqrrl__DepartmentIndexes(Movable, ImplicitlyDeletable):
    var name: UniqueIndex[String]

    def __init__(out self):
        self.name = UniqueIndex[String]()


struct sqrrl__DepartmentTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__DepartmentIndexes, sqrrl__DepartmentInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__DepartmentIndexes, sqrrl__DepartmentInner](sqrrl__DepartmentIndexes()))

    def create(mut self, *, name: String, sqrrl__lead: sqrrl__Employee, var sqrrl__team: List[sqrrl__Employee], var sqrrl__ranks: Dict[sqrrl__Employee, String], var sqrrl__groups: List[List[sqrrl__Employee]], var sqrrl__scores: Dict[String, sqrrl__Employee], var sqrrl__rosters: List[Dict[String, sqrrl__Employee]]) raises -> sqrrl__Department:
        if self.storage[].indexes.name.contains(name):
            raise Error("UniqueConstraintViolation: 'name' already in use by another entity")
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__DepartmentInner(_id=id, _table=self.storage, _name=name, _sqrrl__lead=sqrrl__lead, _sqrrl__team=sqrrl__team^, _sqrrl__ranks=sqrrl__ranks^, _sqrrl__groups=sqrrl__groups^, _sqrrl__scores=sqrrl__scores^, _sqrrl__rosters=sqrrl__rosters^))
        self.storage[].register_weak(id, inner)
        self.storage[].indexes.name.add(id, inner[]._name)
        return sqrrl__Department(inner^)

    def all(self) -> Set[sqrrl__Department]:
        var out = Set[sqrrl__Department]()
        for id in self.storage[].all():
            out.add(sqrrl__Department(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

    def for_name(self, value: String) raises -> sqrrl__Department:
        var id = self.storage[].indexes.name.get_bwd(value)
        return sqrrl__Department(self.storage[].handle_for(id))

    def count_name(self, value: String) -> Int:
        return 1 if self.storage[].indexes.name.contains(value) else 0

    def group_by_name(self) -> Dict[String, sqrrl__Department]:
        ref ids = self.storage[].indexes.name.all_bwd()
        var out = Dict[String, sqrrl__Department]()
        for entry in ids.items():
            out[entry.key] = sqrrl__Department(self.storage[].handle_for(entry.value))
        return out^

    def distinct_name(self) -> Set[String]:
        var out = Set[String]()
        ref ids = self.storage[].indexes.name.all_bwd()
        for key in ids.keys():
            out.add(key.copy())
        return out^

# -- top-level functions: name marking follows the *return* type alone,
# independent of any parameter's own marking --

def shout(name: String) -> String:
    # fully plain -- no @@ anywhere, needs no marking at all
    return name.upper()


def sqrrl__scores_for(sqrrl__d: sqrrl__Department) -> Dict[String, sqrrl__Employee]:
    # marked parameter, and now (widened rule) the return type needs
    # marking too -- a value-position relation is reachable by indexing,
    # so leaving this bare would make the call unable to bind/index/
    # chain at all, the same mandatory-marking reasoning a first-
    # position return already had
    return sqrrl__d._inner[]._sqrrl__scores.copy()


def sqrrl__get_lead(sqrrl__d: sqrrl__Department) -> sqrrl__Employee:
    # bare relation return -- needs marking, but not sqrrl___world (only
    # hops through an existing relation, never constructs one)
    return sqrrl__d._inner[]._sqrrl__lead


def sqrrl__get_team(sqrrl__d: sqrrl__Department) -> List[sqrrl__Employee]:
    # @@container return, same reasoning
    return sqrrl__d._inner[]._sqrrl__team.copy()


def sqrrl__make_employee(mut sqrrl___world: sqrrl___World, name: String) raises -> sqrrl__Employee:
    # constructs an entity -- genuinely needs sqrrl___world
    var sqrrl__e = sqrrl___world.Employee.create(name = name)
    return sqrrl__e


def main() raises:
    var sqrrl___world = sqrrl___init()
    try:
        var sqrrl__alice = sqrrl___world.Employee.create(name = "Alice")
        var sqrrl__bob = sqrrl___world.Employee.create(name = "Bob")
        var sqrrl__carol = sqrrl___world.Employee.create(name = "Carol")

        # container constructors also follow the widened rule -- the
        # relation can be inferred from either the first argument
        # (List[@@Type]()) or, for a two-argument wrapper, the second
        # (Dict[String, @@Type]()) -- at any nesting depth, since the
        # inference reuses the same recursive is_directly_entity_
        # reachable/render_relation_stripped machinery a declaration's
        # own type text already goes through
        var sqrrl__scores_dict = Dict[String, sqrrl__Employee]()
        sqrrl__scores_dict["senior"] = sqrrl__alice;
        var sqrrl__rosters_list = List[Dict[String, sqrrl__Employee]]()
        sqrrl__rosters_list.append(sqrrl__scores_dict.copy())
        var sqrrl__ranks_dict = Dict[sqrrl__Employee, String]()
        sqrrl__ranks_dict[sqrrl__alice] = "principal";

        var sqrrl__eng = sqrrl___world.Department.create(name = "Engineering", sqrrl__lead = sqrrl__alice, sqrrl__team = [sqrrl__alice, sqrrl__bob], sqrrl__ranks = sqrrl__ranks_dict^, sqrrl__groups = [[sqrrl__alice], [sqrrl__bob]], sqrrl__scores = sqrrl__scores_dict^, sqrrl__rosters = sqrrl__rosters_list^)

        print(shout("quiet"))

        # a marked function's value-position return can now be indexed
        # and chained directly, no intermediate variable/explicit type
        # annotation required
        var sqrrl__senior = sqrrl__scores_for(sqrrl__eng)["senior"]
        print(sqrrl__senior._inner[]._name)

        # bind a marked function's return, then use it
        var sqrrl__lead = sqrrl__get_lead(sqrrl__eng)
        print(sqrrl__lead._inner[]._name)

        # direct for-loop over a marked function's return, no binding
        for sqrrl__m in sqrrl__get_team(sqrrl__eng):
            print("team member:", sqrrl__m._inner[]._name)

        # direct access-chain off a marked function's return, no
        # binding and no loop
        print(sqrrl__get_lead(sqrrl__eng)._inner[]._name)

        # a for-loop directly over a value-position (Dict-key-yielding)
        # marked call needs a *bare* loop variable -- iterating never
        # reaches the value/entity, only indexing does, so '@@key' here
        # would be rejected
        for key in sqrrl__scores_for(sqrrl__eng):
            print("score key:", key)

        print(sqrrl__eng.lead_name())
        print("contains bob:", sqrrl__eng.contains(sqrrl__bob))
        print(sqrrl__eng.greet_team([sqrrl__carol]))

        # a method's own name follows the exact same mandatory-marking
        # rule a top-level function's does -- bind-then-use, direct
        # for-loop, and direct chain all work off a marked method's own
        # call, no intermediate variable required
        var sqrrl__teamlead = sqrrl__eng.team_lead()
        print(sqrrl__teamlead._inner[]._name)

        for sqrrl__m in sqrrl__eng.roster():
            print("roster member:", sqrrl__m._inner[]._name)

        print(sqrrl__eng.team_lead()._inner[]._name)

        # a marked method's value-position return, same as the top-
        # level function case above -- direct indexing works, no
        # intermediate variable
        print(sqrrl__eng.scores_by_role()["senior"]._inner[]._name)

        for sqrrl__e in sqrrl__eng._inner[]._sqrrl__ranks:
            print("ranked:", sqrrl__e._inner[]._name)

        # a marked value-position field indexes and chains directly too
        var sqrrl__senior2 = sqrrl__eng._inner[]._sqrrl__rosters[0]["senior"]
        print(sqrrl__senior2._inner[]._name)

        sqrrl__eng.promote_to_lead(sqrrl__bob)
        print("new lead:", sqrrl__eng.lead_name())

        print(sqrrl__eng.headcount(sqrrl___world))
        sqrrl__eng.rename(sqrrl___world, "Platform Engineering")
        print(sqrrl__eng._inner[]._name)

        var sqrrl__dana = sqrrl__make_employee(sqrrl___world, "Dana")
        print(sqrrl__dana._inner[]._name)
    finally:
        sqrrl___world.sqrrl__check_no_leaks()
