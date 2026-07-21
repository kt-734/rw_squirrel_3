from squirrel_compiler.codegen import sqrrl_prefixed
from squirrel_compiler.driver.discovery import DiscoveryResult


def emit_world_module(discovery: DiscoveryResult) -> String:
    """Emits `sqrrl__world.mojo`'s content: `sqrrl___World`, holding one
    table per `@@struct` declared anywhere in the project, plus
    `sqrrl___init()`, the factory `@@init()` calls to obtain it. Built
    project-wide, in its own file, rather than per `.mojo.sqrrl` file --
    Mojo has no mutable global/static state, so this is the one shared
    place a script and a struct's own declaring file (which may differ)
    both reach it from.

    Field names on `sqrrl___World` stay bare (`Person`, not `sqrrl__Person`)
    -- matching what the rewrite engine already emits at every table-level
    call site (`sqrrl___world.Person.create(...)`, README-documented shape,
    unchanged from rw_squirrel_2).

    Every identifier reachable from (or adjacent to) hand-written DSL
    code -- `sqrrl___world`/`sqrrl___init`/`sqrrl___World` here, plus the
    JSON entry points/`sqrrl___temp_keep_alives`/`sqrrl___TempKeepAlives`
    in `driver/json_module.mojo` -- is triple-underscore, not the usual
    double: `sqrrl_prefixed`'s own `sqrrl__` +
    name convention means a user's own `@@`-marked name could otherwise
    collide with one of these (`@@world`/`@@init`/`@@World` are all
    perfectly plausible entity/variable names). `sqrrl__check_no_leaks`
    stays double (a method name, technically callable as `sqrrl___world.
    sqrrl__check_no_leaks()`, even if no real DSL script ever would) --
    it never appears in a scope where hand-written DSL code coexists
    (only ever called from other generated code), so there's nothing for
    it to actually collide with. Its own local `leaked_<name>` counter
    variable, below, carries no `sqrrl__` prefix at all -- unlike a
    method name, a local variable inside this one generated method's own
    body has zero collision surface with anything, prefixed or not.

    Slimmed from rw_squirrel_2's own `emit_world_module` for M1's scope:
    no `TempKeepAlives`/`to_json`/`sqrrl___world_from_json`/
    `sqrrl___init_from_json` (whole-world JSON serialization, M5) -- so no
    topological struct ordering needed either (that existed purely to
    give JSON reload a safe reconstruction order). `sqrrl__check_no_leaks`/
    `__del__` are unchanged: `@@:` still builds a real, live `sqrrl___World`
    immediately, so leak detection at scope-end is unaffected by anything
    else in this rewrite.

    `sqrrl__check_no_leaks` clears *every* keepalive struct's own hold in
    one pass, *before* checking any struct's liveness in a second pass --
    not interleaved (clear mine, check mine, clear the next one's, check
    the next one's...), which was this method's own original shape and a
    real bug: a keepalive struct can hold a genuinely live reference to
    an entity of a *different* struct (a `multi`/relation field, e.g. a
    keepalive `@@Group` holding `@@Person` members), and that other
    struct might be declared -- and therefore checked -- earlier in
    `discovery.structs`' own iteration order, before this struct's own
    keepalive hold on it ever gets cleared. Confirmed via a real end-to-
    end compile (the ported `friends` example, a keepalive join struct
    holding `multi` members of an earlier-declared struct): `Person`
    aborted as "leaked" even though its only remaining reference was
    `Group`'s own keepalive membership, one line away from being cleared
    -- simply declared too early to benefit from it. Two full passes
    fixes this regardless of declaration order: nothing is ever checked
    while a keepalive-only hold on it could still be pending release.

    Pass 1's `_ = self.<Name>.storage[].keepalive_clear()`: `EntityStorage.
    keepalive_clear` deliberately returns the dropped dict instead of
    destroying it itself, so that destruction (and any `__del__`-triggered
    mutation back into the *same* `EntityStorage`, e.g. a `multi` member's
    own `free_id` call) happens only once `self.<Name>.storage[]`'s own
    exclusive borrow has fully ended -- a real, confirmed Mojo aliasing
    hazard otherwise silently discards that nested mutation."""
    var out = String()
    for ds in discovery.structs:
        var table_name = sqrrl_prefixed(ds.parsed.name) + "Table"
        out += "from " + ds.module_path + " import " + table_name + "\n"
    out += "from std.os import abort\n"

    out += "\n\n"
    out += "struct sqrrl___World(Movable):\n"
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
        # Pass 1: drop every keepalive struct's own hold *first*, before
        # any liveness check runs at all -- both call sites (`__del__`
        # and `@@init()`) immediately destroy or replace the whole World
        # right after this runs, so clearing every hold up front is safe
        # regardless of which struct's own check happens to run next.
        for ds in discovery.structs:
            if ds.parsed.is_keepalive:
                out += (
                    "        _ = self."
                    + ds.parsed.name
                    + ".storage[].keepalive_clear()\n"
                )
        # Pass 2: now that every keepalive-only hold is already gone,
        # checking what's still alive is order-independent -- an entity
        # held only by keepalive (its own, or a *different* keepalive
        # struct's, e.g. a relation/`multi` field) already died in pass
        # 1 and stops counting; one *also* held by something else
        # genuinely external stays alive and still gets caught. Simply
        # subtracting the keepalive set's own size would miss that
        # second case (an entity counted as "explained away" by
        # keepalive even though something else is also leaking it) --
        # actually releasing the reference and re-checking liveness
        # doesn't have that blind spot.
        #
        # `.count()`, not `len(.all())`: `.all()` builds a whole `Set`
        # of fresh wrapper instances (one real construction, one Set
        # insertion, per live entity) purely to immediately discard it
        # after taking its length -- `.count()` reads the same live
        # count `EntityStorage` already maintains directly, no
        # construction needed at all.
        for ds in discovery.structs:
            var count_var = "leaked_" + ds.parsed.name
            out += "        var " + count_var + " = self." + ds.parsed.name + ".count()\n"
            out += "        if " + count_var + " > 0:\n"
            out += (
                '            abort("LeakedEntities: \''
                + ds.parsed.name
                + "' still has \" + String("
                + count_var
                + ') + " live entities outside sqrrl___world -- something'
                ' external still references them")\n'
            )

    out += "\n"
    out += "    def __del__(deinit self):\n"
    out += "        self.sqrrl__check_no_leaks()\n"

    out += "\n\n"
    out += "def sqrrl___init() -> sqrrl___World:\n"
    out += "    return sqrrl___World()\n"

    return out
