from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl__init, sqrrl__World


# Every combination of "does this name need @@ marking?" for a struct
# field, a hand-written plain struct field, a def/method parameter, and
# a top-level function's own name -- all governed by one rule:
# is_directly_entity_iterable: a bare relation (@@Type), or a wrapper's
# own *first* type parameter (recursively) satisfying the same rule --
# not tied to any specific wrapper name. A relation confined to a
# container's non-first position (Dict[String, @@Employee], the value)
# is never actually reachable through that type's own iteration/access
# surface (Dict iteration only ever yields keys), so it stays unmarked.


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
    var _scores: Dict[String, sqrrl__Employee]
    var _rosters: List[Dict[String, sqrrl__Employee]]

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

    def set_scores(mut self, var v: Dict[String, sqrrl__Employee]):
        self._scores = v^

    def set_rosters(mut self, var v: List[Dict[String, sqrrl__Employee]]):
        self._rosters = v^

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
    def get_scores(self) -> ref [self._scores] Dict[String, sqrrl__Employee]:
        return self._scores

    @always_inline
    def get_rosters(self) -> ref [self._rosters] List[Dict[String, sqrrl__Employee]]:
        return self._rosters


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
        for sqrrl__m in  self._inner[]._sqrrl__team:
            if sqrrl__m == sqrrl__e:
                return True
        return False

    def greet_team(self, sqrrl__extra: List[sqrrl__Employee]) -> String:
        var out = String("")
        for sqrrl__m in  self._inner[]._sqrrl__team:
            out += sqrrl__m._inner[]._name + " "
        for sqrrl__m in  sqrrl__extra:
            out += sqrrl__m._inner[]._name + " "
        return String(out.strip())

    # -- methods: a method's own name is never '@@'-marked, even when it
    # returns a relation -- only top-level functions/var-decls/fields get
    # the "single @@ vs @@@" mandatory-marking treatment; a method stays
    # bare unless it genuinely needs sqrrl__world, in which case it's
    # '@@@' the same way a top-level function is. A method's own return
    # value also isn't registered as an entity anywhere (unlike a
    # top-level function's, which now is) -- calling one and discarding
    # the result, or querying back through an already-tracked field, are
    # the two shapes that work; binding it to a fresh '@@'-marked local
    # is a separate, unaddressed gap this example doesn't exercise.
    def promote_to_lead(self, sqrrl__e: sqrrl__Employee):
        self._inner[].set_sqrrl__lead(sqrrl__e);

    def headcount(self, mut sqrrl__world: sqrrl__World) raises -> String:
        return self._inner[]._name + ": " + String(sqrrl__world.Employee.count())

    def rename(self, mut sqrrl__world: sqrrl__World, new_name: String) raises:
        if sqrrl__world.Department.count() > 0:
            self._inner[].set_name(new_name);




struct sqrrl__DepartmentIndexes(Movable, ImplicitlyDeletable):
    var name: UniqueIndex[String]

    def __init__(out self):
        self.name = UniqueIndex[String]()


struct sqrrl__DepartmentTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__DepartmentIndexes, sqrrl__DepartmentInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__DepartmentIndexes, sqrrl__DepartmentInner](sqrrl__DepartmentIndexes()))

    def create(mut self, *, name: String, sqrrl__lead: sqrrl__Employee, var sqrrl__team: List[sqrrl__Employee], var sqrrl__ranks: Dict[sqrrl__Employee, String], var sqrrl__groups: List[List[sqrrl__Employee]], var scores: Dict[String, sqrrl__Employee], var rosters: List[Dict[String, sqrrl__Employee]]) raises -> sqrrl__Department:
        if self.storage[].indexes.name.contains(name):
            raise Error("UniqueConstraintViolation: 'name' already in use by another entity")
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__DepartmentInner(_id=id, _table=self.storage, _name=name, _sqrrl__lead=sqrrl__lead, _sqrrl__team=sqrrl__team^, _sqrrl__ranks=sqrrl__ranks^, _sqrrl__groups=sqrrl__groups^, _scores=scores^, _rosters=rosters^))
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


def scores_for(sqrrl__d: sqrrl__Department) -> Dict[String, sqrrl__Employee]:
    # marked parameter, but the return type's only relation is in a
    # Dict's value position -- not directly iterable, so the function's
    # own name stays bare; the embedded @@Employee still resolves to
    # sqrrl__Employee wherever it appears in the return type
    return sqrrl__d._inner[]._scores.copy()


def sqrrl__get_lead(sqrrl__d: sqrrl__Department) -> sqrrl__Employee:
    # bare relation return -- needs marking, but not sqrrl__world (only
    # hops through an existing relation, never constructs one)
    return sqrrl__d._inner[]._sqrrl__lead


def sqrrl__get_team(sqrrl__d: sqrrl__Department) -> List[sqrrl__Employee]:
    # @@container return, same reasoning
    return sqrrl__d._inner[]._sqrrl__team.copy()


def sqrrl__make_employee(mut sqrrl__world: sqrrl__World, name: String) raises -> sqrrl__Employee:
    # constructs an entity -- genuinely needs sqrrl__world
    var sqrrl__e = sqrrl__world.Employee.create(name = name)
    return sqrrl__e


def main() raises:
    var sqrrl__world = sqrrl__init()
    try:
        var sqrrl__alice = sqrrl__world.Employee.create(name = "Alice")
        var sqrrl__bob = sqrrl__world.Employee.create(name = "Bob")
        var sqrrl__carol = sqrrl__world.Employee.create(name = "Carol")

        var scores_dict = Dict[String, sqrrl__Employee]()
        scores_dict["senior"] = sqrrl__alice
        var rosters_list = List[Dict[String, sqrrl__Employee]]()
        rosters_list.append(scores_dict.copy())
        var ranks_dict = Dict[sqrrl__Employee, String]()
        ranks_dict[sqrrl__alice] = "principal"

        var sqrrl__eng = sqrrl__world.Department.create(name = "Engineering", sqrrl__lead = sqrrl__alice, sqrrl__team = [sqrrl__alice, sqrrl__bob], sqrrl__ranks = ranks_dict^, sqrrl__groups = [[sqrrl__alice], [sqrrl__bob]], scores = scores_dict^, rosters = rosters_list^)

        print(shout("quiet"))
        var sqrrl__senior: sqrrl__Employee= scores_for(sqrrl__eng)["senior"]
        print(sqrrl__senior._inner[]._name)

        # bind a marked function's return, then use it
        var sqrrl__lead = sqrrl__get_lead(sqrrl__eng)
        print(sqrrl__lead._inner[]._name)

        # direct for-loop over a marked function's return, no binding
        for sqrrl__m in  sqrrl__get_team(sqrrl__eng):
            print("team member:", sqrrl__m._inner[]._name)

        # direct access-chain off a marked function's return, no
        # binding and no loop
        print(sqrrl__get_lead(sqrrl__eng)._inner[]._name)

        print(sqrrl__eng.lead_name())
        print("contains bob:", sqrrl__eng.contains(sqrrl__bob))
        print(sqrrl__eng.greet_team([sqrrl__carol]))

        for sqrrl__e in  sqrrl__eng._inner[]._sqrrl__ranks:
            print("ranked:", sqrrl__e._inner[]._name)
        var sqrrl__senior2: sqrrl__Employee= sqrrl__eng._inner[]._rosters[0]["senior"]
        print(sqrrl__senior2._inner[]._name)

        sqrrl__eng.promote_to_lead(sqrrl__bob)
        print("new lead:", sqrrl__eng.lead_name())

        print(sqrrl__eng.headcount(sqrrl__world))
        sqrrl__eng.rename(sqrrl__world, "Platform Engineering")
        print(sqrrl__eng._inner[]._name)

        var sqrrl__dana = sqrrl__make_employee(sqrrl__world, "Dana")
        print(sqrrl__dana._inner[]._name)
    finally:
        sqrrl__world.sqrrl__check_no_leaks()
