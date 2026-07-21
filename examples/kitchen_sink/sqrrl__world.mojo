from schema.team import sqrrl__TeamTable
from schema.person import sqrrl__PersonTable
from schema.vendor import sqrrl__VendorTable
from schema.department import sqrrl__DepartmentTable
from schema.audit_log import sqrrl__AuditLogTable
from schema.employee import sqrrl__EmployeeTable
from schema.project import sqrrl__ProjectTable
from std.os import abort


struct sqrrl___World(Movable):
    var Team: sqrrl__TeamTable
    var Person: sqrrl__PersonTable
    var Vendor: sqrrl__VendorTable
    var Department: sqrrl__DepartmentTable
    var AuditLog: sqrrl__AuditLogTable
    var Employee: sqrrl__EmployeeTable
    var Project: sqrrl__ProjectTable

    def __init__(out self):
        self.Team = sqrrl__TeamTable()
        self.Person = sqrrl__PersonTable()
        self.Vendor = sqrrl__VendorTable()
        self.Department = sqrrl__DepartmentTable()
        self.AuditLog = sqrrl__AuditLogTable()
        self.Employee = sqrrl__EmployeeTable()
        self.Project = sqrrl__ProjectTable()

    def sqrrl__check_no_leaks(mut self):
        _ = self.AuditLog.storage[].keepalive_clear()
        var leaked_Team = self.Team.count()
        if leaked_Team > 0:
            abort("LeakedEntities: 'Team' still has " + String(leaked_Team) + " live entities outside sqrrl___world -- something external still references them")
        var leaked_Person = self.Person.count()
        if leaked_Person > 0:
            abort("LeakedEntities: 'Person' still has " + String(leaked_Person) + " live entities outside sqrrl___world -- something external still references them")
        var leaked_Vendor = self.Vendor.count()
        if leaked_Vendor > 0:
            abort("LeakedEntities: 'Vendor' still has " + String(leaked_Vendor) + " live entities outside sqrrl___world -- something external still references them")
        var leaked_Department = self.Department.count()
        if leaked_Department > 0:
            abort("LeakedEntities: 'Department' still has " + String(leaked_Department) + " live entities outside sqrrl___world -- something external still references them")
        var leaked_AuditLog = self.AuditLog.count()
        if leaked_AuditLog > 0:
            abort("LeakedEntities: 'AuditLog' still has " + String(leaked_AuditLog) + " live entities outside sqrrl___world -- something external still references them")
        var leaked_Employee = self.Employee.count()
        if leaked_Employee > 0:
            abort("LeakedEntities: 'Employee' still has " + String(leaked_Employee) + " live entities outside sqrrl___world -- something external still references them")
        var leaked_Project = self.Project.count()
        if leaked_Project > 0:
            abort("LeakedEntities: 'Project' still has " + String(leaked_Project) + " live entities outside sqrrl___world -- something external still references them")

    def __del__(deinit self):
        self.sqrrl__check_no_leaks()


def sqrrl___init() -> sqrrl___World:
    return sqrrl___World()
