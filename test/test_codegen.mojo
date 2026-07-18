from std.testing import assert_true, assert_false, assert_equal, TestSuite

from squirrel_compiler.codegen import transform_source
from squirrel_compiler.driver.cycles import check_no_relation_cycles
from squirrel_compiler.driver.discovery import DiscoveryResult, DiscoveredStruct, PlainStructDiscovery, build_relation_schema
from squirrel_compiler.driver.topo_order import topo_sort_structs
from squirrel_compiler.driver.json_module import emit_json_module
from squirrel_compiler.parser import ParsedStruct, Field, FieldModifier, TypeParam


def test_transform_plain_struct_and_script() raises:
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Person"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()
    indexed_fields["Person"] = List[String]()
    indexed_fields["Person"].append("name")

    var src = String(
        "@@struct @@Person:\n"
        + "    indexed name: String\n"
        + "    age: UInt32\n"
        + "\n"
        + "def main() raises:\n"
        + "    @@@:\n"
        + "        var @@alice = @@@Person { .name = \"alice\", .age = 30 }\n"
        + "        @@alice.age = 31\n"
        + "        print(@@alice.name, @@alice.age)\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
    )
    # Entity/table shape.
    assert_true("struct sqrrl__PersonInner" in out)
    assert_true("struct sqrrl__Person(" in out)
    assert_true("struct sqrrl__PersonIndexes" in out)
    assert_true("struct sqrrl__PersonTable" in out)
    assert_true("var _name: String" in out)
    assert_true("var _age: UInt32" in out)
    assert_true("var name: PlainIndex[String]" in out)
    assert_true("def set_name(mut self, v: String):" in out)
    assert_true("def set_age(mut self, v: UInt32):" in out)
    # get_<field> returns a borrowed ref into the field, not a copy.
    assert_true("def get_name(self) -> ref [self._name] String:" in out)

    # Script rewriting.
    assert_true("var sqrrl__world = sqrrl__init()" in out)
    assert_true('sqrrl__world.Person.create(name = "alice", age = 30)' in out)
    # Non-indexed write -- plain field assignment, no sqrrl__world.
    assert_true("sqrrl__alice._inner[].set_age(31);" in out)
    # Reads -- direct field access.
    assert_true("sqrrl__alice._inner[]._name" in out)
    assert_true("sqrrl__alice._inner[]._age" in out)
    assert_true("finally:" in out)
    assert_true("sqrrl__world.sqrrl__check_no_leaks()" in out)


def test_transform_relation_field_read_and_write() raises:
    var relation_schema = Dict[String, Dict[String, String]]()
    relation_schema["Employee"] = Dict[String, String]()
    relation_schema["Employee"]["dept"] = "Department"
    var struct_names = Dict[String, Bool]()
    struct_names["Employee"] = True
    struct_names["Department"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "@@struct @@Department:\n"
        + "    name: String\n"
        + "\n"
        + "@@struct @@Employee:\n"
        + "    title: String\n"
        + "    @@dept: @@Department\n"
        + "\n"
        + "def main() raises:\n"
        + "    @@@:\n"
        + "        var @@eng = @@@Department { .name = \"Engineering\" }\n"
        + "        var @@ops = @@@Department { .name = \"Ops\" }\n"
        + "        var @@alice = @@@Employee { .title = \"Engineer\", .@@dept = @@eng }\n"
        + "        print(@@alice.@@dept.name)\n"
        + "        @@alice.@@dept = @@ops\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
    )
    assert_true("var _sqrrl__dept: sqrrl__Department" in out)
    # A relation field's set_<field>/get_<field> method NAMES carry sqrrl__
    # too, same as the storage field/create()-parameter names already do --
    # the prefix mirrors @@-marking with no exceptions, generated method
    # names included.
    assert_true("def set_sqrrl__dept(mut self, v: sqrrl__Department):" in out)
    assert_true("def get_sqrrl__dept(self) -> ref [self._sqrrl__dept] sqrrl__Department:" in out)
    assert_true(
        "sqrrl__alice._inner[]._sqrrl__dept._inner[]._name" in out
    )
    # A relation field's create() parameter, and the matching call-site
    # keyword, both carry sqrrl__ too -- the prefix mirrors @@-marking with
    # no exceptions, construction sites included.
    assert_true("def create(mut self, *, title: String, sqrrl__dept: sqrrl__Department)" in out)
    assert_true('sqrrl__world.Employee.create(title = "Engineer", sqrrl__dept = sqrrl__eng)' in out)
    # A write to a relation field calls the matching sqrrl__-prefixed
    # set_<field>, same as the definition side emits.
    assert_true("sqrrl__alice._inner[].set_sqrrl__dept(sqrrl__ops);" in out)


def test_transform_wrapped_relation_field_needs_move_assignment() raises:
    """A `@@container` field (`@@members: List[@@Employee]`, non-`multi`)
    isn't guaranteed `ImplicitlyCopyable` -- `List[T]` turned out NOT to be
    ImplicitlyCopyable in this Mojo build (verified directly against the
    real compiler, contradicting an earlier spike that only checked a bare
    parameter, not a field assignment) -- so `set_<field>`/`create()` need
    the same `var`+`^` (move) treatment `multi`'s own `Set[T]` and a
    plain-struct-typed field already established, not the bare-copy
    assumption an ordinary relation/leaf field safely uses."""
    var relation_schema = Dict[String, Dict[String, String]]()
    relation_schema["Department"] = Dict[String, String]()
    relation_schema["Department"]["members"] = "List[Employee]"
    var struct_names = Dict[String, Bool]()
    struct_names["Department"] = True
    struct_names["Employee"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "@@struct @@Employee:\n"
        + "    name: String\n"
        + "\n"
        + "@@struct @@Department:\n"
        + "    name: String\n"
        + "    @@members: List[@@Employee]\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
    )
    assert_true("var _sqrrl__members: List[sqrrl__Employee]" in out)
    assert_true("def set_sqrrl__members(mut self, var v: List[sqrrl__Employee]):" in out)
    assert_true("self._sqrrl__members = v^" in out)
    assert_true("def create(mut self, *, name: String, var sqrrl__members: List[sqrrl__Employee])" in out)


def test_transform_multi_field() raises:
    var relation_schema = Dict[String, Dict[String, String]]()
    relation_schema["Department"] = Dict[String, String]()
    relation_schema["Department"]["projects"] = "Project"
    var struct_names = Dict[String, Bool]()
    struct_names["Department"] = True
    struct_names["Project"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()
    var multi_fields = Dict[String, List[String]]()
    multi_fields["Department"] = List[String]()
    multi_fields["Department"].append("projects")

    var src = String(
        "@@struct @@Project:\n"
        + "    name: String\n"
        + "\n"
        + "@@struct @@Department:\n"
        + "    name: String\n"
        + "    multi @@projects: @@Project\n"
        + "\n"
        + "def main() raises:\n"
        + "    @@@:\n"
        + "        var @@eng = @@@Department { .name = \"Engineering\" }\n"
        + "        var @@website = @@@Project { .name = \"Website\" }\n"
        + "        _ = @@eng.add_to_@@projects(@@website)\n"
        + "        _ = @@eng.remove_from_@@projects(@@website)\n"
        + "        var @@matches = @@@Department.for_@@projects(@@website)\n"
        + "        print(len(@@matches))\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields, multi_fields
    )
    # Real Set-typed forward field.
    assert_true("var _sqrrl__projects: Set[sqrrl__Project]" in out)
    # A wholesale set_<field> exists alongside add_to_/remove_from_ (not
    # instead of them) -- `var` (owned) on the parameter since Set[T] isn't
    # ImplicitlyCopyable, same reason create()'s own multi parameter needs it.
    assert_true("def set_sqrrl__projects(mut self, var v: Set[sqrrl__Project]):" in out)
    # Old membership is evicted by borrowing the field directly, before
    # reassignment -- no .copy() needed (same ordering UNIQUE's own
    # set_<field> already uses).
    assert_true("self._table[].indexes.projects.remove_many(self._id, self._sqrrl__projects)" in out)
    assert_true("self._table[].indexes.projects.add_many(self._id, self._sqrrl__projects)" in out)
    # A multi field is always a relation field -- its generated method
    # names carry sqrrl__ too, same as set_<field>/get_<field> now do for
    # any other relation field (no exceptions, point 3).
    assert_true("def add_to_sqrrl__projects(mut self, value: sqrrl__Project) -> Bool:" in out)
    # No `raises` -- Set.remove's failure (value not present) is caught
    # internally and converted to the Bool return, not propagated.
    assert_true("def remove_from_sqrrl__projects(mut self, value: sqrrl__Project) -> Bool:" in out)
    assert_true("        try:\n            self._sqrrl__projects.remove(value)\n        except:\n            return False\n" in out)
    # Element-keyed backward index on the table's Indexes struct -- Indexes'
    # own field stays bare (pure table-internal bookkeeping, not exposed).
    assert_true("var projects: MultiIndex[sqrrl__Project]" in out)
    # create() includes the multi field like any other, with an empty-Set
    # default so omitting it (as this script does) keeps working unchanged.
    # `var` (owned) is needed on this one parameter -- Set[T] isn't
    # ImplicitlyCopyable, so building the entity moves it in (`^`) rather
    # than copying.
    assert_true(
        "def create(mut self, *, name: String, var sqrrl__projects: Set[sqrrl__Project] = Set[sqrrl__Project]()) -> sqrrl__Department:"
        in out
    )
    assert_true("_sqrrl__projects=sqrrl__projects^" in out)
    # Construction-time index population is a single bulk-add call
    # (element-keyed, same MultiIndex method __del__'s eviction mirrors).
    assert_true("self.storage[].indexes.projects.add_many(id, inner[]._sqrrl__projects)" in out)
    # __del__ evicts via a single bulk-remove call.
    assert_true("self._table[].indexes.projects.remove_many(self._id, self._sqrrl__projects)" in out)
    # Table-level for_<field> takes the bare element type, Set-returning,
    # and its own generated name carries sqrrl__ too.
    assert_true("def for_sqrrl__projects(self, value: sqrrl__Project) -> Set[sqrrl__Department]:" in out)

    # Script rewriting: instance calls need no sqrrl__world at all, and the
    # DSL's own "@@"-marked "add_to_@@projects"/"for_@@projects" surface
    # syntax (the field-name suffix is @@-marked, same convention as
    # `.@@dept`, since `projects` is a relation field) gets rewritten to the
    # sqrrl__-prefixed generated method name.
    assert_true("sqrrl__eng._inner[].add_to_sqrrl__projects(sqrrl__website)" in out)
    assert_true("sqrrl__eng._inner[].remove_from_sqrrl__projects(sqrrl__website)" in out)
    # Table-level for_<field> still routes through sqrrl__world.
    assert_true("sqrrl__world.Department.for_sqrrl__projects(sqrrl__website)" in out)


def test_transform_multi_field_wholesale_write() raises:
    """A wholesale replacement (`.@@projects = Set(...)`) uses the DSL's
    ordinary field-assignment write syntax -- needs no rewrite-engine
    changes at all, since the write path already emits `set_<field>`
    uniformly for any field (see the plan's addendum: verified by reading
    the actual write-path code, not assumed)."""
    var relation_schema = Dict[String, Dict[String, String]]()
    relation_schema["Department"] = Dict[String, String]()
    relation_schema["Department"]["projects"] = "Project"
    var struct_names = Dict[String, Bool]()
    struct_names["Department"] = True
    struct_names["Project"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()
    var multi_fields = Dict[String, List[String]]()
    multi_fields["Department"] = List[String]()
    multi_fields["Department"].append("projects")

    var src = String(
        "@@struct @@Project:\n"
        + "    name: String\n"
        + "\n"
        + "@@struct @@Department:\n"
        + "    name: String\n"
        + "    multi @@projects: @@Project\n"
        + "\n"
        + "def main() raises:\n"
        + "    @@@:\n"
        + "        var @@eng = @@@Department { .name = \"Engineering\" }\n"
        + "        var @@website = @@@Project { .name = \"Website\" }\n"
        + "        var @@app = @@@Project { .name = \"App\" }\n"
        + "        @@eng.@@projects = Set(@@website, @@app)\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields, multi_fields
    )
    assert_true(
        "sqrrl__eng._inner[].set_sqrrl__projects(Set(sqrrl__website, sqrrl__app));" in out
    )


def test_transform_multi_field_call_requires_marked_field_suffix() raises:
    """The old bare `add_to_projects(...)` surface syntax is now rejected --
    `projects` is a relation field, so its call-site suffix must be
    `@@`-marked (`add_to_@@projects(...)`), same rule `.@@dept` already
    enforces for plain field access."""
    var relation_schema = Dict[String, Dict[String, String]]()
    relation_schema["Department"] = Dict[String, String]()
    relation_schema["Department"]["projects"] = "Project"
    var struct_names = Dict[String, Bool]()
    struct_names["Department"] = True
    struct_names["Project"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()
    var multi_fields = Dict[String, List[String]]()
    multi_fields["Department"] = List[String]()
    multi_fields["Department"].append("projects")

    var src = String(
        "@@struct @@Project:\n"
        + "    name: String\n"
        + "\n"
        + "@@struct @@Department:\n"
        + "    name: String\n"
        + "    multi @@projects: @@Project\n"
        + "\n"
        + "def main() raises:\n"
        + "    @@@:\n"
        + "        var @@eng = @@@Department { .name = \"Engineering\" }\n"
        + "        var @@website = @@@Project { .name = \"Website\" }\n"
        + "        _ = @@eng.add_to_projects(@@website)\n"
    )
    var raised = False
    try:
        _ = transform_source(
            src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields, multi_fields
        )
    except:
        raised = True
    assert_true(raised)


def test_transform_multi_field_inline_construction() raises:
    """A `multi` field's construct-site value is just an ordinary field
    value (a `Set(...)` of already-bound entities) -- no special-cased
    parsing or desugaring, the existing generic construct-field/create-call
    machinery already carries it through unchanged (see the plan's addendum
    for why this needed no parser or rewrite-engine changes at all)."""
    var relation_schema = Dict[String, Dict[String, String]]()
    relation_schema["Department"] = Dict[String, String]()
    relation_schema["Department"]["projects"] = "Project"
    var struct_names = Dict[String, Bool]()
    struct_names["Department"] = True
    struct_names["Project"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()
    var multi_fields = Dict[String, List[String]]()
    multi_fields["Department"] = List[String]()
    multi_fields["Department"].append("projects")

    var src = String(
        "@@struct @@Project:\n"
        + "    name: String\n"
        + "\n"
        + "@@struct @@Department:\n"
        + "    name: String\n"
        + "    multi @@projects: @@Project\n"
        + "\n"
        + "def main() raises:\n"
        + "    @@@:\n"
        + "        var @@website = @@@Project { .name = \"Website\" }\n"
        + "        var @@app = @@@Project { .name = \"App\" }\n"
        + "        var @@eng = @@@Department { .name = \"Engineering\", .@@projects = Set(@@website, @@app) }\n"
        + "        print(len(@@eng.@@projects))\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields, multi_fields
    )
    # The embedded @@website/@@app markers inside Set(...) get rewritten the
    # same generic way any other construct-field value's markers do.
    assert_true(
        'sqrrl__world.Department.create(name = "Engineering", sqrrl__projects = Set(sqrrl__website, sqrrl__app))'
        in out
    )


def test_transform_ordered_field_definition() raises:
    """`ordered`'s generated shape: same PlainIndex-shaped set_<field>/
    __del__/create() index-population (no codegen changes needed there --
    OrderedIndex exposes the same add/remove names), an exact-match
    for_<field> that stays Set-returning, and five new List-returning
    range-query methods that preserve ascending order."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Employee"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()
    var multi_fields = Dict[String, List[String]]()
    var ordered_fields = Dict[String, List[String]]()
    ordered_fields["Employee"] = List[String]()
    ordered_fields["Employee"].append("years_employed")

    var src = String(
        "@@struct @@Employee:\n"
        + "    name: String\n"
        + "    ordered years_employed: UInt32\n"
        + "\n"
        + "def main() raises:\n"
        + "    pass\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields, multi_fields, ordered_fields
    )
    assert_true("var years_employed: OrderedIndex[UInt32]" in out)
    # set_<field> is untouched -- same evict-old/add-new shape INDEXED uses.
    assert_true("def set_years_employed(mut self, v: UInt32):" in out)
    # Exact match stays Set-returning.
    assert_true("def for_years_employed(self, value: UInt32) -> Set[sqrrl__Employee]:" in out)
    # Range queries are List-returning, one per comparator, plus the
    # two-argument between.
    assert_true("def for_years_employed_greater_than(self, value: UInt32) -> List[sqrrl__Employee]:" in out)
    assert_true("def for_years_employed_less_than(self, value: UInt32) -> List[sqrrl__Employee]:" in out)
    assert_true("def for_years_employed_at_least(self, value: UInt32) -> List[sqrrl__Employee]:" in out)
    assert_true("def for_years_employed_at_most(self, value: UInt32) -> List[sqrrl__Employee]:" in out)
    assert_true(
        "def for_years_employed_between(self, low: UInt32, high: UInt32) -> List[sqrrl__Employee]:" in out
    )
    assert_true("self.storage[].indexes.years_employed.greater_than(value)" in out)
    assert_true("self.storage[].indexes.years_employed.between(low, high)" in out)


def test_transform_ordered_field_range_query_call_sites() raises:
    """Script rewriting for ordered range-query calls: distinguishing
    `for_years_employed_greater_than(3)` from a plain `for_<field>` exact
    match relies on matching against the actual declared field name (not
    blind suffix slicing), since the field name itself contains an
    underscore."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Employee"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()
    var multi_fields = Dict[String, List[String]]()
    var ordered_fields = Dict[String, List[String]]()
    ordered_fields["Employee"] = List[String]()
    ordered_fields["Employee"].append("years_employed")

    var src = String(
        "@@struct @@Employee:\n"
        + "    name: String\n"
        + "    ordered years_employed: UInt32\n"
        + "\n"
        + "def main() raises:\n"
        + "    @@@:\n"
        + "        var @@more = @@@Employee.for_years_employed_greater_than(3)\n"
        + "        print(len(@@more))\n"
        + "        var @@ranged = @@@Employee.for_years_employed_between(3, 4)\n"
        + "        print(len(@@ranged))\n"
        + "        var @@exact = @@@Employee.for_years_employed(3)\n"
        + "        print(len(@@exact))\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields, multi_fields, ordered_fields
    )
    assert_true("sqrrl__world.Employee.for_years_employed_greater_than(3)" in out)
    assert_true("sqrrl__world.Employee.for_years_employed_between(3, 4)" in out)
    assert_true("sqrrl__world.Employee.for_years_employed(3)" in out)


def test_transform_method_without_world_marking() raises:
    """A method with no `@@@`-marking compiles with no `sqrrl__world`
    parameter at all -- `self.field` is ordinary bound-variable field
    access (M3 addendum, point 3; `self` is auto-`@@`-marked by
    `_mark_self_field_access` before the ordinary `@@entity.field`
    machinery ever sees it), needing no more `sqrrl__world` than any other
    field read does."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Person"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "@@struct @@Person:\n"
        + "    name: String\n"
        + "\n"
        + "    def greeting(self) -> String:\n"
        + "        return \"Hello, \" + self.name\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
    )
    assert_true("def greeting(self) -> String:" in out)
    assert_true('return "Hello, " + self._inner[]._name' in out)
    assert_false("sqrrl__world" in out)


def test_transform_method_self_write_and_relation_hop_and_word_boundary() raises:
    """`_mark_self_field_access` exercised on its trickiest cases in one
    method: a write through `self.field = ...`, a relation hop
    (`self.@@dept.name`, still explicitly `@@`-marked -- only `self` itself
    is implicit), and a local variable named `myself` that must NOT be
    mistaken for the receiver (word-boundary check)."""
    var relation_schema = Dict[String, Dict[String, String]]()
    relation_schema["Employee"] = Dict[String, String]()
    relation_schema["Employee"]["dept"] = "Department"
    var struct_names = Dict[String, Bool]()
    struct_names["Employee"] = True
    struct_names["Department"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "@@struct @@Department:\n"
        + "    name: String\n"
        + "\n"
        + "@@struct @@Employee:\n"
        + "    title: String\n"
        + "    @@dept: @@Department\n"
        + "\n"
        + "    def relabel(self):\n"
        + "        var myself = 1\n"
        + "        self.title = self.@@dept.name\n"
        + "        print(myself)\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
    )
    assert_true(
        "self._inner[].set_title(self._inner[]._sqrrl__dept._inner[]._name);" in out
    )
    # "myself" must survive untouched -- not mistaken for the receiver.
    assert_true("var myself = 1" in out)
    assert_true("print(myself)" in out)
    assert_false("sqrrl__world" in out)


def test_transform_method_world_marked_threads_world() raises:
    """A `@@@`-marked method gets `mut sqrrl__world: sqrrl__World` spliced
    in right after `self`, and can call a table-level method
    (`@@@Type.count()`) using it -- the same threading `MarkerKind.
    WORLD_FUNC` already does for top-level functions."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Person"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "@@struct @@Person:\n"
        + "    unique name: String\n"
        + "\n"
        + "    def @@@headcount(self) -> Int:\n"
        + "        return @@@Person.count()\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
    )
    assert_true("def headcount(self, mut sqrrl__world: sqrrl__World) -> Int:" in out)
    assert_true("return sqrrl__world.Person.count()" in out)


def test_transform_method_table_level_call_without_world_marking_rejected() raises:
    """A method that isn't `@@@`-marked can't make a table-level call --
    same 'needs sqrrl__world' rejection `MarkerKind.WORLD_FUNC` already
    raises for a plain top-level function."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Person"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "@@struct @@Person:\n"
        + "    unique name: String\n"
        + "\n"
        + "    def headcount(self) -> Int:\n"
        + "        return @@@Person.count()\n"
    )
    var raised = False
    try:
        _ = transform_source(
            src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
        )
    except:
        raised = True
    assert_true(raised)


def test_transform_calling_spliced_methods_from_script() raises:
    """Calling a spliced user method directly from a script works both for
    a plain method (`@@alice.entity_id()`, no `sqrrl__world` threaded, no
    marking at the call site either) and a `@@@`-marked one
    (`@@alice.@@@greeting()`, threaded as the call's own first argument) --
    call-site symmetry with the method's own declaration marking.
    `ctx.world_methods` (built project-wide by `build_world_methods`) is
    what `handle_field_access` validates the call-site marking against."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Person"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()
    var multi_fields = Dict[String, List[String]]()
    var ordered_fields = Dict[String, List[String]]()
    var world_methods = Dict[String, List[String]]()
    world_methods["Person"] = List[String]()
    world_methods["Person"].append("greeting")

    var src = String(
        "@@struct @@Person:\n"
        + "    name: String\n"
        + "\n"
        + "    def entity_id(self) -> UInt32:\n"
        + "        return self.id()\n"
        + "\n"
        + "    def @@@greeting(self) -> String:\n"
        + "        return \"Hello, \" + self.name\n"
        + "\n"
        + "def main() raises:\n"
        + "    @@@:\n"
        + "        var @@alice = @@@Person { .name = \"alice\" }\n"
        + "        print(@@alice.entity_id())\n"
        + "        print(@@alice.@@@greeting())\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields,
        multi_fields, ordered_fields, world_methods
    )
    assert_true("sqrrl__alice.entity_id()" in out)
    assert_true("sqrrl__alice.greeting(sqrrl__world)" in out)


def test_transform_spliced_method_call_site_marking_mismatch_rejected() raises:
    """Both directions of call-site/declaration marking mismatch are
    rejected: calling a `@@@`-marked method without `@@@` at the call site,
    and marking a plain method's call site with `@@@` it doesn't need."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Person"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()
    var multi_fields = Dict[String, List[String]]()
    var ordered_fields = Dict[String, List[String]]()
    var world_methods = Dict[String, List[String]]()
    world_methods["Person"] = List[String]()
    world_methods["Person"].append("greeting")

    var missing_marker_src = String(
        "@@struct @@Person:\n"
        + "    name: String\n"
        + "\n"
        + "    def entity_id(self) -> UInt32:\n"
        + "        return self.id()\n"
        + "\n"
        + "    def @@@greeting(self) -> String:\n"
        + "        return \"Hello, \" + self.name\n"
        + "\n"
        + "def main() raises:\n"
        + "    @@@:\n"
        + "        var @@alice = @@@Person { .name = \"alice\" }\n"
        + "        print(@@alice.greeting())\n"
    )
    var raised_missing = False
    try:
        _ = transform_source(
            missing_marker_src, relation_schema, struct_names, function_returns, unique_fields,
            indexed_fields, multi_fields, ordered_fields, world_methods
        )
    except:
        raised_missing = True
    assert_true(raised_missing)

    var extra_marker_src = String(
        "@@struct @@Person:\n"
        + "    name: String\n"
        + "\n"
        + "    def entity_id(self) -> UInt32:\n"
        + "        return self.id()\n"
        + "\n"
        + "    def @@@greeting(self) -> String:\n"
        + "        return \"Hello, \" + self.name\n"
        + "\n"
        + "def main() raises:\n"
        + "    @@@:\n"
        + "        var @@alice = @@@Person { .name = \"alice\" }\n"
        + "        print(@@alice.@@@entity_id())\n"
    )
    var raised_extra = False
    try:
        _ = transform_source(
            extra_marker_src, relation_schema, struct_names, function_returns, unique_fields,
            indexed_fields, multi_fields, ordered_fields, world_methods
        )
    except:
        raised_extra = True
    assert_true(raised_extra)


def test_transform_trait_list_appears_on_wrapper() raises:
    """`trait_list` (already spliced into `emit_entity`'s trait list since
    M1) still appears on the generated wrapper now that method splicing is
    real too -- a regression check that the two features compose."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Person"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "@@struct @@Person(HasId):\n"
        + "    name: String\n"
        + "\n"
        + "    def entity_id(self) -> UInt32:\n"
        + "        return self.id()\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
    )
    assert_true(
        "struct sqrrl__Person(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable, HasId):" in out
    )
    assert_true("def entity_id(self) -> UInt32:" in out)
    assert_true("return self.id()" in out)


def test_transform_table_level_call_requires_world_marked_entity() raises:
    """A table-level call written with plain '@@' (not '@@@') is rejected --
    construction/table-level calls always need 'sqrrl__world' now (M3
    addendum), so the entity's own marking must match which case this is."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Person"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()
    indexed_fields["Person"] = List[String]()
    indexed_fields["Person"].append("name")

    var src = String(
        "@@struct @@Person:\n"
        + "    indexed name: String\n"
        + "\n"
        + "def main() raises:\n"
        + "    @@@:\n"
        + "        var @@matches = @@Person.for_name(\"a\")\n"
        + "        print(len(@@matches))\n"
    )
    var raised = False
    try:
        _ = transform_source(
            src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
        )
    except:
        raised = True
    assert_true(raised)


def test_transform_instance_access_rejects_world_marked_entity() raises:
    """The reverse mismatch: a bound variable marked with '@@@' (instead of
    plain '@@') is rejected too -- a bound-variable access never needs
    'sqrrl__world'."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Person"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "@@struct @@Person:\n"
        + "    name: String\n"
        + "\n"
        + "def main() raises:\n"
        + "    @@@:\n"
        + "        var @@alice = @@@Person { .name = \"alice\" }\n"
        + "        print(@@@alice.name)\n"
    )
    var raised = False
    try:
        _ = transform_source(
            src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
        )
    except:
        raised = True
    assert_true(raised)


def test_transform_keepalive_struct() raises:
    """A `keepalive`-tagged struct's `create()` adds every new entity to
    `EntityStorage`'s own `keepalive` hold (M4 correction: it lives there,
    not on the generated `Table` struct, since only `EntityStorage` is
    reachable from *both* the table and an instance -- see
    `entity_storage.mojo`'s own doc comment). `dont_keepalive` is an
    *instance* method on the wrapper: it never needed `sqrrl__world`, only
    `self._inner[]._table[]`, reached the same way `add_to_<field>`/
    `remove_from_<field>` already reach shared table state from an
    instance."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Project"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "@@struct keepalive @@Project:\n"
        + "    name: String\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
    )
    assert_true("self.storage[].keepalive_add(id, inner.copy())" in out)
    assert_true("return sqrrl__Project(inner^)" in out)
    assert_true("def dont_keepalive(mut self) -> Bool:" in out)
    assert_true("return self._inner[]._table[].keepalive_remove(self.id())" in out)
    # No Table-level keepalive field any more -- moved to EntityStorage.
    assert_false("var keepalive:" in out)


def test_transform_non_keepalive_struct_has_no_keepalive_machinery() raises:
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Project"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "@@struct @@Project:\n"
        + "    name: String\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
    )
    assert_false("keepalive" in out)
    assert_true("return sqrrl__Project(inner^)" in out)


def test_transform_equatable_struct() raises:
    """`value_eq` is an *instance* method on the wrapper (M4 correction: it
    never needed `sqrrl__world`, it just reads two entities' own fields
    directly), field-by-field via the already-generated `get_<field>`
    accessor on `Inner`, short-circuiting on the first mismatch. Deliberately
    distinct from `__eq__` (id-based, "same row")."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Person"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "@@struct equatable @@Person:\n"
        + "    name: String\n"
        + "    age: UInt32\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
    )
    assert_true("def value_eq(self, other: Self) -> Bool:" in out)
    assert_true("if self._inner[].get_name() != other._inner[].get_name():" in out)
    assert_true("if self._inner[].get_age() != other._inner[].get_age():" in out)
    assert_true("        return True\n" in out)


def test_transform_non_equatable_struct_has_no_value_eq() raises:
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Person"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "@@struct @@Person:\n"
        + "    name: String\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
    )
    assert_false("value_eq" in out)


def test_transform_value_eq_and_dont_keepalive_called_as_instance_methods() raises:
    """`@@alice.value_eq(@@bob)`/`@@handle.dont_keepalive()` -- ordinary
    instance calls, no `@@@` marking and no `sqrrl__world` threaded (M4
    correction: neither ever needed it). Falls through the same M3
    spliced-method-call dispatch with zero new code -- `value_eq`/
    `dont_keepalive` just aren't in `ctx.world_methods`, same as any other
    non-`@@@`-marked instance method."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Project"] = True
    struct_names["Person"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    unique_fields["Project"] = List[String]()
    unique_fields["Project"].append("name")
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "@@struct keepalive @@Project:\n"
        + "    unique name: String\n"
        + "\n"
        + "@@struct equatable @@Person:\n"
        + "    name: String\n"
        + "\n"
        + "def main() raises:\n"
        + "    @@@:\n"
        + "        var @@handle = @@@Project { .name = \"Website\" }\n"
        + "        var released = @@handle.dont_keepalive()\n"
        + "        var @@alice = @@@Person { .name = \"alice\" }\n"
        + "        var @@bob = @@@Person { .name = \"bob\" }\n"
        + "        print(released, @@alice.value_eq(@@bob))\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
    )
    assert_true("sqrrl__handle.dont_keepalive()" in out)
    assert_true("sqrrl__alice.value_eq(sqrrl__bob)" in out)
    assert_false("sqrrl__world.dont_keepalive" in out)
    assert_false("sqrrl__world.value_eq" in out)


def test_transform_value_eq_as_table_level_call_rejected() raises:
    """The old table-level shape (`@@@Person.value_eq(@@a, @@b)`) is no
    longer supported -- it's an instance method now."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Person"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "@@struct equatable @@Person:\n"
        + "    name: String\n"
        + "\n"
        + "def main() raises:\n"
        + "    @@@:\n"
        + "        var @@alice = @@@Person { .name = \"alice\" }\n"
        + "        var @@bob = @@@Person { .name = \"bob\" }\n"
        + "        print(@@@Person.value_eq(@@alice, @@bob))\n"
    )
    var raised = False
    try:
        _ = transform_source(
            src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
        )
    except:
        raised = True
    assert_true(raised)


def test_transform_grouping_query_definitions() raises:
    """`count_<field>`/`group_by_<field>`/`count_by_<field>`/
    `distinct_<field>` for a plain indexed field, a unique field (no
    `count_by_`, no `Set` wrapping on `group_by_`), and a relation field
    (method names carry `sqrrl__`, same as every other relation-derived
    name)."""
    var relation_schema = Dict[String, Dict[String, String]]()
    relation_schema["Employee"] = Dict[String, String]()
    relation_schema["Employee"]["dept"] = "Department"
    var struct_names = Dict[String, Bool]()
    struct_names["Employee"] = True
    struct_names["Department"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    unique_fields["Employee"] = List[String]()
    unique_fields["Employee"].append("ssn")
    var indexed_fields = Dict[String, List[String]]()
    indexed_fields["Employee"] = List[String]()
    indexed_fields["Employee"].append("name")
    indexed_fields["Employee"].append("dept")

    var src = String(
        "@@struct @@Department:\n"
        + "    unique name: String\n"
        + "\n"
        + "@@struct @@Employee:\n"
        + "    indexed name: String\n"
        + "    unique ssn: String\n"
        + "    indexed @@dept: @@Department\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
    )
    # Plain indexed field.
    assert_true("def count_name(self, value: String) -> Int:" in out)
    assert_true("def group_by_name(self) -> Dict[String, Set[sqrrl__Employee]]:" in out)
    assert_true("def count_by_name(self) -> Dict[String, Int]:" in out)
    assert_true("def distinct_name(self) -> Set[String]:" in out)
    # Unique field -- no Set wrapping, no count_by_ at all.
    assert_true("def count_ssn(self, value: String) -> Int:" in out)
    assert_true("return 1 if self.storage[].indexes.ssn.contains(value) else 0" in out)
    assert_true("def group_by_ssn(self) -> Dict[String, sqrrl__Employee]:" in out)
    assert_true("def distinct_ssn(self) -> Set[String]:" in out)
    assert_false("count_by_ssn" in out)
    # Relation field -- sqrrl__-prefixed method names, Dict keyed by the
    # target entity type.
    assert_true("def count_sqrrl__dept(self, value: sqrrl__Department) -> Int:" in out)
    assert_true("def group_by_sqrrl__dept(self) -> Dict[sqrrl__Department, Set[sqrrl__Employee]]:" in out)
    assert_true("def count_by_sqrrl__dept(self) -> Dict[sqrrl__Department, Int]:" in out)
    assert_true("def distinct_sqrrl__dept(self) -> Set[sqrrl__Department]:" in out)


def test_transform_grouping_query_call_sites() raises:
    var relation_schema = Dict[String, Dict[String, String]]()
    relation_schema["Employee"] = Dict[String, String]()
    relation_schema["Employee"]["dept"] = "Department"
    var struct_names = Dict[String, Bool]()
    struct_names["Employee"] = True
    struct_names["Department"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()
    indexed_fields["Employee"] = List[String]()
    indexed_fields["Employee"].append("name")
    indexed_fields["Employee"].append("dept")

    var src = String(
        "@@struct @@Department:\n"
        + "    unique name: String\n"
        + "\n"
        + "@@struct @@Employee:\n"
        + "    indexed name: String\n"
        + "    indexed @@dept: @@Department\n"
        + "\n"
        + "def main() raises:\n"
        + "    @@@:\n"
        + "        var @@eng = @@@Department { .name = \"Engineering\" }\n"
        + "        var @@alice = @@@Employee { .name = \"alice\", .@@dept = @@eng }\n"
        + "        print(@@@Employee.count_name(\"alice\"))\n"
        + "        var by_name = @@@Employee.group_by_name()\n"
        + "        print(len(by_name))\n"
        + "        var counts = @@@Employee.count_by_name()\n"
        + "        print(len(counts))\n"
        + "        var names = @@@Employee.distinct_name()\n"
        + "        print(len(names))\n"
        + "        var @@depts = @@@Employee.distinct_@@dept()\n"
        + "        for @@d in @@depts:\n"
        + "            print(@@d.name)\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
    )
    assert_true('sqrrl__world.Employee.count_name("alice")' in out)
    assert_true("sqrrl__world.Employee.group_by_name()" in out)
    assert_true("sqrrl__world.Employee.count_by_name()" in out)
    assert_true("sqrrl__world.Employee.distinct_name()" in out)
    # distinct_@@dept (marked, relation) rewrites to the sqrrl__-prefixed
    # generated name, same convention every other relation-field-derived
    # call already follows.
    assert_true("sqrrl__world.Employee.distinct_sqrrl__dept()" in out)
    # The for-loop over a relation-keyed distinct_<field>() result binds
    # to the relation target type, proving the Dict-key-only
    # container_element_of fix threads through end to end.
    assert_true("for sqrrl__d in  sqrrl__depts:" in out)
    assert_true("sqrrl__d._inner[]._name" in out)


def test_transform_group_by_relation_field_requires_marked_suffix() raises:
    """`group_by_dept` (unmarked) on a relation field is rejected -- same
    `@@`-marking-matches-relation-ness rule `for_<field>` already enforces."""
    var relation_schema = Dict[String, Dict[String, String]]()
    relation_schema["Employee"] = Dict[String, String]()
    relation_schema["Employee"]["dept"] = "Department"
    var struct_names = Dict[String, Bool]()
    struct_names["Employee"] = True
    struct_names["Department"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()
    indexed_fields["Employee"] = List[String]()
    indexed_fields["Employee"].append("dept")

    var src = String(
        "@@struct @@Department:\n"
        + "    unique name: String\n"
        + "\n"
        + "@@struct @@Employee:\n"
        + "    indexed @@dept: @@Department\n"
        + "\n"
        + "def main() raises:\n"
        + "    @@@:\n"
        + "        var @@groups = @@@Employee.group_by_dept()\n"
    )
    var raised = False
    try:
        _ = transform_source(
            src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
        )
    except:
        raised = True
    assert_true(raised)


def test_transform_count_by_rejected_for_unique_field() raises:
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Person"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    unique_fields["Person"] = List[String]()
    unique_fields["Person"].append("ssn")
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "@@struct @@Person:\n"
        + "    unique ssn: String\n"
        + "\n"
        + "def main() raises:\n"
        + "    @@@:\n"
        + "        var @@counts = @@@Person.count_by_ssn()\n"
    )
    var raised = False
    try:
        _ = transform_source(
            src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
        )
    except:
        raised = True
    assert_true(raised)


def test_transform_aggregates_definitions() raises:
    """`sum_/avg_/min_/max_/median_<field>` -- whole-table (unconditional
    for a `stats` field), `_by_<other>`/`_for_<other>` paired against a
    groupable relation field, generated unconditionally (no demand-driven
    scanning)."""
    var relation_schema = Dict[String, Dict[String, String]]()
    relation_schema["Employee"] = Dict[String, String]()
    relation_schema["Employee"]["dept"] = "Department"
    var struct_names = Dict[String, Bool]()
    struct_names["Employee"] = True
    struct_names["Department"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()
    indexed_fields["Employee"] = List[String]()
    indexed_fields["Employee"].append("dept")
    var multi_fields = Dict[String, List[String]]()
    var ordered_fields = Dict[String, List[String]]()
    var world_methods = Dict[String, List[String]]()
    var stats_fields = Dict[String, List[String]]()
    stats_fields["Employee"] = List[String]()
    stats_fields["Employee"].append("salary")

    var src = String(
        "@@struct @@Department:\n"
        + "    unique name: String\n"
        + "\n"
        + "@@struct @@Employee:\n"
        + "    name: String\n"
        + "    indexed @@dept: @@Department\n"
        + "    stats salary: Float64\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields,
        multi_fields, ordered_fields, world_methods, stats_fields
    )
    # Whole-table -- all five kinds, unconditional.
    assert_true("def sum_salary(self) raises -> Float64:" in out)
    assert_true("def avg_salary(self) raises -> Float64:" in out)
    assert_true("def min_salary(self) raises -> Float64:" in out)
    assert_true("def max_salary(self) raises -> Float64:" in out)
    assert_true("def median_salary(self) raises -> Float64:" in out)
    assert_true('raise Error("sum_salary: table has no entities")' in out)
    # avg divides by a running count, always Float64 regardless of the
    # field's own type.
    assert_true("Float64(sqrrl__acc.value()) / Float64(sqrrl__count)" in out)
    # _by_/_for_ against the one other groupable (relation) field.
    assert_true("def sum_salary_by_sqrrl__dept(self) -> Dict[sqrrl__Department, Float64]:" in out)
    assert_true(
        "def sum_salary_for_sqrrl__dept(self, value: sqrrl__Department) raises -> Float64:" in out
    )
    # Reads the field directly off storage -- no Optional/.take() dance.
    assert_true("self.storage[].handle_for(sqrrl__id)[]._salary" in out)


def test_transform_ordered_field_earns_min_max_median_without_stats() raises:
    """An `ordered` field earns `min_`/`max_`/`median_` for free -- no
    `stats` needed -- but never `sum_`/`avg_` (those need the `+` `stats`
    additionally promises). The whole-table `median_` reads directly off
    the already-sorted index, no fresh collect-and-sort."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Employee"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()
    var multi_fields = Dict[String, List[String]]()
    var ordered_fields = Dict[String, List[String]]()
    ordered_fields["Employee"] = List[String]()
    ordered_fields["Employee"].append("years_employed")

    var src = String(
        "@@struct @@Employee:\n"
        + "    name: String\n"
        + "    ordered years_employed: UInt32\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields,
        multi_fields, ordered_fields
    )
    assert_true("def min_years_employed(self) raises -> UInt32:" in out)
    assert_true("def max_years_employed(self) raises -> UInt32:" in out)
    assert_true("def median_years_employed(self) raises -> UInt32:" in out)
    assert_false("sum_years_employed" in out)
    assert_false("avg_years_employed" in out)
    # Ordered fast path for whole-table median -- reads directly off the
    # already-sorted index, no fresh List/sort.
    assert_true("ref sqrrl__sorted = self.storage[].indexes.years_employed.entries()" in out)
    assert_true("return sqrrl__sorted[len(sqrrl__sorted) // 2].value\n" in out)


def test_transform_aggregate_skips_self_grouping() raises:
    """`sum_salary_by_salary` doesn't exist -- aggregating a field grouped
    by itself is meaningless, every group already holds exactly that one
    value."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Employee"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()
    indexed_fields["Employee"] = List[String]()
    indexed_fields["Employee"].append("department_code")
    var multi_fields = Dict[String, List[String]]()
    var ordered_fields = Dict[String, List[String]]()
    var world_methods = Dict[String, List[String]]()
    var stats_fields = Dict[String, List[String]]()
    stats_fields["Employee"] = List[String]()
    stats_fields["Employee"].append("salary")

    var src = String(
        "@@struct @@Employee:\n"
        + "    indexed department_code: String\n"
        + "    indexed stats salary: Float64\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields,
        multi_fields, ordered_fields, world_methods, stats_fields
    )
    assert_false("sum_salary_by_salary" in out)
    assert_false("sum_salary_for_salary" in out)
    assert_true("def sum_salary_by_department_code(self) -> Dict[String, Float64]:" in out)


def test_transform_multi_field_excluded_from_aggregation_but_still_groupable() raises:
    """A `multi` field can never be the aggregated value `y` (its storage
    is `Set[...]`, no sensible `+` fold over set membership) even when
    `stats`-tagged, but remains fully usable as a grouping key `x`
    elsewhere (Step 4's own `count_<field>`/etc. are unaffected)."""
    var relation_schema = Dict[String, Dict[String, String]]()
    relation_schema["Department"] = Dict[String, String]()
    relation_schema["Department"]["projects"] = "Project"
    var struct_names = Dict[String, Bool]()
    struct_names["Department"] = True
    struct_names["Project"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()
    var multi_fields = Dict[String, List[String]]()
    multi_fields["Department"] = List[String]()
    multi_fields["Department"].append("projects")
    var ordered_fields = Dict[String, List[String]]()
    var world_methods = Dict[String, List[String]]()
    var stats_fields = Dict[String, List[String]]()
    stats_fields["Department"] = List[String]()
    stats_fields["Department"].append("projects")

    var src = String(
        "@@struct @@Project:\n"
        + "    unique name: String\n"
        + "\n"
        + "@@struct @@Department:\n"
        + "    name: String\n"
        + "    multi stats @@projects: @@Project\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields,
        multi_fields, ordered_fields, world_methods, stats_fields
    )
    assert_false("sum_sqrrl__projects" in out)
    assert_false("median_sqrrl__projects" in out)
    # Still groupable (Step 4) -- unaffected by aggregation eligibility.
    assert_true("def count_sqrrl__projects(self, value: sqrrl__Project) -> Int:" in out)


def test_transform_entity_gets_json_serializable_conformance() raises:
    """Every generated entity wrapper conforms to sqrrl__JsonSerializable
    (M5) and gets a trivial sqrrl__to_json returning its own bare id --
    the target row itself is serialized separately, once, as part of its
    own table's dump."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Person"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "@@struct @@Person:\n"
        + "    name: String\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields, json_used=True
    )
    assert_true("sqrrl__JsonSerializable" in out)
    assert_true("def sqrrl__to_json(self) -> String:" in out)
    assert_true("return String(self.id())" in out)


def test_transform_entity_omits_json_serializable_when_project_never_uses_json() raises:
    """The reverse of the test above (and the new default, matching
    `transform_source`'s own `json_used: Bool = False`): a project that
    never touches JSON anywhere doesn't carry `sqrrl__JsonSerializable`
    conformance or its `sqrrl__to_json` method on any entity at all --
    the JSON-container-dispatch rearchitecture's own relation-dump special
    -casing (calling `.id()` directly wherever the compiler already knows
    a field is a relation) left the trait's only remaining consumer as
    `sqrrl__to_json_default`'s `reflect[T]`-based fallback recursing into
    a *plain struct's* own embedded relation field -- meaningless unless
    the project generates that dispatcher at all."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Person"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "@@struct @@Person:\n"
        + "    name: String\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
    )
    assert_true("sqrrl__JsonSerializable" not in out)
    assert_true("sqrrl__to_json" not in out)
    assert_true(
        "struct sqrrl__Person(Hashable, Equatable, ImplicitlyCopyable, ImplicitlyDeletable):" in out
    )


def test_transform_begin_and_end_init_from_json() raises:
    """`@@@begin_init_from_json(json_expr)` binds a local
    `sqrrl__temp_keep_alives` via a call threading `sqrrl__world` (no `mut`
    at the call site -- ordinary Mojo calling convention, ownership comes
    from the callee's own signature); `@@@end_init_from_json()` moves that
    local into a real function call (a hard call boundary for the
    ASAP-destruction fix, not a bare reassignment)."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "def main() raises:\n"
        + "    @@@:\n"
        + "        var dump = \"{}\"\n"
        + "        @@@begin_init_from_json(dump)\n"
        + "        @@@end_init_from_json()\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
    )
    assert_true(
        "var sqrrl__temp_keep_alives = sqrrl__begin_init_from_json(sqrrl__world, dump)" in out
    )
    assert_true("sqrrl__end_init_from_json(sqrrl__temp_keep_alives^)" in out)


def test_transform_init_from_json_and_to_json() raises:
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "def main() raises:\n"
        + "    @@@:\n"
        + "        var dump = @@@to_json()\n"
        + "        @@@init_from_json(dump)\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
    )
    assert_true("sqrrl__world_to_json(sqrrl__world)" in out)
    assert_true("sqrrl__init_from_json(sqrrl__world, dump)" in out)


def test_transform_json_markers_need_world() raises:
    """Every JSON marker needs 'sqrrl__world' opened first, same rule every
    other world-needing construct already enforces."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "def main() raises:\n"
        + "    var dump = @@@to_json()\n"
    )
    var raised = False
    try:
        _ = transform_source(
            src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
        )
    except:
        raised = True
    assert_true(raised)


def test_transform_end_init_from_json_without_begin_rejected() raises:
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "def main() raises:\n"
        + "    @@@:\n"
        + "        @@@end_init_from_json()\n"
    )
    var raised = False
    try:
        _ = transform_source(
            src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
        )
    except:
        raised = True
    assert_true(raised)


def test_transform_repeat_begin_init_from_json_without_end_rejected() raises:
    """A second `@@@begin_init_from_json` without an intervening `end` is a
    hard compile-time error (the conservative first cut -- see the M5
    plan's judgment call #2)."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "def main() raises:\n"
        + "    @@@:\n"
        + "        var dump = \"{}\"\n"
        + "        @@@begin_init_from_json(dump)\n"
        + "        @@@begin_init_from_json(dump)\n"
    )
    var raised = False
    try:
        _ = transform_source(
            src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
        )
    except:
        raised = True
    assert_true(raised)


def test_transform_plain_struct_field_declaration_rewrites() raises:
    """A hand-written plain struct's own `var @@owner: @@Employee` field
    declaration (no `=`, not a def parameter -- previously simply
    unreachable syntax, now the *only* thing that shape can mean, plan's
    §4) rewrites the *type* only -- the name stays bare (matches
    "constructed with plain Mojo": `Address(owner=@@alice)` needs a bare
    keyword parameter to match). A plain `var city: String` field (no `@@`
    at all) is untouched, passed through byte-for-byte like any other
    hand-written Mojo the compiler doesn't recognize."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()
    var plain_struct_names = Dict[String, Bool]()
    plain_struct_names["Address"] = True

    var src = String(
        "struct Address(Copyable, Movable, ImplicitlyDeletable):\n"
        + "    var city: String\n"
        + "    var @@owner: @@Employee\n"
    )
    var out = transform_source(
        src,
        relation_schema,
        struct_names,
        function_returns,
        unique_fields,
        indexed_fields,
        plain_struct_names=plain_struct_names,
    )
    assert_true("var city: String" in out)
    assert_true("var owner: sqrrl__Employee" in out)
    assert_false("@@owner" in out)
    assert_false("@@Employee" in out)


def test_transform_plain_struct_wrapped_relation_field_declaration_rewrites() raises:
    """A hand-written plain struct's own `var @@members: List[@@Employee]`
    field declaration -- a *wrapped* relation, not a bare one -- used to
    raise outright ("a wrapped/container relation field isn't supported
    as a hand-written struct's own field declaration yet"), an explicit,
    honest gap the code itself flagged. Renders the same way the bare
    case already does -- bare field name, wrapper kept as-is, only the
    relation-typed argument gets `sqrrl__`-prefixed -- mirroring the
    `ENTITY_PARAM` marker's own identical rendering for a function
    parameter/var-decl initializer, just without the name prefix (never
    applies to a field). `parse_entity_param`'s own scanner still only
    recognizes this single-wrapper, single-argument shape (`Wrapper[
    @@Type]`) -- a 2-argument wrapper (`Dict[@@K, V]`) or a relation
    nested inside a further container on a hand-written struct's own
    field declaration stays genuinely unsupported, a separate, narrower
    parser limitation this doesn't touch."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()
    var plain_struct_names = Dict[String, Bool]()
    plain_struct_names["Roster"] = True

    var src = String(
        "struct Roster(Movable, ImplicitlyDeletable):\n"
        + "    var @@members: List[@@Employee]\n"
    )
    var out = transform_source(
        src,
        relation_schema,
        struct_names,
        function_returns,
        unique_fields,
        indexed_fields,
        plain_struct_names=plain_struct_names,
    )
    assert_true("var members: List[sqrrl__Employee]" in out)
    assert_false("@@members" in out)
    assert_false("@@Employee" in out)


def test_transform_struct_field_referencing_plain_struct_renders_bare_type() raises:
    """A `@@struct`'s own field whose type is a discovered plain struct
    (`home: Address`, unmarked -- plan's Revision 2 point 1: only a
    relation-*shaped* reference is ever `@@`-marked) renders the plain
    struct's own bare name in its generated storage/setter type, and
    (since a hand-written struct is never guaranteed `ImplicitlyCopyable`)
    needs the same `var`+`^` move treatment `multi`'s own `Set[T]` field
    already established, not a bare copy-assignment."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Person"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()
    var plain_struct_names = Dict[String, Bool]()
    plain_struct_names["Address"] = True
    var plain_value_fields = Dict[String, Dict[String, String]]()
    plain_value_fields["Person"] = Dict[String, String]()
    plain_value_fields["Person"]["home"] = "Address"

    var src = String(
        "@@struct @@Person:\n"
        + "    name: String\n"
        + "    home: Address\n"
    )
    var out = transform_source(
        src,
        relation_schema,
        struct_names,
        function_returns,
        unique_fields,
        indexed_fields,
        plain_struct_names=plain_struct_names,
        plain_value_fields=plain_value_fields,
    )
    assert_true("var _home: Address" in out)
    assert_true("def set_home(mut self, var v: Address):" in out)
    assert_true("self._home = v^" in out)
    assert_true("def create(mut self, *, name: String, var home: Address)" in out)


def test_transform_real_plain_real_hop_chain_read_and_write() raises:
    """The plan's own worked example: `@@alice.home.city` (real -> plain
    leaf) and `@@alice.home.@@owner.name` (real -> plain -> real, hopping
    through an unmarked plain-value field then a marked relation field),
    plus writes at both depths -- direct field assignment throughout the
    plain-struct portion (`Address` has no generated setters), a real
    `set_<field>` only where the walk lands back on a real entity."""
    var relation_schema = Dict[String, Dict[String, String]]()
    relation_schema["Address"] = Dict[String, String]()
    relation_schema["Address"]["owner"] = "Employee"
    var struct_names = Dict[String, Bool]()
    struct_names["Employee"] = True
    struct_names["Person"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()
    var plain_struct_names = Dict[String, Bool]()
    plain_struct_names["Address"] = True
    var plain_value_fields = Dict[String, Dict[String, String]]()
    plain_value_fields["Person"] = Dict[String, String]()
    plain_value_fields["Person"]["home"] = "Address"
    plain_value_fields["Address"] = Dict[String, String]()
    plain_value_fields["Address"]["city"] = "String"
    plain_value_fields["Employee"] = Dict[String, String]()
    plain_value_fields["Employee"]["name"] = "String"

    var src = String(
        "def main() raises:\n"
        + "    @@@:\n"
        + "        var @@bob = @@@Employee { .name = \"Bob\" }\n"
        + "        var addr = Address(city = \"Springfield\", owner = @@bob)\n"
        + "        var @@alice = @@@Person { .name = \"Alice\", .home = addr }\n"
        + "        print(@@alice.home.city)\n"
        + "        print(@@alice.home.@@owner.name)\n"
        + "        @@alice.home.city = \"Shelbyville\"\n"
        + "        @@alice.home.@@owner = @@bob\n"
    )
    var out = transform_source(
        src,
        relation_schema,
        struct_names,
        function_returns,
        unique_fields,
        indexed_fields,
        plain_struct_names=plain_struct_names,
        plain_value_fields=plain_value_fields,
    )
    # Construction: the plain-struct-typed construct-field value gets `^`
    # (Address isn't ImplicitlyCopyable) -- and, separately, an `@@`-marked
    # argument inside ordinary hand-written Mojo (`Address(..., owner =
    # @@bob)`) rewrites correctly with zero construct-specific handling.
    assert_true('sqrrl__world.Person.create(name = "Alice", home = addr^)' in out)
    assert_true("Address(city = \"Springfield\", owner = sqrrl__bob)" in out)
    # Read chain: real -> plain (no deref) -> real (._inner[] again).
    assert_true("sqrrl__alice._inner[]._home.city" in out)
    assert_true("sqrrl__alice._inner[]._home.owner._inner[]._name" in out)
    # Write chain: direct assignment on the plain struct's own bare field,
    # at both depths (no set_<field> -- Address has no generated setters).
    assert_true('sqrrl__alice._inner[]._home.city = "Shelbyville";' in out)
    assert_true("sqrrl__alice._inner[]._home.owner = sqrrl__bob;" in out)


def test_transform_generic_plain_struct_field_access_not_treated_as_container() raises:
    """A generic plain struct's own instantiation (`Tagged[String]`) is
    bracket-shaped, same as a real DSL container (`List[...]`) -- the
    access-chain walk has to tell them apart (checking `plain_struct_names`
    against the bracketed type's own wrapper name *before* treating a
    step's owner as a container), or a plain field read through it
    (`.meta.label`) would incorrectly demand container iteration/indexing
    instead of an ordinary field hop."""
    var relation_schema = Dict[String, Dict[String, String]]()
    var struct_names = Dict[String, Bool]()
    struct_names["Person"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()
    var plain_struct_names = Dict[String, Bool]()
    plain_struct_names["Tagged"] = True
    var plain_value_fields = Dict[String, Dict[String, String]]()
    plain_value_fields["Person"] = Dict[String, String]()
    plain_value_fields["Person"]["meta"] = "Tagged[String]"
    plain_value_fields["Tagged"] = Dict[String, String]()
    plain_value_fields["Tagged"]["label"] = "String"

    var src = String(
        "def main() raises:\n"
        + "    @@@:\n"
        + "        var @@alice = @@@Person { .name = \"Alice\" }\n"
        + "        print(@@alice.meta.label)\n"
    )
    var out = transform_source(
        src,
        relation_schema,
        struct_names,
        function_returns,
        unique_fields,
        indexed_fields,
        plain_struct_names=plain_struct_names,
        plain_value_fields=plain_value_fields,
    )
    assert_true("sqrrl__alice._inner[]._meta.label" in out)


def test_transform_for_loop_over_container_field_registers_element_type() raises:
    """`for @@x in @@entity.@@container_field:` -- unlike `for @@x in
    @@Type.all()`/a table-level List-returning call (already wired), an
    ordinary field *read* reaching the container-shaped terminal branch
    was never registering `pending_for_loop_decl`'s element type at all,
    so `@@x.name` inside the loop body failed with "was never constructed
    via @@Type{...}" -- confirmed missing via a real end-to-end run before
    this fix. Covers both a relation-wrapped field (`@@members`) and an
    ordinary plain-value one (`plain_value_fields`, not `relation_schema`)
    to prove the fix applies on both of the terminal-read's two branches."""
    var relation_schema = Dict[String, Dict[String, String]]()
    relation_schema["Department"] = Dict[String, String]()
    relation_schema["Department"]["members"] = "List[Employee]"
    var struct_names = Dict[String, Bool]()
    struct_names["Department"] = True
    struct_names["Employee"] = True
    var function_returns = Dict[String, String]()
    var unique_fields = Dict[String, List[String]]()
    var indexed_fields = Dict[String, List[String]]()

    var src = String(
        "def foo(@@eng: @@Department) raises:\n"
        + "    for @@e in @@eng.@@members:\n"
        + "        print(@@e.name)\n"
    )
    var out = transform_source(
        src, relation_schema, struct_names, function_returns, unique_fields, indexed_fields
    )
    assert_true("for sqrrl__e in " in out)
    assert_true("sqrrl__e._inner[]._name" in out)


def test_check_no_relation_cycles_through_plain_struct_rejected() raises:
    """A relation cycle running *through* a hand-written plain struct's
    own field is rejected too (plan's §3): `Person.home: Address`,
    `Address.owner: @@Person` -- `collect_relation_targets`'s own
    recursion flattens Address's edges onto whichever real struct embeds
    it, so this is just as real a cycle as one running only through
    `@@struct` fields directly."""
    var person_fields = List[Field]()
    person_fields.append(Field(name="home", type_str="Address", modifier=FieldModifier.NONE, is_stats=False))
    var structs = List[DiscoveredStruct]()
    structs.append(DiscoveredStruct(module_path="main", parsed=ParsedStruct(name="Person", fields=person_fields^)))
    var discovery = DiscoveryResult(structs^, Dict[String, String]())

    var address_fields = List[Field]()
    address_fields.append(Field(name="owner", type_str="@@Person", modifier=FieldModifier.NONE, is_stats=False))
    var plain_struct_fields = Dict[String, List[Field]]()
    plain_struct_fields["Address"] = address_fields^

    var raised = False
    try:
        check_no_relation_cycles(discovery, plain_struct_fields)
    except:
        raised = True
    assert_true(raised)


def test_check_no_relation_cycles_through_dict_value_position_rejected() raises:
    """A relation cycle running through a `Dict`'s own *value* position
    (`Department.leads: Dict[String, @@Employee]`, `Employee.dept:
    @@Department`) is caught too -- `collect_relation_targets`'s own walk
    only used to follow a container's first type argument, so a cycle
    reachable solely through a later one would previously have been
    entirely invisible to this exact check (on top of such a field being
    rejected at parse time in the first place)."""
    var employee_fields = List[Field]()
    employee_fields.append(Field(name="dept", type_str="@@Department", modifier=FieldModifier.NONE, is_stats=False))
    var department_fields = List[Field]()
    department_fields.append(
        Field(name="leads", type_str="Dict[String, @@Employee]", modifier=FieldModifier.NONE, is_stats=False)
    )
    var structs = List[DiscoveredStruct]()
    structs.append(DiscoveredStruct(module_path="main", parsed=ParsedStruct(name="Employee", fields=employee_fields^)))
    structs.append(DiscoveredStruct(module_path="main", parsed=ParsedStruct(name="Department", fields=department_fields^)))
    var discovery = DiscoveryResult(structs^, Dict[String, String]())

    var raised = False
    try:
        check_no_relation_cycles(discovery, Dict[String, List[Field]]())
    except:
        raised = True
    assert_true(raised)


def test_topo_sort_orders_after_a_wrapped_relation_target_too() raises:
    """`topo_sort_structs` has to place `Person` before `Team` here, even
    though `Team`'s *only* relation field is `@@members: List[@@Person]`
    -- a *wrapped* one. `relation_schema["Team"]["members"]` stores the
    whole container-shaped, relation-stripped text (`"List[Person]"`), not
    the bare target name a *bare* relation field's own entry already is
    (`"Department"` for `@@dept: @@Department`) -- `_visit_topo` used to
    check that text against `by_name` (keyed by bare struct names)
    directly, so `"List[Person]" in by_name` was always `False` and the
    whole dependency edge was silently dropped, letting `Team` sort
    *before* `Person` with no cycle ever existing to reject it. Confirmed
    as a real bug (not a hypothetical one) via a real crash during reload
    (`EntityStorage.handle_for: id is no longer live`) once a project
    (the kitchen-sink example) had a struct whose only live dependency
    edges were wrapped ones."""
    var person_fields = List[Field]()
    person_fields.append(Field(name="name", type_str="String", modifier=FieldModifier.UNIQUE, is_stats=False))
    var team_fields = List[Field]()
    team_fields.append(Field(name="name", type_str="String", modifier=FieldModifier.UNIQUE, is_stats=False))
    team_fields.append(
        Field(name="members", type_str="List[@@Person]", modifier=FieldModifier.NONE, is_stats=False)
    )
    var structs = List[DiscoveredStruct]()
    structs.append(DiscoveredStruct(module_path="main", parsed=ParsedStruct(name="Team", fields=team_fields^)))
    structs.append(DiscoveredStruct(module_path="main", parsed=ParsedStruct(name="Person", fields=person_fields^)))
    var discovery = DiscoveryResult(structs^, Dict[String, String]())
    var relation_schema = build_relation_schema(discovery)

    var order = topo_sort_structs(discovery, relation_schema)
    var person_index = -1
    var team_index = -1
    for i in range(len(order)):
        if order[i].parsed.name == "Person":
            person_index = i
        if order[i].parsed.name == "Team":
            team_index = i
    assert_true(person_index >= 0 and team_index >= 0)
    assert_true(person_index < team_index)


def _employee_department_discovery(member_wrapper: String) -> List[DiscoveredStruct]:
    """Shared fixture for the two `emit_json_module` tests below: `Employee`
    (a bare `unique name: String`) and `Department` (`unique name: String`
    plus a wrapped-relation `@@members: <member_wrapper>[@@Employee]`) --
    `Department` declared *after* `Employee` in both `discovery_structs`
    and (matching `driver/topo_order.mojo`'s own dependency-first
    contract) the `topo_order` list `emit_json_module` also takes."""
    var employee_fields = List[Field]()
    employee_fields.append(Field(name="name", type_str="String", modifier=FieldModifier.UNIQUE, is_stats=False))
    var department_fields = List[Field]()
    department_fields.append(Field(name="name", type_str="String", modifier=FieldModifier.UNIQUE, is_stats=False))
    department_fields.append(
        Field(name="members", type_str=member_wrapper + "[@@Employee]", modifier=FieldModifier.NONE, is_stats=False)
    )
    var structs = List[DiscoveredStruct]()
    structs.append(DiscoveredStruct(module_path="main", parsed=ParsedStruct(name="Employee", fields=employee_fields^)))
    structs.append(DiscoveredStruct(module_path="main", parsed=ParsedStruct(name="Department", fields=department_fields^)))
    return structs^


def test_emit_json_module_wrapped_relation_list_round_trips() raises:
    """`@@container` JSON support: a `List[@@Employee]` field dumps as a
    plain JSON array of bare ids (uniform iteration, same shape `multi`
    already has) and reconstructs via `.append(...)` into a real `List`,
    preserving order -- the one wrapper verified safe to both build this
    way *and* construct via ordinary `Table.create()` (`List[T]` isn't
    `ImplicitlyCopyable`, but `.take()`/`var`+`^` sidesteps that either
    way)."""
    var structs = _employee_department_discovery("List")
    var out = emit_json_module(structs, structs)
    # Dump: goes through the recursive `_dump_value_expr` -- `fv_
    # <field>` is the per-field getter ref (still field-suffixed, so a
    # struct with more than one container-shaped field can't collide),
    # `ds1`/`dv1` are `_dump_value_expr`'s own uniquely-
    # numbered locals (not per-field -- there's only one container in
    # this field's own dump, so it's always "1").
    assert_true("ref fv_members = e._inner[].get_sqrrl__members()" in out)
    assert_true("for dv1 in fv_members:" in out)
    assert_true("ds1 += String(dv1.id())" in out)
    # Reload: builds a real List via .append(...), not Set/.add(...) --
    # the id-parse is inlined directly into the call (no separate local),
    # since `_parse_value_expr` returns a plain expression for a relation
    # element. `nc1` is the recursive parser's own uniquely-
    # numbered local (`tmp_id`), not a per-field name -- there's only one
    # container in this field's own parse, so it's always "1".
    assert_true("var nc1 = List[sqrrl__Employee]()" in out)
    assert_true(
        "nc1.append(sqrrl__Employee(sqrrl__tbl_Employee.storage[].handle_for(UInt32(sc.parse_json_int()))))"
        in out
    )
    assert_true("parsed_members = nc1^" in out)


def test_emit_json_module_wrapped_relation_set_round_trips() raises:
    """Parity with rw_squirrel_1/2: an ordinary (non-`multi`) `Set[@@Employee]`
    field is now fully supported too, via `.add(...)` instead of
    `.append(...)` -- the *only* difference from `List`'s own reload code,
    confirming `_parse_value_expr` really does share one implementation
    across both wrappers."""
    var structs = _employee_department_discovery("Set")
    var out = emit_json_module(structs, structs)
    assert_true("var nc1 = Set[sqrrl__Employee]()" in out)
    assert_true(
        "nc1.add(sqrrl__Employee(sqrrl__tbl_Employee.storage[].handle_for(UInt32(sc.parse_json_int()))))"
        in out
    )
    assert_true("parsed_members = nc1^" in out)


def test_emit_json_module_wrapped_relation_optional_round_trips() raises:
    """Parity with rw_squirrel_1/2: `Optional[@@Employee]` -- not iterable the
    same way as `List`/`Set`, so it gets its own dump/reload shape (the
    element's own JSON value, or `null` for absence) rather than the
    array-of-elements one."""
    var structs = _employee_department_discovery("Optional")
    var out = emit_json_module(structs, structs)
    # Dump: null-or-value, not an array.
    assert_true("ref fv_members = e._inner[].get_sqrrl__members()" in out)
    assert_true("if fv_members:" in out)
    assert_true("ds1 = String(fv_members.value().id())" in out)
    assert_true('ds1 = "null"' in out)
    # Reload: null -> empty Optional, else the parsed element wrapped in one.
    assert_true('if sc.try_consume_literal("null"):' in out)
    assert_true("nc1 = Optional[sqrrl__Employee]()" in out)
    assert_true(
        "nc1 = Optional[sqrrl__Employee](sqrrl__Employee(sqrrl__tbl_Employee.storage[].handle_for(UInt32(sc.parse_json_int()))))"
        in out
    )
    assert_true("parsed_members = nc1^" in out)


def test_emit_json_module_plain_leaf_container_round_trips() raises:
    """A plain (non-relation) container field -- `tags: List[String]`, no
    `@@` anywhere -- routes through the shared, generic `sqrrl__to_json`/
    `sqrrl__from_json[T]` dispatcher rather than per-field inline codegen
    (the JSON-container-dispatch rearchitecture): the field itself is just
    a uniform dispatcher call, and the dispatch table gets its own `List[
    String]` branch built from the built-in `sqrrl__List_json_to_list`/
    `_from_list` adapters plus the shared `list_to_json`/`list_from_json`
    helpers -- no per-project hand-rolled parse loop any more."""
    var employee_fields = List[Field]()
    employee_fields.append(Field(name="name", type_str="String", modifier=FieldModifier.UNIQUE, is_stats=False))
    employee_fields.append(Field(name="tags", type_str="List[String]", modifier=FieldModifier.NONE, is_stats=False))
    var structs = List[DiscoveredStruct]()
    structs.append(DiscoveredStruct(module_path="main", parsed=ParsedStruct(name="Employee", fields=employee_fields^)))
    var out = emit_json_module(structs, structs)
    # Field-level: both directions are a single uniform dispatcher call.
    assert_true("out += sqrrl__to_json(e._inner[].get_tags())" in out)
    assert_true("parsed_tags = sqrrl__from_json[List[String]](sc)" in out)
    # The dispatch table itself has a branch built from the built-in List
    # adapters and the shared list_to_json/list_from_json helpers.
    assert_true(
        "elif T == List[String]:\n        return list_to_json(sqrrl__List_json_to_list(rebind[List[String]](value)))"
        in out
    )
    assert_true(
        "elif T == List[String]:\n        return sqrrl__movable_rebind[List[String], T](sqrrl__List_json_from_list"
        "(list_from_json[String](sc)))"
        in out
    )


def test_emit_json_module_dict_field_round_trips() raises:
    """`Dict[@@Employee, String]` -- relation-keyed, not just plain-leaf-
    keyed -- round-trips as an array of `[key,value]` pairs, mirroring
    this codebase's own existing `[id, json]` pairing convention rather
    than a JSON object (which can't represent a non-string key at all)."""
    var employee_fields = List[Field]()
    employee_fields.append(Field(name="name", type_str="String", modifier=FieldModifier.UNIQUE, is_stats=False))
    var department_fields = List[Field]()
    department_fields.append(Field(name="name", type_str="String", modifier=FieldModifier.UNIQUE, is_stats=False))
    department_fields.append(
        Field(name="scores", type_str="Dict[@@Employee, String]", modifier=FieldModifier.NONE, is_stats=False)
    )
    var structs = List[DiscoveredStruct]()
    structs.append(DiscoveredStruct(module_path="main", parsed=ParsedStruct(name="Employee", fields=employee_fields^)))
    structs.append(DiscoveredStruct(module_path="main", parsed=ParsedStruct(name="Department", fields=department_fields^)))
    var out = emit_json_module(structs, structs)
    # Dump: array of [key,value] pairs, both sides through sqrrl__to_json.
    assert_true("ref fv_scores = e._inner[].get_sqrrl__scores()" in out)
    assert_true("for de1 in fv_scores.items():" in out)
    assert_true(
        'ds1 += "[" + String(de1.key.id()) + "," + sqrrl__to_json(de1.value) + "]"'
        in out
    )
    # Reload: builds a real Dict, parsing the relation key and leaf value
    # each through the same recursive dispatch.
    assert_true("var nc1 = Dict[sqrrl__Employee, String]()" in out)
    assert_true(
        "var nck1 = sqrrl__Employee(sqrrl__tbl_Employee.storage[].handle_for(UInt32(sc.parse_json_int())))"
        in out
    )
    assert_true("nc1[nck1] = sc.parse_json_string()" in out)
    assert_true("parsed_scores = nc1^" in out)


def test_emit_json_module_dict_field_relation_in_value_position_round_trips() raises:
    """`Dict[String, @@Employee]` -- a relation in the *value* position,
    not the key -- round-trips correctly, and (the actual bug this test
    guards) `Department`'s own `from_json_with_id` correctly receives
    `Employee`'s sibling table. `_relation_target_base_name`'s own walk
    only ever followed a container's *first* type argument, so a relation
    reachable only through a later one was invisible to sibling-table
    discovery even once `is_wrapped_relation_type` itself was widened to
    notice it at parse time -- `_relation_target_base_names` (plural) is
    the fix, collecting every target at any position/depth."""
    var employee_fields = List[Field]()
    employee_fields.append(Field(name="name", type_str="String", modifier=FieldModifier.UNIQUE, is_stats=False))
    var department_fields = List[Field]()
    department_fields.append(Field(name="name", type_str="String", modifier=FieldModifier.UNIQUE, is_stats=False))
    department_fields.append(
        Field(name="leads", type_str="Dict[String, @@Employee]", modifier=FieldModifier.NONE, is_stats=False)
    )
    var structs = List[DiscoveredStruct]()
    structs.append(DiscoveredStruct(module_path="main", parsed=ParsedStruct(name="Employee", fields=employee_fields^)))
    structs.append(DiscoveredStruct(module_path="main", parsed=ParsedStruct(name="Department", fields=department_fields^)))
    var out = emit_json_module(structs, structs)
    # The actual bug: Department's own from_json_with_id must receive
    # Employee's sibling table, even though the relation sits in the
    # Dict's value position, not its key.
    assert_true(
        "def sqrrl__Department_from_json_with_id(table: sqrrl__DepartmentTable, sqrrl__tbl_Employee:"
        " sqrrl__EmployeeTable, id: UInt32, mut sc: sqrrl__JsonScanner)"
        in out
    )
    assert_true("var nc1 = Dict[String, sqrrl__Employee]()" in out)
    assert_true("nc1[nck1] = sqrrl__Employee(sqrrl__tbl_Employee.storage[].handle_for(UInt32(sc.parse_json_int())))" in out)
    assert_true("parsed_leads = nc1^" in out)


def test_emit_json_module_dict_field_relation_in_both_positions_round_trips() raises:
    """`Dict[@@Employee, @@Department]` -- a *distinct* relation in each
    position at once -- both of `Company`'s own sibling tables get
    discovered and threaded through, not just the first one found."""
    var employee_fields = List[Field]()
    employee_fields.append(Field(name="name", type_str="String", modifier=FieldModifier.UNIQUE, is_stats=False))
    var department_fields = List[Field]()
    department_fields.append(Field(name="name", type_str="String", modifier=FieldModifier.UNIQUE, is_stats=False))
    var company_fields = List[Field]()
    company_fields.append(Field(name="name", type_str="String", modifier=FieldModifier.UNIQUE, is_stats=False))
    company_fields.append(
        Field(
            name="assignments", type_str="Dict[@@Employee, @@Department]", modifier=FieldModifier.NONE, is_stats=False
        )
    )
    var structs = List[DiscoveredStruct]()
    structs.append(DiscoveredStruct(module_path="main", parsed=ParsedStruct(name="Employee", fields=employee_fields^)))
    structs.append(DiscoveredStruct(module_path="main", parsed=ParsedStruct(name="Department", fields=department_fields^)))
    structs.append(DiscoveredStruct(module_path="main", parsed=ParsedStruct(name="Company", fields=company_fields^)))
    var out = emit_json_module(structs, structs)
    assert_true(
        "def sqrrl__Company_from_json_with_id(table: sqrrl__CompanyTable, sqrrl__tbl_Employee: sqrrl__EmployeeTable,"
        " sqrrl__tbl_Department: sqrrl__DepartmentTable, id: UInt32, mut sc: sqrrl__JsonScanner)"
        in out
    )
    assert_true("var nck1 = sqrrl__Employee(sqrrl__tbl_Employee.storage[].handle_for(UInt32(sc.parse_json_int())))" in out)
    assert_true(
        "nc1[nck1] = sqrrl__Department(sqrrl__tbl_Department.storage[].handle_for(UInt32(sc.parse_json_int())))" in out
    )


def test_emit_json_module_nested_container_round_trips() raises:
    """A further-nested container as an element (`List[List[String]]`) is
    fully supported at arbitrary depth via the shared dispatcher (the
    JSON-container-dispatch rearchitecture): the field itself is a single
    uniform dispatcher call for the *outer* `List[List[String]]`, whose
    own dispatch-table branch converts to/from a generic `List[List[
    String]]` via `list_to_json`/`list_from_json` -- the *inner* `List[
    String]` element then recurses back into `sqrrl__to_json`/`sqrrl__
    from_json[T]` uniformly too, needing its own separate dispatch-table
    branch (registered independently by the same collection walk that
    found the outer one, since `_collect_dispatch_types` recurses into a
    container's own element types)."""
    var employee_fields = List[Field]()
    employee_fields.append(Field(name="name", type_str="String", modifier=FieldModifier.UNIQUE, is_stats=False))
    employee_fields.append(
        Field(name="groups", type_str="List[List[String]]", modifier=FieldModifier.NONE, is_stats=False)
    )
    var structs = List[DiscoveredStruct]()
    structs.append(DiscoveredStruct(module_path="main", parsed=ParsedStruct(name="Employee", fields=employee_fields^)))
    var out = emit_json_module(structs, structs)
    assert_true("out += sqrrl__to_json(e._inner[].get_groups())" in out)
    assert_true("parsed_groups = sqrrl__from_json[List[List[String]]](sc)" in out)
    # Both the outer and the inner List each get their own dispatch-table
    # branch -- confirms the collection walk recurses into elements.
    assert_true(
        "elif T == List[List[String]]:\n        return list_to_json(sqrrl__List_json_to_list(rebind[List[List[String]]]"
        "(value)))"
        in out
    )
    assert_true(
        "elif T == List[String]:\n        return list_to_json(sqrrl__List_json_to_list(rebind[List[String]](value)))"
        in out
    )


def test_emit_json_module_custom_container_wrapper_uses_escape_hatch() raises:
    """A custom, single-type-argument wrapper (anything other than
    `List`/`Set`/`Optional`/`Dict`) has neither a guaranteed no-arg
    constructor (a `@fieldwise_init` struct's own synthesized `__init__`
    takes every field, confirmed via a real compile) nor a known build-up
    method or `__iter__` -- the field itself is a single uniform
    dispatcher call, same as any other container; the dispatch table's
    own branch for it converts to/from a generic `List` via the exact
    same hand-written `sqrrl__<Wrapper>_json_to_list`/`_json_from_list`
    escape-hatch companions this project has always required (unchanged
    contract, just called from a dispatch-table branch now instead of
    inline per-field code), feeding into the shared `list_to_json`/`list_
    from_json` helpers. Also confirms the corresponding import line for
    both companions (plus the wrapper type itself) is still emitted,
    sourced from whichever struct's own module first referenced the
    wrapper -- the one piece of this escape hatch with no other way to be
    discovered."""
    var employee_fields = List[Field]()
    employee_fields.append(Field(name="name", type_str="String", modifier=FieldModifier.UNIQUE, is_stats=False))
    employee_fields.append(Field(name="tags", type_str="Ring[String]", modifier=FieldModifier.NONE, is_stats=False))
    var structs = List[DiscoveredStruct]()
    structs.append(DiscoveredStruct(module_path="main", parsed=ParsedStruct(name="Employee", fields=employee_fields^)))
    var out = emit_json_module(structs, structs)
    assert_true("from main import Ring, sqrrl__Ring_json_to_list, sqrrl__Ring_json_from_list" in out)
    assert_true("out += sqrrl__to_json(e._inner[].get_tags())" in out)
    assert_true("parsed_tags = sqrrl__from_json[Ring[String]](sc)" in out)
    assert_true(
        "elif T == Ring[String]:\n        return list_to_json(sqrrl__Ring_json_to_list(rebind[Ring[String]](value)))"
        in out
    )
    assert_true(
        "elif T == Ring[String]:\n        return sqrrl__movable_rebind[Ring[String], T](sqrrl__Ring_json_from_list"
        "(list_from_json[String](sc)))"
        in out
    )


def test_emit_json_module_custom_two_argument_wrapper_uses_pairs_escape_hatch() raises:
    """A custom, two-type-argument wrapper (anything other than `Dict`)
    now shares the exact same escape hatch `Dict` itself uses -- an array
    of `[key,value]` pairs -- via hand-written `sqrrl__<Wrapper>_json_to_
    pairs`/`_json_from_pairs` companions instead of `Dict`'s own native
    `[]=`/`.items()`. The field itself is a single uniform dispatcher
    call, same as any other container; the dispatch table's own branch
    converts to/from an ordinary `List[Tuple[K, V]]` via `pairs_to_json`/
    `pairs_from_json`, mirroring the one-argument custom-wrapper case
    exactly. Also confirms the import line picks the `_to_pairs`/`_from_
    pairs` suffix (not `_to_list`/`_from_list`) based on the wrapper's
    own two-argument arity."""
    var employee_fields = List[Field]()
    employee_fields.append(Field(name="name", type_str="String", modifier=FieldModifier.UNIQUE, is_stats=False))
    employee_fields.append(
        Field(name="grid", type_str="Grid[String, Int]", modifier=FieldModifier.NONE, is_stats=False)
    )
    var structs = List[DiscoveredStruct]()
    structs.append(DiscoveredStruct(module_path="main", parsed=ParsedStruct(name="Employee", fields=employee_fields^)))
    var out = emit_json_module(structs, structs)
    assert_true("from main import Grid, sqrrl__Grid_json_to_pairs, sqrrl__Grid_json_from_pairs" in out)
    assert_true("out += sqrrl__to_json(e._inner[].get_grid())" in out)
    assert_true("parsed_grid = sqrrl__from_json[Grid[String, Int]](sc)" in out)
    assert_true(
        "elif T == Grid[String, Int]:\n        return pairs_to_json(sqrrl__Grid_json_to_pairs(rebind[Grid[String, Int]](value)))"
        in out
    )
    assert_true(
        "elif T == Grid[String, Int]:\n        return sqrrl__movable_rebind[Grid[String, Int], T](sqrrl__Grid_json_from_pairs"
        "(pairs_from_json[String, Int](sc)))"
        in out
    )


def test_emit_json_module_three_argument_wrapper_rejected() raises:
    """The one remaining genuinely-unsupported shape: a 3+-argument
    wrapper has no defined JSON shape at all (unlike a 2-argument one's
    well-defined key/value pairing) -- stays a clear codegen-time error,
    not silently mishandled."""
    var employee_fields = List[Field]()
    employee_fields.append(Field(name="name", type_str="String", modifier=FieldModifier.UNIQUE, is_stats=False))
    employee_fields.append(
        Field(name="triple", type_str="Triple[String, Int, Bool]", modifier=FieldModifier.NONE, is_stats=False)
    )
    var structs = List[DiscoveredStruct]()
    structs.append(DiscoveredStruct(module_path="main", parsed=ParsedStruct(name="Employee", fields=employee_fields^)))
    var raised = False
    try:
        _ = emit_json_module(structs, structs)
    except:
        raised = True
    assert_true(raised)


def test_emit_json_module_generic_plain_struct_relation_field_gets_monomorphized_companion() raises:
    """A generic plain struct's own bare type-parameter field (`Box[T]`'s
    `value: T`) can't be reconstructed by the ordinary, once-per-struct
    generic `sqrrl__Box_from_json[T]` companion whenever some real caller
    instantiates it with a relation (`Box[@@Employee]`) -- that companion
    is generated from `Box`'s own raw, unsubstituted fields, so its body
    routes `value: T` through the shared `sqrrl__from_json[T]` dispatch
    table, which never has (and structurally can't have) a branch for a
    relation. `_plain_struct_from_json_call` detects this via `_type_
    involves_relation` (substituting `T -> Employee` into `Box`'s own
    field list before checking) and routes to a distinct, fully-concrete
    `sqrrl__Box_Employee_from_json` companion instead -- generated from
    `Box`'s substituted field list, so its own `value` field is just an
    ordinary relation field at that point, with `Employee`'s own sibling
    table threaded through both the call site and the companion's own
    signature. The ordinary generic companion is still emitted alongside
    it, unchanged, for any other -- relation-free -- instantiation of
    `Box` reachable project-wide."""
    var box_fields = List[Field]()
    box_fields.append(Field(name="value", type_str="T", modifier=FieldModifier.NONE, is_stats=False))
    var plain_fields = Dict[String, List[Field]]()
    plain_fields["Box"] = box_fields^
    var plain_module_of = Dict[String, String]()
    plain_module_of["Box"] = "box_module"
    var plain_is_generic = Dict[String, Bool]()
    plain_is_generic["Box"] = True
    var plain_type_params = Dict[String, List[TypeParam]]()
    var box_type_params = List[TypeParam]()
    box_type_params.append(TypeParam(name="T", bound="Copyable & ImplicitlyDeletable"))
    plain_type_params["Box"] = box_type_params^
    var plain_struct_discovery = PlainStructDiscovery(
        plain_fields^, plain_module_of^, plain_is_generic^, plain_type_params^
    )

    var employee_fields = List[Field]()
    employee_fields.append(Field(name="name", type_str="String", modifier=FieldModifier.UNIQUE, is_stats=False))
    var department_fields = List[Field]()
    department_fields.append(Field(name="name", type_str="String", modifier=FieldModifier.UNIQUE, is_stats=False))
    department_fields.append(Field(name="box", type_str="Box[@@Employee]", modifier=FieldModifier.NONE, is_stats=False))
    var structs = List[DiscoveredStruct]()
    structs.append(DiscoveredStruct(module_path="main", parsed=ParsedStruct(name="Employee", fields=employee_fields^)))
    structs.append(DiscoveredStruct(module_path="main", parsed=ParsedStruct(name="Department", fields=department_fields^)))

    var out = emit_json_module(structs, structs, plain_struct_discovery)

    assert_true("from box_module import Box\n" in out)
    # The ordinary generic companion is still emitted, untouched -- it's
    # what any relation-free `Box[...]` instantiation still uses.
    assert_true(
        "def sqrrl__Box_from_json[T: Copyable & ImplicitlyDeletable](mut sc: sqrrl__JsonScanner) raises -> Box[T]:"
        in out
    )
    assert_true("parsed_value = sqrrl__from_json[T](sc)" in out)
    # The new monomorphized companion -- fully concrete, `Employee`'s own
    # sibling table threaded through its signature, `value` dispatched as
    # an ordinary relation field (no dispatch-table call at all).
    assert_true(
        "def sqrrl__Box_Employee_from_json(sqrrl__tbl_Employee: sqrrl__EmployeeTable, mut sc: sqrrl__JsonScanner)"
        " raises -> Box[sqrrl__Employee]:"
        in out
    )
    assert_true(
        "parsed_value = sqrrl__Employee(sqrrl__tbl_Employee.storage[].handle_for(rid_value))" in out
    )
    # The call site, inside Department's own `from_json_with_id`, routes
    # to the monomorphized companion -- not the generic one -- passing
    # `Employee`'s own sibling table it already has in scope.
    assert_true("parsed_box = sqrrl__Box_Employee_from_json(sqrrl__tbl_Employee, sc)" in out)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
