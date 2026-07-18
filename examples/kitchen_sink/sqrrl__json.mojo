from std.memory import ArcPointer
from std.collections import Set
from squirrel_runtime.json import sqrrl__JsonScanner, sqrrl__json_string_literal, sqrrl__json_bool_literal, sqrrl__to_json_default, sqrrl__from_json_default, sqrrl__List_json_to_list, sqrrl__List_json_from_list, sqrrl__Set_json_to_list, sqrrl__Set_json_from_list, sqrrl__Optional_json_to_list, sqrrl__Optional_json_from_list, sqrrl__Dict_json_to_pairs, sqrrl__Dict_json_from_pairs, sqrrl__movable_rebind
from sqrrl__world import sqrrl__World, sqrrl__init
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


def list_to_json[T: Movable](lst: List[T]) -> String:
    var out = String("[")
    for i in range(len(lst)):
        if i > 0:
            out += ","
        out += sqrrl__to_json(lst[i])
    out += "]"
    return out^


def list_from_json[T: Movable & ImplicitlyDeletable](mut sc: sqrrl__JsonScanner) raises -> List[T]:
    var lst = List[T]()
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            lst.append(sqrrl__from_json[T](sc))
            if sc.try_consume_byte(UInt8(ord(","))):
                continue
            sc.expect_byte(UInt8(ord("]")))
            break
    return lst^


def pairs_to_json[K: Movable, V: Movable](pairs: List[Tuple[K, V]]) -> String:
    var out = String("[")
    for i in range(len(pairs)):
        if i > 0:
            out += ","
        out += "[" + sqrrl__to_json(pairs[i][0]) + "," + sqrrl__to_json(pairs[i][1]) + "]"
    out += "]"
    return out^


def pairs_from_json[K: Copyable & ImplicitlyDeletable, V: Copyable & ImplicitlyDeletable](mut sc: sqrrl__JsonScanner) raises -> List[Tuple[K, V]]:
    var pairs = List[Tuple[K, V]]()
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var k = sqrrl__from_json[K](sc)
            sc.expect_byte(UInt8(ord(",")))
            var v = sqrrl__from_json[V](sc)
            sc.expect_byte(UInt8(ord("]")))
            pairs.append((k.copy(), v.copy()))
            if sc.try_consume_byte(UInt8(ord(","))):
                continue
            sc.expect_byte(UInt8(ord("]")))
            break
    return pairs^


def sqrrl__to_json[T: AnyType](value: T) -> String:
    comptime if False:
        pass
    elif T == List[String]:
        return list_to_json(sqrrl__List_json_to_list(rebind[List[String]](value)))
    elif T == Optional[List[String]]:
        return list_to_json(sqrrl__Optional_json_to_list(rebind[Optional[List[String]]](value)))
    elif T == Dict[String, Int]:
        return pairs_to_json(sqrrl__Dict_json_to_pairs(rebind[Dict[String, Int]](value)))
    elif T == List[Address]:
        return list_to_json(sqrrl__List_json_to_list(rebind[List[Address]](value)))
    elif T == List[Box[UInt32]]:
        return list_to_json(sqrrl__List_json_to_list(rebind[List[Box[UInt32]]](value)))
    elif T == Address:
        return sqrrl__Address_to_json(rebind[Address](value))
    elif T == Profile:
        return sqrrl__Profile_to_json(rebind[Profile](value))
    elif T == ContactInfo:
        return sqrrl__ContactInfo_to_json(rebind[ContactInfo](value))
    elif T == Box[UInt32]:
        return sqrrl__Box_to_json[UInt32](rebind[Box[UInt32]](value))
    elif T == Pair[Int, Int]:
        return sqrrl__Pair_to_json[Int, Int](rebind[Pair[Int, Int]](value))
    elif T == Money:
        return sqrrl__Money_to_json(rebind[Money](value))
    else:
        return sqrrl__to_json_default(value)


def sqrrl__from_json[T: Movable & ImplicitlyDeletable](mut sc: sqrrl__JsonScanner) raises -> T:
    comptime if False:
        pass
    elif T == List[String]:
        return sqrrl__movable_rebind[List[String], T](sqrrl__List_json_from_list(list_from_json[String](sc)))
    elif T == Optional[List[String]]:
        return sqrrl__movable_rebind[Optional[List[String]], T](sqrrl__Optional_json_from_list(list_from_json[List[String]](sc)))
    elif T == Dict[String, Int]:
        return sqrrl__movable_rebind[Dict[String, Int], T](sqrrl__Dict_json_from_pairs(pairs_from_json[String, Int](sc)))
    elif T == List[Address]:
        return sqrrl__movable_rebind[List[Address], T](sqrrl__List_json_from_list(list_from_json[Address](sc)))
    elif T == List[Box[UInt32]]:
        return sqrrl__movable_rebind[List[Box[UInt32]], T](sqrrl__List_json_from_list(list_from_json[Box[UInt32]](sc)))
    elif T == Address:
        return sqrrl__movable_rebind[Address, T](sqrrl__Address_from_json(sc))
    elif T == Profile:
        return sqrrl__movable_rebind[Profile, T](sqrrl__Profile_from_json(sc))
    elif T == ContactInfo:
        return sqrrl__movable_rebind[ContactInfo, T](sqrrl__ContactInfo_from_json(sc))
    elif T == Box[UInt32]:
        return sqrrl__movable_rebind[Box[UInt32], T](sqrrl__Box_from_json[UInt32](sc))
    elif T == Pair[Int, Int]:
        return sqrrl__movable_rebind[Pair[Int, Int], T](sqrrl__Pair_from_json[Int, Int](sc))
    elif T == Money:
        return sqrrl__movable_rebind[Money, T](sqrrl__Money_from_json(sc))
    else:
        return sqrrl__from_json_default[T](sc)

def sqrrl__Team_to_json(e: sqrrl__Team) -> String:
    var out = String("{")
    out += '"name":'
    out += sqrrl__to_json(e._inner[].get_name())
    out += ","
    out += '"lead":'
    out += sqrrl__Assignment_to_json(e._inner[].get_lead())
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
    out += "}"
    return out^

def sqrrl__Team_from_json_with_id(table: sqrrl__TeamTable, sqrrl__tbl_Person: sqrrl__PersonTable, sqrrl__tbl_Employee: sqrrl__EmployeeTable, id: UInt32, mut sc: sqrrl__JsonScanner) raises -> sqrrl__Team:
    var parsed_name: Optional[String] = None
    var parsed_lead: Optional[Assignment] = None
    var parsed_members: Optional[List[sqrrl__Person]] = None
    var parsed_advisor: Optional[Optional[sqrrl__Employee]] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "name":
                parsed_name = sc.parse_json_string()
            elif key == "lead":
                parsed_lead = sqrrl__Assignment_from_json(sqrrl__tbl_Person, sc)
            elif key == "members":
                var nc1 = List[sqrrl__Person]()
                sc.expect_byte(UInt8(ord("[")))
                if not sc.try_consume_byte(UInt8(ord("]"))):
                    while True:
                        nc1.append(sqrrl__Person(sqrrl__tbl_Person.storage[].handle_for(UInt32(sc.parse_json_int()))))
                        if not sc.try_consume_byte(UInt8(ord(","))):
                            break
                    sc.expect_byte(UInt8(ord("]")))
                parsed_members = nc1^
            elif key == "advisor":
                var nc1: Optional[sqrrl__Employee]
                if sc.try_consume_literal("null"):
                    nc1 = Optional[sqrrl__Employee]()
                else:
                    nc1 = Optional[sqrrl__Employee](sqrrl__Employee(sqrrl__tbl_Employee.storage[].handle_for(UInt32(sc.parse_json_int()))))
                parsed_advisor = nc1^
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
    table.storage[].alloc_specific_id(id)
    var v_name = parsed_name.value()
    var v_lead = parsed_lead.take()
    var v_members = parsed_members.take()
    var v_advisor = parsed_advisor.take()
    var inner = ArcPointer(sqrrl__TeamInner(_id=id, _table=table.storage, _name=v_name, _lead=v_lead^, _sqrrl__members=v_members^, _sqrrl__advisor=v_advisor^))
    table.storage[].register_weak(id, inner)
    return sqrrl__Team(inner^)

def sqrrl__Team_all_to_json(table: sqrrl__TeamTable) -> String:
    var out = String("[")
    var first = True
    for id in table.storage[].all():
        if not first:
            out += ","
        var e = sqrrl__Team(table.storage[].handle_for(id))
        out += "[" + String(id) + "," + sqrrl__Team_to_json(e) + "]"
        first = False
    out += "]"
    return out^

def sqrrl__Team_all_from_json(table: sqrrl__TeamTable, sqrrl__tbl_Person: sqrrl__PersonTable, sqrrl__tbl_Employee: sqrrl__EmployeeTable, mut temp: List[sqrrl__Team], mut sc: sqrrl__JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__Team_from_json_with_id(table, sqrrl__tbl_Person, sqrrl__tbl_Employee, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            temp.append(e)
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

def sqrrl__Person_to_json(e: sqrrl__Person) -> String:
    var out = String("{")
    out += '"name":'
    out += sqrrl__to_json(e._inner[].get_name())
    out += ","
    out += '"home":'
    out += sqrrl__to_json(e._inner[].get_home())
    out += ","
    out += '"job":'
    out += String(e._inner[].get_sqrrl__job().id())
    out += "}"
    return out^

def sqrrl__Person_from_json_with_id(table: sqrrl__PersonTable, sqrrl__tbl_Employee: sqrrl__EmployeeTable, id: UInt32, mut sc: sqrrl__JsonScanner) raises -> sqrrl__Person:
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
                parsed_home = sqrrl__Address_from_json(sc)
            elif key == "job":
                var rid_job = UInt32(sc.parse_json_int())
                parsed_job = sqrrl__Employee(sqrrl__tbl_Employee.storage[].handle_for(rid_job))
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

def sqrrl__Person_all_to_json(table: sqrrl__PersonTable) -> String:
    var out = String("[")
    var first = True
    for id in table.storage[].all():
        if not first:
            out += ","
        var e = sqrrl__Person(table.storage[].handle_for(id))
        out += "[" + String(id) + "," + sqrrl__Person_to_json(e) + "]"
        first = False
    out += "]"
    return out^

def sqrrl__Person_all_from_json(table: sqrrl__PersonTable, sqrrl__tbl_Employee: sqrrl__EmployeeTable, mut temp: List[sqrrl__Person], mut sc: sqrrl__JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__Person_from_json_with_id(table, sqrrl__tbl_Employee, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            temp.append(e)
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

def sqrrl__Vendor_to_json(e: sqrrl__Vendor) -> String:
    var out = String("{")
    out += '"name":'
    out += sqrrl__to_json(e._inner[].get_name())
    out += "}"
    return out^

def sqrrl__Vendor_from_json_with_id(table: sqrrl__VendorTable, id: UInt32, mut sc: sqrrl__JsonScanner) raises -> sqrrl__Vendor:
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

def sqrrl__Vendor_all_to_json(table: sqrrl__VendorTable) -> String:
    var out = String("[")
    var first = True
    for id in table.storage[].all():
        if not first:
            out += ","
        var e = sqrrl__Vendor(table.storage[].handle_for(id))
        out += "[" + String(id) + "," + sqrrl__Vendor_to_json(e) + "]"
        first = False
    out += "]"
    return out^

def sqrrl__Vendor_all_from_json(table: sqrrl__VendorTable, mut temp: List[sqrrl__Vendor], mut sc: sqrrl__JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__Vendor_from_json_with_id(table, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            temp.append(e)
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

def sqrrl__Department_to_json(e: sqrrl__Department) -> String:
    var out = String("{")
    out += '"name":'
    out += sqrrl__to_json(e._inner[].get_name())
    out += ","
    out += '"tags":'
    out += sqrrl__to_json(e._inner[].get_tags())
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
        out += sqrrl__to_json(m_skills)
        mfirst_skills = False
    out += "]"
    out += "}"
    return out^

def sqrrl__Department_from_json_with_id(table: sqrrl__DepartmentTable, sqrrl__tbl_Project: sqrrl__ProjectTable, sqrrl__tbl_Vendor: sqrrl__VendorTable, id: UInt32, mut sc: sqrrl__JsonScanner) raises -> sqrrl__Department:
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
                parsed_tags = sqrrl__from_json[List[String]](sc)
            elif key == "projects":
                var mset = Set[sqrrl__Project]()
                sc.expect_byte(UInt8(ord("[")))
                if not sc.try_consume_byte(UInt8(ord("]"))):
                    while True:
                        var elem_id = UInt32(sc.parse_json_int())
                        mset.add(sqrrl__Project(sqrrl__tbl_Project.storage[].handle_for(elem_id)))
                        if not sc.try_consume_byte(UInt8(ord(","))):
                            break
                    sc.expect_byte(UInt8(ord("]")))
                parsed_projects = mset^
            elif key == "vendors":
                var nc1 = Set[sqrrl__Vendor]()
                sc.expect_byte(UInt8(ord("[")))
                if not sc.try_consume_byte(UInt8(ord("]"))):
                    while True:
                        nc1.add(sqrrl__Vendor(sqrrl__tbl_Vendor.storage[].handle_for(UInt32(sc.parse_json_int()))))
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

def sqrrl__Department_all_to_json(table: sqrrl__DepartmentTable) -> String:
    var out = String("[")
    var first = True
    for id in table.storage[].all():
        if not first:
            out += ","
        var e = sqrrl__Department(table.storage[].handle_for(id))
        out += "[" + String(id) + "," + sqrrl__Department_to_json(e) + "]"
        first = False
    out += "]"
    return out^

def sqrrl__Department_all_from_json(table: sqrrl__DepartmentTable, sqrrl__tbl_Project: sqrrl__ProjectTable, sqrrl__tbl_Vendor: sqrrl__VendorTable, mut temp: List[sqrrl__Department], mut sc: sqrrl__JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__Department_from_json_with_id(table, sqrrl__tbl_Project, sqrrl__tbl_Vendor, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            temp.append(e)
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

def sqrrl__AuditLog_to_json(e: sqrrl__AuditLog) -> String:
    var out = String("{")
    out += '"message":'
    out += sqrrl__to_json(e._inner[].get_message())
    out += "}"
    return out^

def sqrrl__AuditLog_from_json_with_id(table: sqrrl__AuditLogTable, id: UInt32, mut sc: sqrrl__JsonScanner) raises -> sqrrl__AuditLog:
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

def sqrrl__AuditLog_all_to_json(table: sqrrl__AuditLogTable) -> String:
    var out = String("[")
    var first = True
    for id in table.storage[].all():
        if not first:
            out += ","
        var e = sqrrl__AuditLog(table.storage[].handle_for(id))
        out += "[" + String(id) + "," + sqrrl__AuditLog_to_json(e) + "]"
        first = False
    out += "]"
    return out^

def sqrrl__AuditLog_all_from_json(table: sqrrl__AuditLogTable, mut sc: sqrrl__JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__AuditLog_from_json_with_id(table, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            _ = e
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

def sqrrl__Employee_to_json(e: sqrrl__Employee) -> String:
    var out = String("{")
    out += '"email":'
    out += sqrrl__to_json(e._inner[].get_email())
    out += ","
    out += '"title":'
    out += sqrrl__to_json(e._inner[].get_title())
    out += ","
    out += '"years_employed":'
    out += sqrrl__to_json(e._inner[].get_years_employed())
    out += ","
    out += '"salary":'
    out += sqrrl__to_json(e._inner[].get_salary())
    out += ","
    out += '"dept":'
    out += String(e._inner[].get_sqrrl__dept().id())
    out += ","
    out += '"profile":'
    out += sqrrl__to_json(e._inner[].get_profile())
    out += "}"
    return out^

def sqrrl__Employee_from_json_with_id(table: sqrrl__EmployeeTable, sqrrl__tbl_Department: sqrrl__DepartmentTable, id: UInt32, mut sc: sqrrl__JsonScanner) raises -> sqrrl__Employee:
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
                parsed_dept = sqrrl__Department(sqrrl__tbl_Department.storage[].handle_for(rid_dept))
            elif key == "profile":
                parsed_profile = sqrrl__Profile_from_json(sc)
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

def sqrrl__Employee_all_to_json(table: sqrrl__EmployeeTable) -> String:
    var out = String("[")
    var first = True
    for id in table.storage[].all():
        if not first:
            out += ","
        var e = sqrrl__Employee(table.storage[].handle_for(id))
        out += "[" + String(id) + "," + sqrrl__Employee_to_json(e) + "]"
        first = False
    out += "]"
    return out^

def sqrrl__Employee_all_from_json(table: sqrrl__EmployeeTable, sqrrl__tbl_Department: sqrrl__DepartmentTable, mut temp: List[sqrrl__Employee], mut sc: sqrrl__JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__Employee_from_json_with_id(table, sqrrl__tbl_Department, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            temp.append(e)
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

def sqrrl__Project_to_json(e: sqrrl__Project) -> String:
    var out = String("{")
    out += '"name":'
    out += sqrrl__to_json(e._inner[].get_name())
    out += ","
    out += '"priority":'
    out += sqrrl__to_json(e._inner[].get_priority())
    out += ","
    out += '"vendor":'
    out += String(e._inner[].get_sqrrl__vendor().id())
    out += ","
    out += '"budget":'
    out += sqrrl__to_json(e._inner[].get_budget())
    out += "}"
    return out^

def sqrrl__Project_from_json_with_id(table: sqrrl__ProjectTable, sqrrl__tbl_Vendor: sqrrl__VendorTable, id: UInt32, mut sc: sqrrl__JsonScanner) raises -> sqrrl__Project:
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
                parsed_vendor = sqrrl__Vendor(sqrrl__tbl_Vendor.storage[].handle_for(rid_vendor))
            elif key == "budget":
                parsed_budget = sqrrl__Money_from_json(sc)
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

def sqrrl__Project_all_to_json(table: sqrrl__ProjectTable) -> String:
    var out = String("[")
    var first = True
    for id in table.storage[].all():
        if not first:
            out += ","
        var e = sqrrl__Project(table.storage[].handle_for(id))
        out += "[" + String(id) + "," + sqrrl__Project_to_json(e) + "]"
        first = False
    out += "]"
    return out^

def sqrrl__Project_all_from_json(table: sqrrl__ProjectTable, sqrrl__tbl_Vendor: sqrrl__VendorTable, mut temp: List[sqrrl__Project], mut sc: sqrrl__JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__Project_from_json_with_id(table, sqrrl__tbl_Vendor, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            temp.append(e)
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

def sqrrl__Assignment_to_json(value: Assignment) -> String:
    var out = String("{")
    out += '"person":'
    out += String(value.person.id())
    out += ","
    out += '"role":'
    out += sqrrl__to_json(value.role)
    out += "}"
    return out^

def sqrrl__Assignment_from_json(sqrrl__tbl_Person: sqrrl__PersonTable, mut sc: sqrrl__JsonScanner) raises -> Assignment:
    var parsed_person: Optional[sqrrl__Person] = None
    var parsed_role: Optional[String] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "person":
                var rid_person = UInt32(sc.parse_json_int())
                parsed_person = sqrrl__Person(sqrrl__tbl_Person.storage[].handle_for(rid_person))
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
    return Assignment(person=parsed_person.take(), role=parsed_role.take())

def sqrrl__Address_to_json(value: Address) -> String:
    var out = String("{")
    out += '"street":'
    out += sqrrl__to_json(value.street)
    out += ","
    out += '"city":'
    out += sqrrl__to_json(value.city)
    out += "}"
    return out^

def sqrrl__Address_from_json(mut sc: sqrrl__JsonScanner) raises -> Address:
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

def sqrrl__Profile_to_json(value: Profile) -> String:
    var out = String("{")
    out += '"contact":'
    out += sqrrl__to_json(value.contact)
    out += ","
    out += '"nicknames":'
    out += sqrrl__to_json(value.nicknames)
    out += ","
    out += '"scores":'
    out += sqrrl__to_json(value.scores)
    out += ","
    out += '"rating":'
    out += sqrrl__to_json(value.rating)
    out += ","
    out += '"coordinates":'
    out += sqrrl__to_json(value.coordinates)
    out += ","
    out += '"past_addresses":'
    out += sqrrl__to_json(value.past_addresses)
    out += ","
    out += '"boxed_ratings":'
    out += sqrrl__to_json(value.boxed_ratings)
    out += "}"
    return out^

def sqrrl__Profile_from_json(mut sc: sqrrl__JsonScanner) raises -> Profile:
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
                parsed_contact = sqrrl__ContactInfo_from_json(sc)
            elif key == "nicknames":
                parsed_nicknames = sqrrl__from_json[Optional[List[String]]](sc)
            elif key == "scores":
                parsed_scores = sqrrl__from_json[Dict[String, Int]](sc)
            elif key == "rating":
                parsed_rating = sqrrl__Box_from_json[UInt32](sc)
            elif key == "coordinates":
                parsed_coordinates = sqrrl__Pair_from_json[Int, Int](sc)
            elif key == "past_addresses":
                parsed_past_addresses = sqrrl__from_json[List[Address]](sc)
            elif key == "boxed_ratings":
                parsed_boxed_ratings = sqrrl__from_json[List[Box[UInt32]]](sc)
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

def sqrrl__ContactInfo_to_json(value: ContactInfo) -> String:
    var out = String("{")
    out += '"home":'
    out += sqrrl__to_json(value.home)
    out += ","
    out += '"emails":'
    out += sqrrl__to_json(value.emails)
    out += "}"
    return out^

def sqrrl__ContactInfo_from_json(mut sc: sqrrl__JsonScanner) raises -> ContactInfo:
    var parsed_home: Optional[Address] = None
    var parsed_emails: Optional[List[String]] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "home":
                parsed_home = sqrrl__Address_from_json(sc)
            elif key == "emails":
                parsed_emails = sqrrl__from_json[List[String]](sc)
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

def sqrrl__Box_to_json[T: Copyable & ImplicitlyDeletable](value: Box[T]) -> String:
    var out = String("{")
    out += '"value":'
    out += sqrrl__to_json(value.value)
    out += "}"
    return out^

def sqrrl__Box_from_json[T: Copyable & ImplicitlyDeletable](mut sc: sqrrl__JsonScanner) raises -> Box[T]:
    var parsed_value: Optional[T] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "value":
                parsed_value = sqrrl__from_json[T](sc)
            else:
                raise Error("InvalidJson: unknown field " + key + " for Box")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_value:
        raise Error("InvalidJson: missing field value for Box")
    return Box[T](value=parsed_value.take())

def sqrrl__Pair_to_json[A: Copyable & ImplicitlyDeletable, B: Copyable & ImplicitlyDeletable](value: Pair[A, B]) -> String:
    var out = String("{")
    out += '"first":'
    out += sqrrl__to_json(value.first)
    out += ","
    out += '"second":'
    out += sqrrl__to_json(value.second)
    out += "}"
    return out^

def sqrrl__Pair_from_json[A: Copyable & ImplicitlyDeletable, B: Copyable & ImplicitlyDeletable](mut sc: sqrrl__JsonScanner) raises -> Pair[A, B]:
    var parsed_first: Optional[A] = None
    var parsed_second: Optional[B] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "first":
                parsed_first = sqrrl__from_json[A](sc)
            elif key == "second":
                parsed_second = sqrrl__from_json[B](sc)
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

def sqrrl__Money_to_json(value: Money) -> String:
    var out = String("{")
    out += '"cents":'
    out += sqrrl__to_json(value.cents)
    out += "}"
    return out^

def sqrrl__Money_from_json(mut sc: sqrrl__JsonScanner) raises -> Money:
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

struct sqrrl__TempKeepAlives(Movable):
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

def sqrrl__world_to_json(world: sqrrl__World) -> String:
    var out = String("{")
    out += '"Vendor":'
    out += sqrrl__Vendor_all_to_json(world.Vendor)
    out += ","
    out += '"Project":'
    out += sqrrl__Project_all_to_json(world.Project)
    out += ","
    out += '"Department":'
    out += sqrrl__Department_all_to_json(world.Department)
    out += ","
    out += '"Employee":'
    out += sqrrl__Employee_all_to_json(world.Employee)
    out += ","
    out += '"Person":'
    out += sqrrl__Person_all_to_json(world.Person)
    out += ","
    out += '"Team":'
    out += sqrrl__Team_all_to_json(world.Team)
    out += ","
    out += '"AuditLog":'
    out += sqrrl__AuditLog_all_to_json(world.AuditLog)
    out += "}"
    return out^

def sqrrl__world_from_json(mut world: sqrrl__World, mut sc: sqrrl__JsonScanner, mut temp: sqrrl__TempKeepAlives) raises:
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "Vendor":
                sqrrl__Vendor_all_from_json(world.Vendor, temp.Vendor, sc)
            elif key == "Project":
                sqrrl__Project_all_from_json(world.Project, world.Vendor, temp.Project, sc)
            elif key == "Department":
                sqrrl__Department_all_from_json(world.Department, world.Project, world.Vendor, temp.Department, sc)
            elif key == "Employee":
                sqrrl__Employee_all_from_json(world.Employee, world.Department, temp.Employee, sc)
            elif key == "Person":
                sqrrl__Person_all_from_json(world.Person, world.Employee, temp.Person, sc)
            elif key == "Team":
                sqrrl__Team_all_from_json(world.Team, world.Person, world.Employee, temp.Team, sc)
            elif key == "AuditLog":
                sqrrl__AuditLog_all_from_json(world.AuditLog, sc)
            else:
                raise Error("InvalidJson: unknown struct " + key + " in dump")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))

def sqrrl__begin_init_from_json(mut world: sqrrl__World, json: String) raises -> sqrrl__TempKeepAlives:
    world.sqrrl__check_no_leaks()
    world = sqrrl__init()
    var sc = sqrrl__JsonScanner(json)
    var temp = sqrrl__TempKeepAlives()
    sqrrl__world_from_json(world, sc, temp)
    return temp^

def sqrrl__end_init_from_json(var temp: sqrrl__TempKeepAlives):
    pass

def sqrrl__init_from_json(mut world: sqrrl__World, json: String) raises:
    var temp = sqrrl__begin_init_from_json(world, json)
    sqrrl__end_init_from_json(temp^)
