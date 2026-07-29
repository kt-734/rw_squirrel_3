from std.memory import ArcPointer
from std.collections import Set
from squirrel_runtime.json import sqrrl___JsonScanner, sqrrl__json_string_literal, sqrrl__json_bool_literal, sqrrl__to_json_default, sqrrl__from_json_default, sqrrl__movable_rebind
from sqrrl__world import sqrrl___World, sqrrl___init
from company_impl import sqrrl__Project, sqrrl__ProjectInner, sqrrl__ProjectTable
from company_impl import sqrrl__Department, sqrrl__DepartmentInner, sqrrl__DepartmentTable
from company_impl import sqrrl__Tag, sqrrl__TagInner, sqrrl__TagTable


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
    else:
        return sqrrl__to_json_default(value)


def sqrrl__from_json[T: Movable & ImplicitlyDeletable](mut sc: sqrrl___JsonScanner, world: sqrrl___World) raises -> T:
    comptime if False:
        pass
    else:
        return sqrrl__from_json_default[T](sc)

def sqrrl__Project_to_json(e: sqrrl__Project, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"name":'
    out += sqrrl__to_json(e._inner[].get_name(), world)
    out += "}"
    return out^

def sqrrl__Project_from_json_with_id(table: sqrrl__ProjectTable, world: sqrrl___World, id: UInt32, mut sc: sqrrl___JsonScanner) raises -> sqrrl__Project:
    var parsed_name: Optional[String] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "name":
                parsed_name = sc.parse_json_string()
            else:
                raise Error("InvalidJson: unknown field " + key + " for Project")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_name:
        raise Error("InvalidJson: missing field name for Project")
    table.storage[].alloc_specific_id(id)
    var v_name = parsed_name.value()
    var inner = ArcPointer(sqrrl__ProjectInner(_id=id, _table=table.storage, _name=v_name))
    table.storage[].register_weak(id, inner)
    table.storage[].indexes.name.add(id, inner[]._name)
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

def sqrrl__Department_to_json(e: sqrrl__Department, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"name":'
    out += sqrrl__to_json(e._inner[].get_name(), world)
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
    out += "}"
    return out^

def sqrrl__Department_from_json_with_id(table: sqrrl__DepartmentTable, world: sqrrl___World, id: UInt32, mut sc: sqrrl___JsonScanner) raises -> sqrrl__Department:
    var parsed_name: Optional[String] = None
    var parsed_projects: Optional[Set[sqrrl__Project]] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "name":
                parsed_name = sc.parse_json_string()
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
            else:
                raise Error("InvalidJson: unknown field " + key + " for Department")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_name:
        raise Error("InvalidJson: missing field name for Department")
    if not parsed_projects:
        raise Error("InvalidJson: missing field projects for Department")
    table.storage[].alloc_specific_id(id)
    var v_name = parsed_name.value()
    var v_projects = parsed_projects.take()
    var inner = ArcPointer(sqrrl__DepartmentInner(_id=id, _table=table.storage, _name=v_name, _sqrrl__projects=v_projects^))
    table.storage[].register_weak(id, inner)
    table.storage[].indexes.name.add(id, inner[]._name)
    table.storage[].indexes.projects.add_many(id, inner[]._sqrrl__projects)
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

def sqrrl__Tag_to_json(e: sqrrl__Tag, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"label":'
    out += sqrrl__to_json(e._inner[].get_label(), world)
    out += "}"
    return out^

def sqrrl__Tag_from_json_with_id(table: sqrrl__TagTable, world: sqrrl___World, id: UInt32, mut sc: sqrrl___JsonScanner) raises -> sqrrl__Tag:
    var parsed_label: Optional[String] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "label":
                parsed_label = sc.parse_json_string()
            else:
                raise Error("InvalidJson: unknown field " + key + " for Tag")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_label:
        raise Error("InvalidJson: missing field label for Tag")
    table.storage[].alloc_specific_id(id)
    var v_label = parsed_label.value()
    var inner = ArcPointer(sqrrl__TagInner(_id=id, _table=table.storage, _label=v_label))
    table.storage[].register_weak(id, inner)
    table.storage[].indexes.label.add(id, inner[]._label)
    table.storage[].keepalive_add(id, inner.copy())
    return sqrrl__Tag(inner^)

def sqrrl__Tag_all_to_json(table: sqrrl__TagTable, world: sqrrl___World) -> String:
    var out = String("[")
    var first = True
    for id in table.storage[].all():
        if not first:
            out += ","
        var e = sqrrl__Tag(table.storage[].handle_for(id))
        out += "[" + String(id) + "," + sqrrl__Tag_to_json(e, world) + "]"
        first = False
    out += "]"
    return out^

def sqrrl__Tag_all_from_json(table: sqrrl__TagTable, world: sqrrl___World, mut sc: sqrrl___JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__Tag_from_json_with_id(table, world, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            _ = e
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

struct sqrrl___TempKeepAlives(Movable):
    var Project: List[sqrrl__Project]
    var Department: List[sqrrl__Department]

    def __init__(out self):
        self.Project = List[sqrrl__Project]()
        self.Department = List[sqrrl__Department]()

def sqrrl___world_to_json(world: sqrrl___World) -> String:
    var out = String("{")
    out += '"Project":'
    out += sqrrl__Project_all_to_json(world.Project, world)
    out += ","
    out += '"Department":'
    out += sqrrl__Department_all_to_json(world.Department, world)
    out += ","
    out += '"Tag":'
    out += sqrrl__Tag_all_to_json(world.Tag, world)
    out += "}"
    return out^

def sqrrl___world_from_json(mut world: sqrrl___World, mut sc: sqrrl___JsonScanner, mut temp: sqrrl___TempKeepAlives) raises:
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "Project":
                sqrrl__Project_all_from_json(world.Project, world, temp.Project, sc)
            elif key == "Department":
                sqrrl__Department_all_from_json(world.Department, world, temp.Department, sc)
            elif key == "Tag":
                sqrrl__Tag_all_from_json(world.Tag, world, sc)
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
