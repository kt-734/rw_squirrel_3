from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl__JsonSerializable, sqrrl__to_json
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl__init, sqrrl__World


@fieldwise_init
struct sqrrl__DepartmentInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__DepartmentIndexes, sqrrl__DepartmentInner]]
    var _name: String

    def __del__(deinit self):
        self._table[].indexes.name.remove(self._id, self._name)
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_name(mut self, v: String) raises:
        self._table[].indexes.name.check_unique(v, self._id)
        self._table[].indexes.name.remove(self._id, self._name)
        self._name = v

    @always_inline
    def get_name(self) -> ref [self._name] String:
        return self._name


struct sqrrl__Department(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl__JsonSerializable):
    var _inner: ArcPointer[sqrrl__DepartmentInner]

    def __init__(out self, var inner: sqrrl__DepartmentInner):
        self._inner = ArcPointer(inner^)

    def __init__(out self, var inner: ArcPointer[sqrrl__DepartmentInner]):
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

    def sqrrl__to_json(self) -> String:
        return String(self.id())


struct sqrrl__DepartmentIndexes(Movable, ImplicitlyDeletable):
    var name: UniqueIndex[String]

    def __init__(out self):
        self.name = UniqueIndex[String]()


struct sqrrl__DepartmentTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__DepartmentIndexes, sqrrl__DepartmentInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__DepartmentIndexes, sqrrl__DepartmentInner](sqrrl__DepartmentIndexes()))

    def create(mut self, name: String) raises -> sqrrl__Department:
        if self.storage[].indexes.name.contains(name):
            raise Error("UniqueConstraintViolation: 'name' already in use by another entity")
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__DepartmentInner(_id=id, _table=self.storage, _name=name))
        self.storage[].register_weak(id, inner)
        self.storage[].indexes.name.add(id, inner[]._name)
        return sqrrl__Department(inner^)

    def all(self) -> Set[sqrrl__Department]:
        var out = Set[sqrrl__Department]()
        for id in self.storage[].all():
            out.add(sqrrl__Department(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

    def for_name(self, value: String) raises -> sqrrl__Department:
        var id = self.storage[].indexes.name.get_bwd(value)
        return sqrrl__Department(self.storage[].handle_for(id))

    def count_name(self, value: String) -> Int:
        return 1 if self.storage[].indexes.name.contains(value) else 0

    def group_by_name(self) -> Dict[String, sqrrl__Department]:
        ref ids = self.storage[].indexes.name.all_bwd()
        var out = Dict[String, sqrrl__Department]()
        for entry in ids.items():
            out[entry.key] = sqrrl__Department(self.storage[].handle_for(entry.value))
        return out^

    def distinct_name(self) -> Set[String]:
        var out = Set[String]()
        ref ids = self.storage[].indexes.name.all_bwd()
        for key in ids.keys():
            out.add(key.copy())
        return out^

@fieldwise_init
struct sqrrl__EmployeeInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__EmployeeIndexes, sqrrl__EmployeeInner]]
    var _name: String
    var _years_employed: UInt32
    var _salary: Float64
    var _sqrrl__dept: sqrrl__Department

    def __del__(deinit self):
        self._table[].indexes.name.remove(self._id, self._name)
        self._table[].indexes.years_employed.remove(self._id, self._years_employed)
        self._table[].indexes.dept.remove(self._id, self._sqrrl__dept)
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_name(mut self, v: String) raises:
        self._table[].indexes.name.check_unique(v, self._id)
        self._table[].indexes.name.remove(self._id, self._name)
        self._name = v

    def set_years_employed(mut self, v: UInt32):
        self._table[].indexes.years_employed.remove(self._id, self._years_employed)
        self._years_employed = v
        self._table[].indexes.years_employed.add(self._id, self._years_employed)

    def set_salary(mut self, v: Float64):
        self._salary = v

    def set_sqrrl__dept(mut self, v: sqrrl__Department):
        self._table[].indexes.dept.remove(self._id, self._sqrrl__dept)
        self._sqrrl__dept = v
        self._table[].indexes.dept.add(self._id, self._sqrrl__dept)

    @always_inline
    def get_name(self) -> ref [self._name] String:
        return self._name

    @always_inline
    def get_years_employed(self) -> ref [self._years_employed] UInt32:
        return self._years_employed

    @always_inline
    def get_salary(self) -> ref [self._salary] Float64:
        return self._salary

    @always_inline
    def get_sqrrl__dept(self) -> ref [self._sqrrl__dept] sqrrl__Department:
        return self._sqrrl__dept


struct sqrrl__Employee(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, sqrrl__JsonSerializable):
    var _inner: ArcPointer[sqrrl__EmployeeInner]

    def __init__(out self, var inner: sqrrl__EmployeeInner):
        self._inner = ArcPointer(inner^)

    def __init__(out self, var inner: ArcPointer[sqrrl__EmployeeInner]):
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

    def sqrrl__to_json(self) -> String:
        return String(self.id())


struct sqrrl__EmployeeIndexes(Movable, ImplicitlyDeletable):
    var name: UniqueIndex[String]
    var years_employed: OrderedIndex[UInt32]
    var dept: PlainIndex[sqrrl__Department]

    def __init__(out self):
        self.name = UniqueIndex[String]()
        self.years_employed = OrderedIndex[UInt32]()
        self.dept = PlainIndex[sqrrl__Department]()


struct sqrrl__EmployeeTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__EmployeeIndexes, sqrrl__EmployeeInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__EmployeeIndexes, sqrrl__EmployeeInner](sqrrl__EmployeeIndexes()))

    def create(mut self, name: String, years_employed: UInt32, salary: Float64, sqrrl__dept: sqrrl__Department) raises -> sqrrl__Employee:
        if self.storage[].indexes.name.contains(name):
            raise Error("UniqueConstraintViolation: 'name' already in use by another entity")
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__EmployeeInner(_id=id, _table=self.storage, _name=name, _years_employed=years_employed, _salary=salary, _sqrrl__dept=sqrrl__dept))
        self.storage[].register_weak(id, inner)
        self.storage[].indexes.name.add(id, inner[]._name)
        self.storage[].indexes.years_employed.add(id, inner[]._years_employed)
        self.storage[].indexes.dept.add(id, inner[]._sqrrl__dept)
        return sqrrl__Employee(inner^)

    def all(self) -> Set[sqrrl__Employee]:
        var out = Set[sqrrl__Employee]()
        for id in self.storage[].all():
            out.add(sqrrl__Employee(self.storage[].handle_for(id)))
        return out^

    def count(self) -> Int:
        return self.storage[].live_count()

    def for_name(self, value: String) raises -> sqrrl__Employee:
        var id = self.storage[].indexes.name.get_bwd(value)
        return sqrrl__Employee(self.storage[].handle_for(id))

    def for_years_employed(self, value: UInt32) -> Set[sqrrl__Employee]:
        var out = Set[sqrrl__Employee]()
        for id in self.storage[].indexes.years_employed.get_bwd(value):
            out.add(sqrrl__Employee(self.storage[].handle_for(id)))
        return out^

    def for_years_employed_greater_than(self, value: UInt32) -> List[sqrrl__Employee]:
        var out = List[sqrrl__Employee]()
        for id in self.storage[].indexes.years_employed.greater_than(value):
            out.append(sqrrl__Employee(self.storage[].handle_for(id)))
        return out^

    def for_years_employed_less_than(self, value: UInt32) -> List[sqrrl__Employee]:
        var out = List[sqrrl__Employee]()
        for id in self.storage[].indexes.years_employed.less_than(value):
            out.append(sqrrl__Employee(self.storage[].handle_for(id)))
        return out^

    def for_years_employed_at_least(self, value: UInt32) -> List[sqrrl__Employee]:
        var out = List[sqrrl__Employee]()
        for id in self.storage[].indexes.years_employed.at_least(value):
            out.append(sqrrl__Employee(self.storage[].handle_for(id)))
        return out^

    def for_years_employed_at_most(self, value: UInt32) -> List[sqrrl__Employee]:
        var out = List[sqrrl__Employee]()
        for id in self.storage[].indexes.years_employed.at_most(value):
            out.append(sqrrl__Employee(self.storage[].handle_for(id)))
        return out^

    def for_years_employed_between(self, low: UInt32, high: UInt32) -> List[sqrrl__Employee]:
        var out = List[sqrrl__Employee]()
        for id in self.storage[].indexes.years_employed.between(low, high):
            out.append(sqrrl__Employee(self.storage[].handle_for(id)))
        return out^

    def for_sqrrl__dept(self, value: sqrrl__Department) -> Set[sqrrl__Employee]:
        var out = Set[sqrrl__Employee]()
        for id in self.storage[].indexes.dept.get_bwd(value):
            out.add(sqrrl__Employee(self.storage[].handle_for(id)))
        return out^

    def count_name(self, value: String) -> Int:
        return 1 if self.storage[].indexes.name.contains(value) else 0

    def group_by_name(self) -> Dict[String, sqrrl__Employee]:
        ref ids = self.storage[].indexes.name.all_bwd()
        var out = Dict[String, sqrrl__Employee]()
        for entry in ids.items():
            out[entry.key] = sqrrl__Employee(self.storage[].handle_for(entry.value))
        return out^

    def distinct_name(self) -> Set[String]:
        var out = Set[String]()
        ref ids = self.storage[].indexes.name.all_bwd()
        for key in ids.keys():
            out.add(key.copy())
        return out^

    def count_years_employed(self, value: UInt32) -> Int:
        return len(self.storage[].indexes.years_employed.get_bwd(value))

    def group_by_years_employed(self) -> Dict[UInt32, Set[sqrrl__Employee]]:
        var buckets = self.storage[].indexes.years_employed.all_bwd()
        var out = Dict[UInt32, Set[sqrrl__Employee]]()
        for entry in buckets.items():
            var handles = Set[sqrrl__Employee]()
            for id in entry.value:
                handles.add(sqrrl__Employee(self.storage[].handle_for(id)))
            out[entry.key] = handles^
        return out^

    def count_by_years_employed(self) -> Dict[UInt32, Int]:
        var buckets = self.storage[].indexes.years_employed.all_bwd()
        var out = Dict[UInt32, Int]()
        for entry in buckets.items():
            out[entry.key] = len(entry.value)
        return out^

    def distinct_years_employed(self) -> List[UInt32]:
        var out = List[UInt32]()
        var buckets = self.storage[].indexes.years_employed.all_bwd()
        for key in buckets.keys():
            out.append(key.copy())
        return out^

    def count_sqrrl__dept(self, value: sqrrl__Department) -> Int:
        return len(self.storage[].indexes.dept.get_bwd(value))

    def group_by_sqrrl__dept(self) -> Dict[sqrrl__Department, Set[sqrrl__Employee]]:
        ref buckets = self.storage[].indexes.dept.all_bwd()
        var out = Dict[sqrrl__Department, Set[sqrrl__Employee]]()
        for entry in buckets.items():
            var handles = Set[sqrrl__Employee]()
            for id in entry.value:
                handles.add(sqrrl__Employee(self.storage[].handle_for(id)))
            out[entry.key] = handles^
        return out^

    def count_by_sqrrl__dept(self) -> Dict[sqrrl__Department, Int]:
        ref buckets = self.storage[].indexes.dept.all_bwd()
        var out = Dict[sqrrl__Department, Int]()
        for entry in buckets.items():
            out[entry.key] = len(entry.value)
        return out^

    def distinct_sqrrl__dept(self) -> Set[sqrrl__Department]:
        var out = Set[sqrrl__Department]()
        ref buckets = self.storage[].indexes.dept.all_bwd()
        for key in buckets.keys():
            out.add(key.copy())
        return out^

    def min_years_employed(self) raises -> UInt32:
        var sqrrl__ids = self.storage[].all()
        if len(sqrrl__ids) == 0:
            raise Error("min_years_employed: table has no entities")
        var sqrrl__acc: Optional[UInt32] = None
        for sqrrl__id in sqrrl__ids:
            var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._years_employed
            if not sqrrl__acc or sqrrl__v < sqrrl__acc.value():
                sqrrl__acc = sqrrl__v
        return sqrrl__acc.value()

    def min_years_employed_by_name(self) -> Dict[String, UInt32]:
        ref sqrrl__ids = self.storage[].indexes.name.all_bwd()
        var out = Dict[String, UInt32]()
        for entry in sqrrl__ids.items():
            var sqrrl__v = self.storage[].handle_for(entry.value)[]._years_employed
            out[entry.key] = sqrrl__v
        return out^

    def min_years_employed_for_name(self, value: String) raises -> UInt32:
        var sqrrl__id = self.storage[].indexes.name.get_bwd(value)
        var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._years_employed
        return sqrrl__v

    def min_years_employed_by_sqrrl__dept(self) -> Dict[sqrrl__Department, UInt32]:
        ref sqrrl__buckets = self.storage[].indexes.dept.all_bwd()
        var out = Dict[sqrrl__Department, UInt32]()
        for entry in sqrrl__buckets.items():
            var sqrrl__acc: Optional[UInt32] = None
            for sqrrl__id in entry.value:
                var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._years_employed
                if not sqrrl__acc or sqrrl__v < sqrrl__acc.value():
                    sqrrl__acc = sqrrl__v
            out[entry.key] = sqrrl__acc.value()
        return out^

    def min_years_employed_for_sqrrl__dept(self, value: sqrrl__Department) raises -> UInt32:
        var sqrrl__bucket = self.storage[].indexes.dept.get_bwd(value)
        if len(sqrrl__bucket) == 0:
            raise Error("min_years_employed_for_sqrrl__dept: no entities found for this value")
        var sqrrl__acc: Optional[UInt32] = None
        for sqrrl__id in sqrrl__bucket:
            var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._years_employed
            if not sqrrl__acc or sqrrl__v < sqrrl__acc.value():
                sqrrl__acc = sqrrl__v
        return sqrrl__acc.value()

    def max_years_employed(self) raises -> UInt32:
        var sqrrl__ids = self.storage[].all()
        if len(sqrrl__ids) == 0:
            raise Error("max_years_employed: table has no entities")
        var sqrrl__acc: Optional[UInt32] = None
        for sqrrl__id in sqrrl__ids:
            var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._years_employed
            if not sqrrl__acc or sqrrl__v > sqrrl__acc.value():
                sqrrl__acc = sqrrl__v
        return sqrrl__acc.value()

    def max_years_employed_by_name(self) -> Dict[String, UInt32]:
        ref sqrrl__ids = self.storage[].indexes.name.all_bwd()
        var out = Dict[String, UInt32]()
        for entry in sqrrl__ids.items():
            var sqrrl__v = self.storage[].handle_for(entry.value)[]._years_employed
            out[entry.key] = sqrrl__v
        return out^

    def max_years_employed_for_name(self, value: String) raises -> UInt32:
        var sqrrl__id = self.storage[].indexes.name.get_bwd(value)
        var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._years_employed
        return sqrrl__v

    def max_years_employed_by_sqrrl__dept(self) -> Dict[sqrrl__Department, UInt32]:
        ref sqrrl__buckets = self.storage[].indexes.dept.all_bwd()
        var out = Dict[sqrrl__Department, UInt32]()
        for entry in sqrrl__buckets.items():
            var sqrrl__acc: Optional[UInt32] = None
            for sqrrl__id in entry.value:
                var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._years_employed
                if not sqrrl__acc or sqrrl__v > sqrrl__acc.value():
                    sqrrl__acc = sqrrl__v
            out[entry.key] = sqrrl__acc.value()
        return out^

    def max_years_employed_for_sqrrl__dept(self, value: sqrrl__Department) raises -> UInt32:
        var sqrrl__bucket = self.storage[].indexes.dept.get_bwd(value)
        if len(sqrrl__bucket) == 0:
            raise Error("max_years_employed_for_sqrrl__dept: no entities found for this value")
        var sqrrl__acc: Optional[UInt32] = None
        for sqrrl__id in sqrrl__bucket:
            var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._years_employed
            if not sqrrl__acc or sqrrl__v > sqrrl__acc.value():
                sqrrl__acc = sqrrl__v
        return sqrrl__acc.value()

    def median_years_employed(self) raises -> UInt32:
        ref sqrrl__sorted = self.storage[].indexes.years_employed.entries()
        if len(sqrrl__sorted) == 0:
            raise Error("median_years_employed: table has no entities")
        return sqrrl__sorted[len(sqrrl__sorted) // 2].value

    def median_years_employed_by_name(self) -> Dict[String, UInt32]:
        ref sqrrl__ids = self.storage[].indexes.name.all_bwd()
        var out = Dict[String, UInt32]()
        for entry in sqrrl__ids.items():
            var sqrrl__v = self.storage[].handle_for(entry.value)[]._years_employed
            out[entry.key] = sqrrl__v
        return out^

    def median_years_employed_for_name(self, value: String) raises -> UInt32:
        var sqrrl__id = self.storage[].indexes.name.get_bwd(value)
        var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._years_employed
        return sqrrl__v

    def median_years_employed_by_sqrrl__dept(self) -> Dict[sqrrl__Department, UInt32]:
        var sqrrl__buckets = Dict[sqrrl__Department, List[UInt32]]()
        try:
            for sqrrl__entry in self.storage[].indexes.years_employed.entries():
                var sqrrl__key = self.storage[].handle_for(sqrrl__entry.id)[]._sqrrl__dept
                if sqrrl__key not in sqrrl__buckets:
                    sqrrl__buckets[sqrrl__key.copy()] = List[UInt32]()
                sqrrl__buckets[sqrrl__key].append(sqrrl__entry.value)
        except:
            abort("median_years_employed_by_sqrrl__dept: unreachable Dict operation failure")
        var out = Dict[sqrrl__Department, UInt32]()
        for entry in sqrrl__buckets.items():
            out[entry.key] = entry.value[len(entry.value) // 2]
        return out^

    def median_years_employed_for_sqrrl__dept(self, value: sqrrl__Department) raises -> UInt32:
        var sqrrl__bucket = self.storage[].indexes.dept.get_bwd(value)
        if len(sqrrl__bucket) == 0:
            raise Error("median_years_employed_for_sqrrl__dept: no entities found for this value")
        var sqrrl__values = List[UInt32]()
        for sqrrl__id in sqrrl__bucket:
            sqrrl__values.append(self.storage[].handle_for(sqrrl__id)[]._years_employed)
        sort(sqrrl__values)
        return sqrrl__values[len(sqrrl__values) // 2]

    def min_salary(self) raises -> Float64:
        var sqrrl__ids = self.storage[].all()
        if len(sqrrl__ids) == 0:
            raise Error("min_salary: table has no entities")
        var sqrrl__acc: Optional[Float64] = None
        for sqrrl__id in sqrrl__ids:
            var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
            if not sqrrl__acc or sqrrl__v < sqrrl__acc.value():
                sqrrl__acc = sqrrl__v
        return sqrrl__acc.value()

    def min_salary_by_name(self) -> Dict[String, Float64]:
        ref sqrrl__ids = self.storage[].indexes.name.all_bwd()
        var out = Dict[String, Float64]()
        for entry in sqrrl__ids.items():
            var sqrrl__v = self.storage[].handle_for(entry.value)[]._salary
            out[entry.key] = sqrrl__v
        return out^

    def min_salary_for_name(self, value: String) raises -> Float64:
        var sqrrl__id = self.storage[].indexes.name.get_bwd(value)
        var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
        return sqrrl__v

    def min_salary_by_years_employed(self) -> Dict[UInt32, Float64]:
        var sqrrl__buckets = self.storage[].indexes.years_employed.all_bwd()
        var out = Dict[UInt32, Float64]()
        for entry in sqrrl__buckets.items():
            var sqrrl__acc: Optional[Float64] = None
            for sqrrl__id in entry.value:
                var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
                if not sqrrl__acc or sqrrl__v < sqrrl__acc.value():
                    sqrrl__acc = sqrrl__v
            out[entry.key] = sqrrl__acc.value()
        return out^

    def min_salary_for_years_employed(self, value: UInt32) raises -> Float64:
        var sqrrl__bucket = self.storage[].indexes.years_employed.get_bwd(value)
        if len(sqrrl__bucket) == 0:
            raise Error("min_salary_for_years_employed: no entities found for this value")
        var sqrrl__acc: Optional[Float64] = None
        for sqrrl__id in sqrrl__bucket:
            var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
            if not sqrrl__acc or sqrrl__v < sqrrl__acc.value():
                sqrrl__acc = sqrrl__v
        return sqrrl__acc.value()

    def min_salary_by_sqrrl__dept(self) -> Dict[sqrrl__Department, Float64]:
        ref sqrrl__buckets = self.storage[].indexes.dept.all_bwd()
        var out = Dict[sqrrl__Department, Float64]()
        for entry in sqrrl__buckets.items():
            var sqrrl__acc: Optional[Float64] = None
            for sqrrl__id in entry.value:
                var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
                if not sqrrl__acc or sqrrl__v < sqrrl__acc.value():
                    sqrrl__acc = sqrrl__v
            out[entry.key] = sqrrl__acc.value()
        return out^

    def min_salary_for_sqrrl__dept(self, value: sqrrl__Department) raises -> Float64:
        var sqrrl__bucket = self.storage[].indexes.dept.get_bwd(value)
        if len(sqrrl__bucket) == 0:
            raise Error("min_salary_for_sqrrl__dept: no entities found for this value")
        var sqrrl__acc: Optional[Float64] = None
        for sqrrl__id in sqrrl__bucket:
            var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
            if not sqrrl__acc or sqrrl__v < sqrrl__acc.value():
                sqrrl__acc = sqrrl__v
        return sqrrl__acc.value()

    def max_salary(self) raises -> Float64:
        var sqrrl__ids = self.storage[].all()
        if len(sqrrl__ids) == 0:
            raise Error("max_salary: table has no entities")
        var sqrrl__acc: Optional[Float64] = None
        for sqrrl__id in sqrrl__ids:
            var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
            if not sqrrl__acc or sqrrl__v > sqrrl__acc.value():
                sqrrl__acc = sqrrl__v
        return sqrrl__acc.value()

    def max_salary_by_name(self) -> Dict[String, Float64]:
        ref sqrrl__ids = self.storage[].indexes.name.all_bwd()
        var out = Dict[String, Float64]()
        for entry in sqrrl__ids.items():
            var sqrrl__v = self.storage[].handle_for(entry.value)[]._salary
            out[entry.key] = sqrrl__v
        return out^

    def max_salary_for_name(self, value: String) raises -> Float64:
        var sqrrl__id = self.storage[].indexes.name.get_bwd(value)
        var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
        return sqrrl__v

    def max_salary_by_years_employed(self) -> Dict[UInt32, Float64]:
        var sqrrl__buckets = self.storage[].indexes.years_employed.all_bwd()
        var out = Dict[UInt32, Float64]()
        for entry in sqrrl__buckets.items():
            var sqrrl__acc: Optional[Float64] = None
            for sqrrl__id in entry.value:
                var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
                if not sqrrl__acc or sqrrl__v > sqrrl__acc.value():
                    sqrrl__acc = sqrrl__v
            out[entry.key] = sqrrl__acc.value()
        return out^

    def max_salary_for_years_employed(self, value: UInt32) raises -> Float64:
        var sqrrl__bucket = self.storage[].indexes.years_employed.get_bwd(value)
        if len(sqrrl__bucket) == 0:
            raise Error("max_salary_for_years_employed: no entities found for this value")
        var sqrrl__acc: Optional[Float64] = None
        for sqrrl__id in sqrrl__bucket:
            var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
            if not sqrrl__acc or sqrrl__v > sqrrl__acc.value():
                sqrrl__acc = sqrrl__v
        return sqrrl__acc.value()

    def max_salary_by_sqrrl__dept(self) -> Dict[sqrrl__Department, Float64]:
        ref sqrrl__buckets = self.storage[].indexes.dept.all_bwd()
        var out = Dict[sqrrl__Department, Float64]()
        for entry in sqrrl__buckets.items():
            var sqrrl__acc: Optional[Float64] = None
            for sqrrl__id in entry.value:
                var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
                if not sqrrl__acc or sqrrl__v > sqrrl__acc.value():
                    sqrrl__acc = sqrrl__v
            out[entry.key] = sqrrl__acc.value()
        return out^

    def max_salary_for_sqrrl__dept(self, value: sqrrl__Department) raises -> Float64:
        var sqrrl__bucket = self.storage[].indexes.dept.get_bwd(value)
        if len(sqrrl__bucket) == 0:
            raise Error("max_salary_for_sqrrl__dept: no entities found for this value")
        var sqrrl__acc: Optional[Float64] = None
        for sqrrl__id in sqrrl__bucket:
            var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
            if not sqrrl__acc or sqrrl__v > sqrrl__acc.value():
                sqrrl__acc = sqrrl__v
        return sqrrl__acc.value()

    def median_salary(self) raises -> Float64:
        var sqrrl__ids = self.storage[].all()
        if len(sqrrl__ids) == 0:
            raise Error("median_salary: table has no entities")
        var sqrrl__values = List[Float64]()
        for sqrrl__id in sqrrl__ids:
            sqrrl__values.append(self.storage[].handle_for(sqrrl__id)[]._salary)
        sort(sqrrl__values)
        return sqrrl__values[len(sqrrl__values) // 2]

    def median_salary_by_name(self) -> Dict[String, Float64]:
        ref sqrrl__ids = self.storage[].indexes.name.all_bwd()
        var out = Dict[String, Float64]()
        for entry in sqrrl__ids.items():
            var sqrrl__v = self.storage[].handle_for(entry.value)[]._salary
            out[entry.key] = sqrrl__v
        return out^

    def median_salary_for_name(self, value: String) raises -> Float64:
        var sqrrl__id = self.storage[].indexes.name.get_bwd(value)
        var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
        return sqrrl__v

    def median_salary_by_years_employed(self) -> Dict[UInt32, Float64]:
        var sqrrl__buckets = self.storage[].indexes.years_employed.all_bwd()
        var out = Dict[UInt32, Float64]()
        for entry in sqrrl__buckets.items():
            var sqrrl__values = List[Float64]()
            for sqrrl__id in entry.value:
                sqrrl__values.append(self.storage[].handle_for(sqrrl__id)[]._salary)
            sort(sqrrl__values)
            out[entry.key] = sqrrl__values[len(sqrrl__values) // 2]
        return out^

    def median_salary_for_years_employed(self, value: UInt32) raises -> Float64:
        var sqrrl__bucket = self.storage[].indexes.years_employed.get_bwd(value)
        if len(sqrrl__bucket) == 0:
            raise Error("median_salary_for_years_employed: no entities found for this value")
        var sqrrl__values = List[Float64]()
        for sqrrl__id in sqrrl__bucket:
            sqrrl__values.append(self.storage[].handle_for(sqrrl__id)[]._salary)
        sort(sqrrl__values)
        return sqrrl__values[len(sqrrl__values) // 2]

    def median_salary_by_sqrrl__dept(self) -> Dict[sqrrl__Department, Float64]:
        ref sqrrl__buckets = self.storage[].indexes.dept.all_bwd()
        var out = Dict[sqrrl__Department, Float64]()
        for entry in sqrrl__buckets.items():
            var sqrrl__values = List[Float64]()
            for sqrrl__id in entry.value:
                sqrrl__values.append(self.storage[].handle_for(sqrrl__id)[]._salary)
            sort(sqrrl__values)
            out[entry.key] = sqrrl__values[len(sqrrl__values) // 2]
        return out^

    def median_salary_for_sqrrl__dept(self, value: sqrrl__Department) raises -> Float64:
        var sqrrl__bucket = self.storage[].indexes.dept.get_bwd(value)
        if len(sqrrl__bucket) == 0:
            raise Error("median_salary_for_sqrrl__dept: no entities found for this value")
        var sqrrl__values = List[Float64]()
        for sqrrl__id in sqrrl__bucket:
            sqrrl__values.append(self.storage[].handle_for(sqrrl__id)[]._salary)
        sort(sqrrl__values)
        return sqrrl__values[len(sqrrl__values) // 2]

    def sum_salary(self) raises -> Float64:
        var sqrrl__ids = self.storage[].all()
        if len(sqrrl__ids) == 0:
            raise Error("sum_salary: table has no entities")
        var sqrrl__acc: Optional[Float64] = None
        for sqrrl__id in sqrrl__ids:
            var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
            if sqrrl__acc:
                sqrrl__acc = sqrrl__acc.value() + sqrrl__v
            else:
                sqrrl__acc = sqrrl__v
        return sqrrl__acc.value()

    def sum_salary_by_name(self) -> Dict[String, Float64]:
        ref sqrrl__ids = self.storage[].indexes.name.all_bwd()
        var out = Dict[String, Float64]()
        for entry in sqrrl__ids.items():
            var sqrrl__v = self.storage[].handle_for(entry.value)[]._salary
            out[entry.key] = sqrrl__v
        return out^

    def sum_salary_for_name(self, value: String) raises -> Float64:
        var sqrrl__id = self.storage[].indexes.name.get_bwd(value)
        var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
        return sqrrl__v

    def sum_salary_by_years_employed(self) -> Dict[UInt32, Float64]:
        var sqrrl__buckets = self.storage[].indexes.years_employed.all_bwd()
        var out = Dict[UInt32, Float64]()
        for entry in sqrrl__buckets.items():
            var sqrrl__acc: Optional[Float64] = None
            for sqrrl__id in entry.value:
                var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
                if sqrrl__acc:
                    sqrrl__acc = sqrrl__acc.value() + sqrrl__v
                else:
                    sqrrl__acc = sqrrl__v
            out[entry.key] = sqrrl__acc.value()
        return out^

    def sum_salary_for_years_employed(self, value: UInt32) raises -> Float64:
        var sqrrl__bucket = self.storage[].indexes.years_employed.get_bwd(value)
        if len(sqrrl__bucket) == 0:
            raise Error("sum_salary_for_years_employed: no entities found for this value")
        var sqrrl__acc: Optional[Float64] = None
        for sqrrl__id in sqrrl__bucket:
            var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
            if sqrrl__acc:
                sqrrl__acc = sqrrl__acc.value() + sqrrl__v
            else:
                sqrrl__acc = sqrrl__v
        return sqrrl__acc.value()

    def sum_salary_by_sqrrl__dept(self) -> Dict[sqrrl__Department, Float64]:
        ref sqrrl__buckets = self.storage[].indexes.dept.all_bwd()
        var out = Dict[sqrrl__Department, Float64]()
        for entry in sqrrl__buckets.items():
            var sqrrl__acc: Optional[Float64] = None
            for sqrrl__id in entry.value:
                var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
                if sqrrl__acc:
                    sqrrl__acc = sqrrl__acc.value() + sqrrl__v
                else:
                    sqrrl__acc = sqrrl__v
            out[entry.key] = sqrrl__acc.value()
        return out^

    def sum_salary_for_sqrrl__dept(self, value: sqrrl__Department) raises -> Float64:
        var sqrrl__bucket = self.storage[].indexes.dept.get_bwd(value)
        if len(sqrrl__bucket) == 0:
            raise Error("sum_salary_for_sqrrl__dept: no entities found for this value")
        var sqrrl__acc: Optional[Float64] = None
        for sqrrl__id in sqrrl__bucket:
            var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
            if sqrrl__acc:
                sqrrl__acc = sqrrl__acc.value() + sqrrl__v
            else:
                sqrrl__acc = sqrrl__v
        return sqrrl__acc.value()

    def avg_salary(self) raises -> Float64:
        var sqrrl__ids = self.storage[].all()
        if len(sqrrl__ids) == 0:
            raise Error("avg_salary: table has no entities")
        var sqrrl__acc: Optional[Float64] = None
        var sqrrl__count = 0
        for sqrrl__id in sqrrl__ids:
            var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
            sqrrl__count += 1
            if sqrrl__acc:
                sqrrl__acc = sqrrl__acc.value() + sqrrl__v
            else:
                sqrrl__acc = sqrrl__v
        return Float64(sqrrl__acc.value()) / Float64(sqrrl__count)

    def avg_salary_by_name(self) -> Dict[String, Float64]:
        ref sqrrl__ids = self.storage[].indexes.name.all_bwd()
        var out = Dict[String, Float64]()
        for entry in sqrrl__ids.items():
            var sqrrl__v = self.storage[].handle_for(entry.value)[]._salary
            out[entry.key] = Float64(sqrrl__v)
        return out^

    def avg_salary_for_name(self, value: String) raises -> Float64:
        var sqrrl__id = self.storage[].indexes.name.get_bwd(value)
        var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
        return Float64(sqrrl__v)

    def avg_salary_by_years_employed(self) -> Dict[UInt32, Float64]:
        var sqrrl__buckets = self.storage[].indexes.years_employed.all_bwd()
        var out = Dict[UInt32, Float64]()
        for entry in sqrrl__buckets.items():
            var sqrrl__acc: Optional[Float64] = None
            var sqrrl__count = 0
            for sqrrl__id in entry.value:
                var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
                sqrrl__count += 1
                if sqrrl__acc:
                    sqrrl__acc = sqrrl__acc.value() + sqrrl__v
                else:
                    sqrrl__acc = sqrrl__v
            out[entry.key] = Float64(sqrrl__acc.value()) / Float64(sqrrl__count)
        return out^

    def avg_salary_for_years_employed(self, value: UInt32) raises -> Float64:
        var sqrrl__bucket = self.storage[].indexes.years_employed.get_bwd(value)
        if len(sqrrl__bucket) == 0:
            raise Error("avg_salary_for_years_employed: no entities found for this value")
        var sqrrl__acc: Optional[Float64] = None
        var sqrrl__count = 0
        for sqrrl__id in sqrrl__bucket:
            var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
            sqrrl__count += 1
            if sqrrl__acc:
                sqrrl__acc = sqrrl__acc.value() + sqrrl__v
            else:
                sqrrl__acc = sqrrl__v
        return Float64(sqrrl__acc.value()) / Float64(sqrrl__count)

    def avg_salary_by_sqrrl__dept(self) -> Dict[sqrrl__Department, Float64]:
        ref sqrrl__buckets = self.storage[].indexes.dept.all_bwd()
        var out = Dict[sqrrl__Department, Float64]()
        for entry in sqrrl__buckets.items():
            var sqrrl__acc: Optional[Float64] = None
            var sqrrl__count = 0
            for sqrrl__id in entry.value:
                var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
                sqrrl__count += 1
                if sqrrl__acc:
                    sqrrl__acc = sqrrl__acc.value() + sqrrl__v
                else:
                    sqrrl__acc = sqrrl__v
            out[entry.key] = Float64(sqrrl__acc.value()) / Float64(sqrrl__count)
        return out^

    def avg_salary_for_sqrrl__dept(self, value: sqrrl__Department) raises -> Float64:
        var sqrrl__bucket = self.storage[].indexes.dept.get_bwd(value)
        if len(sqrrl__bucket) == 0:
            raise Error("avg_salary_for_sqrrl__dept: no entities found for this value")
        var sqrrl__acc: Optional[Float64] = None
        var sqrrl__count = 0
        for sqrrl__id in sqrrl__bucket:
            var sqrrl__v = self.storage[].handle_for(sqrrl__id)[]._salary
            sqrrl__count += 1
            if sqrrl__acc:
                sqrrl__acc = sqrrl__acc.value() + sqrrl__v
            else:
                sqrrl__acc = sqrrl__v
        return Float64(sqrrl__acc.value()) / Float64(sqrrl__count)

def main() raises:
    var sqrrl__world = sqrrl__init()
    try:
        var sqrrl__eng = sqrrl__world.Department.create(name = "Engineering")
        var sqrrl__sales = sqrrl__world.Department.create(name = "Sales")
        var sqrrl__alice = sqrrl__world.Employee.create(name = "Alice", years_employed = 5, salary = 90000.0, sqrrl__dept = sqrrl__eng)
        var sqrrl__bob = sqrrl__world.Employee.create(name = "Bob", years_employed = 2, salary = 70000.0, sqrrl__dept = sqrrl__eng)
        var sqrrl__carol = sqrrl__world.Employee.create(name = "Carol", years_employed = 8, salary = 120000.0, sqrrl__dept = sqrrl__sales)
        var sqrrl__dave = sqrrl__world.Employee.create(name = "Dave", years_employed = 5, salary = 85000.0, sqrrl__dept = sqrrl__sales)

        print("exact match (5 years):", len(sqrrl__world.Employee.for_years_employed(5)))
        print("more than 3 years:", len(sqrrl__world.Employee.for_years_employed_greater_than(3)))
        print("at least 5 years:", len(sqrrl__world.Employee.for_years_employed_at_least(5)))
        print("less than 5 years:", len(sqrrl__world.Employee.for_years_employed_less_than(5)))
        print("at most 5 years:", len(sqrrl__world.Employee.for_years_employed_at_most(5)))
        print("3 to 6 years inclusive:", len(sqrrl__world.Employee.for_years_employed_between(3, 6)))

        var sqrrl__ranged = sqrrl__world.Employee.for_years_employed_between(0, 100)
        for sqrrl__e in  sqrrl__ranged:
            print("in range:", sqrrl__e._inner[]._name, sqrrl__e._inner[]._years_employed)

        sqrrl__bob._inner[].set_years_employed(9);
        print("after raise, more than 8 years:", len(sqrrl__world.Employee.for_years_employed_greater_than(8)))

        print("total salary:", sqrrl__world.Employee.sum_salary())
        print("average salary:", sqrrl__world.Employee.avg_salary())
        print("min years employed:", sqrrl__world.Employee.min_years_employed())
        print("max years employed:", sqrrl__world.Employee.max_years_employed())
        print("median years employed:", sqrrl__world.Employee.median_years_employed())
        print("median salary:", sqrrl__world.Employee.median_salary())

        print("eng total salary:", sqrrl__world.Employee.sum_salary_for_sqrrl__dept(sqrrl__eng))
        print("sales average salary:", sqrrl__world.Employee.avg_salary_for_sqrrl__dept(sqrrl__sales))

        var sqrrl__salary_by_dept = sqrrl__world.Employee.sum_salary_by_sqrrl__dept()
        print("departments with salary totals:", len(sqrrl__salary_by_dept))

        print("distinct years employed:", len(sqrrl__world.Employee.distinct_years_employed()))
        print("count with 5 years:", sqrrl__world.Employee.count_years_employed(5))

        var sqrrl__by_dept = sqrrl__world.Employee.group_by_sqrrl__dept()
        print("departments with employees:", len(sqrrl__by_dept))

        print("alice", sqrrl__alice._inner[]._name, "bob", sqrrl__bob._inner[]._name, "carol", sqrrl__carol._inner[]._name, "dave", sqrrl__dave._inner[]._name)
    finally:
        sqrrl__world.sqrrl__check_no_leaks()
