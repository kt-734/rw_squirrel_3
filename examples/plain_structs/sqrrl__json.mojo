from std.memory import ArcPointer
from std.collections import Set
from squirrel_runtime.json import sqrrl__JsonScanner, sqrrl__json_string_literal, sqrrl__json_bool_literal, sqrrl__to_json_default, sqrrl__from_json_default, sqrrl__List_json_to_list, sqrrl__List_json_from_list, sqrrl__Set_json_to_list, sqrrl__Set_json_from_list, sqrrl__Optional_json_to_list, sqrrl__Optional_json_from_list, sqrrl__Dict_json_to_pairs, sqrrl__Dict_json_from_pairs, sqrrl__movable_rebind
from sqrrl__world import sqrrl__World, sqrrl__init
from company import sqrrl__Employee, sqrrl__EmployeeInner, sqrrl__EmployeeTable
from company import sqrrl__Person, sqrrl__PersonInner, sqrrl__PersonTable
from company import Address
from company import Box
from company import Tagged
from company import ExternalCity, sqrrl__ExternalCity_from_json


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
    else:
        return sqrrl__to_json_default(value)


def sqrrl__from_json[T: Movable & ImplicitlyDeletable](mut sc: sqrrl__JsonScanner) raises -> T:
    comptime if False:
        pass
    elif T == Tagged[String]:
        return sqrrl__movable_rebind[Tagged[String], T](sqrrl__Tagged_from_json[String](sc))
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

def sqrrl__Person_to_json(e: sqrrl__Person) -> String:
    var out = String("{")
    out += '"name":'
    out += sqrrl__to_json(e._inner[].get_name())
    out += ","
    out += '"home":'
    out += sqrrl__to_json(e._inner[].get_home())
    out += ","
    out += '"meta":'
    out += sqrrl__to_json(e._inner[].get_meta())
    out += ","
    out += '"hometown":'
    out += sqrrl__to_json(e._inner[].get_hometown())
    out += "}"
    return out^

def sqrrl__Person_from_json_with_id(table: sqrrl__PersonTable, sqrrl__tbl_Employee: sqrrl__EmployeeTable, id: UInt32, mut sc: sqrrl__JsonScanner) raises -> sqrrl__Person:
    var parsed_name: Optional[String] = None
    var parsed_home: Optional[Address] = None
    var parsed_meta: Optional[Tagged[String]] = None
    var parsed_hometown: Optional[ExternalCity] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "name":
                parsed_name = sc.parse_json_string()
            elif key == "home":
                parsed_home = sqrrl__Address_from_json(sqrrl__tbl_Employee, sc)
            elif key == "meta":
                parsed_meta = sqrrl__Tagged_from_json[String](sc)
            elif key == "hometown":
                parsed_hometown = sqrrl__ExternalCity_from_json(sc)
            else:
                raise Error("InvalidJson: unknown field " + key + " for Person")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_name:
        raise Error("InvalidJson: missing field name for Person")
    if not parsed_home:
        raise Error("InvalidJson: missing field home for Person")
    if not parsed_meta:
        raise Error("InvalidJson: missing field meta for Person")
    if not parsed_hometown:
        raise Error("InvalidJson: missing field hometown for Person")
    table.storage[].alloc_specific_id(id)
    var v_name = parsed_name.value()
    var v_home = parsed_home.take()
    var v_meta = parsed_meta.take()
    var v_hometown = parsed_hometown.take()
    var inner = ArcPointer(sqrrl__PersonInner(_id=id, _table=table.storage, _name=v_name, _home=v_home^, _meta=v_meta^, _hometown=v_hometown^))
    table.storage[].register_weak(id, inner)
    table.storage[].indexes.name.add(id, inner[]._name)
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

def sqrrl__Address_from_json(sqrrl__tbl_Employee: sqrrl__EmployeeTable, mut sc: sqrrl__JsonScanner) raises -> Address:
    var parsed_city: Optional[String] = None
    var parsed_owner: Optional[sqrrl__Employee] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "city":
                parsed_city = sc.parse_json_string()
            elif key == "owner":
                var rid_owner = UInt32(sc.parse_json_int())
                parsed_owner = sqrrl__Employee(sqrrl__tbl_Employee.storage[].handle_for(rid_owner))
            else:
                raise Error("InvalidJson: unknown field " + key + " for Address")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_city:
        raise Error("InvalidJson: missing field city for Address")
    if not parsed_owner:
        raise Error("InvalidJson: missing field owner for Address")
    return Address(city=parsed_city.take(), owner=parsed_owner.take())

def sqrrl__Tagged_from_json[Kind: Copyable & ImplicitlyDeletable](mut sc: sqrrl__JsonScanner) raises -> Tagged[Kind]:
    var parsed_label: Optional[String] = None
    var parsed_count: Optional[UInt32] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "label":
                parsed_label = sc.parse_json_string()
            elif key == "count":
                parsed_count = UInt32(sc.parse_json_int())
            else:
                raise Error("InvalidJson: unknown field " + key + " for Tagged")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_label:
        raise Error("InvalidJson: missing field label for Tagged")
    if not parsed_count:
        raise Error("InvalidJson: missing field count for Tagged")
    return Tagged[Kind](label=parsed_label.take(), count=parsed_count.take())

struct sqrrl__TempKeepAlives(Movable):
    var Employee: List[sqrrl__Employee]
    var Person: List[sqrrl__Person]

    def __init__(out self):
        self.Employee = List[sqrrl__Employee]()
        self.Person = List[sqrrl__Person]()

def sqrrl__world_to_json(world: sqrrl__World) -> String:
    var out = String("{")
    out += '"Employee":'
    out += sqrrl__Employee_all_to_json(world.Employee)
    out += ","
    out += '"Person":'
    out += sqrrl__Person_all_to_json(world.Person)
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
            elif key == "Person":
                sqrrl__Person_all_from_json(world.Person, world.Employee, temp.Person, sc)
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
