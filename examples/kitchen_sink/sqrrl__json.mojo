from std.memory import ArcPointer
from std.collections import Set
from squirrel_runtime.json import sqrrl___JsonScanner, sqrrl__json_string_literal, sqrrl__json_bool_literal, sqrrl__to_json_default, sqrrl__from_json_default, sqrrl__movable_rebind
from sqrrl__world import sqrrl___World, sqrrl___init
from schema.team import sqrrl__Team, sqrrl__TeamInner, sqrrl__TeamTable
from schema.person import sqrrl__Person, sqrrl__PersonInner, sqrrl__PersonTable
from schema.vendor import sqrrl__Vendor, sqrrl__VendorInner, sqrrl__VendorTable
from schema.department import sqrrl__Department, sqrrl__DepartmentInner, sqrrl__DepartmentTable
from schema.audit_log import sqrrl__AuditLog, sqrrl__AuditLogInner, sqrrl__AuditLogTable
from schema.employee import sqrrl__Employee, sqrrl__EmployeeInner, sqrrl__EmployeeTable
from schema.project import sqrrl__Project, sqrrl__ProjectInner, sqrrl__ProjectTable
from schema.box import Box
from schema.money import Money
from schema.pair import Pair
from schema.profile import Profile
from schema.contact_info import ContactInfo
from schema.assignment import Assignment
from schema.address import Address
from schema.grid_module import Grid, sqrrl__Grid_to_json, sqrrl__Grid_from_json


def sqrrl__List_to_json[T: Movable](value: List[T], world: sqrrl___World) -> String:
    var out = String("[")
    for i in range(len(value)):
        if i > 0:
            out += ","
        out += sqrrl__to_json(value[i], world)
    out += "]"
    return out^


def sqrrl__List_from_json[T: Movable & ImplicitlyDeletable](mut sc: sqrrl___JsonScanner, world: sqrrl___World) raises -> List[T]:
    var out = List[T]()
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            out.append(sqrrl__from_json[T](sc, world))
            if sc.try_consume_byte(UInt8(ord(","))):
                continue
            sc.expect_byte(UInt8(ord("]")))
            break
    return out^


def sqrrl__Set_to_json[T: Movable & ImplicitlyDeletable & Hashable & Equatable](value: Set[T], world: sqrrl___World) -> String:
    var out = String("[")
    var first = True
    for elem in value:
        if not first:
            out += ","
        first = False
        out += sqrrl__to_json(elem, world)
    out += "]"
    return out^


def sqrrl__Set_from_json[T: Copyable & ImplicitlyDeletable & Hashable & Equatable](mut sc: sqrrl___JsonScanner, world: sqrrl___World) raises -> Set[T]:
    var out = Set[T]()
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            out.add(sqrrl__from_json[T](sc, world))
            if sc.try_consume_byte(UInt8(ord(","))):
                continue
            sc.expect_byte(UInt8(ord("]")))
            break
    return out^


def sqrrl__Optional_to_json[T: Movable](value: Optional[T], world: sqrrl___World) -> String:
    if value:
        return sqrrl__to_json(value.value(), world)
    return "null"


def sqrrl__Optional_from_json[T: Movable & ImplicitlyDeletable](mut sc: sqrrl___JsonScanner, world: sqrrl___World) raises -> Optional[T]:
    if sc.try_consume_literal("null"):
        return None
    return sqrrl__from_json[T](sc, world)


def sqrrl__Dict_to_json[K: Movable & Hashable & Equatable, V: Movable](value: Dict[K, V], world: sqrrl___World) -> String:
    var out = String("[")
    var first = True
    for entry in value.items():
        if not first:
            out += ","
        first = False
        out += "[" + sqrrl__to_json(entry.key, world) + "," + sqrrl__to_json(entry.value, world) + "]"
    out += "]"
    return out^


def sqrrl__Dict_from_json[K: Copyable & ImplicitlyDeletable & Hashable & Equatable, V: Copyable & ImplicitlyDeletable](mut sc: sqrrl___JsonScanner, world: sqrrl___World) raises -> Dict[K, V]:
    var out = Dict[K, V]()
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var k = sqrrl__from_json[K](sc, world)
            sc.expect_byte(UInt8(ord(",")))
            var v = sqrrl__from_json[V](sc, world)
            sc.expect_byte(UInt8(ord("]")))
            out[k.copy()] = v.copy()
            if sc.try_consume_byte(UInt8(ord(","))):
                continue
            sc.expect_byte(UInt8(ord("]")))
            break
    return out^


def sqrrl__to_json[T: AnyType](value: T, world: sqrrl___World) -> String:
    comptime if False:
        pass
    elif T == sqrrl__Person:
        return String(rebind[sqrrl__Person](value).id())
    elif T == List[sqrrl__Person]:
        return sqrrl__List_to_json(rebind[List[sqrrl__Person]](value), world)
    elif T == Optional[sqrrl__Employee]:
        return sqrrl__Optional_to_json(rebind[Optional[sqrrl__Employee]](value), world)
    elif T == sqrrl__Employee:
        return String(rebind[sqrrl__Employee](value).id())
    elif T == Grid[String, sqrrl__Employee]:
        return sqrrl__Grid_to_json(rebind[Grid[String, sqrrl__Employee]](value), world)
    elif T == List[String]:
        return sqrrl__List_to_json(rebind[List[String]](value), world)
    elif T == Set[sqrrl__Vendor]:
        return sqrrl__Set_to_json(rebind[Set[sqrrl__Vendor]](value), world)
    elif T == sqrrl__Vendor:
        return String(rebind[sqrrl__Vendor](value).id())
    elif T == sqrrl__Department:
        return String(rebind[sqrrl__Department](value).id())
    elif T == Optional[List[String]]:
        return sqrrl__Optional_to_json(rebind[Optional[List[String]]](value), world)
    elif T == Dict[String, Int]:
        return sqrrl__Dict_to_json(rebind[Dict[String, Int]](value), world)
    elif T == List[Address]:
        return sqrrl__List_to_json(rebind[List[Address]](value), world)
    elif T == List[Box[UInt32]]:
        return sqrrl__List_to_json(rebind[List[Box[UInt32]]](value), world)
    elif T == Assignment:
        return sqrrl__Assignment_to_json(rebind[Assignment](value), world)
    elif T == Address:
        return sqrrl__Address_to_json(rebind[Address](value), world)
    elif T == Profile:
        return sqrrl__Profile_to_json(rebind[Profile](value), world)
    elif T == ContactInfo:
        return sqrrl__ContactInfo_to_json(rebind[ContactInfo](value), world)
    elif T == Box[UInt32]:
        return sqrrl__Box_to_json[UInt32](rebind[Box[UInt32]](value), world)
    elif T == Pair[Int, Int]:
        return sqrrl__Pair_to_json[Int, Int](rebind[Pair[Int, Int]](value), world)
    elif T == Money:
        return sqrrl__Money_to_json(rebind[Money](value), world)
    else:
        return sqrrl__to_json_default(value)


def sqrrl__from_json[T: Movable & ImplicitlyDeletable](mut sc: sqrrl___JsonScanner, world: sqrrl___World) raises -> T:
    comptime if False:
        pass
    elif T == sqrrl__Person:
        return sqrrl__movable_rebind[sqrrl__Person, T](sqrrl__Person(world.Person.storage[].handle_for(UInt32(sc.parse_json_int()))))
    elif T == List[sqrrl__Person]:
        return sqrrl__movable_rebind[List[sqrrl__Person], T](sqrrl__List_from_json[sqrrl__Person](sc, world))
    elif T == Optional[sqrrl__Employee]:
        return sqrrl__movable_rebind[Optional[sqrrl__Employee], T](sqrrl__Optional_from_json[sqrrl__Employee](sc, world))
    elif T == sqrrl__Employee:
        return sqrrl__movable_rebind[sqrrl__Employee, T](sqrrl__Employee(world.Employee.storage[].handle_for(UInt32(sc.parse_json_int()))))
    elif T == Grid[String, sqrrl__Employee]:
        return sqrrl__movable_rebind[Grid[String, sqrrl__Employee], T](sqrrl__Grid_from_json[String, sqrrl__Employee](sc, world))
    elif T == List[String]:
        return sqrrl__movable_rebind[List[String], T](sqrrl__List_from_json[String](sc, world))
    elif T == Set[sqrrl__Vendor]:
        return sqrrl__movable_rebind[Set[sqrrl__Vendor], T](sqrrl__Set_from_json[sqrrl__Vendor](sc, world))
    elif T == sqrrl__Vendor:
        return sqrrl__movable_rebind[sqrrl__Vendor, T](sqrrl__Vendor(world.Vendor.storage[].handle_for(UInt32(sc.parse_json_int()))))
    elif T == sqrrl__Department:
        return sqrrl__movable_rebind[sqrrl__Department, T](sqrrl__Department(world.Department.storage[].handle_for(UInt32(sc.parse_json_int()))))
    elif T == Optional[List[String]]:
        return sqrrl__movable_rebind[Optional[List[String]], T](sqrrl__Optional_from_json[List[String]](sc, world))
    elif T == Dict[String, Int]:
        return sqrrl__movable_rebind[Dict[String, Int], T](sqrrl__Dict_from_json[String, Int](sc, world))
    elif T == List[Address]:
        return sqrrl__movable_rebind[List[Address], T](sqrrl__List_from_json[Address](sc, world))
    elif T == List[Box[UInt32]]:
        return sqrrl__movable_rebind[List[Box[UInt32]], T](sqrrl__List_from_json[Box[UInt32]](sc, world))
    elif T == Assignment:
        return sqrrl__movable_rebind[Assignment, T](sqrrl__Assignment_from_json(sc, world))
    elif T == Address:
        return sqrrl__movable_rebind[Address, T](sqrrl__Address_from_json(sc, world))
    elif T == Profile:
        return sqrrl__movable_rebind[Profile, T](sqrrl__Profile_from_json(sc, world))
    elif T == ContactInfo:
        return sqrrl__movable_rebind[ContactInfo, T](sqrrl__ContactInfo_from_json(sc, world))
    elif T == Box[UInt32]:
        return sqrrl__movable_rebind[Box[UInt32], T](sqrrl__Box_from_json[UInt32](sc, world))
    elif T == Pair[Int, Int]:
        return sqrrl__movable_rebind[Pair[Int, Int], T](sqrrl__Pair_from_json[Int, Int](sc, world))
    elif T == Money:
        return sqrrl__movable_rebind[Money, T](sqrrl__Money_from_json(sc, world))
    else:
        return sqrrl__from_json_default[T](sc)

def sqrrl__Team_to_json(e: sqrrl__Team, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"name":'
    out += sqrrl__to_json(e._inner[].get_name(), world)
    out += ","
    out += '"lead":'
    out += sqrrl__Assignment_to_json(e._inner[].get_lead(), world)
    out += ","
    out += '"members":'
    ref fv_members = e._inner[].get_sqrrl__members()
    var ds1 = String("[")
    var dfirst1 = True
    for dv1 in fv_members:
        if not dfirst1:
            ds1 += ","
        ds1 += String(dv1.id())
        dfirst1 = False
    ds1 += "]"
    out += ds1
    out += ","
    out += '"advisor":'
    ref fv_advisor = e._inner[].get_sqrrl__advisor()
    var ds2: String
    if fv_advisor:
        ds2 = String(fv_advisor.value().id())
    else:
        ds2 = "null"
    out += ds2
    out += ","
    out += '"directory":'
    ref fv_directory = e._inner[].get_sqrrl__directory()
    out += sqrrl__Grid_to_json(fv_directory, world)
    out += "}"
    return out^

def sqrrl__Team_from_json_with_id(table: sqrrl__TeamTable, world: sqrrl___World, id: UInt32, mut sc: sqrrl___JsonScanner) raises -> sqrrl__Team:
    var parsed_name: Optional[String] = None
    var parsed_lead: Optional[Assignment] = None
    var parsed_members: Optional[List[sqrrl__Person]] = None
    var parsed_advisor: Optional[Optional[sqrrl__Employee]] = None
    var parsed_directory: Optional[Grid[String, sqrrl__Employee]] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "name":
                parsed_name = sc.parse_json_string()
            elif key == "lead":
                parsed_lead = sqrrl__Assignment_from_json(sc, world)
            elif key == "members":
                var nc1 = List[sqrrl__Person]()
                sc.expect_byte(UInt8(ord("[")))
                if not sc.try_consume_byte(UInt8(ord("]"))):
                    while True:
                        nc1.append(sqrrl__Person(world.Person.storage[].handle_for(UInt32(sc.parse_json_int()))))
                        if not sc.try_consume_byte(UInt8(ord(","))):
                            break
                    sc.expect_byte(UInt8(ord("]")))
                parsed_members = nc1^
            elif key == "advisor":
                var nc1: Optional[sqrrl__Employee]
                if sc.try_consume_literal("null"):
                    nc1 = Optional[sqrrl__Employee]()
                else:
                    nc1 = Optional[sqrrl__Employee](sqrrl__Employee(world.Employee.storage[].handle_for(UInt32(sc.parse_json_int()))))
                parsed_advisor = nc1^
            elif key == "directory":
                parsed_directory = sqrrl__Grid_from_json[String, sqrrl__Employee](sc, world)
            else:
                raise Error("InvalidJson: unknown field " + key + " for Team")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_name:
        raise Error("InvalidJson: missing field name for Team")
    if not parsed_lead:
        raise Error("InvalidJson: missing field lead for Team")
    if not parsed_members:
        raise Error("InvalidJson: missing field members for Team")
    if not parsed_advisor:
        raise Error("InvalidJson: missing field advisor for Team")
    if not parsed_directory:
        raise Error("InvalidJson: missing field directory for Team")
    table.storage[].alloc_specific_id(id)
    var v_name = parsed_name.value()
    var v_lead = parsed_lead.take()
    var v_members = parsed_members.take()
    var v_advisor = parsed_advisor.take()
    var v_directory = parsed_directory.take()
    var inner = ArcPointer(sqrrl__TeamInner(_id=id, _table=table.storage, _name=v_name, _lead=v_lead^, _sqrrl__members=v_members^, _sqrrl__advisor=v_advisor^, _sqrrl__directory=v_directory^))
    table.storage[].register_weak(id, inner)
    return sqrrl__Team(inner^)

def sqrrl__Team_all_to_json(table: sqrrl__TeamTable, world: sqrrl___World) -> String:
    var out = String("[")
    var first = True
    for id in table.storage[].all():
        if not first:
            out += ","
        var e = sqrrl__Team(table.storage[].handle_for(id))
        out += "[" + String(id) + "," + sqrrl__Team_to_json(e, world) + "]"
        first = False
    out += "]"
    return out^

def sqrrl__Team_all_from_json(table: sqrrl__TeamTable, world: sqrrl___World, mut temp: List[sqrrl__Team], mut sc: sqrrl___JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__Team_from_json_with_id(table, world, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            temp.append(e)
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

def sqrrl__Person_to_json(e: sqrrl__Person, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"name":'
    out += sqrrl__to_json(e._inner[].get_name(), world)
    out += ","
    out += '"home":'
    out += sqrrl__to_json(e._inner[].get_home(), world)
    out += ","
    out += '"job":'
    out += String(e._inner[].get_sqrrl__job().id())
    out += "}"
    return out^

def sqrrl__Person_from_json_with_id(table: sqrrl__PersonTable, world: sqrrl___World, id: UInt32, mut sc: sqrrl___JsonScanner) raises -> sqrrl__Person:
    var parsed_name: Optional[String] = None
    var parsed_home: Optional[Address] = None
    var parsed_job: Optional[sqrrl__Employee] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "name":
                parsed_name = sc.parse_json_string()
            elif key == "home":
                parsed_home = sqrrl__Address_from_json(sc, world)
            elif key == "job":
                var rid_job = UInt32(sc.parse_json_int())
                parsed_job = sqrrl__Employee(world.Employee.storage[].handle_for(rid_job))
            else:
                raise Error("InvalidJson: unknown field " + key + " for Person")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_name:
        raise Error("InvalidJson: missing field name for Person")
    if not parsed_home:
        raise Error("InvalidJson: missing field home for Person")
    if not parsed_job:
        raise Error("InvalidJson: missing field job for Person")
    table.storage[].alloc_specific_id(id)
    var v_name = parsed_name.value()
    var v_home = parsed_home.take()
    var v_job = parsed_job.value()
    var inner = ArcPointer(sqrrl__PersonInner(_id=id, _table=table.storage, _name=v_name, _home=v_home^, _sqrrl__job=v_job))
    table.storage[].register_weak(id, inner)
    return sqrrl__Person(inner^)

def sqrrl__Person_all_to_json(table: sqrrl__PersonTable, world: sqrrl___World) -> String:
    var out = String("[")
    var first = True
    for id in table.storage[].all():
        if not first:
            out += ","
        var e = sqrrl__Person(table.storage[].handle_for(id))
        out += "[" + String(id) + "," + sqrrl__Person_to_json(e, world) + "]"
        first = False
    out += "]"
    return out^

def sqrrl__Person_all_from_json(table: sqrrl__PersonTable, world: sqrrl___World, mut temp: List[sqrrl__Person], mut sc: sqrrl___JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__Person_from_json_with_id(table, world, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            temp.append(e)
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

def sqrrl__Vendor_to_json(e: sqrrl__Vendor, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"name":'
    out += sqrrl__to_json(e._inner[].get_name(), world)
    out += "}"
    return out^

def sqrrl__Vendor_from_json_with_id(table: sqrrl__VendorTable, world: sqrrl___World, id: UInt32, mut sc: sqrrl___JsonScanner) raises -> sqrrl__Vendor:
    var parsed_name: Optional[String] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "name":
                parsed_name = sc.parse_json_string()
            else:
                raise Error("InvalidJson: unknown field " + key + " for Vendor")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_name:
        raise Error("InvalidJson: missing field name for Vendor")
    table.storage[].alloc_specific_id(id)
    var v_name = parsed_name.value()
    var inner = ArcPointer(sqrrl__VendorInner(_id=id, _table=table.storage, _name=v_name))
    table.storage[].register_weak(id, inner)
    return sqrrl__Vendor(inner^)

def sqrrl__Vendor_all_to_json(table: sqrrl__VendorTable, world: sqrrl___World) -> String:
    var out = String("[")
    var first = True
    for id in table.storage[].all():
        if not first:
            out += ","
        var e = sqrrl__Vendor(table.storage[].handle_for(id))
        out += "[" + String(id) + "," + sqrrl__Vendor_to_json(e, world) + "]"
        first = False
    out += "]"
    return out^

def sqrrl__Vendor_all_from_json(table: sqrrl__VendorTable, world: sqrrl___World, mut temp: List[sqrrl__Vendor], mut sc: sqrrl___JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__Vendor_from_json_with_id(table, world, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            temp.append(e)
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

def sqrrl__Department_to_json(e: sqrrl__Department, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"name":'
    out += sqrrl__to_json(e._inner[].get_name(), world)
    out += ","
    out += '"tags":'
    out += sqrrl__to_json(e._inner[].get_tags(), world)
    out += ","
    out += '"projects":'
    out += "["
    var mfirst_projects = True
    ref mval_projects = e._inner[].get_sqrrl__projects()
    for m_projects in mval_projects:
        if not mfirst_projects:
            out += ","
        out += String(m_projects.id())
        mfirst_projects = False
    out += "]"
    out += ","
    out += '"vendors":'
    ref fv_vendors = e._inner[].get_sqrrl__vendors()
    var ds1 = String("[")
    var dfirst1 = True
    for dv1 in fv_vendors:
        if not dfirst1:
            ds1 += ","
        ds1 += String(dv1.id())
        dfirst1 = False
    ds1 += "]"
    out += ds1
    out += ","
    out += '"skills":'
    out += "["
    var mfirst_skills = True
    ref mval_skills = e._inner[].get_skills()
    for m_skills in mval_skills:
        if not mfirst_skills:
            out += ","
        out += sqrrl__to_json(m_skills, world)
        mfirst_skills = False
    out += "]"
    out += "}"
    return out^

def sqrrl__Department_from_json_with_id(table: sqrrl__DepartmentTable, world: sqrrl___World, id: UInt32, mut sc: sqrrl___JsonScanner) raises -> sqrrl__Department:
    var parsed_name: Optional[String] = None
    var parsed_tags: Optional[List[String]] = None
    var parsed_projects: Optional[Set[sqrrl__Project]] = None
    var parsed_vendors: Optional[Set[sqrrl__Vendor]] = None
    var parsed_skills: Optional[Set[String]] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "name":
                parsed_name = sc.parse_json_string()
            elif key == "tags":
                parsed_tags = sqrrl__from_json[List[String]](sc, world)
            elif key == "projects":
                var mset = Set[sqrrl__Project]()
                sc.expect_byte(UInt8(ord("[")))
                if not sc.try_consume_byte(UInt8(ord("]"))):
                    while True:
                        var elem_id = UInt32(sc.parse_json_int())
                        mset.add(sqrrl__Project(world.Project.storage[].handle_for(elem_id)))
                        if not sc.try_consume_byte(UInt8(ord(","))):
                            break
                    sc.expect_byte(UInt8(ord("]")))
                parsed_projects = mset^
            elif key == "vendors":
                var nc1 = Set[sqrrl__Vendor]()
                sc.expect_byte(UInt8(ord("[")))
                if not sc.try_consume_byte(UInt8(ord("]"))):
                    while True:
                        nc1.add(sqrrl__Vendor(world.Vendor.storage[].handle_for(UInt32(sc.parse_json_int()))))
                        if not sc.try_consume_byte(UInt8(ord(","))):
                            break
                    sc.expect_byte(UInt8(ord("]")))
                parsed_vendors = nc1^
            elif key == "skills":
                var mset = Set[String]()
                sc.expect_byte(UInt8(ord("[")))
                if not sc.try_consume_byte(UInt8(ord("]"))):
                    while True:
                        mset.add(sc.parse_json_string())
                        if not sc.try_consume_byte(UInt8(ord(","))):
                            break
                    sc.expect_byte(UInt8(ord("]")))
                parsed_skills = mset^
            else:
                raise Error("InvalidJson: unknown field " + key + " for Department")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_name:
        raise Error("InvalidJson: missing field name for Department")
    if not parsed_tags:
        raise Error("InvalidJson: missing field tags for Department")
    if not parsed_projects:
        raise Error("InvalidJson: missing field projects for Department")
    if not parsed_vendors:
        raise Error("InvalidJson: missing field vendors for Department")
    if not parsed_skills:
        raise Error("InvalidJson: missing field skills for Department")
    table.storage[].alloc_specific_id(id)
    var v_name = parsed_name.value()
    var v_tags = parsed_tags.take()
    var v_projects = parsed_projects.take()
    var v_vendors = parsed_vendors.take()
    var v_skills = parsed_skills.take()
    var inner = ArcPointer(sqrrl__DepartmentInner(_id=id, _table=table.storage, _name=v_name, _tags=v_tags^, _sqrrl__projects=v_projects^, _sqrrl__vendors=v_vendors^, _skills=v_skills^))
    table.storage[].register_weak(id, inner)
    table.storage[].indexes.projects.add_many(id, inner[]._sqrrl__projects)
    table.storage[].indexes.skills.add_many(id, inner[]._skills)
    return sqrrl__Department(inner^)

def sqrrl__Department_all_to_json(table: sqrrl__DepartmentTable, world: sqrrl___World) -> String:
    var out = String("[")
    var first = True
    for id in table.storage[].all():
        if not first:
            out += ","
        var e = sqrrl__Department(table.storage[].handle_for(id))
        out += "[" + String(id) + "," + sqrrl__Department_to_json(e, world) + "]"
        first = False
    out += "]"
    return out^

def sqrrl__Department_all_from_json(table: sqrrl__DepartmentTable, world: sqrrl___World, mut temp: List[sqrrl__Department], mut sc: sqrrl___JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__Department_from_json_with_id(table, world, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            temp.append(e)
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

def sqrrl__AuditLog_to_json(e: sqrrl__AuditLog, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"message":'
    out += sqrrl__to_json(e._inner[].get_message(), world)
    out += "}"
    return out^

def sqrrl__AuditLog_from_json_with_id(table: sqrrl__AuditLogTable, world: sqrrl___World, id: UInt32, mut sc: sqrrl___JsonScanner) raises -> sqrrl__AuditLog:
    var parsed_message: Optional[String] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "message":
                parsed_message = sc.parse_json_string()
            else:
                raise Error("InvalidJson: unknown field " + key + " for AuditLog")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_message:
        raise Error("InvalidJson: missing field message for AuditLog")
    table.storage[].alloc_specific_id(id)
    var v_message = parsed_message.value()
    var inner = ArcPointer(sqrrl__AuditLogInner(_id=id, _table=table.storage, _message=v_message))
    table.storage[].register_weak(id, inner)
    table.storage[].keepalive_add(id, inner.copy())
    return sqrrl__AuditLog(inner^)

def sqrrl__AuditLog_all_to_json(table: sqrrl__AuditLogTable, world: sqrrl___World) -> String:
    var out = String("[")
    var first = True
    for id in table.storage[].all():
        if not first:
            out += ","
        var e = sqrrl__AuditLog(table.storage[].handle_for(id))
        out += "[" + String(id) + "," + sqrrl__AuditLog_to_json(e, world) + "]"
        first = False
    out += "]"
    return out^

def sqrrl__AuditLog_all_from_json(table: sqrrl__AuditLogTable, world: sqrrl___World, mut sc: sqrrl___JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__AuditLog_from_json_with_id(table, world, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            _ = e
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

def sqrrl__Employee_to_json(e: sqrrl__Employee, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"email":'
    out += sqrrl__to_json(e._inner[].get_email(), world)
    out += ","
    out += '"title":'
    out += sqrrl__to_json(e._inner[].get_title(), world)
    out += ","
    out += '"years_employed":'
    out += sqrrl__to_json(e._inner[].get_years_employed(), world)
    out += ","
    out += '"salary":'
    out += sqrrl__to_json(e._inner[].get_salary(), world)
    out += ","
    out += '"dept":'
    out += String(e._inner[].get_sqrrl__dept().id())
    out += ","
    out += '"profile":'
    out += sqrrl__to_json(e._inner[].get_profile(), world)
    out += "}"
    return out^

def sqrrl__Employee_from_json_with_id(table: sqrrl__EmployeeTable, world: sqrrl___World, id: UInt32, mut sc: sqrrl___JsonScanner) raises -> sqrrl__Employee:
    var parsed_email: Optional[String] = None
    var parsed_title: Optional[String] = None
    var parsed_years_employed: Optional[UInt32] = None
    var parsed_salary: Optional[Float64] = None
    var parsed_dept: Optional[sqrrl__Department] = None
    var parsed_profile: Optional[Profile] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "email":
                parsed_email = sc.parse_json_string()
            elif key == "title":
                parsed_title = sc.parse_json_string()
            elif key == "years_employed":
                parsed_years_employed = UInt32(sc.parse_json_int())
            elif key == "salary":
                parsed_salary = Float64(sc.parse_json_float())
            elif key == "dept":
                var rid_dept = UInt32(sc.parse_json_int())
                parsed_dept = sqrrl__Department(world.Department.storage[].handle_for(rid_dept))
            elif key == "profile":
                parsed_profile = sqrrl__Profile_from_json(sc, world)
            else:
                raise Error("InvalidJson: unknown field " + key + " for Employee")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_email:
        raise Error("InvalidJson: missing field email for Employee")
    if not parsed_title:
        raise Error("InvalidJson: missing field title for Employee")
    if not parsed_years_employed:
        raise Error("InvalidJson: missing field years_employed for Employee")
    if not parsed_salary:
        raise Error("InvalidJson: missing field salary for Employee")
    if not parsed_dept:
        raise Error("InvalidJson: missing field dept for Employee")
    if not parsed_profile:
        raise Error("InvalidJson: missing field profile for Employee")
    table.storage[].alloc_specific_id(id)
    var v_email = parsed_email.value()
    var v_title = parsed_title.value()
    var v_years_employed = parsed_years_employed.value()
    var v_salary = parsed_salary.value()
    var v_dept = parsed_dept.value()
    var v_profile = parsed_profile.take()
    var inner = ArcPointer(sqrrl__EmployeeInner(_id=id, _table=table.storage, _email=v_email, _title=v_title, _years_employed=v_years_employed, _salary=v_salary, _sqrrl__dept=v_dept, _profile=v_profile^))
    table.storage[].register_weak(id, inner)
    table.storage[].indexes.email.add(id, inner[]._email)
    table.storage[].indexes.years_employed.add(id, inner[]._years_employed)
    table.storage[].indexes.dept.add(id, inner[]._sqrrl__dept)
    return sqrrl__Employee(inner^)

def sqrrl__Employee_all_to_json(table: sqrrl__EmployeeTable, world: sqrrl___World) -> String:
    var out = String("[")
    var first = True
    for id in table.storage[].all():
        if not first:
            out += ","
        var e = sqrrl__Employee(table.storage[].handle_for(id))
        out += "[" + String(id) + "," + sqrrl__Employee_to_json(e, world) + "]"
        first = False
    out += "]"
    return out^

def sqrrl__Employee_all_from_json(table: sqrrl__EmployeeTable, world: sqrrl___World, mut temp: List[sqrrl__Employee], mut sc: sqrrl___JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__Employee_from_json_with_id(table, world, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            temp.append(e)
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

def sqrrl__Project_to_json(e: sqrrl__Project, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"name":'
    out += sqrrl__to_json(e._inner[].get_name(), world)
    out += ","
    out += '"priority":'
    out += sqrrl__to_json(e._inner[].get_priority(), world)
    out += ","
    out += '"vendor":'
    out += String(e._inner[].get_sqrrl__vendor().id())
    out += ","
    out += '"budget":'
    out += sqrrl__to_json(e._inner[].get_budget(), world)
    out += "}"
    return out^

def sqrrl__Project_from_json_with_id(table: sqrrl__ProjectTable, world: sqrrl___World, id: UInt32, mut sc: sqrrl___JsonScanner) raises -> sqrrl__Project:
    var parsed_name: Optional[String] = None
    var parsed_priority: Optional[UInt32] = None
    var parsed_vendor: Optional[sqrrl__Vendor] = None
    var parsed_budget: Optional[Money] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "name":
                parsed_name = sc.parse_json_string()
            elif key == "priority":
                parsed_priority = UInt32(sc.parse_json_int())
            elif key == "vendor":
                var rid_vendor = UInt32(sc.parse_json_int())
                parsed_vendor = sqrrl__Vendor(world.Vendor.storage[].handle_for(rid_vendor))
            elif key == "budget":
                parsed_budget = sqrrl__Money_from_json(sc, world)
            else:
                raise Error("InvalidJson: unknown field " + key + " for Project")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_name:
        raise Error("InvalidJson: missing field name for Project")
    if not parsed_priority:
        raise Error("InvalidJson: missing field priority for Project")
    if not parsed_vendor:
        raise Error("InvalidJson: missing field vendor for Project")
    if not parsed_budget:
        raise Error("InvalidJson: missing field budget for Project")
    table.storage[].alloc_specific_id(id)
    var v_name = parsed_name.value()
    var v_priority = parsed_priority.value()
    var v_vendor = parsed_vendor.value()
    var v_budget = parsed_budget.take()
    var inner = ArcPointer(sqrrl__ProjectInner(_id=id, _table=table.storage, _name=v_name, _priority=v_priority, _sqrrl__vendor=v_vendor, _budget=v_budget^))
    table.storage[].register_weak(id, inner)
    table.storage[].indexes.priority.add(id, inner[]._priority)
    return sqrrl__Project(inner^)

def sqrrl__Project_all_to_json(table: sqrrl__ProjectTable, world: sqrrl___World) -> String:
    var out = String("[")
    var first = True
    for id in table.storage[].all():
        if not first:
            out += ","
        var e = sqrrl__Project(table.storage[].handle_for(id))
        out += "[" + String(id) + "," + sqrrl__Project_to_json(e, world) + "]"
        first = False
    out += "]"
    return out^

def sqrrl__Project_all_from_json(table: sqrrl__ProjectTable, world: sqrrl___World, mut temp: List[sqrrl__Project], mut sc: sqrrl___JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__Project_from_json_with_id(table, world, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            temp.append(e)
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

def sqrrl__Assignment_to_json(value: Assignment, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"person":'
    out += String(value.sqrrl__person.id())
    out += ","
    out += '"role":'
    out += sqrrl__to_json(value.role, world)
    out += "}"
    return out^

def sqrrl__Assignment_from_json(mut sc: sqrrl___JsonScanner, world: sqrrl___World) raises -> Assignment:
    var parsed_person: Optional[sqrrl__Person] = None
    var parsed_role: Optional[String] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "person":
                var rid_person = UInt32(sc.parse_json_int())
                parsed_person = sqrrl__Person(world.Person.storage[].handle_for(rid_person))
            elif key == "role":
                parsed_role = sc.parse_json_string()
            else:
                raise Error("InvalidJson: unknown field " + key + " for Assignment")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_person:
        raise Error("InvalidJson: missing field person for Assignment")
    if not parsed_role:
        raise Error("InvalidJson: missing field role for Assignment")
    return Assignment(sqrrl__person=parsed_person.take(), role=parsed_role.take())

def sqrrl__Address_to_json(value: Address, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"street":'
    out += sqrrl__to_json(value.street, world)
    out += ","
    out += '"city":'
    out += sqrrl__to_json(value.city, world)
    out += "}"
    return out^

def sqrrl__Address_from_json(mut sc: sqrrl___JsonScanner, world: sqrrl___World) raises -> Address:
    var parsed_street: Optional[String] = None
    var parsed_city: Optional[String] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "street":
                parsed_street = sc.parse_json_string()
            elif key == "city":
                parsed_city = sc.parse_json_string()
            else:
                raise Error("InvalidJson: unknown field " + key + " for Address")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_street:
        raise Error("InvalidJson: missing field street for Address")
    if not parsed_city:
        raise Error("InvalidJson: missing field city for Address")
    return Address(street=parsed_street.take(), city=parsed_city.take())

def sqrrl__Profile_to_json(value: Profile, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"contact":'
    out += sqrrl__to_json(value.contact, world)
    out += ","
    out += '"nicknames":'
    out += sqrrl__to_json(value.nicknames, world)
    out += ","
    out += '"scores":'
    out += sqrrl__to_json(value.scores, world)
    out += ","
    out += '"rating":'
    out += sqrrl__to_json(value.rating, world)
    out += ","
    out += '"coordinates":'
    out += sqrrl__to_json(value.coordinates, world)
    out += ","
    out += '"past_addresses":'
    out += sqrrl__to_json(value.past_addresses, world)
    out += ","
    out += '"boxed_ratings":'
    out += sqrrl__to_json(value.boxed_ratings, world)
    out += "}"
    return out^

def sqrrl__Profile_from_json(mut sc: sqrrl___JsonScanner, world: sqrrl___World) raises -> Profile:
    var parsed_contact: Optional[ContactInfo] = None
    var parsed_nicknames: Optional[Optional[List[String]]] = None
    var parsed_scores: Optional[Dict[String, Int]] = None
    var parsed_rating: Optional[Box[UInt32]] = None
    var parsed_coordinates: Optional[Pair[Int, Int]] = None
    var parsed_past_addresses: Optional[List[Address]] = None
    var parsed_boxed_ratings: Optional[List[Box[UInt32]]] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "contact":
                parsed_contact = sqrrl__ContactInfo_from_json(sc, world)
            elif key == "nicknames":
                parsed_nicknames = sqrrl__from_json[Optional[List[String]]](sc, world)
            elif key == "scores":
                parsed_scores = sqrrl__from_json[Dict[String, Int]](sc, world)
            elif key == "rating":
                parsed_rating = sqrrl__Box_from_json[UInt32](sc, world)
            elif key == "coordinates":
                parsed_coordinates = sqrrl__Pair_from_json[Int, Int](sc, world)
            elif key == "past_addresses":
                parsed_past_addresses = sqrrl__from_json[List[Address]](sc, world)
            elif key == "boxed_ratings":
                parsed_boxed_ratings = sqrrl__from_json[List[Box[UInt32]]](sc, world)
            else:
                raise Error("InvalidJson: unknown field " + key + " for Profile")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_contact:
        raise Error("InvalidJson: missing field contact for Profile")
    if not parsed_nicknames:
        raise Error("InvalidJson: missing field nicknames for Profile")
    if not parsed_scores:
        raise Error("InvalidJson: missing field scores for Profile")
    if not parsed_rating:
        raise Error("InvalidJson: missing field rating for Profile")
    if not parsed_coordinates:
        raise Error("InvalidJson: missing field coordinates for Profile")
    if not parsed_past_addresses:
        raise Error("InvalidJson: missing field past_addresses for Profile")
    if not parsed_boxed_ratings:
        raise Error("InvalidJson: missing field boxed_ratings for Profile")
    return Profile(contact=parsed_contact.take(), nicknames=parsed_nicknames.take(), scores=parsed_scores.take(), rating=parsed_rating.take(), coordinates=parsed_coordinates.take(), past_addresses=parsed_past_addresses.take(), boxed_ratings=parsed_boxed_ratings.take())

def sqrrl__ContactInfo_to_json(value: ContactInfo, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"home":'
    out += sqrrl__to_json(value.home, world)
    out += ","
    out += '"emails":'
    out += sqrrl__to_json(value.emails, world)
    out += "}"
    return out^

def sqrrl__ContactInfo_from_json(mut sc: sqrrl___JsonScanner, world: sqrrl___World) raises -> ContactInfo:
    var parsed_home: Optional[Address] = None
    var parsed_emails: Optional[List[String]] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "home":
                parsed_home = sqrrl__Address_from_json(sc, world)
            elif key == "emails":
                parsed_emails = sqrrl__from_json[List[String]](sc, world)
            else:
                raise Error("InvalidJson: unknown field " + key + " for ContactInfo")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_home:
        raise Error("InvalidJson: missing field home for ContactInfo")
    if not parsed_emails:
        raise Error("InvalidJson: missing field emails for ContactInfo")
    return ContactInfo(home=parsed_home.take(), emails=parsed_emails.take())

def sqrrl__Box_to_json[T: Copyable & ImplicitlyDeletable](value: Box[T], world: sqrrl___World) -> String:
    var out = String("{")
    out += '"value":'
    out += sqrrl__to_json(value.value, world)
    out += "}"
    return out^

def sqrrl__Box_from_json[T: Copyable & ImplicitlyDeletable](mut sc: sqrrl___JsonScanner, world: sqrrl___World) raises -> Box[T]:
    var parsed_value: Optional[T] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "value":
                parsed_value = sqrrl__from_json[T](sc, world)
            else:
                raise Error("InvalidJson: unknown field " + key + " for Box")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_value:
        raise Error("InvalidJson: missing field value for Box")
    return Box[T](value=parsed_value.take())

def sqrrl__Pair_to_json[A: Copyable & ImplicitlyDeletable, B: Copyable & ImplicitlyDeletable](value: Pair[A, B], world: sqrrl___World) -> String:
    var out = String("{")
    out += '"first":'
    out += sqrrl__to_json(value.first, world)
    out += ","
    out += '"second":'
    out += sqrrl__to_json(value.second, world)
    out += "}"
    return out^

def sqrrl__Pair_from_json[A: Copyable & ImplicitlyDeletable, B: Copyable & ImplicitlyDeletable](mut sc: sqrrl___JsonScanner, world: sqrrl___World) raises -> Pair[A, B]:
    var parsed_first: Optional[A] = None
    var parsed_second: Optional[B] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "first":
                parsed_first = sqrrl__from_json[A](sc, world)
            elif key == "second":
                parsed_second = sqrrl__from_json[B](sc, world)
            else:
                raise Error("InvalidJson: unknown field " + key + " for Pair")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_first:
        raise Error("InvalidJson: missing field first for Pair")
    if not parsed_second:
        raise Error("InvalidJson: missing field second for Pair")
    return Pair[A, B](first=parsed_first.take(), second=parsed_second.take())

def sqrrl__Money_to_json(value: Money, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"cents":'
    out += sqrrl__to_json(value.cents, world)
    out += "}"
    return out^

def sqrrl__Money_from_json(mut sc: sqrrl___JsonScanner, world: sqrrl___World) raises -> Money:
    var parsed_cents: Optional[Int64] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "cents":
                parsed_cents = Int64(sc.parse_json_int())
            else:
                raise Error("InvalidJson: unknown field " + key + " for Money")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_cents:
        raise Error("InvalidJson: missing field cents for Money")
    return Money(cents=parsed_cents.take())

struct sqrrl___TempKeepAlives(Movable):
    var Team: List[sqrrl__Team]
    var Person: List[sqrrl__Person]
    var Vendor: List[sqrrl__Vendor]
    var Department: List[sqrrl__Department]
    var Employee: List[sqrrl__Employee]
    var Project: List[sqrrl__Project]

    def __init__(out self):
        self.Team = List[sqrrl__Team]()
        self.Person = List[sqrrl__Person]()
        self.Vendor = List[sqrrl__Vendor]()
        self.Department = List[sqrrl__Department]()
        self.Employee = List[sqrrl__Employee]()
        self.Project = List[sqrrl__Project]()

def sqrrl___world_to_json(world: sqrrl___World) -> String:
    var out = String("{")
    out += '"Vendor":'
    out += sqrrl__Vendor_all_to_json(world.Vendor, world)
    out += ","
    out += '"Project":'
    out += sqrrl__Project_all_to_json(world.Project, world)
    out += ","
    out += '"Department":'
    out += sqrrl__Department_all_to_json(world.Department, world)
    out += ","
    out += '"Employee":'
    out += sqrrl__Employee_all_to_json(world.Employee, world)
    out += ","
    out += '"Person":'
    out += sqrrl__Person_all_to_json(world.Person, world)
    out += ","
    out += '"Team":'
    out += sqrrl__Team_all_to_json(world.Team, world)
    out += ","
    out += '"AuditLog":'
    out += sqrrl__AuditLog_all_to_json(world.AuditLog, world)
    out += "}"
    return out^

def sqrrl___world_from_json(mut world: sqrrl___World, mut sc: sqrrl___JsonScanner, mut temp: sqrrl___TempKeepAlives) raises:
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "Vendor":
                sqrrl__Vendor_all_from_json(world.Vendor, world, temp.Vendor, sc)
            elif key == "Project":
                sqrrl__Project_all_from_json(world.Project, world, temp.Project, sc)
            elif key == "Department":
                sqrrl__Department_all_from_json(world.Department, world, temp.Department, sc)
            elif key == "Employee":
                sqrrl__Employee_all_from_json(world.Employee, world, temp.Employee, sc)
            elif key == "Person":
                sqrrl__Person_all_from_json(world.Person, world, temp.Person, sc)
            elif key == "Team":
                sqrrl__Team_all_from_json(world.Team, world, temp.Team, sc)
            elif key == "AuditLog":
                sqrrl__AuditLog_all_from_json(world.AuditLog, world, sc)
            else:
                raise Error("InvalidJson: unknown struct " + key + " in dump")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))

def sqrrl___begin_init_from_json(mut world: sqrrl___World, json: String) raises -> sqrrl___TempKeepAlives:
    world.sqrrl__check_no_leaks()
    world = sqrrl___init()
    var sc = sqrrl___JsonScanner(json)
    var temp = sqrrl___TempKeepAlives()
    sqrrl___world_from_json(world, sc, temp)
    return temp^

def sqrrl___end_init_from_json(var temp: sqrrl___TempKeepAlives):
    pass

def sqrrl___init_from_json(mut world: sqrrl___World, json: String) raises:
    var temp = sqrrl___begin_init_from_json(world, json)
    sqrrl___end_init_from_json(temp^)
