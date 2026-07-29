from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl___init, sqrrl___World
from main_impl import sqrrl__Department
from main_impl import sqrrl__Employee

# Every combination of "does this name need @@ marking?" for a struct
# field, a hand-written plain struct field, a def/method parameter, and
# a top-level function/method's own name.
#
# Two independent rules now, not one -- and both boil down to the same
# underlying principle: `@@` marks a name only when its own value is
# *directly* an entity, never when it's merely a container of one. That
# principle applies uniformly to struct fields, local variables, for-loop
# variables, AND def/method parameters alike (a local var-decl's own
# container constructor stays bare exactly like a container field does,
# see `scores_dict`/`ranks_dict`/`rosters_list` in `main()` below; a
# container parameter -- `extra: List[@@Employee]` in `greet_team` below
# -- is bare the same way). A *single* (non-container) relation still
# needs marking wherever it appears, parameter included (`@@e: @@Employee`).
#
# 1. A *field*'s own name needs `@@` only when its type is a *single*
#    (non-container) relation (`@@lead: @@Employee`). A *container* of a
#    relation (`List[@@Employee]`, a Dict with the relation in either
#    argument position, arbitrarily nested) is always bare -- the type
#    itself already says it's a relation, so the field's own name no
#    longer needs to repeat that. `is_directly_entity_reachable` still
#    decides *whether* a type is relation-shaped at all (a bare relation,
#    or a wrapper's own first type parameter recursively satisfying the
#    rule, or -- for a wrapper with at least two type parameters -- its
#    second parameter too); `is_container_type` (is the type itself
#    parameterized at all) is what now decides whether that relation's
#    own field name still needs marking or not.
#
# 2. A top-level function's or method's own name no longer signals its
#    *return shape* at all -- it can return anything (plain, a single
#    relation, or a container of one) and stays completely bare either
#    way. `@@@` is the one spelling that remains, and it means only one
#    thing now: this function/method needs `sqrrl___world` (because it
#    constructs a new entity, or calls something that does) -- completely
#    decoupled from what it returns.
#
# Position 1 and position 2 (of a two-argument wrapper) still differ in
# *how* they're reached: iterating a container (`for x in container:`)
# only ever exposes position 1 -- `Dict[K, V]`'s own iteration only ever
# yields `K`, never `V`, the same restriction real Mojo `Dict` iteration
# has. Position 2 is only reachable by *indexing* (`container[key]`). A
# relation confined to position 2 can still be indexed and chained off
# directly, but a `for @@x in ...:` over it is rejected -- iterating it
# never yields an entity, so the loop variable must be bare instead.
#
# A def/method *parameter*'s own marking follows rule 1 exactly, same as
# a field: single relation marked (`@@e: @@Employee`), container of one
# bare (`extra: List[@@Employee]`).

# -- top-level functions: no marking needed on the function's own name
# at all now, regardless of return shape -- only `@@@` remains, and only
# for "needs sqrrl___world" --

def shout(name: String) -> String:
    # fully plain -- no @@ anywhere, needs no marking at all (unaffected
    # by any of this -- always worked this way)
    return name.upper()

def scores_for(sqrrl__d: sqrrl__Department) -> Dict[String, sqrrl__Employee]:
    # marked parameter (unaffected, separate axis), bare function name --
    # a value-position relation is reachable by indexing, and a bare
    # function's own call is tracked (`ctx.bare_function_returns`)
    # regardless of what it returns, so leaving this bare loses nothing
    return sqrrl__d._inner[]._sqrrl__scores.copy()

def get_lead(sqrrl__d: sqrrl__Department) -> sqrrl__Employee:
    # bare relation return -- no marking needed; doesn't construct
    # anything, so no sqrrl___world either
    return sqrrl__d._inner[]._sqrrl__lead

def get_team(sqrrl__d: sqrrl__Department) -> List[sqrrl__Employee]:
    # container return, same reasoning
    return sqrrl__d._inner[]._sqrrl__team.copy()

def sqrrl__make_employee(mut sqrrl___world: sqrrl___World, name: String) raises -> sqrrl__Employee:
    # constructs an entity -- genuinely needs sqrrl___world, so `@@@`
    # stays -- the one axis this milestone doesn't touch
    var sqrrl__e = sqrrl___world.Employee.create(name = name)
    return sqrrl__e

def main() raises:
    var sqrrl___world = sqrrl___init()
    try:
        var sqrrl__alice = sqrrl___world.Employee.create(name = "Alice")
        var sqrrl__bob = sqrrl___world.Employee.create(name = "Bob")
        var sqrrl__carol = sqrrl___world.Employee.create(name = "Carol")

        # local variables follow the exact same rule as fields -- `@@`
        # marks a name only when its own value is *directly* an entity,
        # never when it's merely a container of one, regardless of
        # whether that name is a struct field or a local variable. A
        # container constructor's own relation can be inferred from
        # either the first argument (List[@@Type]()) or, for a two-
        # argument wrapper, the second (Dict[String, @@Type]()) -- at
        # any nesting depth -- but the *destination* stays bare either
        # way, since the Dict/List itself is never the entity.
        var scores_dict = Dict[String, sqrrl__Employee]()
        scores_dict["senior"] = sqrrl__alice;
        var rosters_list = List[Dict[String, sqrrl__Employee]]()
        rosters_list.append(scores_dict.copy())
        var ranks_dict = Dict[sqrrl__Employee, String]()
        ranks_dict[sqrrl__alice] = "principal";

        var sqrrl__eng = sqrrl___world.Department.create(name = "Engineering", sqrrl__lead = sqrrl__alice, sqrrl__team = [sqrrl__alice, sqrrl__bob], sqrrl__ranks = ranks_dict^, sqrrl__groups = [[sqrrl__alice], [sqrrl__bob]], sqrrl__scores = scores_dict^, sqrrl__rosters = rosters_list^)

        print(shout("quiet"))

        # a bare function's value-position return can still be indexed
        # and chained directly, no intermediate variable required --
        # but if you *do* bind the result to a variable meant to persist
        # (not immediately chained/iterated), that destination still
        # needs `@@` (`@@senior`, not `senior`), since the value itself
        # is a real entity -- mandatory marking dropped for the
        # function's own name, not for how an entity-shaped value has to
        # be bound afterward.
        var sqrrl__senior = scores_for(sqrrl__eng)["senior"]
        print(sqrrl__senior._inner[]._name)

        # bind a bare function's return, then use it
        var sqrrl__lead = get_lead(sqrrl__eng)
        print(sqrrl__lead._inner[]._name)

        # direct for-loop over a bare function's return, no binding --
        # the loop variable itself still needs `@@` since it's bound to
        # a real entity each iteration
        for sqrrl__m in get_team(sqrrl__eng):
            print("team member:", sqrrl__m._inner[]._name)

        # direct access-chain off a bare function's return, no binding
        # and no loop
        print(get_lead(sqrrl__eng)._inner[]._name)

        # a for-loop directly over a value-position (Dict-key-yielding)
        # bare call needs a *bare* loop variable -- iterating never
        # reaches the value/entity, only indexing does, so '@@key' here
        # would be rejected
        for key in scores_for(sqrrl__eng):
            print("score key:", key)

        print(sqrrl__eng.lead_name())
        print("contains bob:", sqrrl__eng.contains(sqrrl__bob))
        print(sqrrl__eng.greet_team([sqrrl__carol]))

        # a bare method's own call works exactly the same way -- bind-
        # then-use, direct for-loop, and direct chain all work, no
        # intermediate variable required
        var sqrrl__teamlead = sqrrl__eng.team_lead()
        print(sqrrl__teamlead._inner[]._name)

        for sqrrl__m in sqrrl__eng.roster():
            print("roster member:", sqrrl__m._inner[]._name)

        print(sqrrl__eng.team_lead()._inner[]._name)

        # a bare method's value-position return, same as the top-level
        # function case above -- direct indexing works, no intermediate
        # variable
        print(sqrrl__eng.scores_by_role()["senior"]._inner[]._name)

        for sqrrl__e in sqrrl__eng._inner[]._sqrrl__ranks:
            print("ranked:", sqrrl__e._inner[]._name)

        # a bare value-position field indexes and chains directly too
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
