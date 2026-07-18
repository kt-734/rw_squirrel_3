from std.os import abort
from std.collections import Set


@fieldwise_init
struct OrderedEntry[T: ImplicitlyDeletable & Copyable](Copyable, ImplicitlyDeletable):
    """One `(value, id)` pair in an `OrderedIndex`'s sorted list."""

    var value: Self.T
    var id: UInt32


struct OrderedIndex[T: KeyElement & Comparable & ImplicitlyDeletable & Copyable](Movable, ImplicitlyDeletable):
    """Backward index for an `ordered`-tagged field: a `List[OrderedEntry[T]]`
    kept sorted ascending by `value`, supporting range queries
    (`greater_than`/`less_than`/`at_least`/`at_most`/`between`) via a pair of
    binary searches plus a slice -- O(log n + k), not an O(n) scan.

    Unlike rw_squirrel_2's `OrderedRel[T]`, there is no `_fwd` half and no
    separate `List[UInt32]` needing a value looked up elsewhere during binary
    search -- the forward value lives as a real field on the generated
    `Inner` struct now (see `codegen/entity.mojo`), so each sorted entry
    carries its own value alongside its id directly (point made in the
    project plan's Architecture section: "arguably nicer than today's extra
    indirection, not just a workaround"). A generated `set_<field>` reads the
    old value directly off `Inner`'s own real field before calling `remove`,
    so there's nothing to fetch here either -- same `add`/`remove` method
    names and shape as `PlainIndex`, so the entity-side codegen that already
    calls `.remove(id, old)`/`.add(id, new)` needs no changes to support this
    index type.

    Bounded by `Comparable` in addition to `KeyElement`, same trust-the-
    modifier approach `unique`'s `Hashable` requirement already uses --
    the parser can't verify a field's type is actually ordered, Mojo's own
    compiler rejects it with a clear message if it's wrong."""

    var _sorted: List[OrderedEntry[Self.T]]

    def __init__(out self):
        self._sorted = List[OrderedEntry[Self.T]]()

    def add(mut self, id: UInt32, value: Self.T):
        # Borrowed, not owned -- every generated call site passes a field
        # read (`inner[]._name`), not something it can give up ownership of
        # (same reasoning as PlainIndex.add's own `value.copy()`).
        var insert_at = self._lower_bound(value)
        self._sorted.insert(insert_at, OrderedEntry[Self.T](value=value.copy(), id=id))

    def remove(mut self, id: UInt32, value: Self.T):
        """Removes `id` from the sorted list -- `value` is what it was
        stored under, needed to find the equal-value run to search within
        (ids sharing a value aren't otherwise ordered relative to each
        other)."""
        var start = self._lower_bound(value)
        var end = self._upper_bound(value)
        for i in range(start, end):
            if self._sorted[i].id == id:
                _ = self._sorted.pop(i)
                return
        abort("OrderedIndex.remove: id not found in its own value's range")

    def get_bwd(self, value: Self.T) -> Set[UInt32]:
        """All ids currently holding exactly `value` -- Set-returning, same
        convention `PlainIndex`/`MultiIndex` use for exact-match lookups
        (order doesn't matter for a single value's own bucket)."""
        var out = Set[UInt32]()
        for i in range(self._lower_bound(value), self._upper_bound(value)):
            out.add(self._sorted[i].id)
        return out^

    def greater_than(self, value: Self.T) -> List[UInt32]:
        """Every id whose value is strictly greater than `value`, ascending."""
        return self._slice(self._upper_bound(value), len(self._sorted))

    def at_least(self, value: Self.T) -> List[UInt32]:
        """Every id whose value is greater than or equal to `value`, ascending."""
        return self._slice(self._lower_bound(value), len(self._sorted))

    def less_than(self, value: Self.T) -> List[UInt32]:
        """Every id whose value is strictly less than `value`, ascending."""
        return self._slice(0, self._lower_bound(value))

    def at_most(self, value: Self.T) -> List[UInt32]:
        """Every id whose value is less than or equal to `value`, ascending."""
        return self._slice(0, self._upper_bound(value))

    def between(self, low: Self.T, high: Self.T) -> List[UInt32]:
        """Every id whose value is in `[low, high]` (inclusive both ends),
        ascending. Empty (not an error) if `low > high`."""
        var start = self._lower_bound(low)
        var end = self._upper_bound(high)
        if start >= end:
            return List[UInt32]()
        return self._slice(start, end)

    def entries(self) -> ref [self._sorted] List[OrderedEntry[Self.T]]:
        """Direct borrow of the ascending-sorted (value, id) list -- lets a
        whole-table or `_by_<x>` `median_<field>` (M4) read the middle
        value(s) directly off the already-sorted structure, with no fresh
        `List` collection or re-sort (the entire point of `ordered`), and no
        separate id -> value lookup for this field's own value since each
        entry already carries both together."""
        return self._sorted

    def all_bwd(self) -> Dict[Self.T, List[UInt32]]:
        """Every value currently in use, each mapped to every id holding it
        -- owned, not borrowed (unlike `PlainIndex`/`MultiIndex`/
        `UniqueIndex`'s own `all_bwd`, since there's no single `_bwd` dict
        here to borrow from at all): built fresh by walking the already-
        ascending `_sorted` list and grouping contiguous equal-value runs,
        so `Dict` key insertion order (and therefore Mojo's own insertion-
        ordered iteration) comes out ascending for free -- what
        `group_by_<field>`/`count_by_<field>`/`distinct_<field>` (M4) need
        for an `ordered` field's own ascending guarantee."""
        var out = Dict[Self.T, List[UInt32]]()
        var i = 0
        var n = len(self._sorted)
        while i < n:
            var v = self._sorted[i].value.copy()
            var bucket = List[UInt32]()
            while i < n and self._sorted[i].value == v:
                bucket.append(self._sorted[i].id)
                i += 1
            out[v.copy()] = bucket^
        return out^

    def _slice(self, start: Int, end: Int) -> List[UInt32]:
        var out = List[UInt32]()
        for i in range(start, end):
            out.append(self._sorted[i].id)
        return out^

    def _bound(self, value: Self.T, inclusive: Bool) -> Int:
        """Shared binary search behind `_lower_bound`/`_upper_bound` -- the
        two only ever differed by whether an equal value counts as "still
        before the boundary" (`inclusive=True`, for `_upper_bound`) or not
        (`inclusive=False`, for `_lower_bound`)."""
        var lo = 0
        var hi = len(self._sorted)
        while lo < hi:
            var mid = (lo + hi) // 2
            ref mid_value = self._sorted[mid].value
            var before_boundary = mid_value <= value if inclusive else mid_value < value
            if before_boundary:
                lo = mid + 1
            else:
                hi = mid
        return lo

    def _lower_bound(self, value: Self.T) -> Int:
        """First index whose value is >= `value` -- also the insertion point
        `add` uses. Note this places a newly-added id *before* any existing
        entries already holding the same value, not after -- ties aren't
        ordered by insertion time, only the overall ascending-by-value
        order across distinct values is guaranteed."""
        return self._bound(value, inclusive=False)

    def _upper_bound(self, value: Self.T) -> Int:
        """First index whose value is > `value`."""
        return self._bound(value, inclusive=True)
