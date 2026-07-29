from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl___JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from std.utils import Variant

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

struct SourceArcPart:
    var sqrrl__arc: sqrrl__Arc
    var part: String

@fieldwise_init
struct sqrrl__IssueInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__IssueIndexes, sqrrl__IssueInner]]
    var _title: Optional[String]
    var _sqrrl__source: Variant[SourceArcPart, sqrrl__Series]
    var _no: Int

    def __del__(deinit self):
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_title(mut self, var v: Optional[String]):
        self._title = v^

    def set_sqrrl__source(mut self, var v: Variant[SourceArcPart, sqrrl__Series]):
        self._sqrrl__source = v^

    def set_no(mut self, v: Int):
        self._no = v

    @always_inline
    def get_title(self) -> ref [self._title] Optional[String]:
        return self._title

    @always_inline
    def get_sqrrl__source(self) -> ref [self._sqrrl__source] Variant[SourceArcPart, sqrrl__Series]:
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

    def create(mut self, *, var title: Optional[String], var sqrrl__source: Variant[SourceArcPart, sqrrl__Series], no: Int) -> sqrrl__Issue:
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
