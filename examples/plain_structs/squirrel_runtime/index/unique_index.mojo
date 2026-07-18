from std.os import abort


struct UniqueIndex[T: KeyElement & ImplicitlyDeletable & Copyable](Movable, ImplicitlyDeletable):
    """Backward index for a `unique`-tagged field: `Dict[T, id]`, at most one
    id per value. Like `PlainIndex`, carries no `_fwd` half -- see its own
    doc comment.

    `check_unique`/`add`/`remove` are split (unlike rw_squirrel_2's
    `UniqueRel.put`/`update`, which each did check+mutate together) because
    a generated `set_<field>` needs to validate *before* touching anything:
    check_unique(new_value) -> remove(old_value) -> add(new_value). Checking
    first means a rejected update leaves `_bwd` completely untouched -- no
    rollback needed. It also correctly handles setting a field back to its
    own current value: since the check passes (the value is already owned by
    this same id), remove-then-add nets out to the entry staying exactly as
    it was."""

    var _bwd: Dict[Self.T, UInt32]

    def __init__(out self):
        self._bwd = Dict[Self.T, UInt32]()

    def check_unique(self, value: Self.T, id: UInt32) raises:
        """Raises unless `value` is free, or already owned by `id` itself.
        Call before mutating anything -- see this struct's own doc comment."""
        if value in self._bwd and self._bwd[value] != id:
            raise Error(
                "UniqueConstraintViolation: value already in use by another"
                " entity"
            )

    def add(mut self, id: UInt32, value: Self.T):
        """Unconditional insert -- callers must have already confirmed
        availability via `check_unique`."""
        self._bwd[value.copy()] = id

    def remove(mut self, id: UInt32, value: Self.T):
        _ = id  # only present for signature symmetry with PlainIndex.remove
        try:
            if value in self._bwd:
                _ = self._bwd.pop(value)
        except:
            abort("UniqueIndex.remove: unreachable Dict operation failure")

    def get_bwd(self, value: Self.T) raises -> UInt32:
        """The single id currently holding `value`. Raises if none does."""
        try:
            return self._bwd[value]
        except:
            raise Error(
                "UniqueConstraintViolation: no entity currently holds this"
                " value"
            )

    def contains(self, value: Self.T) -> Bool:
        return value in self._bwd

    def all_bwd(self) -> ref [self._bwd] Dict[Self.T, UInt32]:
        """Every value currently in use, each mapped to the single id
        holding it -- a borrowed reference straight into `_bwd`, one id per
        value by construction."""
        return self._bwd
