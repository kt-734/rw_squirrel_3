from std.memory import ArcPointer
from std.collections import Set
from squirrel_runtime.json import sqrrl___JsonScanner, sqrrl__json_string_literal, sqrrl__json_bool_literal, sqrrl__to_json_default, sqrrl__from_json_default, sqrrl__movable_rebind
from sqrrl__world import sqrrl___World, sqrrl___init
from std.utils import Variant
from absolute_db import sqrrl__Publisher, sqrrl__PublisherInner, sqrrl__PublisherTable
from absolute_db import sqrrl__Series, sqrrl__SeriesInner, sqrrl__SeriesTable
from absolute_db import sqrrl__VolumeSeries, sqrrl__VolumeSeriesInner, sqrrl__VolumeSeriesTable
from absolute_db import sqrrl__Arc, sqrrl__ArcInner, sqrrl__ArcTable
from absolute_db import sqrrl__SourceArcPart, sqrrl__SourceArcPartInner, sqrrl__SourceArcPartTable
from absolute_db import sqrrl__Issue, sqrrl__IssueInner, sqrrl__IssueTable
from absolute_db import sqrrl__Volume, sqrrl__VolumeInner, sqrrl__VolumeTable


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


def sqrrl__Variant_to_json[T0: Movable & ImplicitlyDeletable, T1: Movable & ImplicitlyDeletable](value: Variant[T0, T1], world: sqrrl___World) -> String:
    if value.isa[T0]():
        return "[" + String(0) + "," + sqrrl__to_json(value.unsafe_get[T0](), world) + "]"
    else:
        return "[" + String(1) + "," + sqrrl__to_json(value.unsafe_get[T1](), world) + "]"


def sqrrl__Variant_from_json[T0: Movable & ImplicitlyDeletable, T1: Movable & ImplicitlyDeletable](mut sc: sqrrl___JsonScanner, world: sqrrl___World) raises -> Variant[T0, T1]:
    sc.expect_byte(UInt8(ord("[")))
    var vidx = sc.parse_json_int()
    sc.expect_byte(UInt8(ord(",")))
    var vresult: Variant[T0, T1]
    if vidx == 0:
        vresult = Variant[T0, T1](sqrrl__from_json[T0](sc, world))
    else:
        vresult = Variant[T0, T1](sqrrl__from_json[T1](sc, world))
    sc.expect_byte(UInt8(ord("]")))
    return vresult^


def sqrrl__to_json[T: AnyType](value: T, world: sqrrl___World) -> String:
    comptime if False:
        pass
    elif T == sqrrl__Publisher:
        return String(rebind[sqrrl__Publisher](value).id())
    elif T == sqrrl__Series:
        return String(rebind[sqrrl__Series](value).id())
    elif T == sqrrl__Arc:
        return String(rebind[sqrrl__Arc](value).id())
    elif T == Optional[String]:
        return sqrrl__Optional_to_json(rebind[Optional[String]](value), world)
    elif T == Variant[sqrrl__SourceArcPart, sqrrl__Series]:
        return sqrrl__Variant_to_json(rebind[Variant[sqrrl__SourceArcPart, sqrrl__Series]](value), world)
    elif T == sqrrl__SourceArcPart:
        return String(rebind[sqrrl__SourceArcPart](value).id())
    elif T == Variant[sqrrl__Arc, sqrrl__VolumeSeries]:
        return sqrrl__Variant_to_json(rebind[Variant[sqrrl__Arc, sqrrl__VolumeSeries]](value), world)
    elif T == sqrrl__VolumeSeries:
        return String(rebind[sqrrl__VolumeSeries](value).id())
    else:
        return sqrrl__to_json_default(value)


def sqrrl__from_json[T: Movable & ImplicitlyDeletable](mut sc: sqrrl___JsonScanner, world: sqrrl___World) raises -> T:
    comptime if False:
        pass
    elif T == sqrrl__Publisher:
        return sqrrl__movable_rebind[sqrrl__Publisher, T](sqrrl__Publisher(world.Publisher.storage[].handle_for(UInt32(sc.parse_json_int()))))
    elif T == sqrrl__Series:
        return sqrrl__movable_rebind[sqrrl__Series, T](sqrrl__Series(world.Series.storage[].handle_for(UInt32(sc.parse_json_int()))))
    elif T == sqrrl__Arc:
        return sqrrl__movable_rebind[sqrrl__Arc, T](sqrrl__Arc(world.Arc.storage[].handle_for(UInt32(sc.parse_json_int()))))
    elif T == Optional[String]:
        return sqrrl__movable_rebind[Optional[String], T](sqrrl__Optional_from_json[String](sc, world))
    elif T == Variant[sqrrl__SourceArcPart, sqrrl__Series]:
        return sqrrl__movable_rebind[Variant[sqrrl__SourceArcPart, sqrrl__Series], T](sqrrl__Variant_from_json[sqrrl__SourceArcPart, sqrrl__Series](sc, world))
    elif T == sqrrl__SourceArcPart:
        return sqrrl__movable_rebind[sqrrl__SourceArcPart, T](sqrrl__SourceArcPart(world.SourceArcPart.storage[].handle_for(UInt32(sc.parse_json_int()))))
    elif T == Variant[sqrrl__Arc, sqrrl__VolumeSeries]:
        return sqrrl__movable_rebind[Variant[sqrrl__Arc, sqrrl__VolumeSeries], T](sqrrl__Variant_from_json[sqrrl__Arc, sqrrl__VolumeSeries](sc, world))
    elif T == sqrrl__VolumeSeries:
        return sqrrl__movable_rebind[sqrrl__VolumeSeries, T](sqrrl__VolumeSeries(world.VolumeSeries.storage[].handle_for(UInt32(sc.parse_json_int()))))
    else:
        return sqrrl__from_json_default[T](sc)

def sqrrl__Publisher_to_json(e: sqrrl__Publisher, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"title":'
    out += sqrrl__to_json(e._inner[].get_title(), world)
    out += "}"
    return out^

def sqrrl__Publisher_from_json_with_id(table: sqrrl__PublisherTable, world: sqrrl___World, id: UInt32, mut sc: sqrrl___JsonScanner) raises -> sqrrl__Publisher:
    var parsed_title: Optional[String] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "title":
                parsed_title = sc.parse_json_string()
            else:
                raise Error("InvalidJson: unknown field " + key + " for Publisher")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_title:
        raise Error("InvalidJson: missing field title for Publisher")
    table.storage[].alloc_specific_id(id)
    var v_title = parsed_title.value()
    var inner = ArcPointer(sqrrl__PublisherInner(_id=id, _table=table.storage, _title=v_title))
    table.storage[].register_weak(id, inner)
    return sqrrl__Publisher(inner^)

def sqrrl__Publisher_all_to_json(table: sqrrl__PublisherTable, world: sqrrl___World) -> String:
    var out = String("[")
    var first = True
    for id in table.storage[].all():
        if not first:
            out += ","
        var e = sqrrl__Publisher(table.storage[].handle_for(id))
        out += "[" + String(id) + "," + sqrrl__Publisher_to_json(e, world) + "]"
        first = False
    out += "]"
    return out^

def sqrrl__Publisher_all_from_json(table: sqrrl__PublisherTable, world: sqrrl___World, mut temp: List[sqrrl__Publisher], mut sc: sqrrl___JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__Publisher_from_json_with_id(table, world, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            temp.append(e)
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

def sqrrl__Series_to_json(e: sqrrl__Series, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"title":'
    out += sqrrl__to_json(e._inner[].get_title(), world)
    out += ","
    out += '"start_year":'
    out += sqrrl__to_json(e._inner[].get_start_year(), world)
    out += ","
    out += '"publisher":'
    out += String(e._inner[].get_sqrrl__publisher().id())
    out += "}"
    return out^

def sqrrl__Series_from_json_with_id(table: sqrrl__SeriesTable, world: sqrrl___World, id: UInt32, mut sc: sqrrl___JsonScanner) raises -> sqrrl__Series:
    var parsed_title: Optional[String] = None
    var parsed_start_year: Optional[Int] = None
    var parsed_publisher: Optional[sqrrl__Publisher] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "title":
                parsed_title = sc.parse_json_string()
            elif key == "start_year":
                parsed_start_year = Int(sc.parse_json_int())
            elif key == "publisher":
                var rid_publisher = UInt32(sc.parse_json_int())
                parsed_publisher = sqrrl__Publisher(world.Publisher.storage[].handle_for(rid_publisher))
            else:
                raise Error("InvalidJson: unknown field " + key + " for Series")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_title:
        raise Error("InvalidJson: missing field title for Series")
    if not parsed_start_year:
        raise Error("InvalidJson: missing field start_year for Series")
    if not parsed_publisher:
        raise Error("InvalidJson: missing field publisher for Series")
    table.storage[].alloc_specific_id(id)
    var v_title = parsed_title.value()
    var v_start_year = parsed_start_year.value()
    var v_publisher = parsed_publisher.value()
    var inner = ArcPointer(sqrrl__SeriesInner(_id=id, _table=table.storage, _title=v_title, _start_year=v_start_year, _sqrrl__publisher=v_publisher))
    table.storage[].register_weak(id, inner)
    return sqrrl__Series(inner^)

def sqrrl__Series_all_to_json(table: sqrrl__SeriesTable, world: sqrrl___World) -> String:
    var out = String("[")
    var first = True
    for id in table.storage[].all():
        if not first:
            out += ","
        var e = sqrrl__Series(table.storage[].handle_for(id))
        out += "[" + String(id) + "," + sqrrl__Series_to_json(e, world) + "]"
        first = False
    out += "]"
    return out^

def sqrrl__Series_all_from_json(table: sqrrl__SeriesTable, world: sqrrl___World, mut temp: List[sqrrl__Series], mut sc: sqrrl___JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__Series_from_json_with_id(table, world, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            temp.append(e)
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

def sqrrl__VolumeSeries_to_json(e: sqrrl__VolumeSeries, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"title":'
    out += sqrrl__to_json(e._inner[].get_title(), world)
    out += ","
    out += '"start_year":'
    out += sqrrl__to_json(e._inner[].get_start_year(), world)
    out += ","
    out += '"publisher":'
    out += String(e._inner[].get_sqrrl__publisher().id())
    out += "}"
    return out^

def sqrrl__VolumeSeries_from_json_with_id(table: sqrrl__VolumeSeriesTable, world: sqrrl___World, id: UInt32, mut sc: sqrrl___JsonScanner) raises -> sqrrl__VolumeSeries:
    var parsed_title: Optional[String] = None
    var parsed_start_year: Optional[Int] = None
    var parsed_publisher: Optional[sqrrl__Publisher] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "title":
                parsed_title = sc.parse_json_string()
            elif key == "start_year":
                parsed_start_year = Int(sc.parse_json_int())
            elif key == "publisher":
                var rid_publisher = UInt32(sc.parse_json_int())
                parsed_publisher = sqrrl__Publisher(world.Publisher.storage[].handle_for(rid_publisher))
            else:
                raise Error("InvalidJson: unknown field " + key + " for VolumeSeries")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_title:
        raise Error("InvalidJson: missing field title for VolumeSeries")
    if not parsed_start_year:
        raise Error("InvalidJson: missing field start_year for VolumeSeries")
    if not parsed_publisher:
        raise Error("InvalidJson: missing field publisher for VolumeSeries")
    table.storage[].alloc_specific_id(id)
    var v_title = parsed_title.value()
    var v_start_year = parsed_start_year.value()
    var v_publisher = parsed_publisher.value()
    var inner = ArcPointer(sqrrl__VolumeSeriesInner(_id=id, _table=table.storage, _title=v_title, _start_year=v_start_year, _sqrrl__publisher=v_publisher))
    table.storage[].register_weak(id, inner)
    return sqrrl__VolumeSeries(inner^)

def sqrrl__VolumeSeries_all_to_json(table: sqrrl__VolumeSeriesTable, world: sqrrl___World) -> String:
    var out = String("[")
    var first = True
    for id in table.storage[].all():
        if not first:
            out += ","
        var e = sqrrl__VolumeSeries(table.storage[].handle_for(id))
        out += "[" + String(id) + "," + sqrrl__VolumeSeries_to_json(e, world) + "]"
        first = False
    out += "]"
    return out^

def sqrrl__VolumeSeries_all_from_json(table: sqrrl__VolumeSeriesTable, world: sqrrl___World, mut temp: List[sqrrl__VolumeSeries], mut sc: sqrrl___JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__VolumeSeries_from_json_with_id(table, world, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            temp.append(e)
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

def sqrrl__Arc_to_json(e: sqrrl__Arc, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"title":'
    out += sqrrl__to_json(e._inner[].get_title(), world)
    out += ","
    out += '"series":'
    out += String(e._inner[].get_sqrrl__series().id())
    out += "}"
    return out^

def sqrrl__Arc_from_json_with_id(table: sqrrl__ArcTable, world: sqrrl___World, id: UInt32, mut sc: sqrrl___JsonScanner) raises -> sqrrl__Arc:
    var parsed_title: Optional[String] = None
    var parsed_series: Optional[sqrrl__Series] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "title":
                parsed_title = sc.parse_json_string()
            elif key == "series":
                var rid_series = UInt32(sc.parse_json_int())
                parsed_series = sqrrl__Series(world.Series.storage[].handle_for(rid_series))
            else:
                raise Error("InvalidJson: unknown field " + key + " for Arc")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_title:
        raise Error("InvalidJson: missing field title for Arc")
    if not parsed_series:
        raise Error("InvalidJson: missing field series for Arc")
    table.storage[].alloc_specific_id(id)
    var v_title = parsed_title.value()
    var v_series = parsed_series.value()
    var inner = ArcPointer(sqrrl__ArcInner(_id=id, _table=table.storage, _title=v_title, _sqrrl__series=v_series))
    table.storage[].register_weak(id, inner)
    return sqrrl__Arc(inner^)

def sqrrl__Arc_all_to_json(table: sqrrl__ArcTable, world: sqrrl___World) -> String:
    var out = String("[")
    var first = True
    for id in table.storage[].all():
        if not first:
            out += ","
        var e = sqrrl__Arc(table.storage[].handle_for(id))
        out += "[" + String(id) + "," + sqrrl__Arc_to_json(e, world) + "]"
        first = False
    out += "]"
    return out^

def sqrrl__Arc_all_from_json(table: sqrrl__ArcTable, world: sqrrl___World, mut temp: List[sqrrl__Arc], mut sc: sqrrl___JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__Arc_from_json_with_id(table, world, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            temp.append(e)
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

def sqrrl__SourceArcPart_to_json(e: sqrrl__SourceArcPart, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"arc":'
    out += String(e._inner[].get_sqrrl__arc().id())
    out += ","
    out += '"part":'
    out += sqrrl__to_json(e._inner[].get_part(), world)
    out += "}"
    return out^

def sqrrl__SourceArcPart_from_json_with_id(table: sqrrl__SourceArcPartTable, world: sqrrl___World, id: UInt32, mut sc: sqrrl___JsonScanner) raises -> sqrrl__SourceArcPart:
    var parsed_arc: Optional[sqrrl__Arc] = None
    var parsed_part: Optional[String] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "arc":
                var rid_arc = UInt32(sc.parse_json_int())
                parsed_arc = sqrrl__Arc(world.Arc.storage[].handle_for(rid_arc))
            elif key == "part":
                parsed_part = sc.parse_json_string()
            else:
                raise Error("InvalidJson: unknown field " + key + " for SourceArcPart")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_arc:
        raise Error("InvalidJson: missing field arc for SourceArcPart")
    if not parsed_part:
        raise Error("InvalidJson: missing field part for SourceArcPart")
    table.storage[].alloc_specific_id(id)
    var v_arc = parsed_arc.value()
    var v_part = parsed_part.value()
    var inner = ArcPointer(sqrrl__SourceArcPartInner(_id=id, _table=table.storage, _sqrrl__arc=v_arc, _part=v_part))
    table.storage[].register_weak(id, inner)
    return sqrrl__SourceArcPart(inner^)

def sqrrl__SourceArcPart_all_to_json(table: sqrrl__SourceArcPartTable, world: sqrrl___World) -> String:
    var out = String("[")
    var first = True
    for id in table.storage[].all():
        if not first:
            out += ","
        var e = sqrrl__SourceArcPart(table.storage[].handle_for(id))
        out += "[" + String(id) + "," + sqrrl__SourceArcPart_to_json(e, world) + "]"
        first = False
    out += "]"
    return out^

def sqrrl__SourceArcPart_all_from_json(table: sqrrl__SourceArcPartTable, world: sqrrl___World, mut temp: List[sqrrl__SourceArcPart], mut sc: sqrrl___JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__SourceArcPart_from_json_with_id(table, world, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            temp.append(e)
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

def sqrrl__Issue_to_json(e: sqrrl__Issue, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"title":'
    out += sqrrl__to_json(e._inner[].get_title(), world)
    out += ","
    out += '"source":'
    ref fv_source = e._inner[].get_sqrrl__source()
    out += sqrrl__Variant_to_json(fv_source, world)
    out += ","
    out += '"no":'
    out += sqrrl__to_json(e._inner[].get_no(), world)
    out += ","
    out += '"owned":'
    out += sqrrl__to_json(e._inner[].get_owned(), world)
    out += "}"
    return out^

def sqrrl__Issue_from_json_with_id(table: sqrrl__IssueTable, world: sqrrl___World, id: UInt32, mut sc: sqrrl___JsonScanner) raises -> sqrrl__Issue:
    var parsed_title: Optional[Optional[String]] = None
    var parsed_source: Optional[Variant[sqrrl__SourceArcPart, sqrrl__Series]] = None
    var parsed_no: Optional[Int] = None
    var parsed_owned: Optional[Bool] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "title":
                parsed_title = sqrrl__from_json[Optional[String]](sc, world)
            elif key == "source":
                parsed_source = sqrrl__Variant_from_json[sqrrl__SourceArcPart, sqrrl__Series](sc, world)
            elif key == "no":
                parsed_no = Int(sc.parse_json_int())
            elif key == "owned":
                parsed_owned = sc.parse_json_bool()
            else:
                raise Error("InvalidJson: unknown field " + key + " for Issue")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_title:
        raise Error("InvalidJson: missing field title for Issue")
    if not parsed_source:
        raise Error("InvalidJson: missing field source for Issue")
    if not parsed_no:
        raise Error("InvalidJson: missing field no for Issue")
    if not parsed_owned:
        raise Error("InvalidJson: missing field owned for Issue")
    table.storage[].alloc_specific_id(id)
    var v_title = parsed_title.take()
    var v_source = parsed_source.take()
    var v_no = parsed_no.value()
    var v_owned = parsed_owned.value()
    var inner = ArcPointer(sqrrl__IssueInner(_id=id, _table=table.storage, _title=v_title^, _sqrrl__source=v_source^, _no=v_no, _owned=v_owned))
    table.storage[].register_weak(id, inner)
    table.storage[].indexes.owned.add(id, inner[]._owned)
    table.storage[].keepalive_add(id, inner.copy())
    return sqrrl__Issue(inner^)

def sqrrl__Issue_all_to_json(table: sqrrl__IssueTable, world: sqrrl___World) -> String:
    var out = String("[")
    var first = True
    for id in table.storage[].all():
        if not first:
            out += ","
        var e = sqrrl__Issue(table.storage[].handle_for(id))
        out += "[" + String(id) + "," + sqrrl__Issue_to_json(e, world) + "]"
        first = False
    out += "]"
    return out^

def sqrrl__Issue_all_from_json(table: sqrrl__IssueTable, world: sqrrl___World, mut sc: sqrrl___JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__Issue_from_json_with_id(table, world, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            _ = e
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

def sqrrl__Volume_to_json(e: sqrrl__Volume, world: sqrrl___World) -> String:
    var out = String("{")
    out += '"source":'
    ref fv_source = e._inner[].get_sqrrl__source()
    out += sqrrl__Variant_to_json(fv_source, world)
    out += ","
    out += '"issues":'
    out += "["
    var mfirst_issues = True
    ref mval_issues = e._inner[].get_sqrrl__issues()
    for m_issues in mval_issues:
        if not mfirst_issues:
            out += ","
        out += String(m_issues.id())
        mfirst_issues = False
    out += "]"
    out += ","
    out += '"no":'
    out += sqrrl__to_json(e._inner[].get_no(), world)
    out += ","
    out += '"owned":'
    out += sqrrl__to_json(e._inner[].get_owned(), world)
    out += "}"
    return out^

def sqrrl__Volume_from_json_with_id(table: sqrrl__VolumeTable, world: sqrrl___World, id: UInt32, mut sc: sqrrl___JsonScanner) raises -> sqrrl__Volume:
    var parsed_source: Optional[Variant[sqrrl__Arc, sqrrl__VolumeSeries]] = None
    var parsed_issues: Optional[Set[sqrrl__Issue]] = None
    var parsed_no: Optional[Int] = None
    var parsed_owned: Optional[Bool] = None
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "source":
                parsed_source = sqrrl__Variant_from_json[sqrrl__Arc, sqrrl__VolumeSeries](sc, world)
            elif key == "issues":
                var mset = Set[sqrrl__Issue]()
                sc.expect_byte(UInt8(ord("[")))
                if not sc.try_consume_byte(UInt8(ord("]"))):
                    while True:
                        var elem_id = UInt32(sc.parse_json_int())
                        mset.add(sqrrl__Issue(world.Issue.storage[].handle_for(elem_id)))
                        if not sc.try_consume_byte(UInt8(ord(","))):
                            break
                    sc.expect_byte(UInt8(ord("]")))
                parsed_issues = mset^
            elif key == "no":
                parsed_no = Int(sc.parse_json_int())
            elif key == "owned":
                parsed_owned = sc.parse_json_bool()
            else:
                raise Error("InvalidJson: unknown field " + key + " for Volume")
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("}")))
    if not parsed_source:
        raise Error("InvalidJson: missing field source for Volume")
    if not parsed_issues:
        raise Error("InvalidJson: missing field issues for Volume")
    if not parsed_no:
        raise Error("InvalidJson: missing field no for Volume")
    if not parsed_owned:
        raise Error("InvalidJson: missing field owned for Volume")
    table.storage[].alloc_specific_id(id)
    var v_source = parsed_source.take()
    var v_issues = parsed_issues.take()
    var v_no = parsed_no.value()
    var v_owned = parsed_owned.value()
    var inner = ArcPointer(sqrrl__VolumeInner(_id=id, _table=table.storage, _sqrrl__source=v_source^, _sqrrl__issues=v_issues^, _no=v_no, _owned=v_owned))
    table.storage[].register_weak(id, inner)
    table.storage[].indexes.issues.add_many(id, inner[]._sqrrl__issues)
    table.storage[].indexes.owned.add(id, inner[]._owned)
    table.storage[].keepalive_add(id, inner.copy())
    return sqrrl__Volume(inner^)

def sqrrl__Volume_all_to_json(table: sqrrl__VolumeTable, world: sqrrl___World) -> String:
    var out = String("[")
    var first = True
    for id in table.storage[].all():
        if not first:
            out += ","
        var e = sqrrl__Volume(table.storage[].handle_for(id))
        out += "[" + String(id) + "," + sqrrl__Volume_to_json(e, world) + "]"
        first = False
    out += "]"
    return out^

def sqrrl__Volume_all_from_json(table: sqrrl__VolumeTable, world: sqrrl___World, mut sc: sqrrl___JsonScanner) raises:
    sc.expect_byte(UInt8(ord("[")))
    if not sc.try_consume_byte(UInt8(ord("]"))):
        while True:
            sc.expect_byte(UInt8(ord("[")))
            var eid = UInt32(sc.parse_json_int())
            sc.expect_byte(UInt8(ord(",")))
            var e = sqrrl__Volume_from_json_with_id(table, world, eid, sc)
            sc.expect_byte(UInt8(ord("]")))
            _ = e
            if not sc.try_consume_byte(UInt8(ord(","))):
                break
        sc.expect_byte(UInt8(ord("]")))

struct sqrrl___TempKeepAlives(Movable):
    var Publisher: List[sqrrl__Publisher]
    var Series: List[sqrrl__Series]
    var VolumeSeries: List[sqrrl__VolumeSeries]
    var Arc: List[sqrrl__Arc]
    var SourceArcPart: List[sqrrl__SourceArcPart]

    def __init__(out self):
        self.Publisher = List[sqrrl__Publisher]()
        self.Series = List[sqrrl__Series]()
        self.VolumeSeries = List[sqrrl__VolumeSeries]()
        self.Arc = List[sqrrl__Arc]()
        self.SourceArcPart = List[sqrrl__SourceArcPart]()

def sqrrl___world_to_json(world: sqrrl___World) -> String:
    var out = String("{")
    out += '"Publisher":'
    out += sqrrl__Publisher_all_to_json(world.Publisher, world)
    out += ","
    out += '"Series":'
    out += sqrrl__Series_all_to_json(world.Series, world)
    out += ","
    out += '"VolumeSeries":'
    out += sqrrl__VolumeSeries_all_to_json(world.VolumeSeries, world)
    out += ","
    out += '"Arc":'
    out += sqrrl__Arc_all_to_json(world.Arc, world)
    out += ","
    out += '"SourceArcPart":'
    out += sqrrl__SourceArcPart_all_to_json(world.SourceArcPart, world)
    out += ","
    out += '"Issue":'
    out += sqrrl__Issue_all_to_json(world.Issue, world)
    out += ","
    out += '"Volume":'
    out += sqrrl__Volume_all_to_json(world.Volume, world)
    out += "}"
    return out^

def sqrrl___world_from_json(mut world: sqrrl___World, mut sc: sqrrl___JsonScanner, mut temp: sqrrl___TempKeepAlives) raises:
    sc.expect_byte(UInt8(ord("{")))
    if not sc.try_consume_byte(UInt8(ord("}"))):
        while True:
            var key = sc.parse_json_string()
            sc.expect_byte(UInt8(ord(":")))
            if key == "Publisher":
                sqrrl__Publisher_all_from_json(world.Publisher, world, temp.Publisher, sc)
            elif key == "Series":
                sqrrl__Series_all_from_json(world.Series, world, temp.Series, sc)
            elif key == "VolumeSeries":
                sqrrl__VolumeSeries_all_from_json(world.VolumeSeries, world, temp.VolumeSeries, sc)
            elif key == "Arc":
                sqrrl__Arc_all_from_json(world.Arc, world, temp.Arc, sc)
            elif key == "SourceArcPart":
                sqrrl__SourceArcPart_all_from_json(world.SourceArcPart, world, temp.SourceArcPart, sc)
            elif key == "Issue":
                sqrrl__Issue_all_from_json(world.Issue, world, sc)
            elif key == "Volume":
                sqrrl__Volume_all_from_json(world.Volume, world, sc)
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
