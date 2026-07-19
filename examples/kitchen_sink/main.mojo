from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl___JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl___init, sqrrl___World
from sqrrl__json import sqrrl___begin_init_from_json, sqrrl___end_init_from_json, sqrrl___init_from_json, sqrrl___world_to_json
from schema.address import Address
from schema.assignment import Assignment
from schema.box import Box
from schema.contact_info import ContactInfo
from schema.money import Money
from schema.pair import Pair
from schema.profile import Profile
from schema.employee import sqrrl__Employee
from schema.person import sqrrl__Person
from schema.vendor import sqrrl__Vendor


from schema.money import Money
from schema.address import Address
from schema.contact_info import ContactInfo
from schema.box import Box
from schema.pair import Pair
from schema.profile import Profile
from schema.assignment import Assignment
from logic.factories import sqrrl__make_vendor, sqrrl__make_project, sqrrl__make_department, sqrrl__hire, sqrrl__hire_team, sqrrl__make_team, sqrrl__log


def sqrrl__promote(sqrrl__e: sqrrl__Employee, new_title: String) -> sqrrl__Employee:
    sqrrl__e._inner[].set_title(new_title);
    return sqrrl__e


def main() raises:
    # `@@:` brings `sqrrl___world` into scope, already a real, empty world --
    # everything indented under it runs inside a `try:`, closed by an
    # implicit `finally:` at the end of that indented block (which checks
    # nothing is still alive before the function returns -- a workaround for
    # a Mojo `__del__` ordering bug, see `mojo-del-destructor-ordering-bug.md`/
    # README's "Known limitation"). `@@init()`/`@@@begin_init_from_json(...)`
    # may still be called any number of times afterward, in any control-flow
    # shape (`if restoring: @@@begin_init_from_json(dump); else: @@init();`),
    # each one just replacing whatever `sqrrl___world` currently holds.
    var sqrrl___world = sqrrl___init()
    try:
        # ---- deep dependency chain: Vendor -> Project -> Department -> Employee -> Person -> Team ----
        var sqrrl__acme = sqrrl__make_vendor(sqrrl___world, "Acme Supplies")
        var sqrrl__globex = sqrrl__make_vendor(sqrrl___world, "Globex Corp")

        var sqrrl__website = sqrrl__make_project(sqrrl___world, "Website Revamp", 3, sqrrl__acme, 500000)
        var sqrrl__onboarding = sqrrl__make_project(sqrrl___world, "Onboarding Redesign", 1, sqrrl__globex, 250000)

        var sqrrl__eng = sqrrl__make_department(sqrrl___world, "Engineering")
        var sqrrl__sales = sqrrl__make_department(sqrrl___world, "Sales")

        _ = sqrrl__eng._inner[].add_to_sqrrl__projects(sqrrl__website)
        _ = sqrrl__eng._inner[].add_to_sqrrl__projects(sqrrl__onboarding)
        _ = sqrrl__sales._inner[].add_to_sqrrl__projects(sqrrl__onboarding)
        print("eng project count:", len(sqrrl__eng._inner[]._sqrrl__projects))
        print("departments running onboarding:", len(sqrrl___world.Department.for_sqrrl__projects(sqrrl__onboarding)))

        # Set-wrapped *ordinary* relation field (not `multi`) -- a whole Set
        # assigned/read at once, unlike `multi`'s one-member-at-a-time API.
        var sqrrl__eng_vendors = Set[sqrrl__Vendor]()
        sqrrl__eng_vendors.add(sqrrl__acme)
        sqrrl__eng_vendors.add(sqrrl__globex)
        sqrrl__eng._inner[].set_sqrrl__vendors(sqrrl__eng_vendors^);
        print("eng vendor count (Set-wrapped ordinary field):", len(sqrrl__eng._inner[]._sqrrl__vendors))

        # `multi` on a *plain* (non-relation) field -- Set[String]-backed.
        _ = sqrrl__eng._inner[].add_to_skills("mojo")
        _ = sqrrl__eng._inner[].add_to_skills("distributed-systems")
        print("eng skills:", len(sqrrl__eng._inner[]._skills))
        print("departments with mojo skill:", len(sqrrl___world.Department.for_skills("mojo")))

        var sqrrl__alice_emp = sqrrl__hire(sqrrl___world, "Alice", "alice@example.com", "Engineer", 5, 85000.0, sqrrl__eng)
        var sqrrl__bob_emp = sqrrl__hire(sqrrl___world, "Bob", "bob@example.com", "Sales Rep", 2, 60000.0, sqrrl__sales)

        var sqrrl__alice = sqrrl___world.Person.create(name = "Alice", home = Address("1 Elm St", "Springfield"), sqrrl__job = sqrrl__alice_emp)
        var sqrrl__bob = sqrrl___world.Person.create(name = "Bob", home = Address("2 Oak St", "Shelbyville"), sqrrl__job = sqrrl__bob_emp)

        # Multi-hop chain, four levels deep: Person -> Employee -> Department -> Project.
        print("alice works in:", sqrrl__alice._inner[]._sqrrl__job._inner[]._sqrrl__dept._inner[]._name)

        # unique field's own for_<field> -- raises variant.
        var sqrrl__found_by_email = sqrrl___world.Employee.for_email("bob@example.com")
        print("found by email, title:", sqrrl__found_by_email._inner[]._title)

        var sqrrl__eng_team = sqrrl___world.Employee.for_sqrrl__dept(sqrrl__eng)
        print("eng team size (via for_dept):", len(sqrrl__eng_team))
        for sqrrl__member in sqrrl__eng_team:
            print("a member's title before promotion:", sqrrl__member._inner[]._title)
            sqrrl__member._inner[].set_title("Staff Engineer");
            print("that member's title after writing through the loop variable:", sqrrl__member._inner[]._title)
            break

        var names = List[String]()
        names.append("Carol")
        names.append("Dave")
        var sqrrl__sales_team = sqrrl__hire_team(sqrrl___world, names, "@example.com", 3, 55000.0, sqrrl__sales)
        print("sales team size (via hire_team):", len(sqrrl__sales_team))

        # `count()` -- whole table, O(1), without building a handle for
        # every entity just to len() them.
        print("employee count (via count()):", sqrrl___world.Employee.count())

        # `count_<field>` -- cheaper than len(for_dept(...)), and the one
        # non-raising way to ask a `unique` field "is this value taken".
        print("employees in sales (via count_dept):", sqrrl___world.Employee.count_sqrrl__dept(sqrrl__sales))

        # `group_by_<field>`/`count_by_<field>`/`distinct_<field>` -- every
        # value at once, keyed by the relation field's own target type
        # (tracked the same way `for_<field>`/`all()` are).
        for sqrrl__d in sqrrl___world.Employee.group_by_sqrrl__dept():
            print("department has employees:", sqrrl__d._inner[]._name)
        for entry in sqrrl___world.Employee.count_by_sqrrl__dept().items():
            print("department employee count:", entry.value)
        for sqrrl__d in sqrrl___world.Employee.distinct_sqrrl__dept():
            print("department in use:", sqrrl__d._inner[]._name)

        # `value_eq` -- field-by-field, deliberately different from `==`
        # (id-based): the same handle is `value_eq` with itself, but never
        # with a genuinely different row, however similar its fields are.
        # Opt-in via `equatable` on the struct declaration (`@@struct
        # equatable @@Department:`) -- every field's own type needs to
        # support `!=` to compile, never checked ahead of time (Mojo's own
        # compiler is the one that catches it, same trust-the-compiler
        # reasoning as `unique`/`ordered`/`stats`), so this is confined to
        # structs that actually ask for it. `Employee` doesn't (its
        # `profile: Profile` field isn't `Equatable`, so tagging it
        # `equatable` would never compile) -- `Department` does, since none
        # of its own fields have that problem.
        print("value_eq(eng, eng):", sqrrl__eng.value_eq(sqrrl__eng))
        print("value_eq(eng, sales):", sqrrl__eng.value_eq(sqrrl__sales))

        # `stats salary` -- whole-table, `_by_<field>`, and `_for_<field>`
        # aggregate siblings, all three shapes.
        print("total salary (whole table):", sqrrl___world.Employee.sum_salary())
        print("average salary (whole table):", sqrrl___world.Employee.avg_salary())
        print("lowest salary (whole table):", sqrrl___world.Employee.min_salary())
        print("highest salary (whole table):", sqrrl___world.Employee.max_salary())
        for sqrrl__d in sqrrl___world.Employee.sum_salary_by_sqrrl__dept():
            print("department salary total:", sqrrl__d._inner[]._name)
        print("average sales salary (via avg_salary_for_dept):", sqrrl___world.Employee.avg_salary_for_sqrrl__dept(sqrrl__sales))

        # `ordered` alone (no `stats`) already earns `min_<field>`/
        # `max_<field>` for free -- it already proves `Comparable` for its
        # own range queries above; only `sum_`/`avg_` need `stats` too.
        print("fewest years employed:", sqrrl___world.Employee.min_years_employed())
        print("most years employed:", sqrrl___world.Employee.max_years_employed())

        # ordered field on Employee.
        print("more than 3 years:", len(sqrrl___world.Employee.for_years_employed_greater_than(3)))
        print("at least 3 years:", len(sqrrl___world.Employee.for_years_employed_at_least(3)))
        print("less than 3 years:", len(sqrrl___world.Employee.for_years_employed_less_than(3)))
        print("3 to 4 years inclusive:", len(sqrrl___world.Employee.for_years_employed_between(3, 4)))

        # ordered field on Project too -- the same modifier on a completely
        # different struct's own numeric field.
        print("projects with priority >= 2:", len(sqrrl___world.Project.for_priority_at_least(2)))
        for sqrrl__p in sqrrl___world.Project.for_priority_between(1, 3):
            print("project in priority range:", sqrrl__p._inner[]._name)

        var sqrrl__promoted_bob = sqrrl__promote(sqrrl__bob_emp, "Senior Sales Rep")
        print("bob's new title:", sqrrl__promoted_bob._inner[]._title)

        var tags = List[String]()
        tags.append("fast-paced")
        tags.append("hybrid")
        sqrrl__eng._inner[].set_tags(tags^);
        print("eng tags count (plain field, no backward index):", len(sqrrl__eng._inner[]._tags))

        sqrrl__alice._inner[]._sqrrl__job._inner[].set_title("Junior Engineer");
        print("alice's job title after hop-chain write:", sqrrl__alice._inner[]._sqrrl__job._inner[]._title)

        # A team: plain struct embedding a relation (`Assignment.@@person`),
        # an ordinary List-wrapped relation field, and an Optional-wrapped one.
        var sqrrl__platform_team = sqrrl__make_team(sqrrl___world, "Platform", sqrrl__alice, "Tech Lead")
        var members = List[sqrrl__Person]()
        members.append(sqrrl__alice)
        members.append(sqrrl__bob)
        sqrrl__platform_team._inner[].set_sqrrl__members(members^);
        print("platform team member count:", len(sqrrl__platform_team._inner[]._sqrrl__members))
        print("platform team lead role:", sqrrl__platform_team._inner[]._lead.role)

        # A wrapped relation field can be read, indexed, and have one
        # further field read off the indexed element, all in a single
        # expression -- no intermediate `var @@x = @@platform_team.@@members;`
        # binding needed first.
        print("platform team first member (read+index+field in one expr):", sqrrl__platform_team._inner[]._sqrrl__members[0]._inner[]._name)

        # Iterating a relation field's own read result directly (not a
        # bound variable, not a table-level `for_<field>`/`all()` call)
        # binds the loop variable the same way either of those already do.
        for sqrrl__m in sqrrl__platform_team._inner[]._sqrrl__members:
            print("platform team member:", sqrrl__m._inner[]._name)

        # A plain struct's own relation field, read through a fully
        # unmarked local variable -- `lead_assignment` is never itself
        # `@@`-marked; the explicit `: Assignment` annotation is what lets
        # this parser resolve `.@@person` against `Assignment`'s own
        # relation field, direct Mojo field access under the hood (`Note`/
        # `Assignment` have no generated table of their own to route a
        # `get_<field>` call through).
        var lead_assignment: Assignment = sqrrl__platform_team._inner[]._lead.copy()
        print("platform team lead person:", lead_assignment.person._inner[].get_name())

        sqrrl__platform_team._inner[].set_sqrrl__advisor(Optional(sqrrl__promoted_bob));
        if sqrrl__platform_team._inner[]._sqrrl__advisor:
            print("platform team advisor:", sqrrl__platform_team._inner[]._sqrrl__advisor.value()._inner[].get_title())

        # keepalive: AuditLog entities survive with no local var and no
        # relation field pointing at them, purely via `keepalive`.
        sqrrl__log(sqrrl___world, "started")
        sqrrl__log(sqrrl___world, "did a thing")
        sqrrl__log(sqrrl___world, "finished")
        print("audit log entries kept alive:", len(sqrrl___world.AuditLog.all()))
        for sqrrl__entry in sqrrl___world.AuditLog.all():
            print("audit log entry:", sqrrl__entry._inner[]._message)

        # ---- deep plain-struct nesting + generics, through Employee.profile ----
        var profile = sqrrl__alice_emp._inner[]._profile.copy()
        profile.contact.emails.append("alice@work.example.com")
        profile.scores["mojo"] = 97
        profile.scores["systems"] = 88
        profile.nicknames = List[String]()
        profile.nicknames.value().append("Ali")
        profile.rating = Box[UInt32](5)
        profile.coordinates = Pair[Int, Int](10, -3)
        # A container wrapping a bare, non-generic plain struct, and one
        # wrapping a generic plain struct's own instantiation -- both used to
        # fail from_json the moment they round-tripped through JSON (no
        # sqrrl__from_json[T] dispatch branch existed for the element type),
        # since list_from_json[X]'s own recursion into sqrrl__from_json[X] has
        # no way to special-case X at codegen time.
        profile.past_addresses.append(Address("10 Birch Rd", "Capital City"))
        profile.past_addresses.append(Address("22 Cedar Ln", "Ogdenville"))
        profile.boxed_ratings.append(Box[UInt32](3))
        profile.boxed_ratings.append(Box[UInt32](4))
        sqrrl__alice_emp._inner[].set_profile(profile^);

        var got_profile = sqrrl__alice_emp._inner[]._profile.copy()
        print("alice's city (deep nested plain struct):", got_profile.contact.home.city)
        print("alice's email count:", len(got_profile.contact.emails))
        print("alice's mojo score (Dict field):", got_profile.scores["mojo"])
        print("alice's rating (generic Box[UInt32]):", got_profile.rating.value)
        print("alice's coordinates (generic Pair[Int, Int]):", got_profile.coordinates.first, got_profile.coordinates.second)
        print("alice's nickname count (Optional[List[String]]):", len(got_profile.nicknames.value()))
        print("alice's past address count (List[Address]):", len(got_profile.past_addresses))
        print("alice's first past address city:", got_profile.past_addresses[0].city)
        print("alice's boxed rating count (List[Box[UInt32]]):", len(got_profile.boxed_ratings))
        print("alice's first boxed rating:", got_profile.boxed_ratings[0].value)

        # ---- per-entity JSON round trip ----
        # ---- whole-world JSON round trip, reusing `sqrrl___world` itself --
        # the dump has to happen *before* every entity built above has its
        # actual last mention (the "keep alive" print just below): Mojo's own
        # ASAP destruction drops a local var right after its last textual use,
        # regardless of what unrelated statements come later in the function,
        # so `sqrrl___world.to_json()` called *after* that print would see an
        # empty world -- confirmed empirically (every count read back as 0
        # until this was reordered). Once the dump is taken and "keep alive"
        # has run, nothing is left referencing the current world, so
        # `@@@begin_init_from_json(...)` can safely replace it in place -- no
        # need to hand-thread a second, independent `sqrrl__World`.
        # `sqrrl___world.to_json()` is still the one unavoidably
        # `sqrrl__`-prefixed call here -- there's no `@@`-marked sugar for
        # "dump the current world," only for the reload half.
        var world_json = sqrrl___world_to_json(sqrrl___world)
        print("whole world byte length:", world_json.byte_length())

        print(
            "keep alive:",
            sqrrl__alice._inner[]._name, sqrrl__bob._inner[]._name, sqrrl__eng._inner[]._name, sqrrl__sales._inner[]._name,
            sqrrl__alice_emp._inner[]._title, sqrrl__bob_emp._inner[]._title, sqrrl__promoted_bob._inner[]._title,
            sqrrl__sales_team[0]._inner[]._title, sqrrl__sales_team[1]._inner[]._title,
            sqrrl__found_by_email._inner[]._title, sqrrl__website._inner[]._name, sqrrl__onboarding._inner[]._name,
            sqrrl__platform_team._inner[]._name,
        )

        var sqrrl___temp_keep_alives = sqrrl___begin_init_from_json(sqrrl___world, world_json)
        print("reloaded department count:", len(sqrrl___world.Department.all()))
        print("reloaded employee count:", len(sqrrl___world.Employee.all()))
        var sqrrl__reloaded_alice = sqrrl___world.Employee.for_email("alice@example.com")
        print("reloaded alice's dept:", sqrrl__reloaded_alice._inner[]._sqrrl__dept._inner[]._name)
        print("reloaded alice's rating survived:", sqrrl__reloaded_alice._inner[]._profile.rating.value)
        print("reloaded audit log count:", len(sqrrl___world.AuditLog.all()))

        # `@@reloaded_alice` is a real, independently-held handle now --
        # everything else `@@@begin_init_from_json(...)` only retained
        # *temporarily* (`TempKeepAlives`) can be dropped in one shot via
        # `@@@end_init_from_json()`. Department count drops from 2 to 1 --
        # `sales` (Bob/Carol/Dave's own department, nothing here still
        # references) goes with the drop; `eng` survives, kept alive
        # transitively through `@@reloaded_alice`'s own `dept` relation
        # field, since she's referenced again below.
        print("reloaded department count before finalize:", len(sqrrl___world.Department.all()))
        sqrrl___end_init_from_json(sqrrl___temp_keep_alives^)
        print("reloaded department count after finalize:", len(sqrrl___world.Department.all()))
        print("reloaded alice's title survives finalize:", sqrrl__reloaded_alice._inner[]._title)
    finally:
        sqrrl___world.sqrrl__check_no_leaks()
