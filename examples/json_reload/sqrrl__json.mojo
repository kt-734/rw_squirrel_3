from std.memory import ArcPointer
from std.collections import Set
from squirrel_runtime.json import sqrrl__JsonScanner, sqrrl__json_string_literal, sqrrl__json_bool_literal, sqrrl__to_json
from sqrrl__world import sqrrl__World, sqrrl__init
from company import sqrrl__Project, sqrrl__ProjectInner, sqrrl__ProjectTable
from company import sqrrl__Department, sqrrl__DepartmentInner, sqrrl__DepartmentTable
from company import sqrrl__Tag, sqrrl__TagInner, sqrrl__TagTable

def sqrrl__Project_to_json(e: sqrrl__Project) -> String:
    var sqrrl__out = String("{")
    sqrrl__out += '"name":'
    sqrrl__out += sqrrl__to_json(e._inner[].get_name())
    sqrrl__out += "}"
    return sqrrl__out^

def sqrrl__Project_from_json_with_id(table: sqrrl__ProjectTable, id: UInt32, mut sqrrl__sc: sqrrl__JsonScanner) raises -> sqrrl__Project:
    var sqrrl__parsed_name: Optional[String] = None
    sqrrl__sc.expect_byte(UInt8(ord("{")))
    if not sqrrl__sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var sqrrl__key = sqrrl__sc.parse_json_string()
            sqrrl__sc.expect_byte(UInt8(ord(":")))
            if sqrrl__key == "name":
                sqrrl__parsed_name = sqrrl__sc.parse_json_string()
            else:
                raise Error("InvalidJson: unknown field " + sqrrl__key + " for Project")
            if not sqrrl__sc.try_consume_byte(UInt8(ord(","))):
                break
        sqrrl__sc.expect_byte(UInt8(ord("}")))
    if not sqrrl__parsed_name:
        raise Error("InvalidJson: missing field name for Project")
    table.storage[].alloc_specific_id(id)
    var sqrrl__v_name = sqrrl__parsed_name.value()
    var sqrrl__inner = ArcPointer(sqrrl__ProjectInner(_id=id, _table=table.storage, _name=sqrrl__v_name))
    table.storage[].register_weak(id, sqrrl__inner)
    table.storage[].indexes.name.add(id, sqrrl__inner[]._name)
    return sqrrl__Project(sqrrl__inner^)

def sqrrl__Project_all_to_json(table: sqrrl__ProjectTable) -> String:
    var sqrrl__out = String("[")
    var sqrrl__first = True
    for sqrrl__id in table.storage[].all():
        if not sqrrl__first:
            sqrrl__out += ","
        var sqrrl__e = sqrrl__Project(table.storage[].handle_for(sqrrl__id))
        sqrrl__out += "[" + String(sqrrl__id) + "," + sqrrl__Project_to_json(sqrrl__e) + "]"
        sqrrl__first = False
    sqrrl__out += "]"
    return sqrrl__out^

def sqrrl__Project_all_from_json(table: sqrrl__ProjectTable, mut sqrrl__temp: List[sqrrl__Project], mut sqrrl__sc: sqrrl__JsonScanner) raises:
    sqrrl__sc.expect_byte(UInt8(ord("[")))
    if not sqrrl__sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sqrrl__sc.expect_byte(UInt8(ord("[")))
            var sqrrl__eid = UInt32(sqrrl__sc.parse_json_int())
            sqrrl__sc.expect_byte(UInt8(ord(",")))
            var sqrrl__e = sqrrl__Project_from_json_with_id(table, sqrrl__eid, sqrrl__sc)
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
    sqrrl__out += '"projects":'
    sqrrl__out += "["
    var sqrrl__mfirst_projects = True
    ref sqrrl__mval_projects = e._inner[].get_sqrrl__projects()
    for sqrrl__m_projects in sqrrl__mval_projects:
        if not sqrrl__mfirst_projects:
            sqrrl__out += ","
        sqrrl__out += sqrrl__to_json(sqrrl__m_projects)
        sqrrl__mfirst_projects = False
    sqrrl__out += "]"
    sqrrl__out += "}"
    return sqrrl__out^

def sqrrl__Department_from_json_with_id(table: sqrrl__DepartmentTable, sqrrl__tbl_Project: sqrrl__ProjectTable, id: UInt32, mut sqrrl__sc: sqrrl__JsonScanner) raises -> sqrrl__Department:
    var sqrrl__parsed_name: Optional[String] = None
    var sqrrl__parsed_projects: Optional[Set[sqrrl__Project]] = None
    sqrrl__sc.expect_byte(UInt8(ord("{")))
    if not sqrrl__sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var sqrrl__key = sqrrl__sc.parse_json_string()
            sqrrl__sc.expect_byte(UInt8(ord(":")))
            if sqrrl__key == "name":
                sqrrl__parsed_name = sqrrl__sc.parse_json_string()
            elif sqrrl__key == "projects":
                var sqrrl__mset = Set[sqrrl__Project]()
                sqrrl__sc.expect_byte(UInt8(ord("[")))
                if not sqrrl__sc.try_consume_byte(UInt8(ord("]"))):
                    while True:
                        var sqrrl__elem_id = UInt32(sqrrl__sc.parse_json_int())
                        sqrrl__mset.add(sqrrl__Project(sqrrl__tbl_Project.storage[].handle_for(sqrrl__elem_id)))
                        if not sqrrl__sc.try_consume_byte(UInt8(ord(","))):
                            break
                    sqrrl__sc.expect_byte(UInt8(ord("]")))
                sqrrl__parsed_projects = sqrrl__mset^
            else:
                raise Error("InvalidJson: unknown field " + sqrrl__key + " for Department")
            if not sqrrl__sc.try_consume_byte(UInt8(ord(","))):
                break
        sqrrl__sc.expect_byte(UInt8(ord("}")))
    if not sqrrl__parsed_name:
        raise Error("InvalidJson: missing field name for Department")
    if not sqrrl__parsed_projects:
        raise Error("InvalidJson: missing field projects for Department")
    table.storage[].alloc_specific_id(id)
    var sqrrl__v_name = sqrrl__parsed_name.value()
    var sqrrl__v_projects = sqrrl__parsed_projects.take()
    var sqrrl__inner = ArcPointer(sqrrl__DepartmentInner(_id=id, _table=table.storage, _name=sqrrl__v_name, _sqrrl__projects=sqrrl__v_projects^))
    table.storage[].register_weak(id, sqrrl__inner)
    table.storage[].indexes.name.add(id, sqrrl__inner[]._name)
    table.storage[].indexes.projects.add_many(id, sqrrl__inner[]._sqrrl__projects)
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

def sqrrl__Department_all_from_json(table: sqrrl__DepartmentTable, sqrrl__tbl_Project: sqrrl__ProjectTable, mut sqrrl__temp: List[sqrrl__Department], mut sqrrl__sc: sqrrl__JsonScanner) raises:
    sqrrl__sc.expect_byte(UInt8(ord("[")))
    if not sqrrl__sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sqrrl__sc.expect_byte(UInt8(ord("[")))
            var sqrrl__eid = UInt32(sqrrl__sc.parse_json_int())
            sqrrl__sc.expect_byte(UInt8(ord(",")))
            var sqrrl__e = sqrrl__Department_from_json_with_id(table, sqrrl__tbl_Project, sqrrl__eid, sqrrl__sc)
            sqrrl__sc.expect_byte(UInt8(ord("]")))
            sqrrl__temp.append(sqrrl__e)
            if not sqrrl__sc.try_consume_byte(UInt8(ord(","))):
                break
        sqrrl__sc.expect_byte(UInt8(ord("]")))

def sqrrl__Tag_to_json(e: sqrrl__Tag) -> String:
    var sqrrl__out = String("{")
    sqrrl__out += '"label":'
    sqrrl__out += sqrrl__to_json(e._inner[].get_label())
    sqrrl__out += "}"
    return sqrrl__out^

def sqrrl__Tag_from_json_with_id(table: sqrrl__TagTable, id: UInt32, mut sqrrl__sc: sqrrl__JsonScanner) raises -> sqrrl__Tag:
    var sqrrl__parsed_label: Optional[String] = None
    sqrrl__sc.expect_byte(UInt8(ord("{")))
    if not sqrrl__sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var sqrrl__key = sqrrl__sc.parse_json_string()
            sqrrl__sc.expect_byte(UInt8(ord(":")))
            if sqrrl__key == "label":
                sqrrl__parsed_label = sqrrl__sc.parse_json_string()
            else:
                raise Error("InvalidJson: unknown field " + sqrrl__key + " for Tag")
            if not sqrrl__sc.try_consume_byte(UInt8(ord(","))):
                break
        sqrrl__sc.expect_byte(UInt8(ord("}")))
    if not sqrrl__parsed_label:
        raise Error("InvalidJson: missing field label for Tag")
    table.storage[].alloc_specific_id(id)
    var sqrrl__v_label = sqrrl__parsed_label.value()
    var sqrrl__inner = ArcPointer(sqrrl__TagInner(_id=id, _table=table.storage, _label=sqrrl__v_label))
    table.storage[].register_weak(id, sqrrl__inner)
    table.storage[].indexes.label.add(id, sqrrl__inner[]._label)
    table.storage[].keepalive_add(id, sqrrl__inner.copy())
    return sqrrl__Tag(sqrrl__inner^)

def sqrrl__Tag_all_to_json(table: sqrrl__TagTable) -> String:
    var sqrrl__out = String("[")
    var sqrrl__first = True
    for sqrrl__id in table.storage[].all():
        if not sqrrl__first:
            sqrrl__out += ","
        var sqrrl__e = sqrrl__Tag(table.storage[].handle_for(sqrrl__id))
        sqrrl__out += "[" + String(sqrrl__id) + "," + sqrrl__Tag_to_json(sqrrl__e) + "]"
        sqrrl__first = False
    sqrrl__out += "]"
    return sqrrl__out^

def sqrrl__Tag_all_from_json(table: sqrrl__TagTable, mut sqrrl__sc: sqrrl__JsonScanner) raises:
    sqrrl__sc.expect_byte(UInt8(ord("[")))
    if not sqrrl__sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sqrrl__sc.expect_byte(UInt8(ord("[")))
            var sqrrl__eid = UInt32(sqrrl__sc.parse_json_int())
            sqrrl__sc.expect_byte(UInt8(ord(",")))
            var sqrrl__e = sqrrl__Tag_from_json_with_id(table, sqrrl__eid, sqrrl__sc)
            sqrrl__sc.expect_byte(UInt8(ord("]")))
            _ = sqrrl__e
            if not sqrrl__sc.try_consume_byte(UInt8(ord(","))):
                break
        sqrrl__sc.expect_byte(UInt8(ord("]")))

struct sqrrl__TempKeepAlives(Movable):
    var Project: List[sqrrl__Project]
    var Department: List[sqrrl__Department]

    def __init__(out self):
        self.Project = List[sqrrl__Project]()
        self.Department = List[sqrrl__Department]()

def sqrrl__world_to_json(world: sqrrl__World) -> String:
    var sqrrl__out = String("{")
    sqrrl__out += '"Project":'
    sqrrl__out += sqrrl__Project_all_to_json(world.Project)
    sqrrl__out += ","
    sqrrl__out += '"Department":'
    sqrrl__out += sqrrl__Department_all_to_json(world.Department)
    sqrrl__out += ","
    sqrrl__out += '"Tag":'
    sqrrl__out += sqrrl__Tag_all_to_json(world.Tag)
    sqrrl__out += "}"
    return sqrrl__out^

def sqrrl__world_from_json(mut world: sqrrl__World, mut sqrrl__sc: sqrrl__JsonScanner, mut sqrrl__temp: sqrrl__TempKeepAlives) raises:
    sqrrl__sc.expect_byte(UInt8(ord("{")))
    if not sqrrl__sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var sqrrl__key = sqrrl__sc.parse_json_string()
            sqrrl__sc.expect_byte(UInt8(ord(":")))
            if sqrrl__key == "Project":
                sqrrl__Project_all_from_json(world.Project, sqrrl__temp.Project, sqrrl__sc)
            elif sqrrl__key == "Department":
                sqrrl__Department_all_from_json(world.Department, world.Project, sqrrl__temp.Department, sqrrl__sc)
            elif sqrrl__key == "Tag":
                sqrrl__Tag_all_from_json(world.Tag, sqrrl__sc)
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
