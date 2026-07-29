from std.memory import ArcPointer
from std.collections import Set
from squirrel_runtime.json import sqrrl___JsonScanner, sqrrl__json_string_literal, sqrrl__json_bool_literal, sqrrl__to_json_default, sqrrl__from_json_default, sqrrl__movable_rebind
from sqrrl__world import sqrrl___World, sqrrl___init
from company_impl import sqrrl__Employee, sqrrl__EmployeeInner, sqrrl__EmployeeTable
from company_impl import sqrrl__Department, sqrrl__DepartmentInner, sqrrl__DepartmentTable
from ring_module import Ring, sqrrl__Ring_to_json, sqrrl__Ring_from_json
from grid_module import Grid, sqrrl__Grid_to_json, sqrrl__Grid_from_json


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
    elif T == List[sqrrl__Employee]:
        return sqrrl__List_to_json(rebind[List[sqrrl__Employee]](value), world)
    elif T == sqrrl__Employee:
        return String(rebind[sqrrl__Employee](value).id())
    elif T == Set[sqrrl__Employee]:
        return sqrrl__Set_to_json(rebind[Set[sqrrl__Employee]](value), world)
    elif T == Optional[sqrrl__Employee]:
        return sqrrl__Optional_to_json(rebind[Optional[sqrrl__Employee]](value), world)
    elif T == List[String]:
        return sqrrl__List_to_json(rebind[List[String]](value), world)
    elif T == Dict[sqrrl__Employee, String]:
        return sqrrl__Dict_to_json(rebind[Dict[sqrrl__Employee, String]](value), world)
    elif T == Dict[String, sqrrl__Employee]:
        return sqrrl__Dict_to_json(rebind[Dict[String, sqrrl__Employee]](value), world)
    elif T == List[List[String]]:
        return sqrrl__List_to_json(rebind[List[List[String]]](value), world)
    elif T == Ring[String]:
        return sqrrl__Ring_to_json(rebind[Ring[String]](value), world)
    elif T == Grid[String, Int]:
        return sqrrl__Grid_to_json(rebind[Grid[String, Int]](value), world)
    else:
        return sqrrl__to_json_default(value)


def sqrrl__from_json[T: Movable & ImplicitlyDeletable](mut sc: sqrrl___JsonScanner, world: sqrrl___World) raises -> T:
    comptime if False:
        pass
    elif T == List[sqrrl__Employee]:
        return sqrrl__movable_rebind[List[sqrrl__Employee], T](sqrrl__List_from_json[sqrrl__Employee](sc, world))
    elif T == sqrrl__Employee:
        return sqrrl__movable_rebind[sqrrl__Employee, T](sqrrl__Employee(world.Employee.storage[].handle_for(UInt32(sc.parse_json_int()))))
    elif T == Set[sqrrl__Employee]:
        return sqrrl__movable_rebind[Set[sqrrl__Employee], T](sqrrl__Set_from_json[sqrrl__Employee](sc, world))
    elif T == Optional[sqrrl__Employee]:
        return sqrrl__movable_rebind[Optional[sqrrl__Employee], T](sqrrl__Optional_from_json[sqrrl__Employee](sc, world))
    elif T == List[String]:
        return sqrrl__movable_rebind[List[String], T](sqrrl__List_from_json[String](sc, world))
    elif T == Dict[sqrrl__Employee, String]:
        return sqrrl__movable_rebind[Dict[sqrrl__Employee, String], T](sqrrl__Dict_from_json[sqrrl__Employee, String](sc, world))
    elif T == Dict[String, sqrrl__Employee]:
        return sqrrl__movable_rebind[Dict[String, sqrrl__Employee], T](sqrrl__Dict_from_json[String, sqrrl__Employee](sc, world))
    elif T == List[List[String]]:
        return sqrrl__movable_rebind[List[List[String]], T](sqrrl__List_from_json[List[String]](sc, world))
    elif T == Ring[String]:
        return sqrrl__movable_rebind[Ring[String], T](sqrrl__Ring_from_json[String](sc, world))
    elif T == Grid[String, Int]:
        return sqrrl__movable_rebind[Grid[String, Int], T](sqrrl__Grid_from_json[String, Int](sc, world))
    else:
        return sqrrl__from_json_default[T](sc)

def sqrrl__Employee_to_json(e: sqrrl__Employee, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"name":'
    out += sqrrl__to_json(e._inner[].get_name(), world)
    out += "}"
    return out^

def sqrrl__Employee_from_json_with_id(table: sqrrl__EmployeeTable, world: sqrrl___World, id: UInt32, mut sc: sqrrl___JsonScanner) raises -> sqrrl__Employee:
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

def sqrrl__Department_to_json(e: sqrrl__Department, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"name":'
    out += sqrrl__to_json(e._inner[].get_name(), world)
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
    out += sqrrl__to_json(e._inner[].get_tags(), world)
    out += ","
    out += '"scores":'
    ref fv_scores = e._inner[].get_sqrrl__scores()
    var ds4 = String("[")
    var dfirst4 = True
    for de4 in fv_scores.items():
        if not dfirst4:
            ds4 += ","
        ds4 += "[" + String(de4.key.id()) + "," + sqrrl__to_json(de4.value, world) + "]"
        dfirst4 = False
    ds4 += "]"
    out += ds4
    out += ","
    out += '"leads":'
    ref fv_leads = e._inner[].get_sqrrl__leads()
    var ds5 = String("[")
    var dfirst5 = True
    for de5 in fv_leads.items():
        if not dfirst5:
            ds5 += ","
        ds5 += "[" + sqrrl__to_json(de5.key, world) + "," + String(de5.value.id()) + "]"
        dfirst5 = False
    ds5 += "]"
    out += ds5
    out += ","
    out += '"groups":'
    out += sqrrl__to_json(e._inner[].get_groups(), world)
    out += ","
    out += '"ring":'
    out += sqrrl__to_json(e._inner[].get_ring(), world)
    out += ","
    out += '"grid":'
    out += sqrrl__to_json(e._inner[].get_grid(), world)
    out += "}"
    return out^

def sqrrl__Department_from_json_with_id(table: sqrrl__DepartmentTable, world: sqrrl___World, id: UInt32, mut sc: sqrrl___JsonScanner) raises -> sqrrl__Department:
    var parsed_name: Optional[String] = None
    var parsed_members: Optional[List[sqrrl__Employee]] = None
    var parsed_backup: Optional[Set[sqrrl__Employee]] = None
    var parsed_lead: Optional[Optional[sqrrl__Employee]] = None
    var parsed_tags: Optional[List[String]] = None
    var parsed_scores: Optional[Dict[sqrrl__Employee, String]] = None
    var parsed_leads: Optional[Dict[String, sqrrl__Employee]] = None
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
                        nc1.append(sqrrl__Employee(world.Employee.storage[].handle_for(UInt32(sc.parse_json_int()))))
                        if not sc.try_consume_byte(UInt8(ord(","))):
                            break
                    sc.expect_byte(UInt8(ord("]")))
                parsed_members = nc1^
            elif key == "backup":
                var nc1 = Set[sqrrl__Employee]()
                sc.expect_byte(UInt8(ord("[")))
                if not sc.try_consume_byte(UInt8(ord("]"))):
                    while True:
                        nc1.add(sqrrl__Employee(world.Employee.storage[].handle_for(UInt32(sc.parse_json_int()))))
                        if not sc.try_consume_byte(UInt8(ord(","))):
                            break
                    sc.expect_byte(UInt8(ord("]")))
                parsed_backup = nc1^
            elif key == "lead":
                var nc1: Optional[sqrrl__Employee]
                if sc.try_consume_literal("null"):
                    nc1 = Optional[sqrrl__Employee]()
                else:
                    nc1 = Optional[sqrrl__Employee](sqrrl__Employee(world.Employee.storage[].handle_for(UInt32(sc.parse_json_int()))))
                parsed_lead = nc1^
            elif key == "tags":
                parsed_tags = sqrrl__from_json[List[String]](sc, world)
            elif key == "scores":
                var nc1 = Dict[sqrrl__Employee, String]()
                sc.expect_byte(UInt8(ord("[")))
                if not sc.try_consume_byte(UInt8(ord("]"))):
                    while True:
                        sc.expect_byte(UInt8(ord("[")))
                        var nck1 = sqrrl__Employee(world.Employee.storage[].handle_for(UInt32(sc.parse_json_int())))
                        sc.expect_byte(UInt8(ord(",")))
                        nc1[nck1] = sc.parse_json_string()
                        sc.expect_byte(UInt8(ord("]")))
                        if not sc.try_consume_byte(UInt8(ord(","))):
                            break
                    sc.expect_byte(UInt8(ord("]")))
                parsed_scores = nc1^
            elif key == "leads":
                var nc1 = Dict[String, sqrrl__Employee]()
                sc.expect_byte(UInt8(ord("[")))
                if not sc.try_consume_byte(UInt8(ord("]"))):
                    while True:
                        sc.expect_byte(UInt8(ord("[")))
                        var nck1 = sc.parse_json_string()
                        sc.expect_byte(UInt8(ord(",")))
                        nc1[nck1] = sqrrl__Employee(world.Employee.storage[].handle_for(UInt32(sc.parse_json_int())))
                        sc.expect_byte(UInt8(ord("]")))
                        if not sc.try_consume_byte(UInt8(ord(","))):
                            break
                    sc.expect_byte(UInt8(ord("]")))
                parsed_leads = nc1^
            elif key == "groups":
                parsed_groups = sqrrl__from_json[List[List[String]]](sc, world)
            elif key == "ring":
                parsed_ring = sqrrl__from_json[Ring[String]](sc, world)
            elif key == "grid":
                parsed_grid = sqrrl__from_json[Grid[String, Int]](sc, world)
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
    if not parsed_leads:
        raise Error("InvalidJson: missing field leads for Department")
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
    var v_leads = parsed_leads.take()
    var v_groups = parsed_groups.take()
    var v_ring = parsed_ring.take()
    var v_grid = parsed_grid.take()
    var inner = ArcPointer(sqrrl__DepartmentInner(_id=id, _table=table.storage, _name=v_name, _sqrrl__members=v_members^, _sqrrl__backup=v_backup^, _sqrrl__lead=v_lead^, _tags=v_tags^, _sqrrl__scores=v_scores^, _sqrrl__leads=v_leads^, _groups=v_groups^, _ring=v_ring^, _grid=v_grid^))
    table.storage[].register_weak(id, inner)
    table.storage[].indexes.name.add(id, inner[]._name)
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

struct sqrrl___TempKeepAlives(Movable):
    var Employee: List[sqrrl__Employee]
    var Department: List[sqrrl__Department]

    def __init__(out self):
        self.Employee = List[sqrrl__Employee]()
        self.Department = List[sqrrl__Department]()

def sqrrl___world_to_json(world: sqrrl___World) -> String:
    var out = String("{")
    out += '"Employee":'
    out += sqrrl__Employee_all_to_json(world.Employee, world)
    out += ","
    out += '"Department":'
    out += sqrrl__Department_all_to_json(world.Department, world)
    out += "}"
    return out^

def sqrrl___world_from_json(mut world: sqrrl___World, mut sc: sqrrl___JsonScanner, mut temp: sqrrl___TempKeepAlives) raises:
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "Employee":
                sqrrl__Employee_all_from_json(world.Employee, world, temp.Employee, sc)
            elif key == "Department":
                sqrrl__Department_all_from_json(world.Department, world, temp.Department, sc)
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
