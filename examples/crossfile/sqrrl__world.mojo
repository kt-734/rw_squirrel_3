from main import sqrrl__EmployeeTable
from schema.department import sqrrl__DepartmentTable
from std.os import abort


struct sqrrl___World(Movable):
    var Employee: sqrrl__EmployeeTable
    var Department: sqrrl__DepartmentTable

    def __init__(out self):
        self.Employee = sqrrl__EmployeeTable()
        self.Department = sqrrl__DepartmentTable()

    def sqrrl__check_no_leaks(mut self):
        var sqrrl__leaked_Employee = len(self.Employee.all())
        if sqrrl__leaked_Employee > 0:
            abort("LeakedEntities: 'Employee' still has " + String(sqrrl__leaked_Employee) + " live entities outside sqrrl___world -- something external still references them")
        var sqrrl__leaked_Department = len(self.Department.all())
        if sqrrl__leaked_Department > 0:
            abort("LeakedEntities: 'Department' still has " + String(sqrrl__leaked_Department) + " live entities outside sqrrl___world -- something external still references them")

    def __del__(deinit self):
        self.sqrrl__check_no_leaks()


def sqrrl___init() -> sqrrl___World:
    return sqrrl___World()
