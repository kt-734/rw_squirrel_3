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
        var sqrrl__leaked_Team = len(self.Team.all())
        if sqrrl__leaked_Team > 0:
            abort("LeakedEntities: 'Team' still has " + String(sqrrl__leaked_Team) + " live entities outside sqrrl___world -- something external still references them")
        var sqrrl__leaked_Person = len(self.Person.all())
        if sqrrl__leaked_Person > 0:
            abort("LeakedEntities: 'Person' still has " + String(sqrrl__leaked_Person) + " live entities outside sqrrl___world -- something external still references them")
        var sqrrl__leaked_Vendor = len(self.Vendor.all())
        if sqrrl__leaked_Vendor > 0:
            abort("LeakedEntities: 'Vendor' still has " + String(sqrrl__leaked_Vendor) + " live entities outside sqrrl___world -- something external still references them")
        var sqrrl__leaked_Department = len(self.Department.all())
        if sqrrl__leaked_Department > 0:
            abort("LeakedEntities: 'Department' still has " + String(sqrrl__leaked_Department) + " live entities outside sqrrl___world -- something external still references them")
        self.AuditLog.storage[].keepalive_clear()
        var sqrrl__leaked_AuditLog = len(self.AuditLog.all())
        if sqrrl__leaked_AuditLog > 0:
            abort("LeakedEntities: 'AuditLog' still has " + String(sqrrl__leaked_AuditLog) + " live entities outside sqrrl___world -- something external still references them")
        var sqrrl__leaked_Employee = len(self.Employee.all())
        if sqrrl__leaked_Employee > 0:
            abort("LeakedEntities: 'Employee' still has " + String(sqrrl__leaked_Employee) + " live entities outside sqrrl___world -- something external still references them")
        var sqrrl__leaked_Project = len(self.Project.all())
        if sqrrl__leaked_Project > 0:
            abort("LeakedEntities: 'Project' still has " + String(sqrrl__leaked_Project) + " live entities outside sqrrl___world -- something external still references them")

    def __del__(deinit self):
        self.sqrrl__check_no_leaks()


def sqrrl___init() -> sqrrl___World:
    return sqrrl___World()
