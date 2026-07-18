from std.memory import ArcPointer
from std.collections import Set
from squirrel_runtime.json import sqrrl__JsonScanner, sqrrl__json_string_literal, sqrrl__json_bool_literal, sqrrl__to_json_default, sqrrl__from_json_default, sqrrl__List_json_to_list, sqrrl__List_json_from_list, sqrrl__Set_json_to_list, sqrrl__Set_json_from_list, sqrrl__Optional_json_to_list, sqrrl__Optional_json_from_list, sqrrl__Dict_json_to_pairs, sqrrl__Dict_json_from_pairs, sqrrl__movable_rebind
from sqrrl__world import sqrrl__World, sqrrl__init
from company import sqrrl__Employee, sqrrl__EmployeeInner, sqrrl__EmployeeTable
from company import sqrrl__Department, sqrrl__DepartmentInner, sqrrl__DepartmentTable
from company import Ring, sqrrl__Ring_json_to_list, sqrrl__Ring_json_from_list
from company import Grid, sqrrl__Grid_json_to_pairs, sqrrl__Grid_json_from_pairs


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
    elif T == List[List[String]]:
        return list_to_json(sqrrl__List_json_to_list(rebind[List[List[String]]](value)))
    elif T == Ring[String]:
        return list_to_json(sqrrl__Ring_json_to_list(rebind[Ring[String]](value)))
    elif T == Grid[String, Int]:
        return pairs_to_json(sqrrl__Grid_json_to_pairs(rebind[Grid[String, Int]](value)))
    else:
        return sqrrl__to_json_default(value)


def sqrrl__from_json[T: Movable & ImplicitlyDeletable](mut sc: sqrrl__JsonScanner) raises -> T:
    comptime if False:
        pass
    elif T == List[String]:
        return sqrrl__movable_rebind[List[String], T](sqrrl__List_json_from_list(list_from_json[String](sc)))
    elif T == List[List[String]]:
        return sqrrl__movable_rebind[List[List[String]], T](sqrrl__List_json_from_list(list_from_json[List[String]](sc)))
    elif T == Ring[String]:
        return sqrrl__movable_rebind[Ring[String], T](sqrrl__Ring_json_from_list(list_from_json[String](sc)))
    elif T == Grid[String, Int]:
        return sqrrl__movable_rebind[Grid[String, Int], T](sqrrl__Grid_json_from_pairs(pairs_from_json[String, Int](sc)))
    else:
        return sqrrl__from_json_default[T](sc)

def sqrrl__Employee_to_json(e: sqrrl__Employee) -> String:
    var out = String("{")
    out += '"name":'
    out += sqrrl__to_json(e._inner[].get_name())
    out += "}"
    return out^

def sqrrl__Employee_from_json_with_id(table: sqrrl__EmployeeTable, id: UInt32, mut sc: sqrrl__JsonScanner) raises -> sqrrl__Employee:
    var parsed_name: Optional[String] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "name":
                parsed_name = sc.parse_json_string()
            else:
                raise Error("InvalidJson: unknown field " + key + " for Employee")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_name:
        raise Error("InvalidJson: missing field name for Employee")
    table.storage[].alloc_specific_id(id)
    var v_name = parsed_name.value()
    var inner = ArcPointer(sqrrl__EmployeeInner(_id=id, _table=table.storage, _name=v_name))
    table.storage[].register_weak(id, inner)
    table.storage[].indexes.name.add(id, inner[]._name)
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

def sqrrl__Employee_all_from_json(table: sqrrl__EmployeeTable, mut temp: List[sqrrl__Employee], mut sc: sqrrl__JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__Employee_from_json_with_id(table, eid, sc)
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
    out += '"backup":'
    ref fv_backup = e._inner[].get_sqrrl__backup()
    var ds2 = String("[")
    var dfirst2 = True
    for dv2 in fv_backup:
        if not dfirst2:
            ds2 += ","
        ds2 += String(dv2.id())
        dfirst2 = False
    ds2 += "]"
    out += ds2
    out += ","
    out += '"lead":'
    ref fv_lead = e._inner[].get_sqrrl__lead()
    var ds3: String
    if fv_lead:
        ds3 = String(fv_lead.value().id())
    else:
        ds3 = "null"
    out += ds3
    out += ","
    out += '"tags":'
    out += sqrrl__to_json(e._inner[].get_tags())
    out += ","
    out += '"scores":'
    ref fv_scores = e._inner[].get_sqrrl__scores()
    var ds4 = String("[")
    var dfirst4 = True
    for de4 in fv_scores.items():
        if not dfirst4:
            ds4 += ","
        ds4 += "[" + String(de4.key.id()) + "," + sqrrl__to_json(de4.value) + "]"
        dfirst4 = False
    ds4 += "]"
    out += ds4
    out += ","
    out += '"groups":'
    out += sqrrl__to_json(e._inner[].get_groups())
    out += ","
    out += '"ring":'
    out += sqrrl__to_json(e._inner[].get_ring())
    out += ","
    out += '"grid":'
    out += sqrrl__to_json(e._inner[].get_grid())
    out += "}"
    return out^

def sqrrl__Department_from_json_with_id(table: sqrrl__DepartmentTable, sqrrl__tbl_Employee: sqrrl__EmployeeTable, id: UInt32, mut sc: sqrrl__JsonScanner) raises -> sqrrl__Department:
    var parsed_name: Optional[String] = None
    var parsed_members: Optional[List[sqrrl__Employee]] = None
    var parsed_backup: Optional[Set[sqrrl__Employee]] = None
    var parsed_lead: Optional[Optional[sqrrl__Employee]] = None
    var parsed_tags: Optional[List[String]] = None
    var parsed_scores: Optional[Dict[sqrrl__Employee, String]] = None
    var parsed_groups: Optional[List[List[String]]] = None
    var parsed_ring: Optional[Ring[String]] = None
    var parsed_grid: Optional[Grid[String, Int]] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "name":
                parsed_name = sc.parse_json_string()
            elif key == "members":
                var nc1 = List[sqrrl__Employee]()
                sc.expect_byte(UInt8(ord("[")))
                if not sc.try_consume_byte(UInt8(ord("]"))):
                    while True:
                        nc1.append(sqrrl__Employee(sqrrl__tbl_Employee.storage[].handle_for(UInt32(sc.parse_json_int()))))
                        if not sc.try_consume_byte(UInt8(ord(","))):
                            break
                    sc.expect_byte(UInt8(ord("]")))
                parsed_members = nc1^
            elif key == "backup":
                var nc1 = Set[sqrrl__Employee]()
                sc.expect_byte(UInt8(ord("[")))
                if not sc.try_consume_byte(UInt8(ord("]"))):
                    while True:
                        nc1.add(sqrrl__Employee(sqrrl__tbl_Employee.storage[].handle_for(UInt32(sc.parse_json_int()))))
                        if not sc.try_consume_byte(UInt8(ord(","))):
                            break
                    sc.expect_byte(UInt8(ord("]")))
                parsed_backup = nc1^
            elif key == "lead":
                var nc1: Optional[sqrrl__Employee]
                if sc.try_consume_literal("null"):
                    nc1 = Optional[sqrrl__Employee]()
                else:
                    nc1 = Optional[sqrrl__Employee](sqrrl__Employee(sqrrl__tbl_Employee.storage[].handle_for(UInt32(sc.parse_json_int()))))
                parsed_lead = nc1^
            elif key == "tags":
                parsed_tags = sqrrl__from_json[List[String]](sc)
            elif key == "scores":
                var nc1 = Dict[sqrrl__Employee, String]()
                sc.expect_byte(UInt8(ord("[")))
                if not sc.try_consume_byte(UInt8(ord("]"))):
                    while True:
                        sc.expect_byte(UInt8(ord("[")))
                        var nck1 = sqrrl__Employee(sqrrl__tbl_Employee.storage[].handle_for(UInt32(sc.parse_json_int())))
                        sc.expect_byte(UInt8(ord(",")))
                        nc1[nck1] = sc.parse_json_string()
                        sc.expect_byte(UInt8(ord("]")))
                        if not sc.try_consume_byte(UInt8(ord(","))):
                            break
                    sc.expect_byte(UInt8(ord("]")))
                parsed_scores = nc1^
            elif key == "groups":
                parsed_groups = sqrrl__from_json[List[List[String]]](sc)
            elif key == "ring":
                parsed_ring = sqrrl__from_json[Ring[String]](sc)
            elif key == "grid":
                parsed_grid = sqrrl__from_json[Grid[String, Int]](sc)
            else:
                raise Error("InvalidJson: unknown field " + key + " for Department")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_name:
        raise Error("InvalidJson: missing field name for Department")
    if not parsed_members:
        raise Error("InvalidJson: missing field members for Department")
    if not parsed_backup:
        raise Error("InvalidJson: missing field backup for Department")
    if not parsed_lead:
        raise Error("InvalidJson: missing field lead for Department")
    if not parsed_tags:
        raise Error("InvalidJson: missing field tags for Department")
    if not parsed_scores:
        raise Error("InvalidJson: missing field scores for Department")
    if not parsed_groups:
        raise Error("InvalidJson: missing field groups for Department")
    if not parsed_ring:
        raise Error("InvalidJson: missing field ring for Department")
    if not parsed_grid:
        raise Error("InvalidJson: missing field grid for Department")
    table.storage[].alloc_specific_id(id)
    var v_name = parsed_name.value()
    var v_members = parsed_members.take()
    var v_backup = parsed_backup.take()
    var v_lead = parsed_lead.take()
    var v_tags = parsed_tags.take()
    var v_scores = parsed_scores.take()
    var v_groups = parsed_groups.take()
    var v_ring = parsed_ring.take()
    var v_grid = parsed_grid.take()
    var inner = ArcPointer(sqrrl__DepartmentInner(_id=id, _table=table.storage, _name=v_name, _sqrrl__members=v_members^, _sqrrl__backup=v_backup^, _sqrrl__lead=v_lead^, _tags=v_tags^, _sqrrl__scores=v_scores^, _groups=v_groups^, _ring=v_ring^, _grid=v_grid^))
    table.storage[].register_weak(id, inner)
    table.storage[].indexes.name.add(id, inner[]._name)
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

def sqrrl__Department_all_from_json(table: sqrrl__DepartmentTable, sqrrl__tbl_Employee: sqrrl__EmployeeTable, mut temp: List[sqrrl__Department], mut sc: sqrrl__JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__Department_from_json_with_id(table, sqrrl__tbl_Employee, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            temp.append(e)
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

struct sqrrl__TempKeepAlives(Movable):
    var Employee: List[sqrrl__Employee]
    var Department: List[sqrrl__Department]

    def __init__(out self):
        self.Employee = List[sqrrl__Employee]()
        self.Department = List[sqrrl__Department]()

def sqrrl__world_to_json(world: sqrrl__World) -> String:
    var out = String("{")
    out += '"Employee":'
    out += sqrrl__Employee_all_to_json(world.Employee)
    out += ","
    out += '"Department":'
    out += sqrrl__Department_all_to_json(world.Department)
    out += "}"
    return out^

def sqrrl__world_from_json(mut world: sqrrl__World, mut sc: sqrrl__JsonScanner, mut temp: sqrrl__TempKeepAlives) raises:
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "Employee":
                sqrrl__Employee_all_from_json(world.Employee, temp.Employee, sc)
            elif key == "Department":
                sqrrl__Department_all_from_json(world.Department, world.Employee, temp.Department, sc)
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
