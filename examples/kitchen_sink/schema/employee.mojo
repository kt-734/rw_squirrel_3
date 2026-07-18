from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from squirrel_runtime.json import sqrrl__JsonSerializable
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from schema.profile import Profile
from schema.department import sqrrl__Department


@fieldwise_init
struct sqrrl__EmployeeInner(Movable, ImplicitlyDeletable):
    var _id: UInt32
    var _table: ArcPointer[EntityStorage[sqrrl__EmployeeIndexes, sqrrl__EmployeeInner]]
    var _email: String
    var _title: String
    var _years_employed: UInt32
    var _salary: Float64
    var _sqrrl__dept: sqrrl__Department
    var _profile: Profile

    def __del__(deinit self):
        self._table[].indexes.email.remove(self._id, self._email)
        self._table[].indexes.years_employed.remove(self._id, self._years_employed)
        self._table[].indexes.dept.remove(self._id, self._sqrrl__dept)
        self._table[].free_id(self._id)
        self._table[].clear_weak_ref(self._id)

    def set_email(mut self, v: String) raises:
        self._table[].indexes.email.check_unique(v, self._id)
        self._table[].indexes.email.remove(self._id, self._email)
        self._email = v

    def set_title(mut self, v: String):
        self._title = v

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

    def set_profile(mut self, var v: Profile):
        self._profile = v^

    @always_inline
    def get_email(self) -> ref [self._email] String:
        return self._email

    @always_inline
    def get_title(self) -> ref [self._title] String:
        return self._title

    @always_inline
    def get_years_employed(self) -> ref [self._years_employed] UInt32:
        return self._years_employed

    @always_inline
    def get_salary(self) -> ref [self._salary] Float64:
        return self._salary

    @always_inline
    def get_sqrrl__dept(self) -> ref [self._sqrrl__dept] sqrrl__Department:
        return self._sqrrl__dept

    @always_inline
    def get_profile(self) -> ref [self._profile] Profile:
        return self._profile


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
    var email: UniqueIndex[String]
    var years_employed: OrderedIndex[UInt32]
    var dept: PlainIndex[sqrrl__Department]

    def __init__(out self):
        self.email = UniqueIndex[String]()
        self.years_employed = OrderedIndex[UInt32]()
        self.dept = PlainIndex[sqrrl__Department]()


struct sqrrl__EmployeeTable(Movable):
    var storage: ArcPointer[EntityStorage[sqrrl__EmployeeIndexes, sqrrl__EmployeeInner]]

    def __init__(out self):
        self.storage = ArcPointer(EntityStorage[sqrrl__EmployeeIndexes, sqrrl__EmployeeInner](sqrrl__EmployeeIndexes()))

    def create(mut self, *, email: String, title: String, years_employed: UInt32, salary: Float64, sqrrl__dept: sqrrl__Department, var profile: Profile) raises -> sqrrl__Employee:
        if self.storage[].indexes.email.contains(email):
            raise Error("UniqueConstraintViolation: 'email' already in use by another entity")
        var id = self.storage[].alloc_id()
        var inner = ArcPointer(sqrrl__EmployeeInner(_id=id, _table=self.storage, _email=email, _title=title, _years_employed=years_employed, _salary=salary, _sqrrl__dept=sqrrl__dept, _profile=profile^))
        self.storage[].register_weak(id, inner)
        self.storage[].indexes.email.add(id, inner[]._email)
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

    def for_email(self, value: String) raises -> sqrrl__Employee:
        var id = self.storage[].indexes.email.get_bwd(value)
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

    def count_email(self, value: String) -> Int:
        return 1 if self.storage[].indexes.email.contains(value) else 0

    def group_by_email(self) -> Dict[String, sqrrl__Employee]:
        ref ids = self.storage[].indexes.email.all_bwd()
        var out = Dict[String, sqrrl__Employee]()
        for entry in ids.items():
            out[entry.key] = sqrrl__Employee(self.storage[].handle_for(entry.value))
        return out^

    def distinct_email(self) -> Set[String]:
        var out = Set[String]()
        ref ids = self.storage[].indexes.email.all_bwd()
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

    def min_years_employed_by_email(self) -> Dict[String, UInt32]:
        ref sqrrl__ids = self.storage[].indexes.email.all_bwd()
        var out = Dict[String, UInt32]()
        for entry in sqrrl__ids.items():
            var sqrrl__v = self.storage[].handle_for(entry.value)[]._years_employed
            out[entry.key] = sqrrl__v
        return out^

    def min_years_employed_for_email(self, value: String) raises -> UInt32:
        var sqrrl__id = self.storage[].indexes.email.get_bwd(value)
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

    def max_years_employed_by_email(self) -> Dict[String, UInt32]:
        ref sqrrl__ids = self.storage[].indexes.email.all_bwd()
        var out = Dict[String, UInt32]()
        for entry in sqrrl__ids.items():
            var sqrrl__v = self.storage[].handle_for(entry.value)[]._years_employed
            out[entry.key] = sqrrl__v
        return out^

    def max_years_employed_for_email(self, value: String) raises -> UInt32:
        var sqrrl__id = self.storage[].indexes.email.get_bwd(value)
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

    def median_years_employed_by_email(self) -> Dict[String, UInt32]:
        ref sqrrl__ids = self.storage[].indexes.email.all_bwd()
        var out = Dict[String, UInt32]()
        for entry in sqrrl__ids.items():
            var sqrrl__v = self.storage[].handle_for(entry.value)[]._years_employed
            out[entry.key] = sqrrl__v
        return out^

    def median_years_employed_for_email(self, value: String) raises -> UInt32:
        var sqrrl__id = self.storage[].indexes.email.get_bwd(value)
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

    def min_salary_by_email(self) -> Dict[String, Float64]:
        ref sqrrl__ids = self.storage[].indexes.email.all_bwd()
        var out = Dict[String, Float64]()
        for entry in sqrrl__ids.items():
            var sqrrl__v = self.storage[].handle_for(entry.value)[]._salary
            out[entry.key] = sqrrl__v
        return out^

    def min_salary_for_email(self, value: String) raises -> Float64:
        var sqrrl__id = self.storage[].indexes.email.get_bwd(value)
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

    def max_salary_by_email(self) -> Dict[String, Float64]:
        ref sqrrl__ids = self.storage[].indexes.email.all_bwd()
        var out = Dict[String, Float64]()
        for entry in sqrrl__ids.items():
            var sqrrl__v = self.storage[].handle_for(entry.value)[]._salary
            out[entry.key] = sqrrl__v
        return out^

    def max_salary_for_email(self, value: String) raises -> Float64:
        var sqrrl__id = self.storage[].indexes.email.get_bwd(value)
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

    def median_salary_by_email(self) -> Dict[String, Float64]:
        ref sqrrl__ids = self.storage[].indexes.email.all_bwd()
        var out = Dict[String, Float64]()
        for entry in sqrrl__ids.items():
            var sqrrl__v = self.storage[].handle_for(entry.value)[]._salary
            out[entry.key] = sqrrl__v
        return out^

    def median_salary_for_email(self, value: String) raises -> Float64:
        var sqrrl__id = self.storage[].indexes.email.get_bwd(value)
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

    def sum_salary_by_email(self) -> Dict[String, Float64]:
        ref sqrrl__ids = self.storage[].indexes.email.all_bwd()
        var out = Dict[String, Float64]()
        for entry in sqrrl__ids.items():
            var sqrrl__v = self.storage[].handle_for(entry.value)[]._salary
            out[entry.key] = sqrrl__v
        return out^

    def sum_salary_for_email(self, value: String) raises -> Float64:
        var sqrrl__id = self.storage[].indexes.email.get_bwd(value)
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

    def avg_salary_by_email(self) -> Dict[String, Float64]:
        ref sqrrl__ids = self.storage[].indexes.email.all_bwd()
        var out = Dict[String, Float64]()
        for entry in sqrrl__ids.items():
            var sqrrl__v = self.storage[].handle_for(entry.value)[]._salary
            out[entry.key] = Float64(sqrrl__v)
        return out^

    def avg_salary_for_email(self, value: String) raises -> Float64:
        var sqrrl__id = self.storage[].indexes.email.get_bwd(value)
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

