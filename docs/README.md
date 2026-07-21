# docs

Curated, reference-style documentation for rw_squirrel_3 — the future
documentation site's source material. `notes.md`/`notes2.md`/`notes3.md`
(gitignored, repo root) remain the working session log; this directory is
distilled, durable reference material, not a session-by-session history.

- [overview.md](overview.md) — what squirrel is, core concepts, a minimal
  end-to-end example.
- [syntax-reference.md](syntax-reference.md) — every DSL construct: field
  modifiers and the methods each one generates, relation fields, custom
  containers, function/method marking, world scope, keepalive, JSON.
- [architecture.md](architecture.md) — how `squirrelc` itself is built: the
  compiler pipeline, the rewrite engine, the runtime library it generates
  against.
- [walkthrough.md](walkthrough.md) — `examples/kitchen_sink` read end to
  end, the largest real example in the repo.
- [json-and-custom-containers.md](json-and-custom-containers.md) — the JSON
  escape hatch in full: how a custom container's companions are found, the
  override mechanism, and how iteration/indexing are independent of JSON
  support entirely.
- [pitfalls.md](pitfalls.md) — real errors you'll actually hit, quoted
  verbatim, with what each one means and how to fix it.
- [method-reference.md](method-reference.md) — every generated method,
  exact signature and return type, verified against the actual codegen —
  not summarized from a table.

Not yet covered here (fair game for a future pass): the JSON module's own
internal dispatch-table structure, a second, smaller worked example geared
at a first-time reader (kitchen_sink is comprehensive but dense), and a
comparison against rw_squirrel_2's storage model for anyone coming from
that project.

(The plain-struct field-access gap flagged in an earlier pass here —
`n.@@ref.name` failing off an unmarked `var n: Note = ...` — turned out to
be a real, previously-undocumented milestone gap, not deliberate. Fixed;
see [syntax-reference.md](syntax-reference.md#plain-struct-locals) and
`notes.md`.)
