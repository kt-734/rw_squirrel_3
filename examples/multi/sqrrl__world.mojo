from company import sqrrl__ProjectTable
from company import sqrrl__DepartmentTable
from std.os import abort


struct sqrrl___World(Movable):
    var Project: sqrrl__ProjectTable
    var Department: sqrrl__DepartmentTable

    def __init__(out self):
        self.Project = sqrrl__ProjectTable()
        self.Department = sqrrl__DepartmentTable()

    def sqrrl__check_no_leaks(mut self):
        var leaked_Project = self.Project.count()
        if leaked_Project > 0:
            abort("LeakedEntities: 'Project' still has " + String(leaked_Project) + " live entities outside sqrrl___world -- something external still references them")
        var leaked_Department = self.Department.count()
        if leaked_Department > 0:
            abort("LeakedEntities: 'Department' still has " + String(leaked_Department) + " live entities outside sqrrl___world -- something external still references them")

    def __del__(deinit self):
        self.sqrrl__check_no_leaks()


def sqrrl___init() -> sqrrl___World:
    return sqrrl___World()
