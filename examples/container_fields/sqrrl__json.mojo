from std.memory import ArcPointer
from std.collections import Set
from squirrel_runtime.json import sqrrl__JsonScanner, sqrrl__json_string_literal, sqrrl__json_bool_literal, sqrrl__to_json
from sqrrl__world import sqrrl__World, sqrrl__init
from company import sqrrl__Employee, sqrrl__EmployeeInner, sqrrl__EmployeeTable
from company import sqrrl__Department, sqrrl__DepartmentInner, sqrrl__DepartmentTable
from company import Ring, sqrrl__Ring_json_to_list, sqrrl__Ring_json_from_list

def sqrrl__Employee_to_json(e: sqrrl__Employee) -> String:
    var sqrrl__out = String("{")
    sqrrl__out += '"name":'
    sqrrl__out += sqrrl__to_json(e._inner[].get_name())
    sqrrl__out += "}"
    return sqrrl__out^

def sqrrl__Employee_from_json_with_id(table: sqrrl__EmployeeTable, id: UInt32, mut sqrrl__sc: sqrrl__JsonScanner) raises -> sqrrl__Employee:
    var sqrrl__parsed_name: Optional[String] = None
    sqrrl__sc.expect_byte(UInt8(ord("{")))
    if not sqrrl__sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var sqrrl__key = sqrrl__sc.parse_json_string()
            sqrrl__sc.expect_byte(UInt8(ord(":")))
            if sqrrl__key == "name":
                sqrrl__parsed_name = sqrrl__sc.parse_json_string()
            else:
                raise Error("InvalidJson: unknown field " + sqrrl__key + " for Employee")
            if not sqrrl__sc.try_consume_byte(UInt8(ord(","))):
                break
        sqrrl__sc.expect_byte(UInt8(ord("}")))
    if not sqrrl__parsed_name:
        raise Error("InvalidJson: missing field name for Employee")
    table.storage[].alloc_specific_id(id)
    var sqrrl__v_name = sqrrl__parsed_name.value()
    var sqrrl__inner = ArcPointer(sqrrl__EmployeeInner(_id=id, _table=table.storage, _name=sqrrl__v_name))
    table.storage[].register_weak(id, sqrrl__inner)
    table.storage[].indexes.name.add(id, sqrrl__inner[]._name)
    return sqrrl__Employee(sqrrl__inner^)

def sqrrl__Employee_all_to_json(table: sqrrl__EmployeeTable) -> String:
    var sqrrl__out = String("[")
    var sqrrl__first = True
    for sqrrl__id in table.storage[].all():
        if not sqrrl__first:
            sqrrl__out += ","
        var sqrrl__e = sqrrl__Employee(table.storage[].handle_for(sqrrl__id))
        sqrrl__out += "[" + String(sqrrl__id) + "," + sqrrl__Employee_to_json(sqrrl__e) + "]"
        sqrrl__first = False
    sqrrl__out += "]"
    return sqrrl__out^

def sqrrl__Employee_all_from_json(table: sqrrl__EmployeeTable, mut sqrrl__temp: List[sqrrl__Employee], mut sqrrl__sc: sqrrl__JsonScanner) raises:
    sqrrl__sc.expect_byte(UInt8(ord("[")))
    if not sqrrl__sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sqrrl__sc.expect_byte(UInt8(ord("[")))
            var sqrrl__eid = UInt32(sqrrl__sc.parse_json_int())
            sqrrl__sc.expect_byte(UInt8(ord(",")))
            var sqrrl__e = sqrrl__Employee_from_json_with_id(table, sqrrl__eid, sqrrl__sc)
            sqrrl__sc.expect_byte(UInt8(ord("]")))
            sqrrl__temp.append(sqrrl__e)
            if not sqrrl__sc.try_consume_byte(UInt8(ord(","))):
                break
        sqrrl__sc.expect_byte(UInt8(ord("]")))

def sqrrl__Department_to_json(e: sqrrl__Department) -> String:
    var sqrrl__out = String("{")
    sqrrl__out += '"name":'
    sqrrl__out += sqrrl__to_json(e._inner[].get_name())
    sqrrl__out += ","
    sqrrl__out += '"members":'
    ref sqrrl__fv_members = e._inner[].get_sqrrl__members()
    var sqrrl__ds1 = String("[")
    var sqrrl__dfirst1 = True
    for sqrrl__dv1 in sqrrl__fv_members:
        if not sqrrl__dfirst1:
            sqrrl__ds1 += ","
        sqrrl__ds1 += sqrrl__to_json(sqrrl__dv1)
        sqrrl__dfirst1 = False
    sqrrl__ds1 += "]"
    sqrrl__out += sqrrl__ds1
    sqrrl__out += ","
    sqrrl__out += '"backup":'
    ref sqrrl__fv_backup = e._inner[].get_sqrrl__backup()
    var sqrrl__ds2 = String("[")
    var sqrrl__dfirst2 = True
    for sqrrl__dv2 in sqrrl__fv_backup:
        if not sqrrl__dfirst2:
            sqrrl__ds2 += ","
        sqrrl__ds2 += sqrrl__to_json(sqrrl__dv2)
        sqrrl__dfirst2 = False
    sqrrl__ds2 += "]"
    sqrrl__out += sqrrl__ds2
    sqrrl__out += ","
    sqrrl__out += '"lead":'
    ref sqrrl__fv_lead = e._inner[].get_sqrrl__lead()
    var sqrrl__ds3: String
    if sqrrl__fv_lead:
        sqrrl__ds3 = sqrrl__to_json(sqrrl__fv_lead.value())
    else:
        sqrrl__ds3 = "null"
    sqrrl__out += sqrrl__ds3
    sqrrl__out += ","
    sqrrl__out += '"tags":'
    ref sqrrl__fv_tags = e._inner[].get_tags()
    var sqrrl__ds4 = String("[")
    var sqrrl__dfirst4 = True
    for sqrrl__dv4 in sqrrl__fv_tags:
        if not sqrrl__dfirst4:
            sqrrl__ds4 += ","
        sqrrl__ds4 += sqrrl__to_json(sqrrl__dv4)
        sqrrl__dfirst4 = False
    sqrrl__ds4 += "]"
    sqrrl__out += sqrrl__ds4
    sqrrl__out += ","
    sqrrl__out += '"scores":'
    ref sqrrl__fv_scores = e._inner[].get_sqrrl__scores()
    var sqrrl__ds5 = String("[")
    var sqrrl__dfirst5 = True
    for sqrrl__de5 in sqrrl__fv_scores.items():
        if not sqrrl__dfirst5:
            sqrrl__ds5 += ","
        sqrrl__ds5 += "[" + sqrrl__to_json(sqrrl__de5.key) + "," + sqrrl__to_json(sqrrl__de5.value) + "]"
        sqrrl__dfirst5 = False
    sqrrl__ds5 += "]"
    sqrrl__out += sqrrl__ds5
    sqrrl__out += ","
    sqrrl__out += '"groups":'
    ref sqrrl__fv_groups = e._inner[].get_groups()
    var sqrrl__ds6 = String("[")
    var sqrrl__dfirst6 = True
    for sqrrl__dv6 in sqrrl__fv_groups:
        if not sqrrl__dfirst6:
            sqrrl__ds6 += ","
        var sqrrl__ds7 = String("[")
        var sqrrl__dfirst7 = True
        for sqrrl__dv7 in sqrrl__dv6:
            if not sqrrl__dfirst7:
                sqrrl__ds7 += ","
            sqrrl__ds7 += sqrrl__to_json(sqrrl__dv7)
            sqrrl__dfirst7 = False
        sqrrl__ds7 += "]"
        sqrrl__ds6 += sqrrl__ds7
        sqrrl__dfirst6 = False
    sqrrl__ds6 += "]"
    sqrrl__out += sqrrl__ds6
    sqrrl__out += ","
    sqrrl__out += '"ring":'
    ref sqrrl__fv_ring = e._inner[].get_ring()
    var sqrrl__ds8 = String("[")
    var sqrrl__dfirst8 = True
    for sqrrl__dv8 in sqrrl__Ring_json_to_list(sqrrl__fv_ring):
        if not sqrrl__dfirst8:
            sqrrl__ds8 += ","
        sqrrl__ds8 += sqrrl__to_json(sqrrl__dv8)
        sqrrl__dfirst8 = False
    sqrrl__ds8 += "]"
    sqrrl__out += sqrrl__ds8
    sqrrl__out += "}"
    return sqrrl__out^

def sqrrl__Department_from_json_with_id(table: sqrrl__DepartmentTable, sqrrl__tbl_Employee: sqrrl__EmployeeTable, id: UInt32, mut sqrrl__sc: sqrrl__JsonScanner) raises -> sqrrl__Department:
    var sqrrl__parsed_name: Optional[String] = None
    var sqrrl__parsed_members: Optional[List[sqrrl__Employee]] = None
    var sqrrl__parsed_backup: Optional[Set[sqrrl__Employee]] = None
    var sqrrl__parsed_lead: Optional[Optional[sqrrl__Employee]] = None
    var sqrrl__parsed_tags: Optional[List[String]] = None
    var sqrrl__parsed_scores: Optional[Dict[sqrrl__Employee, String]] = None
    var sqrrl__parsed_groups: Optional[List[List[String]]] = None
    var sqrrl__parsed_ring: Optional[Ring[String]] = None
    sqrrl__sc.expect_byte(UInt8(ord("{")))
    if not sqrrl__sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var sqrrl__key = sqrrl__sc.parse_json_string()
            sqrrl__sc.expect_byte(UInt8(ord(":")))
            if sqrrl__key == "name":
                sqrrl__parsed_name = sqrrl__sc.parse_json_string()
            elif sqrrl__key == "members":
                var sqrrl__nc1 = List[sqrrl__Employee]()
                sqrrl__sc.expect_byte(UInt8(ord("[")))
                if not sqrrl__sc.try_consume_byte(UInt8(ord("]"))):
                    while True:
                        sqrrl__nc1.append(sqrrl__Employee(sqrrl__tbl_Employee.storage[].handle_for(UInt32(sqrrl__sc.parse_json_int()))))
                        if not sqrrl__sc.try_consume_byte(UInt8(ord(","))):
                            break
                    sqrrl__sc.expect_byte(UInt8(ord("]")))
                sqrrl__parsed_members = sqrrl__nc1^
            elif sqrrl__key == "backup":
                var sqrrl__nc1 = Set[sqrrl__Employee]()
                sqrrl__sc.expect_byte(UInt8(ord("[")))
                if not sqrrl__sc.try_consume_byte(UInt8(ord("]"))):
                    while True:
                        sqrrl__nc1.add(sqrrl__Employee(sqrrl__tbl_Employee.storage[].handle_for(UInt32(sqrrl__sc.parse_json_int()))))
                        if not sqrrl__sc.try_consume_byte(UInt8(ord(","))):
                            break
                    sqrrl__sc.expect_byte(UInt8(ord("]")))
                sqrrl__parsed_backup = sqrrl__nc1^
            elif sqrrl__key == "lead":
                var sqrrl__nc1: Optional[sqrrl__Employee]
                if sqrrl__sc.try_consume_literal("null"):
                    sqrrl__nc1 = Optional[sqrrl__Employee]()
                else:
                    sqrrl__nc1 = Optional[sqrrl__Employee](sqrrl__Employee(sqrrl__tbl_Employee.storage[].handle_for(UInt32(sqrrl__sc.parse_json_int()))))
                sqrrl__parsed_lead = sqrrl__nc1^
            elif sqrrl__key == "tags":
                var sqrrl__nc1 = List[String]()
                sqrrl__sc.expect_byte(UInt8(ord("[")))
                if not sqrrl__sc.try_consume_byte(UInt8(ord("]"))):
                    while True:
                        sqrrl__nc1.append(sqrrl__sc.parse_json_string())
                        if not sqrrl__sc.try_consume_byte(UInt8(ord(","))):
                            break
                    sqrrl__sc.expect_byte(UInt8(ord("]")))
                sqrrl__parsed_tags = sqrrl__nc1^
            elif sqrrl__key == "scores":
                var sqrrl__nc1 = Dict[sqrrl__Employee, String]()
                sqrrl__sc.expect_byte(UInt8(ord("[")))
                if not sqrrl__sc.try_consume_byte(UInt8(ord("]"))):
                    while True:
                        sqrrl__sc.expect_byte(UInt8(ord("[")))
                        var sqrrl__nck1 = sqrrl__Employee(sqrrl__tbl_Employee.storage[].handle_for(UInt32(sqrrl__sc.parse_json_int())))
                        sqrrl__sc.expect_byte(UInt8(ord(",")))
                        sqrrl__nc1[sqrrl__nck1] = sqrrl__sc.parse_json_string()
                        sqrrl__sc.expect_byte(UInt8(ord("]")))
                        if not sqrrl__sc.try_consume_byte(UInt8(ord(","))):
                            break
                    sqrrl__sc.expect_byte(UInt8(ord("]")))
                sqrrl__parsed_scores = sqrrl__nc1^
            elif sqrrl__key == "groups":
                var sqrrl__nc1 = List[List[String]]()
                sqrrl__sc.expect_byte(UInt8(ord("[")))
                if not sqrrl__sc.try_consume_byte(UInt8(ord("]"))):
                    while True:
                        var sqrrl__nc2 = List[String]()
                        sqrrl__sc.expect_byte(UInt8(ord("[")))
                        if not sqrrl__sc.try_consume_byte(UInt8(ord("]"))):
                            while True:
                                sqrrl__nc2.append(sqrrl__sc.parse_json_string())
                                if not sqrrl__sc.try_consume_byte(UInt8(ord(","))):
                                    break
                            sqrrl__sc.expect_byte(UInt8(ord("]")))
                        sqrrl__nc1.append(sqrrl__nc2^)
                        if not sqrrl__sc.try_consume_byte(UInt8(ord(","))):
                            break
                    sqrrl__sc.expect_byte(UInt8(ord("]")))
                sqrrl__parsed_groups = sqrrl__nc1^
            elif sqrrl__key == "ring":
                var sqrrl__nc1 = List[String]()
                sqrrl__sc.expect_byte(UInt8(ord("[")))
                if not sqrrl__sc.try_consume_byte(UInt8(ord("]"))):
                    while True:
                        sqrrl__nc1.append(sqrrl__sc.parse_json_string())
                        if not sqrrl__sc.try_consume_byte(UInt8(ord(","))):
                            break
                    sqrrl__sc.expect_byte(UInt8(ord("]")))
                sqrrl__parsed_ring = sqrrl__Ring_json_from_list(sqrrl__nc1^)
            else:
                raise Error("InvalidJson: unknown field " + sqrrl__key + " for Department")
            if not sqrrl__sc.try_consume_byte(UInt8(ord(","))):
                break
        sqrrl__sc.expect_byte(UInt8(ord("}")))
    if not sqrrl__parsed_name:
        raise Error("InvalidJson: missing field name for Department")
    if not sqrrl__parsed_members:
        raise Error("InvalidJson: missing field members for Department")
    if not sqrrl__parsed_backup:
        raise Error("InvalidJson: missing field backup for Department")
    if not sqrrl__parsed_lead:
        raise Error("InvalidJson: missing field lead for Department")
    if not sqrrl__parsed_tags:
        raise Error("InvalidJson: missing field tags for Department")
    if not sqrrl__parsed_scores:
        raise Error("InvalidJson: missing field scores for Department")
    if not sqrrl__parsed_groups:
        raise Error("InvalidJson: missing field groups for Department")
    if not sqrrl__parsed_ring:
        raise Error("InvalidJson: missing field ring for Department")
    table.storage[].alloc_specific_id(id)
    var sqrrl__v_name = sqrrl__parsed_name.value()
    var sqrrl__v_members = sqrrl__parsed_members.take()
    var sqrrl__v_backup = sqrrl__parsed_backup.take()
    var sqrrl__v_lead = sqrrl__parsed_lead.take()
    var sqrrl__v_tags = sqrrl__parsed_tags.take()
    var sqrrl__v_scores = sqrrl__parsed_scores.take()
    var sqrrl__v_groups = sqrrl__parsed_groups.take()
    var sqrrl__v_ring = sqrrl__parsed_ring.take()
    var sqrrl__inner = ArcPointer(sqrrl__DepartmentInner(_id=id, _table=table.storage, _name=sqrrl__v_name, _sqrrl__members=sqrrl__v_members^, _sqrrl__backup=sqrrl__v_backup^, _sqrrl__lead=sqrrl__v_lead^, _tags=sqrrl__v_tags^, _sqrrl__scores=sqrrl__v_scores^, _groups=sqrrl__v_groups^, _ring=sqrrl__v_ring^))
    table.storage[].register_weak(id, sqrrl__inner)
    table.storage[].indexes.name.add(id, sqrrl__inner[]._name)
    return sqrrl__Department(sqrrl__inner^)

def sqrrl__Department_all_to_json(table: sqrrl__DepartmentTable) -> String:
    var sqrrl__out = String("[")
    var sqrrl__first = True
    for sqrrl__id in table.storage[].all():
        if not sqrrl__first:
            sqrrl__out += ","
        var sqrrl__e = sqrrl__Department(table.storage[].handle_for(sqrrl__id))
        sqrrl__out += "[" + String(sqrrl__id) + "," + sqrrl__Department_to_json(sqrrl__e) + "]"
        sqrrl__first = False
    sqrrl__out += "]"
    return sqrrl__out^

def sqrrl__Department_all_from_json(table: sqrrl__DepartmentTable, sqrrl__tbl_Employee: sqrrl__EmployeeTable, mut sqrrl__temp: List[sqrrl__Department], mut sqrrl__sc: sqrrl__JsonScanner) raises:
    sqrrl__sc.expect_byte(UInt8(ord("[")))
    if not sqrrl__sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sqrrl__sc.expect_byte(UInt8(ord("[")))
            var sqrrl__eid = UInt32(sqrrl__sc.parse_json_int())
            sqrrl__sc.expect_byte(UInt8(ord(",")))
            var sqrrl__e = sqrrl__Department_from_json_with_id(table, sqrrl__tbl_Employee, sqrrl__eid, sqrrl__sc)
            sqrrl__sc.expect_byte(UInt8(ord("]")))
            sqrrl__temp.append(sqrrl__e)
            if not sqrrl__sc.try_consume_byte(UInt8(ord(","))):
                break
        sqrrl__sc.expect_byte(UInt8(ord("]")))

struct sqrrl__TempKeepAlives(Movable):
    var Employee: List[sqrrl__Employee]
    var Department: List[sqrrl__Department]

    def __init__(out self):
        self.Employee = List[sqrrl__Employee]()
        self.Department = List[sqrrl__Department]()

def sqrrl__world_to_json(world: sqrrl__World) -> String:
    var sqrrl__out = String("{")
    sqrrl__out += '"Employee":'
    sqrrl__out += sqrrl__Employee_all_to_json(world.Employee)
    sqrrl__out += ","
    sqrrl__out += '"Department":'
    sqrrl__out += sqrrl__Department_all_to_json(world.Department)
    sqrrl__out += "}"
    return sqrrl__out^

def sqrrl__world_from_json(mut world: sqrrl__World, mut sqrrl__sc: sqrrl__JsonScanner, mut sqrrl__temp: sqrrl__TempKeepAlives) raises:
    sqrrl__sc.expect_byte(UInt8(ord("{")))
    if not sqrrl__sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var sqrrl__key = sqrrl__sc.parse_json_string()
            sqrrl__sc.expect_byte(UInt8(ord(":")))
            if sqrrl__key == "Employee":
                sqrrl__Employee_all_from_json(world.Employee, sqrrl__temp.Employee, sqrrl__sc)
            elif sqrrl__key == "Department":
                sqrrl__Department_all_from_json(world.Department, world.Employee, sqrrl__temp.Department, sqrrl__sc)
            else:
                raise Error("InvalidJson: unknown struct " + sqrrl__key + " in dump")
            if not sqrrl__sc.try_consume_byte(UInt8(ord(","))):
                break
        sqrrl__sc.expect_byte(UInt8(ord("}")))

def sqrrl__begin_init_from_json(mut world: sqrrl__World, json: String) raises -> sqrrl__TempKeepAlives:
    world.sqrrl__check_no_leaks()
    world = sqrrl__init()
    var sqrrl__sc = sqrrl__JsonScanner(json)
    var sqrrl__temp = sqrrl__TempKeepAlives()
    sqrrl__world_from_json(world, sqrrl__sc, sqrrl__temp)
    return sqrrl__temp^

def sqrrl__end_init_from_json(var sqrrl__temp: sqrrl__TempKeepAlives):
    pass

def sqrrl__init_from_json(mut world: sqrrl__World, json: String) raises:
    var sqrrl__temp = sqrrl__begin_init_from_json(world, json)
    sqrrl__end_init_from_json(sqrrl__temp^)
