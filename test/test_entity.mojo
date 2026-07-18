from std.testing import assert_equal, assert_true, assert_false, TestSuite
from std.memory import ArcPointer

from squirrel_runtime.entity_storage import EntityStorage
from testing_support import (
    TestIndexes,
    TestInner,
    TestEntity,
    test_create,
    test_all,
    EmployeeIndexes,
    EmployeeInner,
    test_create_employee,
    PersonIndexes,
    PersonInner,
    test_create_person,
)


def test_create_allocates_a_live_id() raises:
    var storage = ArcPointer(EntityStorage[TestIndexes, TestInner](TestIndexes()))
    var e = test_create(storage)
    assert_true(storage[].is_live(0))
    assert_equal(e.id(), UInt32(0))


def test_id_is_recycled_when_last_handle_drops() raises:
    var storage = ArcPointer(EntityStorage[TestIndexes, TestInner](TestIndexes()))
    var e = test_create(storage)
    assert_true(storage[].is_live(0))
    _ = e^
    assert_false(storage[].is_live(0))

    var e2 = test_create(storage)
    assert_equal(e2.id(), UInt32(0))


def test_copying_into_a_container_bumps_the_count_automatically() raises:
    var storage = ArcPointer(EntityStorage[TestIndexes, TestInner](TestIndexes()))
    var e = test_create(storage)

    var holders = List[TestEntity]()
    holders.append(e)
    holders.append(e)
    assert_equal(e.ref_count(), 3)  # e itself, plus the two copies in holders

    assert_true(storage[].is_live(0))
    holders.clear()
    assert_equal(e.ref_count(), 1)
    assert_true(storage[].is_live(0))

    _ = e^
    assert_false(storage[].is_live(0))


def test_all_returns_every_currently_live_entity() raises:
    var storage = ArcPointer(EntityStorage[TestIndexes, TestInner](TestIndexes()))
    var kept = List[TestEntity]()
    kept.append(test_create(storage))
    kept.append(test_create(storage))
    _ = test_create(storage)  # created and immediately dropped

    var live = test_all(storage)
    assert_equal(len(live), 2)
    for e in kept:
        assert_true(e in live)


def test_all_reflects_a_dropped_entity() raises:
    var storage = ArcPointer(EntityStorage[TestIndexes, TestInner](TestIndexes()))
    var e = test_create(storage)
    assert_equal(len(test_all(storage)), 1)
    _ = e^
    assert_equal(len(test_all(storage)), 0)


def test_handle_for_shares_the_same_row_not_a_second_owner() raises:
    var storage = ArcPointer(EntityStorage[TestIndexes, TestInner](TestIndexes()))
    var e = test_create(storage)
    var again = TestEntity(storage[].handle_for(0))
    assert_equal(e.ref_count(), 2)
    assert_true(e == again)


def test_destroying_an_entity_releases_its_embedded_relation_field_automatically() raises:
    # The claim this test guards: a non-indexed relation field, embedded as
    # a real struct field on the generated Inner (not addressed indirectly
    # through the owning table's own storage, the way rw_squirrel_2's Rel
    # fields were), needs NO manual cleanup code at all -- Mojo's own
    # field-wise destructor cascade releases it when the owning row dies.
    var employees = ArcPointer(EntityStorage[EmployeeIndexes, EmployeeInner](EmployeeIndexes()))
    var bob = test_create_employee(employees)
    assert_equal(bob.ref_count(), 1)

    var people = ArcPointer(EntityStorage[PersonIndexes, PersonInner](PersonIndexes()))
    var alice = test_create_person(people, bob)
    assert_equal(bob.ref_count(), 2)  # bob itself + alice's own copy in her field
    assert_true(people[].is_live(alice.id()))

    _ = alice^
    assert_false(people[].is_live(0))
    assert_equal(bob.ref_count(), 1)  # cascade cleanup already released her copy


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
