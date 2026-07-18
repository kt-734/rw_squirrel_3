from std.memory import ArcPointer
from std.hashlib import Hasher

from squirrel_runtime.entity_storage import EntityStorage

# Test-only stand-ins for what squirrel_compiler/codegen/entity.mojo
# generates concretely per @@struct: a bare "no indexed fields" Inner/Indexes/
# Entity triple (Test*), plus a second pair (Employee*/Person*) where Person
# embeds a non-indexed relation field directly, to prove the cleanup-cascade
# claim in the plan's Architecture section works with no manual cleanup code
# at all.
#
# Lives in its own file, not test_entity.mojo itself, so
# TestSuite.discover_tests[__functions_in_module()] (scoped to the file being
# run) never sees these as test cases -- same reason rw_squirrel_2 kept its
# own equivalent helpers in a separate testing_support.mojo.


struct TestIndexes(Movable, ImplicitlyDeletable):
    def __init__(out self):
        pass


struct TestInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[TestIndexes, TestInner]]

    def __init__(out self, id: UInt32, var table: ArcPointer[EntityStorage[TestIndexes, TestInner]]):
        self._id = id
        self._table = table^

    def __del__(deinit self):
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)


struct TestEntity(ImplicitlyCopyable, ImplicitlyDeletable, Hashable, Equatable):
    var _inner: ArcPointer[TestInner]

    def __init__(out self, var inner: ArcPointer[TestInner]):
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


def test_create(mut storage: ArcPointer[EntityStorage[TestIndexes, TestInner]]) -> TestEntity:
    var id = storage[].alloc_id()
    var inner = ArcPointer(TestInner(id=id, table=storage))
    storage[].register_weak(id, inner)
    return TestEntity(inner^)


def test_all(storage: ArcPointer[EntityStorage[TestIndexes, TestInner]]) -> List[TestEntity]:
    var out = List[TestEntity]()
    for id in storage[].all():
        out.append(TestEntity(storage[].handle_for(id)))
    return out^


struct EmployeeIndexes(Movable, ImplicitlyDeletable):
    def __init__(out self):
        pass


struct EmployeeInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[EmployeeIndexes, EmployeeInner]]

    def __init__(out self, id: UInt32, var table: ArcPointer[EntityStorage[EmployeeIndexes, EmployeeInner]]):
        self._id = id
        self._table = table^

    def __del__(deinit self):
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)


struct EmployeeEntity(ImplicitlyCopyable, ImplicitlyDeletable, Hashable, Equatable):
    var _inner: ArcPointer[EmployeeInner]

    def __init__(out self, var inner: ArcPointer[EmployeeInner]):
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


def test_create_employee(
    mut storage: ArcPointer[EntityStorage[EmployeeIndexes, EmployeeInner]]
) -> EmployeeEntity:
    var id = storage[].alloc_id()
    var inner = ArcPointer(EmployeeInner(id=id, table=storage))
    storage[].register_weak(id, inner)
    return EmployeeEntity(inner^)


struct PersonIndexes(Movable, ImplicitlyDeletable):
    def __init__(out self):
        pass


struct PersonInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[PersonIndexes, PersonInner]]
    var _sqrrl__employee: EmployeeEntity  # non-indexed relation field, a real field

    def __init__(
        out self,
        id: UInt32,
        var table: ArcPointer[EntityStorage[PersonIndexes, PersonInner]],
        var employee: EmployeeEntity,
    ):
        self._id = id
        self._table = table^
        self._sqrrl__employee = employee^

    def __del__(deinit self):
        # No cleanup of _sqrrl__employee here at all -- that's the point of
        # the test that uses this. Mojo's own field-wise destructor cascade
        # drops it (decref'ing whatever EmployeeEntity it held) automatically.
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)


struct PersonEntity(ImplicitlyCopyable, ImplicitlyDeletable, Hashable, Equatable):
    var _inner: ArcPointer[PersonInner]

    def __init__(out self, var inner: ArcPointer[PersonInner]):
        self._inner = inner^

    def id(self) -> UInt32:
        return self._inner[]._id

    def __hash__[H: Hasher](self, mut hasher: H):
        hasher.update(self.id())

    def __eq__(self, other: Self) -> Bool:
        return self.id() == other.id()

    def __ne__(self, other: Self) -> Bool:
        return self.id() != other.id()


def test_create_person(
    mut storage: ArcPointer[EntityStorage[PersonIndexes, PersonInner]], employee: EmployeeEntity
) -> PersonEntity:
    var id = storage[].alloc_id()
    var inner = ArcPointer(PersonInner(id=id, table=storage, employee=employee))
    storage[].register_weak(id, inner)
    return PersonEntity(inner^)
