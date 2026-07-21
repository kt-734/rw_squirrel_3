from friends import sqrrl__PersonTable
from friends import sqrrl__GroupTable
from std.os import abort


struct sqrrl___World(Movable):
    var Person: sqrrl__PersonTable
    var Group: sqrrl__GroupTable

    def __init__(out self):
        self.Person = sqrrl__PersonTable()
        self.Group = sqrrl__GroupTable()

    def sqrrl__check_no_leaks(mut self):
        _ = self.Group.storage[].keepalive_clear()
        var leaked_Person = self.Person.count()
        if leaked_Person > 0:
            abort("LeakedEntities: 'Person' still has " + String(leaked_Person) + " live entities outside sqrrl___world -- something external still references them")
        var leaked_Group = self.Group.count()
        if leaked_Group > 0:
            abort("LeakedEntities: 'Group' still has " + String(leaked_Group) + " live entities outside sqrrl___world -- something external still references them")

    def __del__(deinit self):
        self.sqrrl__check_no_leaks()


def sqrrl___init() -> sqrrl___World:
    return sqrrl___World()
