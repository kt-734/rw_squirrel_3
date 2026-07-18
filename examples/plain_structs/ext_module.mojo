from squirrel_runtime.json import sqrrl__JsonScanner


@fieldwise_init
struct ExternalCity(Copyable, Movable, ImplicitlyDeletable):
    """A plain-value type this project never scans as `@@struct` or a
    hand-written plain struct at all -- an ordinary, external `.mojo`
    module a DSL script merely imports. `to_json` still works on it fully
    automatically (`sqrrl__to_json[T]`'s own reflection doesn't care
    whether the compiler ever discovered the type); `from_json` needs
    this hand-written escape-hatch companion below instead, since
    generated code can't reconstruct a type it never parsed a field list
    for."""

    var name: String


def sqrrl__ExternalCity_from_json(mut sc: sqrrl__JsonScanner) raises -> ExternalCity:
    """The from_json escape hatch `driver/json_module.mojo`'s
    `_leaf_from_json_expr` assumes exists for exactly this case -- called
    directly, by this exact name, with no declaration/registration needed
    anywhere else."""
    sc.expect_byte(UInt8(ord("{")))
    var key = sc.parse_json_string()
    if key != "name":
        raise Error("InvalidJson: expected 'name' for ExternalCity")
    sc.expect_byte(UInt8(ord(":")))
    var name = sc.parse_json_string()
    sc.expect_byte(UInt8(ord("}")))
    return ExternalCity(name=name)
