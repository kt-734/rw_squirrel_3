from std.testing import assert_equal, assert_true, assert_false, TestSuite

from squirrel_runtime.id_allocator import IdAllocator


def test_basic_alloc() raises:
    var ids = IdAllocator()
    assert_equal(ids.alloc(), UInt32(0))
    assert_equal(ids.alloc(), UInt32(1))
    assert_equal(ids.alloc(), UInt32(2))
    assert_true(ids.is_live(0))
    assert_true(ids.is_live(1))
    assert_true(ids.is_live(2))


def test_recycles_freed_ids() raises:
    var ids = IdAllocator()
    _ = ids.alloc()  # 0
    _ = ids.alloc()  # 1
    _ = ids.alloc()  # 2

    ids.free(1)
    assert_false(ids.is_live(1))

    var recycled = ids.alloc()
    assert_equal(recycled, UInt32(1))
    assert_true(ids.is_live(1))

    # 1 is taken again now; the next fresh id continues from next_id, not 0.
    assert_equal(ids.alloc(), UInt32(3))


def test_free_then_recycle() raises:
    var ids = IdAllocator()
    _ = ids.alloc()  # 0
    ids.free(0)
    assert_false(ids.is_live(0))
    assert_equal(ids.alloc(), UInt32(0))


def test_id_count_tracks_highest_id_ever_allocated() raises:
    var ids = IdAllocator()
    assert_equal(ids.id_count(), 0)
    _ = ids.alloc()  # 0
    _ = ids.alloc()  # 1
    assert_equal(ids.id_count(), 2)
    ids.free(0)
    assert_equal(ids.id_count(), 2)
    _ = ids.alloc()  # recycles 0
    assert_equal(ids.id_count(), 2)
    _ = ids.alloc()  # 2
    assert_equal(ids.id_count(), 3)


def test_alloc_specific_reserves_out_of_order() raises:
    var ids = IdAllocator()
    _ = ids.alloc()  # 0
    ids.alloc_specific(5)
    assert_true(ids.is_live(5))
    # ids 1..4 are now on the free list (LIFO -- alloc() pops the most
    # recently appended one first, so 4 comes back before 1..3 do).
    assert_equal(ids.alloc(), UInt32(4))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
