from company import sqrrl__EmployeeTable
from company import sqrrl__PersonTable
from std.os import abort


struct sqrrl___World(Movable):
    var Employee: sqrrl__EmployeeTable
    var Person: sqrrl__PersonTable

    def __init__(out self):
        self.Employee = sqrrl__EmployeeTable()
        self.Person = sqrrl__PersonTable()

    def sqrrl__check_no_leaks(mut self):
        var leaked_Employee = self.Employee.count()
        if leaked_Employee > 0:
            abort("LeakedEntities: 'Employee' still has " + String(leaked_Employee) + " live entities outside sqrrl___world -- something external still references them")
        var leaked_Person = self.Person.count()
        if leaked_Person > 0:
            abort("LeakedEntities: 'Person' still has " + String(leaked_Person) + " live entities outside sqrrl___world -- something external still references them")

    def __del__(deinit self):
        self.sqrrl__check_no_leaks()


def sqrrl___init() -> sqrrl___World:
    return sqrrl___World()
