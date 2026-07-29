from absolute_db_impl import sqrrl__PublisherTable
from absolute_db_impl import sqrrl__SeriesTable
from absolute_db_impl import sqrrl__VolumeSeriesTable
from absolute_db_impl import sqrrl__ArcTable
from absolute_db_impl import sqrrl__IssueTable
from absolute_db_impl import sqrrl__VolumeTable
from absolute_db_impl import sqrrl__OwnedTable
from std.os import abort


struct sqrrl___World(Movable):
    var Publisher: sqrrl__PublisherTable
    var Series: sqrrl__SeriesTable
    var VolumeSeries: sqrrl__VolumeSeriesTable
    var Arc: sqrrl__ArcTable
    var Issue: sqrrl__IssueTable
    var Volume: sqrrl__VolumeTable
    var Owned: sqrrl__OwnedTable

    def __init__(out self):
        self.Publisher = sqrrl__PublisherTable()
        self.Series = sqrrl__SeriesTable()
        self.VolumeSeries = sqrrl__VolumeSeriesTable()
        self.Arc = sqrrl__ArcTable()
        self.Issue = sqrrl__IssueTable()
        self.Volume = sqrrl__VolumeTable()
        self.Owned = sqrrl__OwnedTable()

    def sqrrl__check_no_leaks(mut self):
        _ = self.Issue.storage[].keepalive_clear()
        _ = self.Volume.storage[].keepalive_clear()
        _ = self.Owned.storage[].keepalive_clear()
        var leaked_Publisher = self.Publisher.count()
        if leaked_Publisher > 0:
            abort("LeakedEntities: 'Publisher' still has " + String(leaked_Publisher) + " live entities outside sqrrl___world -- something external still references them")
        var leaked_Series = self.Series.count()
        if leaked_Series > 0:
            abort("LeakedEntities: 'Series' still has " + String(leaked_Series) + " live entities outside sqrrl___world -- something external still references them")
        var leaked_VolumeSeries = self.VolumeSeries.count()
        if leaked_VolumeSeries > 0:
            abort("LeakedEntities: 'VolumeSeries' still has " + String(leaked_VolumeSeries) + " live entities outside sqrrl___world -- something external still references them")
        var leaked_Arc = self.Arc.count()
        if leaked_Arc > 0:
            abort("LeakedEntities: 'Arc' still has " + String(leaked_Arc) + " live entities outside sqrrl___world -- something external still references them")
        var leaked_Issue = self.Issue.count()
        if leaked_Issue > 0:
            abort("LeakedEntities: 'Issue' still has " + String(leaked_Issue) + " live entities outside sqrrl___world -- something external still references them")
        var leaked_Volume = self.Volume.count()
        if leaked_Volume > 0:
            abort("LeakedEntities: 'Volume' still has " + String(leaked_Volume) + " live entities outside sqrrl___world -- something external still references them")
        var leaked_Owned = self.Owned.count()
        if leaked_Owned > 0:
            abort("LeakedEntities: 'Owned' still has " + String(leaked_Owned) + " live entities outside sqrrl___world -- something external still references them")

    def __del__(deinit self):
        self.sqrrl__check_no_leaks()


def sqrrl___init() -> sqrrl___World:
    return sqrrl___World()
