from squirrel_compiler.codegen import sqrrl_prefixed
from squirrel_compiler.driver.discovery import DiscoveryResult


def emit_world_module(discovery: DiscoveryResult) -> String:
    """Emits `sqrrl__world.mojo`'s content: `sqrrl__World`, holding one
    table per `@@struct` declared anywhere in the project, plus
    `sqrrl__init()`, the factory `@@init()` calls to obtain it. Built
    project-wide, in its own file, rather than per `.mojo.sqrrl` file --
    Mojo has no mutable global/static state, so this is the one shared
    place a script and a struct's own declaring file (which may differ)
    both reach it from.

    Field names on `sqrrl__World` stay bare (`Person`, not `sqrrl__Person`)
    -- matching what the rewrite engine already emits at every table-level
    call site (`sqrrl__world.Person.create(...)`, README-documented shape,
    unchanged from rw_squirrel_2).

    Slimmed from rw_squirrel_2's own `emit_world_module` for M1's scope:
    no `TempKeepAlives`/`to_json`/`sqrrl__world_from_json`/
    `sqrrl__init_from_json` (whole-world JSON serialization, M5) -- so no
    topological struct ordering needed either (that existed purely to
    give JSON reload a safe reconstruction order). `sqrrl__check_no_leaks`/
    `__del__` are unchanged: `@@:` still builds a real, live `sqrrl__World`
    immediately, so leak detection at scope-end is unaffected by anything
    else in this rewrite."""
    var out = String()
    for ds in discovery.structs:
        var table_name = sqrrl_prefixed(ds.parsed.name) + "Table"
        out += "from " + ds.module_path + " import " + table_name + "\n"
    out += "from std.os import abort\n"

    out += "\n\n"
    out += "struct sqrrl__World(Movable):\n"
    for ds in discovery.structs:
        var table_name = sqrrl_prefixed(ds.parsed.name) + "Table"
        out += "    var " + ds.parsed.name + ": " + table_name + "\n"
    out += "\n"
    out += "    def __init__(out self):\n"
    for ds in discovery.structs:
        var table_name = sqrrl_prefixed(ds.parsed.name) + "Table"
        out += "        self." + ds.parsed.name + " = " + table_name + "()\n"

    out += "\n"
    out += "    def sqrrl__check_no_leaks(mut self):\n"
    if len(discovery.structs) == 0:
        out += "        pass\n"
    else:
        for ds in discovery.structs:
            var count_var = "sqrrl__leaked_" + ds.parsed.name
            if ds.parsed.is_keepalive:
                # A keepalive-tagged struct's own keepalive hold
                # (`EntityStorage.keepalive`, M4) is a real, deliberate
                # strong reference -- an entity retained *only* by it is
                # expected to still be live at scope-end, not a leak.
                # Actually *drop* the hold first (both call sites --
                # __del__ and @@init() -- immediately destroy or replace
                # the whole World right after this runs, so clearing it
                # here is safe), then check what's still alive: an entity
                # held only by keepalive dies right here and stops
                # counting; one *also* held by something else genuinely
                # external stays alive and still gets caught. Simply
                # subtracting the keepalive set's own size would miss that
                # second case (an entity counted as "explained away" by
                # keepalive even though something else is also leaking it)
                # -- actually releasing the reference and re-checking
                # liveness doesn't have that blind spot.
                out += "        self." + ds.parsed.name + ".storage[].keepalive_clear()\n"
            out += "        var " + count_var + " = len(self." + ds.parsed.name + ".all())\n"
            out += "        if " + count_var + " > 0:\n"
            out += (
                '            abort("LeakedEntities: \''
                + ds.parsed.name
                + "' still has \" + String("
                + count_var
                + ') + " live entities outside sqrrl__world -- something'
                ' external still references them")\n'
            )

    out += "\n"
    out += "    def __del__(deinit self):\n"
    out += "        self.sqrrl__check_no_leaks()\n"

    out += "\n\n"
    out += "def sqrrl__init() -> sqrrl__World:\n"
    out += "    return sqrrl__World()\n"

    return out
