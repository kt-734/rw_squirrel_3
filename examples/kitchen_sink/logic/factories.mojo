from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl__JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl__init, sqrrl__World
from schema.address import Address
from schema.assignment import Assignment
from schema.box import Box
from schema.contact_info import ContactInfo
from schema.money import Money
from schema.pair import Pair
from schema.profile import Profile
from schema.department import sqrrl__Department
from schema.employee import sqrrl__Employee
from schema.person import sqrrl__Person
from schema.project import sqrrl__Project
from schema.team import sqrrl__Team
from schema.vendor import sqrrl__Vendor


from schema.money import Money
from schema.address import Address
from schema.contact_info import ContactInfo
from schema.box import Box
from schema.pair import Pair
from schema.profile import Profile
from schema.assignment import Assignment


def sqrrl__make_vendor(mut sqrrl__world: sqrrl__World, name: String) -> sqrrl__Vendor:
    var sqrrl__v = sqrrl__world.Vendor.create(name = name)
    return sqrrl__v

def sqrrl__make_project(mut sqrrl__world: sqrrl__World, name: String, priority: UInt32, sqrrl__vendor: sqrrl__Vendor, budget_cents: Int64) -> sqrrl__Project:
    var sqrrl__p = sqrrl__world.Project.create(name = name, priority = priority, sqrrl__vendor = sqrrl__vendor, budget = Money(budget_cents))
    return sqrrl__p

def sqrrl__make_department(mut sqrrl__world: sqrrl__World, name: String) -> sqrrl__Department:
    var sqrrl__d = sqrrl__world.Department.create(name = name, tags = List[String](), sqrrl__projects = Set[sqrrl__Project](), sqrrl__vendors = Set[sqrrl__Vendor](), skills = Set[String]())
    return sqrrl__d

def sqrrl__hire(mut sqrrl__world: sqrrl__World, name: String, email: String, title: String, years_employed: UInt32, salary: Float64, sqrrl__dept: sqrrl__Department) raises -> sqrrl__Employee:
    var profile = Profile(
        contact=ContactInfo(home=Address("1 Main St", "Springfield"), emails=List[String]()),
        nicknames=None,
        scores=Dict[String, Int](),
        rating=Box[UInt32](0),
        coordinates=Pair[Int, Int](0, 0),
        past_addresses=List[Address](),
        boxed_ratings=List[Box[UInt32]](),
    )
    var sqrrl__e = sqrrl__world.Employee.create(email = email, title = title, years_employed = years_employed, salary = salary, sqrrl__dept = sqrrl__dept, profile = profile^)
    return sqrrl__e

def sqrrl__hire_team(mut sqrrl__world: sqrrl__World, names: List[String], email_suffix: String, starting_years: UInt32, starting_salary: Float64, sqrrl__dept: sqrrl__Department) raises -> List[sqrrl__Employee]:
    var sqrrl__team = List[sqrrl__Employee]()
    var years = starting_years
    var salary = starting_salary
    for name in names:
        var sqrrl__emp = sqrrl__hire(sqrrl__world, name, name + email_suffix, "Engineer", years, salary, sqrrl__dept)
        sqrrl__team.append(sqrrl__emp)
        years += 1
        salary += 5000.0
    return sqrrl__team^

def sqrrl__make_team(mut sqrrl__world: sqrrl__World, name: String, sqrrl__lead_person: sqrrl__Person, role: String) -> sqrrl__Team:
    var assignment = Assignment(person=sqrrl__lead_person, role=role)
    var sqrrl__t = sqrrl__world.Team.create(name = name, lead = assignment^, sqrrl__members = List[sqrrl__Person](), sqrrl__advisor = None)
    return sqrrl__t

def sqrrl__log(mut sqrrl__world: sqrrl__World, message: String) raises:
    # AuditLog is `keepalive` -- discarding the result here is deliberate,
    # not sloppy: there's no local var, no relation field pointing at it,
    # nothing at all keeping this entity alive except keepalive itself.
    _ = sqrrl__world.AuditLog.create(message = message)
