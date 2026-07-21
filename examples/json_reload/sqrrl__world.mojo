from company import sqrrl__ProjectTable
from company import sqrrl__DepartmentTable
from company import sqrrl__TagTable
from std.os import abort


struct sqrrl___World(Movable):
    var Project: sqrrl__ProjectTable
    var Department: sqrrl__DepartmentTable
    var Tag: sqrrl__TagTable

    def __init__(out self):
        self.Project = sqrrl__ProjectTable()
        self.Department = sqrrl__DepartmentTable()
        self.Tag = sqrrl__TagTable()

    def sqrrl__check_no_leaks(mut self):
        _ = self.Tag.storage[].keepalive_clear()
        var leaked_Project = self.Project.count()
        if leaked_Project > 0:
            abort("LeakedEntities: 'Project' still has " + String(leaked_Project) + " live entities outside sqrrl___world -- something external still references them")
        var leaked_Department = self.Department.count()
        if leaked_Department > 0:
            abort("LeakedEntities: 'Department' still has " + String(leaked_Department) + " live entities outside sqrrl___world -- something external still references them")
        var leaked_Tag = self.Tag.count()
        if leaked_Tag > 0:
            abort("LeakedEntities: 'Tag' still has " + String(leaked_Tag) + " live entities outside sqrrl___world -- something external still references them")

    def __del__(deinit self):
        self.sqrrl__check_no_leaks()


def sqrrl___init() -> sqrrl___World:
    return sqrrl___World()
