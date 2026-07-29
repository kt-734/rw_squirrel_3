from squirrel_runtime.entity_storage import EntityStorage
from squirrel_runtime.index import PlainIndex, UniqueIndex, MultiIndex, OrderedIndex
from std.memory import ArcPointer
from std.hashlib import Hasher
from std.collections import Set
from std.os import abort
from sqrrl__world import sqrrl___init, sqrrl___World

def main() raises:
    var sqrrl___world = sqrrl___init()
    try:
        var sqrrl__eng = sqrrl___world.Department.create(name = "Engineering")
        var sqrrl__sales = sqrrl___world.Department.create(name = "Sales")
        var sqrrl__alice = sqrrl___world.Employee.create(name = "Alice", years_employed = 5, salary = 90000.0, sqrrl__dept = sqrrl__eng)
        var sqrrl__bob = sqrrl___world.Employee.create(name = "Bob", years_employed = 2, salary = 70000.0, sqrrl__dept = sqrrl__eng)
        var sqrrl__carol = sqrrl___world.Employee.create(name = "Carol", years_employed = 8, salary = 120000.0, sqrrl__dept = sqrrl__sales)
        var sqrrl__dave = sqrrl___world.Employee.create(name = "Dave", years_employed = 5, salary = 85000.0, sqrrl__dept = sqrrl__sales)

        print("exact match (5 years):", len(sqrrl___world.Employee.for_years_employed(5)))
        print("more than 3 years:", len(sqrrl___world.Employee.for_years_employed_greater_than(3)))
        print("at least 5 years:", len(sqrrl___world.Employee.for_years_employed_at_least(5)))
        print("less than 5 years:", len(sqrrl___world.Employee.for_years_employed_less_than(5)))
        print("at most 5 years:", len(sqrrl___world.Employee.for_years_employed_at_most(5)))
        print("3 to 6 years inclusive:", len(sqrrl___world.Employee.for_years_employed_between(3, 6)))

        # direct index + chain off a table-level range-query call, no
        # intermediate variable required
        print("first with 3-6 years:", sqrrl___world.Employee.for_years_employed_between(3, 6)[0]._inner[]._name)

        var sqrrl__ranged = sqrrl___world.Employee.for_years_employed_between(0, 100)
        for sqrrl__e in sqrrl__ranged:
            print("in range:", sqrrl__e._inner[]._name, sqrrl__e._inner[]._years_employed)

        sqrrl__bob._inner[].set_years_employed(9);
        print("after raise, more than 8 years:", len(sqrrl___world.Employee.for_years_employed_greater_than(8)))

        print("total salary:", sqrrl___world.Employee.sum_salary())
        print("average salary:", sqrrl___world.Employee.avg_salary())
        print("min years employed:", sqrrl___world.Employee.min_years_employed())
        print("max years employed:", sqrrl___world.Employee.max_years_employed())
        print("median years employed:", sqrrl___world.Employee.median_years_employed())
        print("median salary:", sqrrl___world.Employee.median_salary())

        print("eng total salary:", sqrrl___world.Employee.sum_salary_for_sqrrl__dept(sqrrl__eng))
        print("sales average salary:", sqrrl___world.Employee.avg_salary_for_sqrrl__dept(sqrrl__sales))

        var sqrrl__salary_by_dept = sqrrl___world.Employee.sum_salary_by_sqrrl__dept()
        print("departments with salary totals:", len(sqrrl__salary_by_dept))

        print("distinct years employed:", len(sqrrl___world.Employee.distinct_years_employed()))
        print("count with 5 years:", sqrrl___world.Employee.count_for_years_employed(5))

        var sqrrl__by_dept = sqrrl___world.Employee.group_by_sqrrl__dept()
        print("departments with employees:", len(sqrrl__by_dept))

        print("alice", sqrrl__alice._inner[]._name, "bob", sqrrl__bob._inner[]._name, "carol", sqrrl__carol._inner[]._name, "dave", sqrrl__dave._inner[]._name)
    finally:
        sqrrl___world.sqrrl__check_no_leaks()
