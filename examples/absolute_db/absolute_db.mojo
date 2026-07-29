from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl___JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from std.utils import Variant
from sqrrl__world import sqrrl___init, sqrrl___World
from sqrrl__json import sqrrl___begin_init_from_json, sqrrl___end_init_from_json, sqrrl___init_from_json, sqrrl___world_to_json


@fieldwise_init
struct sqrrl__PublisherInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__PublisherIndexes, sqrrl__PublisherInner]]
    var _title: String

    def __del__(deinit self):
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_title(mut self, v: String):
        self._title = v

    @always_inline
    def get_title(self) -> ref [self._title] String:
        return self._title


struct sqrrl__Publisher(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl___JsonSerializable):
    var _inner: ArcPointer[sqrrl__PublisherInner]

    def __init__(out self, var inner: sqrrl__PublisherInner):
        self._inner = ArcPointer(inner^)

    def __init__(out self, var inner: ArcPointer[sqrrl__PublisherInner]):
        self._inner = inner^

    def id(self) -> UInt32:
        return self._inner[]._id

    def ref_count(self) -> Int:
        return Int(self._inner.count())

    def __hash__[H: Hasher](self, mut hasher: H):
        hasher.update(self.id())

    def __eq__(self, other: Self) -> Bool:
        return self.id() == other.id()

    def __ne__(self, other: Self) -> Bool:
        return self.id() != other.id()

    def sqrrl__to_json(self) -> String:
        return String(self.id())


struct sqrrl__PublisherIndexes(Movable, ImplicitlyDeletable):
    def __init__(out self):
        pass


struct sqrrl__PublisherTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__PublisherIndexes, sqrrl__PublisherInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__PublisherIndexes, sqrrl__PublisherInner](sqrrl__PublisherIndexes()))

    def create(mut self, *, title: String) -> sqrrl__Publisher:
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__PublisherInner(_id=id, _table=self.storage, _title=title))
        self.storage[].register_weak(id, inner)
        return sqrrl__Publisher(inner^)

    def all(self) -> Set[sqrrl__Publisher]:
        var out = Set[sqrrl__Publisher]()
        for id in self.storage[].all():
            out.add(sqrrl__Publisher(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

@fieldwise_init
struct sqrrl__SeriesInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__SeriesIndexes, sqrrl__SeriesInner]]
    var _title: String
    var _start_year: Int
    var _sqrrl__publisher: sqrrl__Publisher

    def __del__(deinit self):
        self._table[].indexes._sqrrl__key0.remove(self._id, sqrrl__SeriesKey0(title=self._title, start_year=self._start_year))
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_sqrrl__publisher(mut self, v: sqrrl__Publisher):
        self._sqrrl__publisher = v

    @always_inline
    def get_title(self) -> ref [self._title] String:
        return self._title

    @always_inline
    def get_start_year(self) -> ref [self._start_year] Int:
        return self._start_year

    @always_inline
    def get_sqrrl__publisher(self) -> ref [self._sqrrl__publisher] sqrrl__Publisher:
        return self._sqrrl__publisher


struct sqrrl__Series(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl___JsonSerializable):
    var _inner: ArcPointer[sqrrl__SeriesInner]

    def __init__(out self, var inner: sqrrl__SeriesInner):
        self._inner = ArcPointer(inner^)

    def __init__(out self, var inner: ArcPointer[sqrrl__SeriesInner]):
        self._inner = inner^

    def id(self) -> UInt32:
        return self._inner[]._id

    def ref_count(self) -> Int:
        return Int(self._inner.count())

    def __hash__[H: Hasher](self, mut hasher: H):
        hasher.update(self.id())

    def __eq__(self, other: Self) -> Bool:
        return self.id() == other.id()

    def __ne__(self, other: Self) -> Bool:
        return self.id() != other.id()

    def sqrrl__to_json(self) -> String:
        return String(self.id())

    def describe(self) -> String:
        return self._inner[]._title + " (" + String(self._inner[]._start_year) + ")"



@fieldwise_init
struct sqrrl__SeriesKey0(Copyable, Movable, Hashable, Equatable):
    var title: String
    var start_year: Int

    def __eq__(self, other: Self) -> Bool:
        if self.title != other.title:
            return False
        if self.start_year != other.start_year:
            return False
        return True

    def __ne__(self, other: Self) -> Bool:
        return not (self == other)

    def __hash__[H: Hasher](self, mut hasher: H):
        hasher.update(self.title)
        hasher.update(self.start_year)


struct sqrrl__SeriesIndexes(Movable, ImplicitlyDeletable):
    var _sqrrl__key0: UniqueIndex[sqrrl__SeriesKey0]

    def __init__(out self):
        self._sqrrl__key0 = UniqueIndex[sqrrl__SeriesKey0]()


struct sqrrl__SeriesTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__SeriesIndexes, sqrrl__SeriesInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__SeriesIndexes, sqrrl__SeriesInner](sqrrl__SeriesIndexes()))

    def create(mut self, *, title: String, start_year: Int, sqrrl__publisher: sqrrl__Publisher) raises -> sqrrl__Series:
        var sqrrl___key0 = sqrrl__SeriesKey0(title=title, start_year=start_year)
        if self.storage[].indexes._sqrrl__key0.contains(sqrrl___key0):
            raise Error("UniqueConstraintViolation: key(title, start_year) already in use by another entity")
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__SeriesInner(_id=id, _table=self.storage, _title=title, _start_year=start_year, _sqrrl__publisher=sqrrl__publisher))
        self.storage[].register_weak(id, inner)
        self.storage[].indexes._sqrrl__key0.add(id, sqrrl___key0)
        return sqrrl__Series(inner^)

    def all(self) -> Set[sqrrl__Series]:
        var out = Set[sqrrl__Series]()
        for id in self.storage[].all():
            out.add(sqrrl__Series(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

    def for_title_start_year(self, title: String, start_year: Int) raises -> sqrrl__Series:
        var id = self.storage[].indexes._sqrrl__key0.get_bwd(sqrrl__SeriesKey0(title=title, start_year=start_year))
        return sqrrl__Series(self.storage[].handle_for(id))

@fieldwise_init
struct sqrrl__VolumeSeriesInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__VolumeSeriesIndexes, sqrrl__VolumeSeriesInner]]
    var _title: String
    var _start_year: Int
    var _sqrrl__publisher: sqrrl__Publisher

    def __del__(deinit self):
        self._table[].indexes._sqrrl__key0.remove(self._id, sqrrl__VolumeSeriesKey0(title=self._title, start_year=self._start_year))
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_sqrrl__publisher(mut self, v: sqrrl__Publisher):
        self._sqrrl__publisher = v

    @always_inline
    def get_title(self) -> ref [self._title] String:
        return self._title

    @always_inline
    def get_start_year(self) -> ref [self._start_year] Int:
        return self._start_year

    @always_inline
    def get_sqrrl__publisher(self) -> ref [self._sqrrl__publisher] sqrrl__Publisher:
        return self._sqrrl__publisher


struct sqrrl__VolumeSeries(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl___JsonSerializable):
    var _inner: ArcPointer[sqrrl__VolumeSeriesInner]

    def __init__(out self, var inner: sqrrl__VolumeSeriesInner):
        self._inner = ArcPointer(inner^)

    def __init__(out self, var inner: ArcPointer[sqrrl__VolumeSeriesInner]):
        self._inner = inner^

    def id(self) -> UInt32:
        return self._inner[]._id

    def ref_count(self) -> Int:
        return Int(self._inner.count())

    def __hash__[H: Hasher](self, mut hasher: H):
        hasher.update(self.id())

    def __eq__(self, other: Self) -> Bool:
        return self.id() == other.id()

    def __ne__(self, other: Self) -> Bool:
        return self.id() != other.id()

    def sqrrl__to_json(self) -> String:
        return String(self.id())

    def describe(self) -> String:
        return self._inner[]._title + " (" + String(self._inner[]._start_year) + ")"



@fieldwise_init
struct sqrrl__VolumeSeriesKey0(Copyable, Movable, Hashable, Equatable):
    var title: String
    var start_year: Int

    def __eq__(self, other: Self) -> Bool:
        if self.title != other.title:
            return False
        if self.start_year != other.start_year:
            return False
        return True

    def __ne__(self, other: Self) -> Bool:
        return not (self == other)

    def __hash__[H: Hasher](self, mut hasher: H):
        hasher.update(self.title)
        hasher.update(self.start_year)


struct sqrrl__VolumeSeriesIndexes(Movable, ImplicitlyDeletable):
    var _sqrrl__key0: UniqueIndex[sqrrl__VolumeSeriesKey0]

    def __init__(out self):
        self._sqrrl__key0 = UniqueIndex[sqrrl__VolumeSeriesKey0]()


struct sqrrl__VolumeSeriesTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__VolumeSeriesIndexes, sqrrl__VolumeSeriesInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__VolumeSeriesIndexes, sqrrl__VolumeSeriesInner](sqrrl__VolumeSeriesIndexes()))

    def create(mut self, *, title: String, start_year: Int, sqrrl__publisher: sqrrl__Publisher) raises -> sqrrl__VolumeSeries:
        var sqrrl___key0 = sqrrl__VolumeSeriesKey0(title=title, start_year=start_year)
        if self.storage[].indexes._sqrrl__key0.contains(sqrrl___key0):
            raise Error("UniqueConstraintViolation: key(title, start_year) already in use by another entity")
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__VolumeSeriesInner(_id=id, _table=self.storage, _title=title, _start_year=start_year, _sqrrl__publisher=sqrrl__publisher))
        self.storage[].register_weak(id, inner)
        self.storage[].indexes._sqrrl__key0.add(id, sqrrl___key0)
        return sqrrl__VolumeSeries(inner^)

    def all(self) -> Set[sqrrl__VolumeSeries]:
        var out = Set[sqrrl__VolumeSeries]()
        for id in self.storage[].all():
            out.add(sqrrl__VolumeSeries(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

    def for_title_start_year(self, title: String, start_year: Int) raises -> sqrrl__VolumeSeries:
        var id = self.storage[].indexes._sqrrl__key0.get_bwd(sqrrl__VolumeSeriesKey0(title=title, start_year=start_year))
        return sqrrl__VolumeSeries(self.storage[].handle_for(id))

@fieldwise_init
struct sqrrl__ArcInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__ArcIndexes, sqrrl__ArcInner]]
    var _title: String
    var _sqrrl__series: sqrrl__Series

    def __del__(deinit self):
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_title(mut self, v: String):
        self._title = v

    def set_sqrrl__series(mut self, v: sqrrl__Series):
        self._sqrrl__series = v

    @always_inline
    def get_title(self) -> ref [self._title] String:
        return self._title

    @always_inline
    def get_sqrrl__series(self) -> ref [self._sqrrl__series] sqrrl__Series:
        return self._sqrrl__series


struct sqrrl__Arc(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl___JsonSerializable):
    var _inner: ArcPointer[sqrrl__ArcInner]

    def __init__(out self, var inner: sqrrl__ArcInner):
        self._inner = ArcPointer(inner^)

    def __init__(out self, var inner: ArcPointer[sqrrl__ArcInner]):
        self._inner = inner^

    def id(self) -> UInt32:
        return self._inner[]._id

    def ref_count(self) -> Int:
        return Int(self._inner.count())

    def __hash__[H: Hasher](self, mut hasher: H):
        hasher.update(self.id())

    def __eq__(self, other: Self) -> Bool:
        return self.id() == other.id()

    def __ne__(self, other: Self) -> Bool:
        return self.id() != other.id()

    def sqrrl__to_json(self) -> String:
        return String(self.id())


struct sqrrl__ArcIndexes(Movable, ImplicitlyDeletable):
    def __init__(out self):
        pass


struct sqrrl__ArcTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__ArcIndexes, sqrrl__ArcInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__ArcIndexes, sqrrl__ArcInner](sqrrl__ArcIndexes()))

    def create(mut self, *, title: String, sqrrl__series: sqrrl__Series) -> sqrrl__Arc:
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__ArcInner(_id=id, _table=self.storage, _title=title, _sqrrl__series=sqrrl__series))
        self.storage[].register_weak(id, inner)
        return sqrrl__Arc(inner^)

    def all(self) -> Set[sqrrl__Arc]:
        var out = Set[sqrrl__Arc]()
        for id in self.storage[].all():
            out.add(sqrrl__Arc(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

@fieldwise_init
struct sqrrl__SourceArcPartInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__SourceArcPartIndexes, sqrrl__SourceArcPartInner]]
    var _sqrrl__arc: sqrrl__Arc
    var _part: String

    def __del__(deinit self):
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_sqrrl__arc(mut self, v: sqrrl__Arc):
        self._sqrrl__arc = v

    def set_part(mut self, v: String):
        self._part = v

    @always_inline
    def get_sqrrl__arc(self) -> ref [self._sqrrl__arc] sqrrl__Arc:
        return self._sqrrl__arc

    @always_inline
    def get_part(self) -> ref [self._part] String:
        return self._part


struct sqrrl__SourceArcPart(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl___JsonSerializable):
    var _inner: ArcPointer[sqrrl__SourceArcPartInner]

    def __init__(out self, var inner: sqrrl__SourceArcPartInner):
        self._inner = ArcPointer(inner^)

    def __init__(out self, var inner: ArcPointer[sqrrl__SourceArcPartInner]):
        self._inner = inner^

    def id(self) -> UInt32:
        return self._inner[]._id

    def ref_count(self) -> Int:
        return Int(self._inner.count())

    def __hash__[H: Hasher](self, mut hasher: H):
        hasher.update(self.id())

    def __eq__(self, other: Self) -> Bool:
        return self.id() == other.id()

    def __ne__(self, other: Self) -> Bool:
        return self.id() != other.id()

    def sqrrl__to_json(self) -> String:
        return String(self.id())


struct sqrrl__SourceArcPartIndexes(Movable, ImplicitlyDeletable):
    def __init__(out self):
        pass


struct sqrrl__SourceArcPartTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__SourceArcPartIndexes, sqrrl__SourceArcPartInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__SourceArcPartIndexes, sqrrl__SourceArcPartInner](sqrrl__SourceArcPartIndexes()))

    def create(mut self, *, sqrrl__arc: sqrrl__Arc, part: String) -> sqrrl__SourceArcPart:
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__SourceArcPartInner(_id=id, _table=self.storage, _sqrrl__arc=sqrrl__arc, _part=part))
        self.storage[].register_weak(id, inner)
        return sqrrl__SourceArcPart(inner^)

    def all(self) -> Set[sqrrl__SourceArcPart]:
        var out = Set[sqrrl__SourceArcPart]()
        for id in self.storage[].all():
            out.add(sqrrl__SourceArcPart(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

@fieldwise_init
struct sqrrl__IssueInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__IssueIndexes, sqrrl__IssueInner]]
    var _title: Optional[String]
    var _sqrrl__source: Variant[sqrrl__SourceArcPart, sqrrl__Series]
    var _no: Int

    def __del__(deinit self):
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_title(mut self, var v: Optional[String]):
        self._title = v^

    def set_sqrrl__source(mut self, var v: Variant[sqrrl__SourceArcPart, sqrrl__Series]):
        self._sqrrl__source = v^

    def set_no(mut self, v: Int):
        self._no = v

    @always_inline
    def get_title(self) -> ref [self._title] Optional[String]:
        return self._title

    @always_inline
    def get_sqrrl__source(self) -> ref [self._sqrrl__source] Variant[sqrrl__SourceArcPart, sqrrl__Series]:
        return self._sqrrl__source

    @always_inline
    def get_no(self) -> ref [self._no] Int:
        return self._no


struct sqrrl__Issue(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl___JsonSerializable):
    var _inner: ArcPointer[sqrrl__IssueInner]

    def __init__(out self, var inner: sqrrl__IssueInner):
        self._inner = ArcPointer(inner^)

    def __init__(out self, var inner: ArcPointer[sqrrl__IssueInner]):
        self._inner = inner^

    def id(self) -> UInt32:
        return self._inner[]._id

    def ref_count(self) -> Int:
        return Int(self._inner.count())

    def __hash__[H: Hasher](self, mut hasher: H):
        hasher.update(self.id())

    def __eq__(self, other: Self) -> Bool:
        return self.id() == other.id()

    def __ne__(self, other: Self) -> Bool:
        return self.id() != other.id()

    def sqrrl__to_json(self) -> String:
        return String(self.id())

    def dont_keepalive(mut self) -> Bool:
        return self._inner[]._table[].keepalive_remove(self.id())


struct sqrrl__IssueIndexes(Movable, ImplicitlyDeletable):
    def __init__(out self):
        pass


struct sqrrl__IssueTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__IssueIndexes, sqrrl__IssueInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__IssueIndexes, sqrrl__IssueInner](sqrrl__IssueIndexes()))

    def create(mut self, *, var title: Optional[String], var sqrrl__source: Variant[sqrrl__SourceArcPart, sqrrl__Series], no: Int) -> sqrrl__Issue:
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__IssueInner(_id=id, _table=self.storage, _title=title^, _sqrrl__source=sqrrl__source^, _no=no))
        self.storage[].register_weak(id, inner)
        self.storage[].keepalive_add(id, inner.copy())
        return sqrrl__Issue(inner^)

    def all(self) -> Set[sqrrl__Issue]:
        var out = Set[sqrrl__Issue]()
        for id in self.storage[].all():
            out.add(sqrrl__Issue(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

@fieldwise_init
struct sqrrl__VolumeInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__VolumeIndexes, sqrrl__VolumeInner]]
    var _sqrrl__source: Variant[sqrrl__Arc, sqrrl__VolumeSeries]
    var _sqrrl__issues: Set[sqrrl__Issue]
    var _no: Int

    def __del__(deinit self):
        self._table[].indexes.issues.remove_many(self._id, self._sqrrl__issues)
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_sqrrl__source(mut self, var v: Variant[sqrrl__Arc, sqrrl__VolumeSeries]):
        self._sqrrl__source = v^

    def set_sqrrl__issues(mut self, var v: Set[sqrrl__Issue]):
        self._table[].indexes.issues.remove_many(self._id, self._sqrrl__issues)
        self._sqrrl__issues = v^
        self._table[].indexes.issues.add_many(self._id, self._sqrrl__issues)

    def add_to_sqrrl__issues(mut self, value: sqrrl__Issue) -> Bool:
        if value in self._sqrrl__issues:
            return False
        self._sqrrl__issues.add(value)
        self._table[].indexes.issues.add(self._id, value)
        return True

    def remove_from_sqrrl__issues(mut self, value: sqrrl__Issue) -> Bool:
        try:
            self._sqrrl__issues.remove(value)
        except:
            return False
        self._table[].indexes.issues.remove(self._id, value)
        return True

    def set_no(mut self, v: Int):
        self._no = v

    @always_inline
    def get_sqrrl__source(self) -> ref [self._sqrrl__source] Variant[sqrrl__Arc, sqrrl__VolumeSeries]:
        return self._sqrrl__source

    @always_inline
    def get_sqrrl__issues(self) -> ref [self._sqrrl__issues] Set[sqrrl__Issue]:
        return self._sqrrl__issues

    @always_inline
    def get_no(self) -> ref [self._no] Int:
        return self._no


struct sqrrl__Volume(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl___JsonSerializable):
    var _inner: ArcPointer[sqrrl__VolumeInner]

    def __init__(out self, var inner: sqrrl__VolumeInner):
        self._inner = ArcPointer(inner^)

    def __init__(out self, var inner: ArcPointer[sqrrl__VolumeInner]):
        self._inner = inner^

    def id(self) -> UInt32:
        return self._inner[]._id

    def ref_count(self) -> Int:
        return Int(self._inner.count())

    def __hash__[H: Hasher](self, mut hasher: H):
        hasher.update(self.id())

    def __eq__(self, other: Self) -> Bool:
        return self.id() == other.id()

    def __ne__(self, other: Self) -> Bool:
        return self.id() != other.id()

    def sqrrl__to_json(self) -> String:
        return String(self.id())

    def dont_keepalive(mut self) -> Bool:
        return self._inner[]._table[].keepalive_remove(self.id())


struct sqrrl__VolumeIndexes(Movable, ImplicitlyDeletable):
    var issues: MultiIndex[sqrrl__Issue]

    def __init__(out self):
        self.issues = MultiIndex[sqrrl__Issue]()


struct sqrrl__VolumeTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__VolumeIndexes, sqrrl__VolumeInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__VolumeIndexes, sqrrl__VolumeInner](sqrrl__VolumeIndexes()))

    def create(mut self, *, var sqrrl__source: Variant[sqrrl__Arc, sqrrl__VolumeSeries], var sqrrl__issues: Set[sqrrl__Issue] = Set[sqrrl__Issue](), no: Int) -> sqrrl__Volume:
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__VolumeInner(_id=id, _table=self.storage, _sqrrl__source=sqrrl__source^, _sqrrl__issues=sqrrl__issues^, _no=no))
        self.storage[].register_weak(id, inner)
        self.storage[].indexes.issues.add_many(id, inner[]._sqrrl__issues)
        self.storage[].keepalive_add(id, inner.copy())
        return sqrrl__Volume(inner^)

    def all(self) -> Set[sqrrl__Volume]:
        var out = Set[sqrrl__Volume]()
        for id in self.storage[].all():
            out.add(sqrrl__Volume(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

    def for_sqrrl__issues(self, value: sqrrl__Issue) -> Set[sqrrl__Volume]:
        var out = Set[sqrrl__Volume]()
        for id in self.storage[].indexes.issues.get_bwd(value):
            out.add(sqrrl__Volume(self.storage[].handle_for(id)))
        return out^

    def count_for_sqrrl__issues(self, value: sqrrl__Issue) -> Int:
        return len(self.storage[].indexes.issues.get_bwd(value))

    def group_by_sqrrl__issues(self) -> Dict[sqrrl__Issue, Set[sqrrl__Volume]]:
        ref buckets = self.storage[].indexes.issues.all_bwd()
        var out = Dict[sqrrl__Issue, Set[sqrrl__Volume]]()
        for entry in buckets.items():
            var handles = Set[sqrrl__Volume]()
            for id in entry.value:
                handles.add(sqrrl__Volume(self.storage[].handle_for(id)))
            out[entry.key] = handles^
        return out^

    def count_by_sqrrl__issues(self) -> Dict[sqrrl__Issue, Int]:
        ref buckets = self.storage[].indexes.issues.all_bwd()
        var out = Dict[sqrrl__Issue, Int]()
        for entry in buckets.items():
            out[entry.key] = len(entry.value)
        return out^

    def distinct_sqrrl__issues(self) -> Set[sqrrl__Issue]:
        var out = Set[sqrrl__Issue]()
        ref buckets = self.storage[].indexes.issues.all_bwd()
        for key in buckets.keys():
            out.add(key.copy())
        return out^

# Ownership as its own entity, not a flag on @@Issue/@@Volume directly --
# existence of a matching row *is* "owned"; there's no explicit "not
# owned" state to maintain. `unique item` enforces at most one @@Owned row
# per Issue/Volume (can't double-own the same item), and its own
# Variant[@@Volume, @@Issue] lets one table cover both ownable kinds.
# `keepalive` because nothing else ever holds a forward reference *to* an
# @@Owned row (it only ever points *at* an Issue/Volume, never the other
# way) -- unlike @@Series/@@Publisher/@@Arc, which stay alive transitively
# through @@Issue's own forward fields, an @@Owned row's only chance of
# surviving past its own local variable's last use is this tag.
@fieldwise_init
struct sqrrl__OwnedInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__OwnedIndexes, sqrrl__OwnedInner]]
    var _sqrrl__item: Variant[sqrrl__Volume, sqrrl__Issue]

    def __del__(deinit self):
        self._table[].indexes.item.remove(self._id, self._sqrrl__item)
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_sqrrl__item(mut self, v: Variant[sqrrl__Volume, sqrrl__Issue]) raises:
        self._table[].indexes.item.check_unique(v, self._id)
        self._table[].indexes.item.remove(self._id, self._sqrrl__item)
        self._sqrrl__item = v
        self._table[].indexes.item.add(self._id, self._sqrrl__item)

    @always_inline
    def get_sqrrl__item(self) -> ref [self._sqrrl__item] Variant[sqrrl__Volume, sqrrl__Issue]:
        return self._sqrrl__item


struct sqrrl__Owned(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl___JsonSerializable):
    var _inner: ArcPointer[sqrrl__OwnedInner]

    def __init__(out self, var inner: sqrrl__OwnedInner):
        self._inner = ArcPointer(inner^)

    def __init__(out self, var inner: ArcPointer[sqrrl__OwnedInner]):
        self._inner = inner^

    def id(self) -> UInt32:
        return self._inner[]._id

    def ref_count(self) -> Int:
        return Int(self._inner.count())

    def __hash__[H: Hasher](self, mut hasher: H):
        hasher.update(self.id())

    def __eq__(self, other: Self) -> Bool:
        return self.id() == other.id()

    def __ne__(self, other: Self) -> Bool:
        return self.id() != other.id()

    def sqrrl__to_json(self) -> String:
        return String(self.id())

    def dont_keepalive(mut self) -> Bool:
        return self._inner[]._table[].keepalive_remove(self.id())


struct sqrrl__OwnedIndexes(Movable, ImplicitlyDeletable):
    var item: UniqueIndex[Variant[sqrrl__Volume, sqrrl__Issue]]

    def __init__(out self):
        self.item = UniqueIndex[Variant[sqrrl__Volume, sqrrl__Issue]]()


struct sqrrl__OwnedTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__OwnedIndexes, sqrrl__OwnedInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__OwnedIndexes, sqrrl__OwnedInner](sqrrl__OwnedIndexes()))

    def create(mut self, *, var sqrrl__item: Variant[sqrrl__Volume, sqrrl__Issue]) raises -> sqrrl__Owned:
        if self.storage[].indexes.item.contains(sqrrl__item):
            raise Error("UniqueConstraintViolation: 'item' already in use by another entity")
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__OwnedInner(_id=id, _table=self.storage, _sqrrl__item=sqrrl__item^))
        self.storage[].register_weak(id, inner)
        self.storage[].indexes.item.add(id, inner[]._sqrrl__item)
        self.storage[].keepalive_add(id, inner.copy())
        return sqrrl__Owned(inner^)

    def all(self) -> Set[sqrrl__Owned]:
        var out = Set[sqrrl__Owned]()
        for id in self.storage[].all():
            out.add(sqrrl__Owned(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

    def for_sqrrl__item(self, value: Variant[sqrrl__Volume, sqrrl__Issue]) raises -> sqrrl__Owned:
        var id = self.storage[].indexes.item.get_bwd(value)
        return sqrrl__Owned(self.storage[].handle_for(id))

    def count_for_sqrrl__item(self, value: Variant[sqrrl__Volume, sqrrl__Issue]) -> Int:
        return 1 if self.storage[].indexes.item.contains(value) else 0

    def group_by_sqrrl__item(self) -> Dict[Variant[sqrrl__Volume, sqrrl__Issue], sqrrl__Owned]:
        ref ids = self.storage[].indexes.item.all_bwd()
        var out = Dict[Variant[sqrrl__Volume, sqrrl__Issue], sqrrl__Owned]()
        for entry in ids.items():
            out[entry.key] = sqrrl__Owned(self.storage[].handle_for(entry.value))
        return out^

    def distinct_sqrrl__item(self) -> Set[Variant[sqrrl__Volume, sqrrl__Issue]]:
        var out = Set[Variant[sqrrl__Volume, sqrrl__Issue]]()
        ref ids = self.storage[].indexes.item.all_bwd()
        for key in ids.keys():
            out.add(key.copy())
        return out^

def main() raises:
    var sqrrl___world = sqrrl___init()
    try:
        var sqrrl__acme = sqrrl___world.Publisher.create(title = "Acme Press")

        var sqrrl__series = sqrrl___world.Series.create(title = "Foundation", start_year = 1951, sqrrl__publisher = sqrrl__acme)
        print("series describe (own method):", sqrrl__series.describe())

        # `< @@Series` copies title/start_year/@@publisher/key(title,
        # start_year)/describe() into VolumeSeries verbatim 
        var sqrrl__volume = sqrrl___world.VolumeSeries.create(title = "Foundation", start_year = 1951, sqrrl__publisher = sqrrl__acme)
        print("volume series describe (inherited method):", sqrrl__volume.describe())
        
        # Purely structural, not polymorphic -- separate tables, separate
        # id spaces, separate counts, even with identical title/start_year.
        print("series count:", sqrrl___world.Series.count())
        print("volume series count:", sqrrl___world.VolumeSeries.count())

        # The inherited key(title, start_year) group earns its own
        # composite lookup on VolumeSeries too.
        var sqrrl__found_volume = sqrrl___world.VolumeSeries.for_title_start_year("Foundation", 1951)
        print("found volume series via inherited composite lookup:", sqrrl__found_volume._inner[]._title)

        # create() raises on a genuine collision -- inherited from Series,
        # enforced independently of Series's own key(title, start_year).
        var volume_duplicate_raised = False
        try:
            _ = sqrrl___world.VolumeSeries.create(title = "Foundation", start_year = 1951, sqrrl__publisher = sqrrl__acme)
        except:
            volume_duplicate_raised = True
        print("volume series duplicate (title, start_year) correctly rejected:", volume_duplicate_raised)

        # A VolumeSeries with a different (title, start_year) doesn't
        # collide with Series's own row, or with the first VolumeSeries.
        var sqrrl__volume2 = sqrrl___world.VolumeSeries.create(title = "Second Foundation", start_year = 1953, sqrrl__publisher = sqrrl__acme)
        print("second volume series count:", sqrrl___world.VolumeSeries.count())

        var sqrrl__arc = sqrrl___world.Arc.create(title = "The Mule", sqrrl__series = sqrrl__series)
        print("arc's series:", sqrrl__arc._inner[]._sqrrl__series._inner[]._title)



        var sqrrl__issue = sqrrl___world.Issue.create(title = "Issue 1", sqrrl__source = Variant[sqrrl__SourceArcPart, sqrrl__Series](sqrrl___world.SourceArcPart.create(sqrrl__arc = sqrrl__arc, part = "The part")), no = 1)
        print("issue number:", sqrrl__issue._inner[]._no)
        var sqrrl__issue_owned = sqrrl___world.Owned.create(sqrrl__item = Variant[sqrrl__Volume, sqrrl__Issue](sqrrl__issue))
        print("issue owned:", sqrrl__issue_owned._inner[]._sqrrl__item.isa[sqrrl__Issue]())

        # A collection tracker needs wishlist items too -- catalogued, no
        # matching @@Owned row (yet).
        var sqrrl__issue2 = sqrrl___world.Issue.create(title = "Issue 2", sqrrl__source = Variant[sqrrl__SourceArcPart, sqrrl__Series](sqrrl___world.SourceArcPart.create(sqrrl__arc = sqrrl__arc, part = "The other part")), no = 2)
        print("issue 1 owned:", sqrrl___world.Owned.count_for_sqrrl__item(Variant[sqrrl__Volume, sqrrl__Issue](sqrrl__issue)) > 0)
        print("issue 2 owned:", sqrrl___world.Owned.count_for_sqrrl__item(Variant[sqrrl__Volume, sqrrl__Issue](sqrrl__issue2)) > 0)

        # @@Volume ties a single-book-or-series source (Variant[@@Arc,
        # @@VolumeSeries]) together with the issues collected under it
        # (multi @@issues) -- here sourced from the VolumeSeries created
        # above.
        var sqrrl__vol1 = sqrrl___world.Volume.create(sqrrl__source = Variant[sqrrl__Arc, sqrrl__VolumeSeries](sqrrl__volume), sqrrl__issues = Set(sqrrl__issue), no = 1)
        var sqrrl__volume_wishlist = sqrrl___world.Volume.create(sqrrl__source = Variant[sqrrl__Arc, sqrrl__VolumeSeries](sqrrl__volume), sqrrl__issues = Set(sqrrl__issue), no = 2)
        var sqrrl__vol1_owned = sqrrl___world.Owned.create(sqrrl__item = Variant[sqrrl__Volume, sqrrl__Issue](sqrrl__vol1))
        print("book volume issue count:", sqrrl___world.Volume.count_for_sqrrl__issues(sqrrl__issue))
        print("total owned items:", sqrrl___world.Owned.count())

        # Acquiring a wishlist volume -- creating its own @@Owned row, not
        # flipping a flag; there's nothing to "un-acquire" to, since not
        # owning something is just the absence of a row.
        var sqrrl__volume_wishlist_owned = sqrrl___world.Owned.create(sqrrl__item = Variant[sqrrl__Volume, sqrrl__Issue](sqrrl__volume_wishlist))
        print("total owned items after acquiring the wishlist copy:", sqrrl___world.Owned.count())

        var no = sqrrl__vol1_owned._inner[]._sqrrl__item.unsafe_get[sqrrl__Volume]()._inner[]._no
        print(
            "keep alive:",
            sqrrl__series._inner[]._title, sqrrl__volume._inner[]._title, sqrrl__volume2._inner[]._title,
            sqrrl__found_volume._inner[]._title, sqrrl__arc._inner[]._title, sqrrl__issue._inner[]._no, sqrrl__issue2._inner[]._no,
            sqrrl__issue_owned._inner[]._sqrrl__item.isa[sqrrl__Issue](), sqrrl__vol1_owned._inner[]._sqrrl__item.isa[sqrrl__Volume](),
            sqrrl__volume_wishlist_owned._inner[]._sqrrl__item.isa[sqrrl__Volume](),
            no
        )

        var s = sqrrl___world_to_json(sqrrl___world)

        sqrrl___init_from_json(sqrrl___world, s)

        print(s)
    finally:
        sqrrl___world.sqrrl__check_no_leaks()
