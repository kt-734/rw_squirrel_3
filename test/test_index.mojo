from std.testing import assert_equal, assert_true, assert_false, TestSuite
from std.collections import Set

from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex


def test_plain_index_add_and_get_bwd() raises:
    var idx = PlainIndex[String]()
    idx.add(0, "alice")
    idx.add(1, "bob")
    idx.add(2, "alice")  # shared value

    assert_equal(len(idx.get_bwd("alice")), 2)
    assert_equal(len(idx.get_bwd("bob")), 1)
    assert_equal(len(idx.get_bwd("carol")), 0)


def test_plain_index_remove_empties_bucket() raises:
    var idx = PlainIndex[String]()
    idx.add(0, "alice")
    idx.add(1, "alice")

    idx.remove(0, "alice")
    assert_equal(len(idx.get_bwd("alice")), 1)

    idx.remove(1, "alice")
    assert_equal(len(idx.get_bwd("alice")), 0)
    # The key itself is gone now too, not just emptied -- confirmed via
    # all_bwd() not containing it at all.
    assert_false("alice" in idx.all_bwd())


def test_plain_index_remove_is_a_no_op_for_untracked_value() raises:
    var idx = PlainIndex[String]()
    idx.add(0, "alice")
    idx.remove(0, "someone_else")  # value never added -- must not abort/raise
    assert_equal(len(idx.get_bwd("alice")), 1)


def test_plain_index_all_bwd_reflects_every_bucket() raises:
    var idx = PlainIndex[Int]()
    idx.add(0, 10)
    idx.add(1, 20)
    idx.add(2, 10)

    ref all = idx.all_bwd()
    assert_equal(len(all), 2)
    assert_equal(len(all[10]), 2)
    assert_equal(len(all[20]), 1)


def test_unique_index_add_and_get_bwd() raises:
    var idx = UniqueIndex[String]()
    idx.check_unique("alice@x.com", 0)
    idx.add(0, "alice@x.com")

    assert_equal(idx.get_bwd("alice@x.com"), UInt32(0))
    assert_true(idx.contains("alice@x.com"))
    assert_false(idx.contains("bob@x.com"))


def test_unique_index_check_unique_raises_for_different_id() raises:
    var idx = UniqueIndex[String]()
    idx.add(0, "alice@x.com")

    var raised = False
    try:
        idx.check_unique("alice@x.com", 1)
    except:
        raised = True
    assert_true(raised)
    # Nothing was mutated by the failed check.
    assert_equal(idx.get_bwd("alice@x.com"), UInt32(0))


def test_unique_index_check_unique_allows_same_id_same_value() raises:
    var idx = UniqueIndex[String]()
    idx.add(0, "alice@x.com")

    # Must not raise -- id 0 re-checking the value it already owns.
    idx.check_unique("alice@x.com", 0)


def test_unique_index_update_to_same_value_is_a_correct_no_op() raises:
    # Mirrors what a generated set_<field> does: check_unique -> remove(old)
    # -> add(new). When old == new, this must net out to the entry still
    # being present -- the exact ordering bug this struct's own doc comment
    # warns against getting backwards.
    var idx = UniqueIndex[String]()
    idx.add(0, "alice@x.com")

    idx.check_unique("alice@x.com", 0)  # same id, same value -- must not raise
    idx.remove(0, "alice@x.com")
    idx.add(0, "alice@x.com")

    assert_equal(idx.get_bwd("alice@x.com"), UInt32(0))


def test_unique_index_get_bwd_raises_for_unused_value() raises:
    var idx = UniqueIndex[String]()
    var raised = False
    try:
        _ = idx.get_bwd("nobody@x.com")
    except:
        raised = True
    assert_true(raised)


def test_multi_index_add_and_get_bwd() raises:
    # element-keyed: "project1" -> {dept0, dept1}, "project2" -> {dept0}
    var idx = MultiIndex[String]()
    idx.add(0, "project1")
    idx.add(1, "project1")
    idx.add(0, "project2")

    assert_equal(len(idx.get_bwd("project1")), 2)
    assert_equal(len(idx.get_bwd("project2")), 1)
    assert_equal(len(idx.get_bwd("project3")), 0)


def test_multi_index_remove_empties_bucket() raises:
    var idx = MultiIndex[String]()
    idx.add(0, "project1")
    idx.add(1, "project1")

    idx.remove(0, "project1")
    assert_equal(len(idx.get_bwd("project1")), 1)

    idx.remove(1, "project1")
    assert_equal(len(idx.get_bwd("project1")), 0)
    assert_false("project1" in idx.all_bwd())


def test_multi_index_remove_is_a_no_op_for_untracked_membership() raises:
    var idx = MultiIndex[String]()
    idx.add(0, "project1")
    idx.remove(0, "project2")  # never added -- must not abort/raise
    idx.remove(99, "project1")  # id never in this bucket -- must not abort/raise
    assert_equal(len(idx.get_bwd("project1")), 1)


def test_multi_index_all_bwd_reflects_every_bucket() raises:
    var idx = MultiIndex[Int]()
    idx.add(0, 10)
    idx.add(1, 20)
    idx.add(2, 10)

    ref all = idx.all_bwd()
    assert_equal(len(all), 2)
    assert_equal(len(all[10]), 2)
    assert_equal(len(all[20]), 1)


def test_multi_index_add_many_bulk_adds() raises:
    # create()'s use case: a brand-new id, no prior membership.
    var idx = MultiIndex[String]()
    var values = Set[String]()
    values.add("project1")
    values.add("project2")

    idx.add_many(0, values)
    assert_equal(len(idx.get_bwd("project1")), 1)
    assert_equal(len(idx.get_bwd("project2")), 1)

    # A second id sharing one of the same values.
    var more = Set[String]()
    more.add("project1")
    idx.add_many(1, more)
    assert_equal(len(idx.get_bwd("project1")), 2)


def test_multi_index_remove_many_bulk_removes() raises:
    var idx = MultiIndex[String]()
    var values = Set[String]()
    values.add("project1")
    values.add("project2")
    idx.add_many(0, values)
    idx.add(1, "project1")  # a second owner of project1, untouched below

    idx.remove_many(0, values)
    assert_equal(len(idx.get_bwd("project1")), 1)  # id 1 still there
    assert_equal(len(idx.get_bwd("project2")), 0)
    assert_false("project2" in idx.all_bwd())


def test_multi_index_remove_many_then_add_many_replaces_membership() raises:
    # set_<field>'s use case: an id already tracked under {project1,
    # project2}, wholesale-replaced with {project2, project3}.
    var idx = MultiIndex[String]()
    var old = Set[String]()
    old.add("project1")
    old.add("project2")
    idx.add_many(0, old)

    var new_values = Set[String]()
    new_values.add("project2")
    new_values.add("project3")
    idx.remove_many(0, old)
    idx.add_many(0, new_values)

    assert_equal(len(idx.get_bwd("project1")), 0)
    assert_false("project1" in idx.all_bwd())
    assert_equal(len(idx.get_bwd("project2")), 1)
    assert_equal(len(idx.get_bwd("project3")), 1)


def test_ordered_index_add_and_get_bwd() raises:
    var idx = OrderedIndex[Int]()
    idx.add(0, 10)
    idx.add(1, 20)
    idx.add(2, 10)  # shared value

    assert_equal(len(idx.get_bwd(10)), 2)
    assert_equal(len(idx.get_bwd(20)), 1)
    assert_equal(len(idx.get_bwd(30)), 0)


def test_ordered_index_remove() raises:
    var idx = OrderedIndex[Int]()
    idx.add(0, 10)
    idx.add(1, 10)

    idx.remove(0, 10)
    assert_equal(len(idx.get_bwd(10)), 1)

    idx.remove(1, 10)
    assert_equal(len(idx.get_bwd(10)), 0)


def test_ordered_index_range_queries_are_ascending_and_correct() raises:
    var idx = OrderedIndex[Int]()
    # ids inserted out of value order, to prove the sort isn't just
    # insertion order.
    idx.add(0, 30)
    idx.add(1, 10)
    idx.add(2, 20)
    idx.add(3, 20)  # shares a value with id 2

    assert_equal(len(idx.greater_than(20)), 1)  # just id 0 (30)
    assert_equal(len(idx.at_least(20)), 3)  # ids 2, 3, 0
    assert_equal(len(idx.less_than(20)), 1)  # just id 1 (10)
    assert_equal(len(idx.at_most(20)), 3)  # ids 1, 2, 3
    assert_equal(len(idx.between(15, 25)), 2)  # ids 2, 3

    # Ascending order is preserved, not just correct membership.
    var asc = idx.at_least(10)
    assert_equal(len(asc), 4)
    assert_equal(asc[0], UInt32(1))  # value 10
    assert_equal(asc[3], UInt32(0))  # value 30


def test_ordered_index_between_empty_when_low_greater_than_high() raises:
    var idx = OrderedIndex[Int]()
    idx.add(0, 10)
    idx.add(1, 20)

    assert_equal(len(idx.between(25, 5)), 0)


def test_ordered_index_remove_finds_correct_id_within_equal_value_run() raises:
    # Two ids share a value -- removing one must not disturb the other, and
    # must find the *specific* id within the equal-value run, not just any
    # entry at that value.
    var idx = OrderedIndex[Int]()
    idx.add(0, 10)
    idx.add(1, 10)
    idx.add(2, 10)

    idx.remove(1, 10)
    var remaining = idx.get_bwd(10)
    assert_equal(len(remaining), 2)
    assert_true(0 in remaining)
    assert_true(2 in remaining)
    assert_false(1 in remaining)


def test_ordered_index_all_bwd_groups_ascending_by_value() raises:
    var idx = OrderedIndex[Int]()
    # inserted out of value order, to prove all_bwd's own key order isn't
    # just insertion order either.
    idx.add(0, 30)
    idx.add(1, 10)
    idx.add(2, 20)
    idx.add(3, 20)  # shares a value with id 2

    var buckets = idx.all_bwd()
    assert_equal(len(buckets), 3)
    assert_equal(len(buckets[10]), 1)
    assert_equal(len(buckets[20]), 2)
    assert_equal(len(buckets[30]), 1)
    assert_true(2 in buckets[20])
    assert_true(3 in buckets[20])

    # Dict iteration order matches insertion order -- all_bwd must insert
    # ascending for this to actually prove anything.
    var keys_in_order = List[Int]()
    for key in buckets.keys():
        keys_in_order.append(key)
    assert_equal(len(keys_in_order), 3)
    assert_equal(keys_in_order[0], 10)
    assert_equal(keys_in_order[1], 20)
    assert_equal(keys_in_order[2], 30)


def test_ordered_index_all_bwd_empty_when_no_entries() raises:
    var idx = OrderedIndex[Int]()
    assert_equal(len(idx.all_bwd()), 0)


def test_ordered_index_entries_reflects_ascending_sorted_order() raises:
    var idx = OrderedIndex[Int]()
    idx.add(0, 30)
    idx.add(1, 10)
    idx.add(2, 20)

    ref sorted = idx.entries()
    assert_equal(len(sorted), 3)
    assert_equal(sorted[0].value, 10)
    assert_equal(sorted[0].id, 1)
    assert_equal(sorted[1].value, 20)
    assert_equal(sorted[1].id, 2)
    assert_equal(sorted[2].value, 30)
    assert_equal(sorted[2].id, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
