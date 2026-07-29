from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl___init, sqrrl___World

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
