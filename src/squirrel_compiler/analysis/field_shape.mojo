from squirrel_compiler.parser import Field, FieldModifier


def is_groupable(f: Field) -> Bool:
    """True if `f` has a backward index at all -- eligible as the grouping
    key (`x`) in `group_by_<field>`/`count_by_<field>`/`distinct_<field>`,
    and as the `x` in an aggregate's own `_by_<x>`/`_for_<x>` forms.
    Independent of `stats` entirely -- a `multi` field, for instance, is
    fully groupable even though it can never be the aggregated value
    itself (see `is_aggregatable`)."""
    return f.modifier != FieldModifier.NONE


def is_aggregatable(f: Field) -> Bool:
    """True if `f` is eligible to be the aggregated value (`y`) in
    `sum_<y>`/`avg_<y>`/`min_<y>`/`max_<y>`/`median_<y>` -- `stats`-tagged
    (any modifier), or `ordered` (min/max/median only, free of charge,
    since `ordered` already requires `Comparable`; `sum`/`avg` still need
    `stats` for the `+` it additionally promises).

    `multi` is excluded even when `stats`-tagged -- its storage is
    `Set[ElementType]`, and there's no sensible `+`-fold over set
    membership (a deliberate difference from rw_squirrel_2, which never
    exercised this combination). A `multi` field remains fully usable as
    the *grouping* key elsewhere (`is_groupable` doesn't check `is_stats`
    at all)."""
    if f.modifier == FieldModifier.MULTI:
        return False
    return f.is_stats or f.modifier == FieldModifier.ORDERED
