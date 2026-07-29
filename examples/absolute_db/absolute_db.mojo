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
from absolute_db_impl import SourceArcPart
from absolute_db_impl import sqrrl__Arc
from absolute_db_impl import sqrrl__Issue
from absolute_db_impl import sqrrl__Series
from absolute_db_impl import sqrrl__Volume
from absolute_db_impl import sqrrl__VolumeSeries

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
