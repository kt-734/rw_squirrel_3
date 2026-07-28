from catalog import sqrrl__PublisherTable
from catalog import sqrrl__SeriesTable
from catalog import sqrrl__BookingTable
from std.os import abort


struct sqrrl___World(Movable):
    var Publisher: sqrrl__PublisherTable
    var Series: sqrrl__SeriesTable
    var Booking: sqrrl__BookingTable

    def __init__(out self):
        self.Publisher = sqrrl__PublisherTable()
        self.Series = sqrrl__SeriesTable()
        self.Booking = sqrrl__BookingTable()

    def sqrrl__check_no_leaks(mut self):
        var leaked_Publisher = self.Publisher.count()
        if leaked_Publisher > 0:
            abort("LeakedEntities: 'Publisher' still has " + String(leaked_Publisher) + " live entities outside sqrrl___world -- something external still references them")
        var leaked_Series = self.Series.count()
        if leaked_Series > 0:
            abort("LeakedEntities: 'Series' still has " + String(leaked_Series) + " live entities outside sqrrl___world -- something external still references them")
        var leaked_Booking = self.Booking.count()
        if leaked_Booking > 0:
            abort("LeakedEntities: 'Booking' still has " + String(leaked_Booking) + " live entities outside sqrrl___world -- something external still references them")

    def __del__(deinit self):
        self.sqrrl__check_no_leaks()


def sqrrl___init() -> sqrrl___World:
    return sqrrl___World()
