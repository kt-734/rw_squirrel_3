# Walkthrough: kitchen_sink

`examples/kitchen_sink` is the largest real example in this repo — 17
structs across 13 files, exercising nearly every feature described in the
[syntax reference](syntax-reference.md) at once. This walks through it in
the order a reader would actually encounter it.

## Layout

```
kitchen_sink/
  schema/          -- every @@struct and hand-written plain struct
    vendor.mojo.sqrrl
    project.mojo.sqrrl
    department.mojo.sqrrl
    employee.mojo.sqrrl
    person.mojo.sqrrl
    team.mojo.sqrrl
    audit_log.mojo.sqrrl
    profile.mojo.sqrrl, contact_info.mojo.sqrrl, address.mojo.sqrrl,
    money.mojo.sqrrl, box.mojo.sqrrl, pair.mojo.sqrrl, assignment.mojo.sqrrl
    grid_module.mojo  -- hand-written, not .sqrrl -- a custom container
  logic/
    factories.mojo.sqrrl  -- @@@-marked helper functions
  main.mojo.sqrrl
```

A DSL project has no required layout — this is just an organizational
choice (schema declarations separated from construction logic separated
from the entry point). squirrelc discovers every `.mojo.sqrrl` file under
the target root regardless of directory structure.

## The dependency chain

The schema forms one deliberate chain: `Vendor -> Project -> Department ->
Employee -> Person -> Team`, each level referencing the one before it as a
relation field. This is what exercises multi-hop chaining
(`@@alice.@@job.@@dept.name`, four levels deep, single expression) and cross-
file relation resolution (each struct lives in its own file; nothing needs
an explicit import for another struct's type — see
[architecture.md](architecture.md)'s discovery step).

`Department` also demonstrates every relation-field shape side by side:

```
@@struct equatable @@Department:
    name: String
    tags: List[String]              # plain container field, no backward index
    multi @@projects: @@Project      # one-at-a-time membership
    @@vendors: Set[@@Vendor]         # ordinary Set-wrapped relation
    multi skills: String             # multi on a *plain* field, Set[String]-backed
```

## Factories (`logic/factories.mojo.sqrrl`)

Every constructor here is `@@@`-marked (needs the world to call `create()`
under the hood) and returns an `@@`-marked value:

```
def @@@make_vendor(name: String) -> @@Vendor:
    var @@v = @@@Vendor { .name = name }
    return @@v
```

`@@promote` (in `main.mojo.sqrrl`, not `factories.mojo.sqrrl`) is the one
function in this example that's `@@`-marked, not `@@@`-marked: it mutates an
already-held employee's title and returns it, without needing the world
itself.

## main.mojo.sqrrl highlights

- **Aggregates, all three shapes** — `Employee.salary` is `stats`, so it has
  the whole-table (`sum_salary()`), grouped (`sum_salary_by_dept()`), and
  targeted (`avg_salary_for_dept(sales)`) forms all at once.
- **`ordered` without `stats`** — `Employee.years_employed` and
  `Project.priority` both get range queries (`for_years_employed_between(3,
  4)`, `for_priority_at_least(2)`) and free `min_`/`max_`, but no `sum_`/
  `avg_` (that needs `stats` specifically).
- **A direct table-level chain, no intermediate variable** —
  `@@@Employee.for_years_employed_between(3, 6)[0].name`.
- **`keepalive` with no local handle at all** — `@@@log(message)` discards
  its own return value immediately; `AuditLog` entities survive purely
  because the struct is `keepalive`.
- **`dont_keepalive()`** releases a single keepalive-held entity early —
  once nothing else references it either, it's gone, same as any other
  entity.
- **A custom container with a relation in value position** —
  `Team.@@directory: Grid[String, @@Employee]`, indexed
  (`.@@directory["lead"].title`) and iterated (`for role in
  .@@directory:` — bare loop variable, since iterating only ever yields
  keys, matching `Dict`'s own semantics).
- **A whole-world JSON round-trip** at the end, reloading and re-verifying
  several entities' state (including the `Grid` field above) after
  `@@@begin_init_from_json(...)`.

Run it yourself:

```
./squirrelc examples/kitchen_sink
cd examples/kitchen_sink && pixi run -e default mojo run -I . main.mojo
```
