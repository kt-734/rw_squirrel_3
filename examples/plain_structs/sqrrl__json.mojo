from std.memory import ArcPointer
from std.collections import Set
from squirrel_runtime.json import sqrrl__JsonScanner, sqrrl__json_string_literal, sqrrl__json_bool_literal, sqrrl__to_json
from sqrrl__world import sqrrl__World, sqrrl__init
from company import sqrrl__Employee, sqrrl__EmployeeInner, sqrrl__EmployeeTable
from company import sqrrl__Person, sqrrl__PersonInner, sqrrl__PersonTable
from company import Address
from company import Box
from company import Tagged
from company import ExternalCity, sqrrl__ExternalCity_from_json

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

def sqrrl__Person_to_json(e: sqrrl__Person) -> String:
    var sqrrl__out = String("{")
    sqrrl__out += '"name":'
    sqrrl__out += sqrrl__to_json(e._inner[].get_name())
    sqrrl__out += ","
    sqrrl__out += '"home":'
    sqrrl__out += sqrrl__to_json(e._inner[].get_home())
    sqrrl__out += ","
    sqrrl__out += '"meta":'
    sqrrl__out += sqrrl__to_json(e._inner[].get_meta())
    sqrrl__out += ","
    sqrrl__out += '"hometown":'
    sqrrl__out += sqrrl__to_json(e._inner[].get_hometown())
    sqrrl__out += "}"
    return sqrrl__out^

def sqrrl__Person_from_json_with_id(table: sqrrl__PersonTable, sqrrl__tbl_Employee: sqrrl__EmployeeTable, id: UInt32, mut sqrrl__sc: sqrrl__JsonScanner) raises -> sqrrl__Person:
    var sqrrl__parsed_name: Optional[String] = None
    var sqrrl__parsed_home: Optional[Address] = None
    var sqrrl__parsed_meta: Optional[Tagged[String]] = None
    var sqrrl__parsed_hometown: Optional[ExternalCity] = None
    sqrrl__sc.expect_byte(UInt8(ord("{")))
    if not sqrrl__sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var sqrrl__key = sqrrl__sc.parse_json_string()
            sqrrl__sc.expect_byte(UInt8(ord(":")))
            if sqrrl__key == "name":
                sqrrl__parsed_name = sqrrl__sc.parse_json_string()
            elif sqrrl__key == "home":
                sqrrl__parsed_home = sqrrl__Address_from_json(sqrrl__tbl_Employee, sqrrl__sc)
            elif sqrrl__key == "meta":
                sqrrl__parsed_meta = sqrrl__Tagged_from_json[String](sqrrl__sc)
            elif sqrrl__key == "hometown":
                sqrrl__parsed_hometown = sqrrl__ExternalCity_from_json(sqrrl__sc)
            else:
                raise Error("InvalidJson: unknown field " + sqrrl__key + " for Person")
            if not sqrrl__sc.try_consume_byte(UInt8(ord(","))):
                break
        sqrrl__sc.expect_byte(UInt8(ord("}")))
    if not sqrrl__parsed_name:
        raise Error("InvalidJson: missing field name for Person")
    if not sqrrl__parsed_home:
        raise Error("InvalidJson: missing field home for Person")
    if not sqrrl__parsed_meta:
        raise Error("InvalidJson: missing field meta for Person")
    if not sqrrl__parsed_hometown:
        raise Error("InvalidJson: missing field hometown for Person")
    table.storage[].alloc_specific_id(id)
    var sqrrl__v_name = sqrrl__parsed_name.value()
    var sqrrl__v_home = sqrrl__parsed_home.take()
    var sqrrl__v_meta = sqrrl__parsed_meta.take()
    var sqrrl__v_hometown = sqrrl__parsed_hometown.take()
    var sqrrl__inner = ArcPointer(sqrrl__PersonInner(_id=id, _table=table.storage, _name=sqrrl__v_name, _home=sqrrl__v_home^, _meta=sqrrl__v_meta^, _hometown=sqrrl__v_hometown^))
    table.storage[].register_weak(id, sqrrl__inner)
    table.storage[].indexes.name.add(id, sqrrl__inner[]._name)
    return sqrrl__Person(sqrrl__inner^)

def sqrrl__Person_all_to_json(table: sqrrl__PersonTable) -> String:
    var sqrrl__out = String("[")
    var sqrrl__first = True
    for sqrrl__id in table.storage[].all():
        if not sqrrl__first:
            sqrrl__out += ","
        var sqrrl__e = sqrrl__Person(table.storage[].handle_for(sqrrl__id))
        sqrrl__out += "[" + String(sqrrl__id) + "," + sqrrl__Person_to_json(sqrrl__e) + "]"
        sqrrl__first = False
    sqrrl__out += "]"
    return sqrrl__out^

def sqrrl__Person_all_from_json(table: sqrrl__PersonTable, sqrrl__tbl_Employee: sqrrl__EmployeeTable, mut sqrrl__temp: List[sqrrl__Person], mut sqrrl__sc: sqrrl__JsonScanner) raises:
    sqrrl__sc.expect_byte(UInt8(ord("[")))
    if not sqrrl__sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sqrrl__sc.expect_byte(UInt8(ord("[")))
            var sqrrl__eid = UInt32(sqrrl__sc.parse_json_int())
            sqrrl__sc.expect_byte(UInt8(ord(",")))
            var sqrrl__e = sqrrl__Person_from_json_with_id(table, sqrrl__tbl_Employee, sqrrl__eid, sqrrl__sc)
            sqrrl__sc.expect_byte(UInt8(ord("]")))
            sqrrl__temp.append(sqrrl__e)
            if not sqrrl__sc.try_consume_byte(UInt8(ord(","))):
                break
        sqrrl__sc.expect_byte(UInt8(ord("]")))

def sqrrl__Address_from_json(sqrrl__tbl_Employee: sqrrl__EmployeeTable, mut sqrrl__sc: sqrrl__JsonScanner) raises -> Address:
    var sqrrl__parsed_city: Optional[String] = None
    var sqrrl__parsed_owner: Optional[sqrrl__Employee] = None
    sqrrl__sc.expect_byte(UInt8(ord("{")))
    if not sqrrl__sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var sqrrl__key = sqrrl__sc.parse_json_string()
            sqrrl__sc.expect_byte(UInt8(ord(":")))
            if sqrrl__key == "city":
                sqrrl__parsed_city = sqrrl__sc.parse_json_string()
            elif sqrrl__key == "owner":
                var sqrrl__rid_owner = UInt32(sqrrl__sc.parse_json_int())
                sqrrl__parsed_owner = sqrrl__Employee(sqrrl__tbl_Employee.storage[].handle_for(sqrrl__rid_owner))
            else:
                raise Error("InvalidJson: unknown field " + sqrrl__key + " for Address")
            if not sqrrl__sc.try_consume_byte(UInt8(ord(","))):
                break
        sqrrl__sc.expect_byte(UInt8(ord("}")))
    if not sqrrl__parsed_city:
        raise Error("InvalidJson: missing field city for Address")
    if not sqrrl__parsed_owner:
        raise Error("InvalidJson: missing field owner for Address")
    return Address(city=sqrrl__parsed_city.take(), owner=sqrrl__parsed_owner.take())

def sqrrl__Tagged_from_json[Kind: Copyable & ImplicitlyDeletable](mut sqrrl__sc: sqrrl__JsonScanner) raises -> Tagged[Kind]:
    var sqrrl__parsed_label: Optional[String] = None
    var sqrrl__parsed_count: Optional[UInt32] = None
    sqrrl__sc.expect_byte(UInt8(ord("{")))
    if not sqrrl__sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var sqrrl__key = sqrrl__sc.parse_json_string()
            sqrrl__sc.expect_byte(UInt8(ord(":")))
            if sqrrl__key == "label":
                sqrrl__parsed_label = sqrrl__sc.parse_json_string()
            elif sqrrl__key == "count":
                sqrrl__parsed_count = UInt32(sqrrl__sc.parse_json_int())
            else:
                raise Error("InvalidJson: unknown field " + sqrrl__key + " for Tagged")
            if not sqrrl__sc.try_consume_byte(UInt8(ord(","))):
                break
        sqrrl__sc.expect_byte(UInt8(ord("}")))
    if not sqrrl__parsed_label:
        raise Error("InvalidJson: missing field label for Tagged")
    if not sqrrl__parsed_count:
        raise Error("InvalidJson: missing field count for Tagged")
    return Tagged[Kind](label=sqrrl__parsed_label.take(), count=sqrrl__parsed_count.take())

struct sqrrl__TempKeepAlives(Movable):
    var Employee: List[sqrrl__Employee]
    var Person: List[sqrrl__Person]

    def __init__(out self):
        self.Employee = List[sqrrl__Employee]()
        self.Person = List[sqrrl__Person]()

def sqrrl__world_to_json(world: sqrrl__World) -> String:
    var sqrrl__out = String("{")
    sqrrl__out += '"Employee":'
    sqrrl__out += sqrrl__Employee_all_to_json(world.Employee)
    sqrrl__out += ","
    sqrrl__out += '"Person":'
    sqrrl__out += sqrrl__Person_all_to_json(world.Person)
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
            elif sqrrl__key == "Person":
                sqrrl__Person_all_from_json(world.Person, world.Employee, sqrrl__temp.Person, sqrrl__sc)
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
