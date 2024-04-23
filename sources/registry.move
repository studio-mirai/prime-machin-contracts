module prime_machin::registry {

    // === Imports ===

    use sui::display;
    use sui::package;
    use sui::table::{Self, Table};

    use prime_machin::admin::AdminCap;
    use prime_machin::collection;

    // === Friends ===

    /* friend prime_machin::factory; */

    public struct REGISTRY has drop {}

    /// Stores a Prime Machin number: to ID mapping.
    ///
    /// This object is used to maintain a stable mapping between a Prime Machin's
    /// number: and its object ID. When the contract is deployed, `is_initialized` is set to false.
    /// Once ADMIN initializes the registry with 3,333 Prime Machin, `is_initialized` will be set to
    /// true. At this point, the registry should be transformed into an immutable object.
    public struct Registry has key {
        id: UID,
        pfps: Table<u16, ID>,
        is_initialized: bool,
        is_frozen: bool,
    }

    // === Constants ===

    const EInvalidPfpNumber: u64 = 1;
    const ERegistryNotIntialized: u64 = 2;
    const ERegistryAlreadyFrozen: u64 = 3;
    const ERegistryNotFrozen: u64 = 4;

    // === Init Function ===

    #[allow(unused_variable, lint(share_owned))]
    fun init(
        otw: REGISTRY,
        ctx: &mut TxContext,
    ) {
        let publisher = package::claim(otw, ctx);

        let registry = Registry {
            id: object::new(ctx),
            pfps: table::new(ctx),
            is_initialized: false,
            is_frozen: false,
        };

        let mut registry_display = display::new<Registry>(&publisher, ctx);
        registry_display.add(b"name".to_string(), b"Prime Machin Registry".to_string());
        registry_display.add(b"description".to_string(), b"The official registry of the Prime Machin collection by Studio Mirai.".to_string());
        registry_display.add(b"image_url".to_string(), b"https://prime.nozomi.world/images/registry.webp.".to_string());
        registry_display.add(b"is_initialized".to_string(), b"{is_initialized}".to_string());
        registry_display.add(b"is_frozen".to_string(), b"{is_frozen}".to_string());

        transfer::transfer(registry, tx_context::sender(ctx));

        transfer::public_transfer(registry_display, @sm_treasury);
        transfer::public_transfer(publisher, @sm_treasury);
    }

    public fun pfp_id_from_number(
        number: u16,
        registry: &Registry,
    ): ID {

        assert!(number >= 1 && number <= collection::size(), EInvalidPfpNumber);
        assert!(registry.is_frozen == true, ERegistryNotFrozen);

        registry.pfps[number]
    }

    // === Public-Friend Functions ===

    public(package) fun add(
        number: u16,
        pfp_id: ID,
        registry: &mut Registry,
    ) {
        registry.pfps.add(number, pfp_id);

        if ((registry.pfps.length() as u16) == collection::size()) {
            registry.is_initialized = true;
        };
    }

    public(package) fun is_frozen(
        registry: &Registry,
    ): bool {
        registry.is_frozen
    }

    public(package) fun is_initialized(
        registry: &Registry,
    ): bool {
        registry.is_initialized
    }

    // === Admin Functions ===

    #[lint_allow(freeze_wrapped)]
    public fun admin_freeze_registry(
        cap: &AdminCap,
        mut registry: Registry,
        ctx: &TxContext,
    ) {
        cap.verify_admin_cap(ctx);

        assert!(registry.is_frozen == false, ERegistryAlreadyFrozen);
        assert!(registry.is_initialized == true, ERegistryNotIntialized);
        registry.is_frozen = true;
        transfer::freeze_object(registry);
    }
}
