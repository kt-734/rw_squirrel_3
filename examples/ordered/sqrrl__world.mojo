from company import sqrrl__DepartmentTable
from company import sqrrl__EmployeeTable
from std.os import abort


struct sqrrl___World(Movable):
    var Department: sqrrl__DepartmentTable
    var Employee: sqrrl__EmployeeTable

    def __init__(out self):
        self.Department = sqrrl__DepartmentTable()
        self.Employee = sqrrl__EmployeeTable()

    def sqrrl__check_no_leaks(mut self):
        var leaked_Department = self.Department.count()
        if leaked_Department > 0:
            abort("LeakedEntities: 'Department' still has " + String(leaked_Department) + " live entities outside sqrrl___world -- something external still references them")
        var leaked_Employee = self.Employee.count()
        if leaked_Employee > 0:
            abort("LeakedEntities: 'Employee' still has " + String(leaked_Employee) + " live entities outside sqrrl___world -- something external still references them")

    def __del__(deinit self):
        self.sqrrl__check_no_leaks()


def sqrrl___init() -> sqrrl___World:
    return sqrrl___World()
