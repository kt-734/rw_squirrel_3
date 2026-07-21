from company import sqrrl__ProjectTable
from company import sqrrl__PersonTable
from std.os import abort


struct sqrrl___World(Movable):
    var Project: sqrrl__ProjectTable
    var Person: sqrrl__PersonTable

    def __init__(out self):
        self.Project = sqrrl__ProjectTable()
        self.Person = sqrrl__PersonTable()

    def sqrrl__check_no_leaks(mut self):
        _ = self.Project.storage[].keepalive_clear()
        var leaked_Project = self.Project.count()
        if leaked_Project > 0:
            abort("LeakedEntities: 'Project' still has " + String(leaked_Project) + " live entities outside sqrrl___world -- something external still references them")
        var leaked_Person = self.Person.count()
        if leaked_Person > 0:
            abort("LeakedEntities: 'Person' still has " + String(leaked_Person) + " live entities outside sqrrl___world -- something external still references them")

    def __del__(deinit self):
        self.sqrrl__check_no_leaks()


def sqrrl___init() -> sqrrl___World:
    return sqrrl___World()
