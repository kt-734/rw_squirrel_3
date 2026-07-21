from people import sqrrl__PersonTable
from std.os import abort


struct sqrrl___World(Movable):
    var Person: sqrrl__PersonTable

    def __init__(out self):
        self.Person = sqrrl__PersonTable()

    def sqrrl__check_no_leaks(mut self):
        var leaked_Person = self.Person.count()
        if leaked_Person > 0:
            abort("LeakedEntities: 'Person' still has " + String(leaked_Person) + " live entities outside sqrrl___world -- something external still references them")

    def __del__(deinit self):
        self.sqrrl__check_no_leaks()


def sqrrl___init() -> sqrrl___World:
    return sqrrl___World()
