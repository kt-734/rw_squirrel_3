from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl___init, sqrrl___World


@fieldwise_init
struct sqrrl__PublisherInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__PublisherIndexes, sqrrl__PublisherInner]]
    var _name: String

    def __del__(deinit self):
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_name(mut self, v: String):
        self._name = v

    @always_inline
    def get_name(self) -> ref [self._name] String:
        return self._name


struct sqrrl__Publisher(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable):
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



struct sqrrl__PublisherIndexes(Movable, ImplicitlyDeletable):
    def __init__(out self):
        pass


struct sqrrl__PublisherTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__PublisherIndexes, sqrrl__PublisherInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__PublisherIndexes, sqrrl__PublisherInner](sqrrl__PublisherIndexes()))

    def create(mut self, *, name: String) -> sqrrl__Publisher:
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__PublisherInner(_id=id, _table=self.storage, _name=name))
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
    var _name: String
    var _start_year: Int
    var _sqrrl__publisher: sqrrl__Publisher

    def __del__(deinit self):
        self._table[].indexes._sqrrl__key0.remove(self._id, sqrrl__SeriesKey0(name=self._name, start_year=self._start_year))
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_sqrrl__publisher(mut self, v: sqrrl__Publisher):
        self._sqrrl__publisher = v

    @always_inline
    def get_name(self) -> ref [self._name] String:
        return self._name

    @always_inline
    def get_start_year(self) -> ref [self._start_year] Int:
        return self._start_year

    @always_inline
    def get_sqrrl__publisher(self) -> ref [self._sqrrl__publisher] sqrrl__Publisher:
        return self._sqrrl__publisher


struct sqrrl__Series(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable):
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



@fieldwise_init
struct sqrrl__SeriesKey0(Copyable, Movable, Hashable, Equatable):
    var name: String
    var start_year: Int

    def __eq__(self, other: Self) -> Bool:
        if self.name != other.name:
            return False
        if self.start_year != other.start_year:
            return False
        return True

    def __ne__(self, other: Self) -> Bool:
        return not (self == other)

    def __hash__[H: Hasher](self, mut hasher: H):
        hasher.update(self.name)
        hasher.update(self.start_year)


struct sqrrl__SeriesIndexes(Movable, ImplicitlyDeletable):
    var _sqrrl__key0: UniqueIndex[sqrrl__SeriesKey0]

    def __init__(out self):
        self._sqrrl__key0 = UniqueIndex[sqrrl__SeriesKey0]()


struct sqrrl__SeriesTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__SeriesIndexes, sqrrl__SeriesInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__SeriesIndexes, sqrrl__SeriesInner](sqrrl__SeriesIndexes()))

    def create(mut self, *, name: String, start_year: Int, sqrrl__publisher: sqrrl__Publisher) raises -> sqrrl__Series:
        var sqrrl___key0 = sqrrl__SeriesKey0(name=name, start_year=start_year)
        if self.storage[].indexes._sqrrl__key0.contains(sqrrl___key0):
            raise Error("UniqueConstraintViolation: key(name, start_year) already in use by another entity")
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__SeriesInner(_id=id, _table=self.storage, _name=name, _start_year=start_year, _sqrrl__publisher=sqrrl__publisher))
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

    def for_name_start_year(self, name: String, start_year: Int) raises -> sqrrl__Series:
        var id = self.storage[].indexes._sqrrl__key0.get_bwd(sqrrl__SeriesKey0(name=name, start_year=start_year))
        return sqrrl__Series(self.storage[].handle_for(id))

@fieldwise_init
struct sqrrl__BookingInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__BookingIndexes, sqrrl__BookingInner]]
    var _room: String
    var _date: String
    var _guest: String

    def __del__(deinit self):
        self._table[].indexes._sqrrl__key0.remove(self._id, sqrrl__BookingKey0(room=self._room, date=self._date))
        self._table[].indexes._sqrrl__key1.remove(self._id, sqrrl__BookingKey1(guest=self._guest, date=self._date))
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    @always_inline
    def get_room(self) -> ref [self._room] String:
        return self._room

    @always_inline
    def get_date(self) -> ref [self._date] String:
        return self._date

    @always_inline
    def get_guest(self) -> ref [self._guest] String:
        return self._guest


struct sqrrl__Booking(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable):
    var _inner: ArcPointer[sqrrl__BookingInner]

    def __init__(out self, var inner: sqrrl__BookingInner):
        self._inner = ArcPointer(inner^)

    def __init__(out self, var inner: ArcPointer[sqrrl__BookingInner]):
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



@fieldwise_init
struct sqrrl__BookingKey0(Copyable, Movable, Hashable, Equatable):
    var room: String
    var date: String

    def __eq__(self, other: Self) -> Bool:
        if self.room != other.room:
            return False
        if self.date != other.date:
            return False
        return True

    def __ne__(self, other: Self) -> Bool:
        return not (self == other)

    def __hash__[H: Hasher](self, mut hasher: H):
        hasher.update(self.room)
        hasher.update(self.date)


@fieldwise_init
struct sqrrl__BookingKey1(Copyable, Movable, Hashable, Equatable):
    var guest: String
    var date: String

    def __eq__(self, other: Self) -> Bool:
        if self.guest != other.guest:
            return False
        if self.date != other.date:
            return False
        return True

    def __ne__(self, other: Self) -> Bool:
        return not (self == other)

    def __hash__[H: Hasher](self, mut hasher: H):
        hasher.update(self.guest)
        hasher.update(self.date)


struct sqrrl__BookingIndexes(Movable, ImplicitlyDeletable):
    var _sqrrl__key0: UniqueIndex[sqrrl__BookingKey0]
    var _sqrrl__key1: UniqueIndex[sqrrl__BookingKey1]

    def __init__(out self):
        self._sqrrl__key0 = UniqueIndex[sqrrl__BookingKey0]()
        self._sqrrl__key1 = UniqueIndex[sqrrl__BookingKey1]()


struct sqrrl__BookingTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__BookingIndexes, sqrrl__BookingInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__BookingIndexes, sqrrl__BookingInner](sqrrl__BookingIndexes()))

    def create(mut self, *, room: String, date: String, guest: String) raises -> sqrrl__Booking:
        var sqrrl___key0 = sqrrl__BookingKey0(room=room, date=date)
        if self.storage[].indexes._sqrrl__key0.contains(sqrrl___key0):
            raise Error("UniqueConstraintViolation: key(room, date) already in use by another entity")
        var sqrrl___key1 = sqrrl__BookingKey1(guest=guest, date=date)
        if self.storage[].indexes._sqrrl__key1.contains(sqrrl___key1):
            raise Error("UniqueConstraintViolation: key(guest, date) already in use by another entity")
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__BookingInner(_id=id, _table=self.storage, _room=room, _date=date, _guest=guest))
        self.storage[].register_weak(id, inner)
        self.storage[].indexes._sqrrl__key0.add(id, sqrrl___key0)
        self.storage[].indexes._sqrrl__key1.add(id, sqrrl___key1)
        return sqrrl__Booking(inner^)

    def all(self) -> Set[sqrrl__Booking]:
        var out = Set[sqrrl__Booking]()
        for id in self.storage[].all():
            out.add(sqrrl__Booking(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

    def for_room_date(self, room: String, date: String) raises -> sqrrl__Booking:
        var id = self.storage[].indexes._sqrrl__key0.get_bwd(sqrrl__BookingKey0(room=room, date=date))
        return sqrrl__Booking(self.storage[].handle_for(id))

    def for_guest_date(self, guest: String, date: String) raises -> sqrrl__Booking:
        var id = self.storage[].indexes._sqrrl__key1.get_bwd(sqrrl__BookingKey1(guest=guest, date=date))
        return sqrrl__Booking(self.storage[].handle_for(id))

def main() raises:
    var sqrrl___world = sqrrl___init()
    try:
        var sqrrl__acme = sqrrl___world.Publisher.create(name = "Acme Press")
        var sqrrl__series1 = sqrrl___world.Series.create(name = "Foundation", start_year = 1951, sqrrl__publisher = sqrrl__acme)

        # key(...) raises on a genuine collision -- it does NOT get-or-
        # create the way a whole-entity `value` match does (a *subset*
        # match doesn't make the rest of the incoming row's data safely
        # discardable, since a real Series with a different publisher
        # could otherwise be silently dropped).
        var duplicate_raised = False
        try:
            _ = sqrrl___world.Series.create(name = "Foundation", start_year = 1951, sqrrl__publisher = sqrrl__acme)
        except:
            duplicate_raised = True
        print("duplicate (name, start_year) correctly rejected:", duplicate_raised)

        # A *partial* match -- same name, different start_year -- is a
        # different combination for this key group, so it's fine.
        var sqrrl__series2 = sqrrl___world.Series.create(name = "Foundation", start_year = 1985, sqrrl__publisher = sqrrl__acme)
        print("partial match allowed:", sqrrl__series1._inner[]._name, sqrrl__series1._inner[]._start_year, sqrrl__series2._inner[]._start_year)

        # The generated composite lookup -- mirrors a single `unique`
        # field's own for_<field>, just over the whole (name, start_year)
        # tuple at once.
        var sqrrl__found_series = sqrrl___world.Series.for_name_start_year("Foundation", 1951)
        print("found via composite lookup:", sqrrl__found_series._inner[]._name, sqrrl__found_series._inner[]._start_year)

        # `Booking` declares *two* independent key(...) groups sharing a
        # field (`date`) -- each is checked and maintained on its own.
        var sqrrl__booking1 = sqrrl___world.Booking.create(room = "101", date = "2026-08-01", guest = "Alice")

        var room_date_raised = False
        try:
            _ = sqrrl___world.Booking.create(room = "101", date = "2026-08-01", guest = "Bob")
        except:
            room_date_raised = True
        print("room+date collision rejected even with a different guest:", room_date_raised)

        var guest_date_raised = False
        try:
            _ = sqrrl___world.Booking.create(room = "202", date = "2026-08-01", guest = "Alice")
        except:
            guest_date_raised = True
        print("guest+date collision rejected even with a different room:", guest_date_raised)

        # Neither the room nor the guest nor the date alone collides with
        # booking1 -- both groups' constraints are satisfied, so this
        # succeeds.
        var sqrrl__booking2 = sqrrl___world.Booking.create(room = "202", date = "2026-08-02", guest = "Carol")

        var sqrrl__found_booking = sqrrl___world.Booking.for_room_date("101", "2026-08-01")
        print("found booking via room+date lookup:", sqrrl__found_booking._inner[]._guest)
        var sqrrl__found_by_guest = sqrrl___world.Booking.for_guest_date("Carol", "2026-08-02")
        print("found booking via guest+date lookup:", sqrrl__found_by_guest._inner[]._room)

        print(
            "keep alive:",
            sqrrl__series1._inner[]._name, sqrrl__series2._inner[]._name, sqrrl__booking1._inner[]._guest, sqrrl__booking2._inner[]._guest,
            sqrrl__found_series._inner[]._name, sqrrl__found_booking._inner[]._guest, sqrrl__found_by_guest._inner[]._room,
        )
    finally:
        sqrrl___world.sqrrl__check_no_leaks()
