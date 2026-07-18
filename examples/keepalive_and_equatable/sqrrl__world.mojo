from company import sqrrl__ProjectTable
from company import sqrrl__PersonTable
from std.os import abort


struct sqrrl__World(Movable):
    var Project: sqrrl__ProjectTable
    var Person: sqrrl__PersonTable

    def __init__(out self):
        self.Project = sqrrl__ProjectTable()
        self.Person = sqrrl__PersonTable()

    def sqrrl__check_no_leaks(mut self):
        self.Project.storage[].keepalive_clear()
        var sqrrl__leaked_Project = len(self.Project.all())
        if sqrrl__leaked_Project > 0:
            abort("LeakedEntities: 'Project' still has " + String(sqrrl__leaked_Project) + " live entities outside sqrrl__world -- something external still references them")
        var sqrrl__leaked_Person = len(self.Person.all())
        if sqrrl__leaked_Person > 0:
            abort("LeakedEntities: 'Person' still has " + String(sqrrl__leaked_Person) + " live entities outside sqrrl__world -- something external still references them")

    def __del__(deinit self):
        self.sqrrl__check_no_leaks()


def sqrrl__init() -> sqrrl__World:
    return sqrrl__World()
