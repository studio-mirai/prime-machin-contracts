module prime_machin::admin {

    // === Errors ===

    const EAdminCapExpired: u64 = 1;

    // === Structs ===

    public struct ADMIN has drop {}

    public struct AdminCap has key {
        id: UID,
        epoch: u64,
    }

    public struct SuperadminCap has key, store {
        id: UID,
    }

    // === Init Function ===

    #[allow(unused_variable, lint(share_owned))]
    fun init(
        otw: ADMIN,
        ctx: &mut TxContext,
    ) {
        let superadmin_cap = SuperadminCap{
            id: object::new(ctx)
        };

        let admin_cap = internal_create_admin_cap(ctx);

        transfer::transfer(superadmin_cap, @sm_treasury);
        transfer::transfer(admin_cap, ctx.sender());
    }

    // === Public-Mutative Functions ===

    public fun destroy_admin_cap(
        cap: AdminCap,
    ) {
        let AdminCap { id, epoch: _ } = cap;
        object::delete(id);
    }

    entry fun superadmin_issue_admin_cap(
        _: &SuperadminCap,
        beneficiary: address,
        ctx: &mut TxContext,
    ) {
        let admin_cap = internal_create_admin_cap(ctx);
        transfer::transfer(admin_cap, beneficiary)
    }

    // === Public-Friend Functions ===

    public(package) fun verify_admin_cap(
        cap: &AdminCap,
        ctx: &TxContext,
    ) {
        assert!(cap.epoch == ctx.epoch(), EAdminCapExpired);
    }

    // === Private Functions ===

    fun internal_create_admin_cap(
        ctx: &mut TxContext,
    ): AdminCap {
        let admin_cap = AdminCap {
            id: object::new(ctx),
            // Expiration epoch is current epoch + 2.
            // This means if current epoch is 350, expiration epoch would be the start of epoch 352.
            epoch: ctx.epoch(),
        };

        admin_cap
    }
}
