module prime_machin::mint {

    // === Imports ===

    use std::option::{Self, Option};
    use std::string::{Self};
    use std::vector::{Self};

    use sui::coin::{Self, Coin};
    use sui::display::{Self};
    use sui::event;
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
    use sui::object::{Self, ID, UID};
    use sui::object_table::{Self, ObjectTable};
    use sui::package::{Self};
    use sui::sui::{SUI};
    use sui::table_vec::{Self, TableVec};
    use sui::transfer::{Self};
    use sui::transfer_policy::{TransferPolicy};
    use sui::tx_context::{Self, TxContext};

    use prime_machin::admin::{Self, AdminCap};
    use prime_machin::attributes::{Self, Attributes};
    use prime_machin::factory::{Self , PrimeMachin};
    use prime_machin::image::{Self, Image};
    use prime_machin::rarity::{Self, Rarity};

    // === Errors ===

    const ECurrentPhaseNotPhaseThree: u64 = 1;
    const EInvalidDestroyCapForMintReceipt: u64 = 2;
    const EInvalidMigrationPfpNumber: u64 = 3;
    const EInvalidPaymentAmount: u64 = 4;
    const EInvalidPhaseNumber: u64 = 5;
    const EInvalidPrice: u64 = 6;
    const EInvalidRevealMintCapForMint: u64 = 7;
    const EInvalidReceiptForMint: u64 = 8;
    const EInvalidStatusNumber: u64 = 9;
    const EInvalidTicketForMintPhase: u64 = 10;
    const EInvalidWhitelistPhaseNumber: u64 = 11;
    const EMigrationMintWarehouseNotIntialized: u64 = 12;
    const EMigrationWarehouseAlreadyInitialized: u64 = 13;
    const EMigrationWarehouseNotEmpty: u64 = 14;
    const EMigrationWarehouseNotInitialized: u64 = 15;
    const EMintClaimPeriodNotExpired: u64 = 16;
    const EMintNotLive: u64 = 17;
    const EMintPhaseNotSet: u64 = 18;
    const EMintWarehouseAlreadyInitialized: u64 = 19;
    const EMintWarehouseNotEmpty: u64 = 20;
    const EMintWarehouseNotInitialized: u64 = 21;
    const EPrimeMachinNotRevealed: u64 = 22;
    const EWarehouseIsEmpty: u64 = 23;

    // === Constants ===

    const TARGET_NEW_MINT_COUNT: u16 = 1304;
    const TARGET_MIGRATION_MINT_COUNT: u16 = 2029;
    const EPOCHS_TO_CLAIM_MINT: u64 = 30;

    // === Structs ===

    struct MINT has drop {}

    struct DestroyMintReceiptCap has key {
        id: UID,
        number: u16,
    }

    struct MigrationTicket has key, store {
        id: UID,
        number: u16,
    }

    struct MigrationWarehouse has key {
        id: UID,
        pfps: ObjectTable<u16, PrimeMachin>,
        is_initialized: bool,
    }

    struct Mint has key {
        id: UID,
        number: u16,    
        pfp: Option<PrimeMachin>,
        payment: Option<Coin<SUI>>,
        is_revealed: bool,
        minted_by: address,
        claim_expiration_epoch: u64,
    }

    struct MintReceipt has key {
        id: UID,
        number: u16,
        mint_id: ID,
    }

    struct MintSettings has key {
        id: UID,
        price: u64,
        phase: u8,
        status: u8,
    }

    struct MintWarehouse has key {
        id: UID,
        pfps: TableVec<PrimeMachin>,
        is_initialized: bool,
    }

    struct RevealMintCap has key {
        id: UID,
        number: u16,
        pfp_id: ID,
        mint_id: ID,
        create_attributes_cap_id: ID,
        create_image_cap_id: ID,
        create_rarity_cap_id: ID,
    }

    struct WhitelistTicket has key {
        id: UID,
        phase: u8,
    }

    // === Events ===
    
    struct MintClaimedEvent has copy, drop {
        pfp_id: ID,
        pfp_number: u16,
        claimed_by: address,
        kiosk_id: ID,
    }

    struct MintEvent has copy, drop {
        mint_id: ID,
        pfp_id: ID,
        pfp_number: u16,
        minted_by: address,
    }

    // === Init Function ===

    #[allow(unused_variable)]
    fun init(
        otw: MINT,
        ctx: &mut TxContext,
    ) {
        let publisher = package::claim(otw, ctx);  

        let migration_ticket_display = display::new<MigrationTicket>(&publisher, ctx);
        display::add(&mut migration_ticket_display, string::utf8(b"name"), string::utf8(b"Prime Machin Migration Ticket #{number}"));
        display::add(&mut migration_ticket_display, string::utf8(b"description"), string::utf8(b"A ticket that can be used to migrate Prime Machin #{number} from ICON to Sui."));
        display::add(&mut migration_ticket_display, string::utf8(b"number"), string::utf8(b"{number}"));
        display::add(&mut migration_ticket_display, string::utf8(b"image_url"), string::utf8(b"https://prime.nozomi.world/images/migration-ticket.webp"));
        display::update_version(&mut migration_ticket_display);
        transfer::public_transfer(migration_ticket_display, tx_context::sender(ctx));

        let mint_receipt_display = display::new<MintReceipt>(&publisher, ctx);
        display::add(&mut mint_receipt_display, string::utf8(b"name"), string::utf8(b"Prime Machin Mint Receipt #{number}"));
        display::add(&mut mint_receipt_display, string::utf8(b"description"), string::utf8(b"A receipt that can be used to claim Prime Machin #{number}."));
        display::add(&mut mint_receipt_display, string::utf8(b"number"), string::utf8(b"{number}"));
        display::add(&mut mint_receipt_display, string::utf8(b"mint_id"), string::utf8(b"{mint_id}"));
        display::add(&mut mint_receipt_display, string::utf8(b"image_url"), string::utf8(b"https://prime.nozomi.world/images/mint-receipt.webp"));
        display::update_version(&mut mint_receipt_display);
        transfer::public_transfer(mint_receipt_display, tx_context::sender(ctx));

        let wl_ticket_display = display::new<WhitelistTicket>(&publisher, ctx);
        display::add(&mut wl_ticket_display, string::utf8(b"name"), string::utf8(b"Prime Machin Whitelist Ticket (Phase {phase})"));
        display::add(&mut wl_ticket_display, string::utf8(b"description"), string::utf8(b"A Phase {phase} whitelist ticket for the Prime Machin collection by Studio Mirai."));
        display::add(&mut wl_ticket_display, string::utf8(b"phase"), string::utf8(b"{phase}"));
        display::add(&mut wl_ticket_display, string::utf8(b"image_url"), string::utf8(b"https://prime.nozomi.world/images/wl-ticket-phase-{phase}.webp"));
        display::update_version(&mut wl_ticket_display);
        transfer::public_transfer(wl_ticket_display, tx_context::sender(ctx));

        let mint_settings = MintSettings {
            id: object::new(ctx),
            phase: 0,
            price: 0,
            status: 0,
        };
        
        let mint_warehouse = MintWarehouse {
            id: object::new(ctx),
            pfps: table_vec::empty(ctx),
            is_initialized: false,
        };

        let migration_warehouse = MigrationWarehouse {
            id: object::new(ctx),
            pfps: object_table::new(ctx),
            is_initialized: false,
        };

        transfer::public_transfer(publisher, @sm_treasury);
        
        transfer::share_object(migration_warehouse);
        transfer::share_object(mint_settings);
        transfer::share_object(mint_warehouse);
    }

    // === Public-Mutative Functions ===

    public fun claim_mint(
        receipt: MintReceipt,
        mint: Mint,
        kiosk: &mut Kiosk,
        kiosk_owner_cap: &KioskOwnerCap,
        policy: &TransferPolicy<PrimeMachin>,
        ctx: &TxContext,
    ) {
        assert!(receipt.mint_id == object::id(&mint), EInvalidReceiptForMint);
        assert!(mint.is_revealed == true, EPrimeMachinNotRevealed);

        // Extract Prime Machin and payment from Mint.
        let pfp = option::extract(&mut mint.pfp);
        let payment = option::extract(&mut mint.payment);

        event::emit(
            MintClaimedEvent {
                pfp_id: factory::id(&pfp),
                pfp_number: factory::number(&pfp),
                claimed_by: tx_context::sender(ctx),
                kiosk_id: object::id(kiosk),
            }
        );

        // Lock Prime Machin into buyer's kiosk.
        kiosk::lock(kiosk, kiosk_owner_cap, policy, pfp);

        // Transfer payment to SM.
        transfer::public_transfer(payment, @sm_treasury);

        // Destroy the mint.
        destroy_mint_internal(mint);

        // Destroy the mint receipt.
        let MintReceipt { id, number: _, mint_id: _ } = receipt;
        object::delete(id);
    }

    /// Destroys a mint receipt in the case that a mint is refunded by ADMIN.
    /// During the refund process, a DestroyMintReceiptCap is issued to the
    /// original minter. Both the cap and receipt have to be passed into this function
    /// in order to destroy the receipt. This prevents accidental destruction of a receipt.
    public fun destroy_mint_receipt(
        cap: DestroyMintReceiptCap,
        receipt: MintReceipt,
    ) {
        assert!(cap.number == receipt.number, EInvalidDestroyCapForMintReceipt);

        let DestroyMintReceiptCap { id, number: _ } = cap;
        object::delete(id);

        let MintReceipt { id, number: _, mint_id: _ } = receipt;
        object::delete(id);
    }

    /// Destroy a migration ticket.
    public fun destroy_migration_ticket(
        ticket: MigrationTicket,
    ) {
        let MigrationTicket { id, number: _ } = ticket;
        object::delete(id);
    }

    /// Destroy a whitelist ticket.
    public fun destroy_whitelist_ticket(
        ticket: WhitelistTicket,
    ) {
        let WhitelistTicket { id, phase: _ } = ticket;
        object::delete(id);
    }


    public fun migration_mint(
        ticket: MigrationTicket,
        warehouse: &mut MigrationWarehouse,
        settings: &MintSettings,
        ctx: &mut TxContext,
    ) {
        assert!(settings.status == 1, EMintNotLive);
        assert!(settings.phase != 0, EMintPhaseNotSet);

        let pfp = object_table::remove(&mut warehouse.pfps, ticket.number);
        let payment = coin::zero<SUI>(ctx);

        let MigrationTicket {
            id,
            number: _,
        } = ticket;
        object::delete(id);
        
        mint_internal(pfp, payment, ctx);
    }

    public fun public_mint(
        payment: Coin<SUI>,
        warehouse: &mut MintWarehouse,
        settings: &MintSettings,
        ctx: &mut TxContext,
    ) {
        assert!(table_vec::length(&warehouse.pfps) > 0, EWarehouseIsEmpty);

        assert!(settings.status == 1, EMintNotLive);
        assert!(settings.phase == 3, ECurrentPhaseNotPhaseThree);

        assert!(coin::value(&payment) == settings.price, EInvalidPaymentAmount);

        let pfp = table_vec::pop_back(&mut warehouse.pfps);
        mint_internal(pfp, payment, ctx);
    }

    public fun whitelist_mint(
        ticket: WhitelistTicket,
        payment: Coin<SUI>,
        warehouse: &mut MintWarehouse,
        settings: &MintSettings,
        ctx: &mut TxContext,
    ) {
        assert!(settings.status == 1, EMintNotLive);
        assert!(ticket.phase == settings.phase, EInvalidTicketForMintPhase);

        assert!(coin::value(&payment) == settings.price, EInvalidPaymentAmount);

        let pfp = table_vec::pop_back(&mut warehouse.pfps);
        mint_internal(pfp, payment, ctx);

        let WhitelistTicket { id, phase: _ } = ticket;
        object::delete(id);
    }

    /// Add Prime Machin PFPs to the mint warehouse.
    public fun admin_add_to_mint_warehouse(
        cap: &AdminCap,
        pfps: vector<PrimeMachin>,
        warehouse: &mut MintWarehouse,
        ctx: &TxContext,
    ) {
        admin::verify_admin_cap(cap, ctx);

        assert!(warehouse.is_initialized == false, EMintWarehouseAlreadyInitialized);

        while (!vector::is_empty(&pfps)) {
            let pfp = vector::pop_back(&mut pfps);
            table_vec::push_back(&mut warehouse.pfps, pfp);
        };

        if ((table_vec::length(&warehouse.pfps) as u16) == TARGET_NEW_MINT_COUNT) {
            warehouse.is_initialized = true;
        };

        vector::destroy_empty(pfps);
    }

    /// Add Prime Machin PFPs to the migration warehouse.
    public fun admin_add_to_migration_warehouse(
        cap: &AdminCap,
        pfps: vector<PrimeMachin>,
        warehouse: &mut MigrationWarehouse,
        ctx: &TxContext,
    ) {
        admin::verify_admin_cap(cap, ctx);

        assert!(warehouse.is_initialized == false, EMigrationWarehouseAlreadyInitialized);

        while (!vector::is_empty(&pfps)) {
            let pfp = vector::pop_back(&mut pfps);
            object_table::add(&mut warehouse.pfps, factory::number(&pfp), pfp);
        };

        if ((object_table::length(&warehouse.pfps) as u16) == TARGET_MIGRATION_MINT_COUNT) {
            warehouse.is_initialized = true;
        };

        vector::destroy_empty(pfps);
    }

    /// Destroy an empty migration warehouse when it's no longer needed.
    public fun admin_destroy_migration_warehouse(
        cap: &AdminCap,
        warehouse: MigrationWarehouse,
        ctx: &TxContext,
    ) {
        admin::verify_admin_cap(cap, ctx);

        assert!(object_table::is_empty(&warehouse.pfps), EMigrationWarehouseNotEmpty);
        assert!(warehouse.is_initialized == true, EMigrationWarehouseNotInitialized);

        let MigrationWarehouse {
            id,
            pfps,
            is_initialized: _,
        } = warehouse;

        object_table::destroy_empty(pfps);
        object::delete(id);
    }

    /// Destroy an empty mint warehouse when it's no longer needed.
    public fun admin_destroy_mint_warehouse(
        cap: &AdminCap,
        warehouse: MintWarehouse,
        ctx: &TxContext,
    ) {
        admin::verify_admin_cap(cap, ctx);

        assert!(table_vec::is_empty(&warehouse.pfps), EMintWarehouseNotEmpty);
        assert!(warehouse.is_initialized == true, EMintWarehouseNotInitialized);

        let MintWarehouse {
            id,
            pfps,
            is_initialized: _,
        } = warehouse;

        table_vec::destroy_empty(pfps);
        object::delete(id);
    }

    /// Set phase and mint price.
    public fun admin_set_mint_phase(
        cap: &AdminCap,
        phase: u8,
        settings: &mut MintSettings,
        ctx: &TxContext,
    ) {
        admin::verify_admin_cap(cap, ctx);

        assert!(phase >= 1 && phase <= 3, EInvalidPhaseNumber);
        settings.phase = phase;
    }

    public fun admin_set_mint_price(
        cap: &AdminCap,
        price: u64,
        settings: &mut MintSettings,
        ctx: &TxContext,
    ) {
        admin::verify_admin_cap(cap, ctx);

        assert!(price > 0, EInvalidPrice);
        settings.price = price;
    }

    public fun admin_set_mint_status(
        cap: &AdminCap,
        status: u8,
        settings: &mut MintSettings,
        ctx: &TxContext,
    ) {
        admin::verify_admin_cap(cap, ctx);

        assert!(settings.status == 0 || settings.status == 1, EInvalidStatusNumber);
        settings.status = status;
    }

    public fun admin_issue_migration_ticket(
        cap: &AdminCap,
        number: u16,
        beneficiary: address,
        warehouse: &MigrationWarehouse,
        ctx: &mut TxContext,
    ) {
        admin::verify_admin_cap(cap, ctx);

        assert!(warehouse.is_initialized == true, EMigrationMintWarehouseNotIntialized);
        assert!(object_table::contains(&warehouse.pfps, number), EInvalidMigrationPfpNumber);

        let migration_ticket = MigrationTicket {
            id: object::new(ctx),
            number: number,
        };

        transfer::transfer(migration_ticket, beneficiary);
    }

    public fun admin_issue_whitelist_ticket(
        cap: &AdminCap,
        phase: u8,
        beneficiary: address,
        ctx: &mut TxContext,
    ) {
        admin::verify_admin_cap(cap, ctx);

        assert!(phase == 1 || phase == 2, EInvalidWhitelistPhaseNumber);

        let wl_ticket = WhitelistTicket {
            id: object::new(ctx),
            phase: phase,
        };
        
        transfer::transfer(wl_ticket, beneficiary);
    }

    public fun admin_refund_mint(
        cap: &AdminCap,
        mint: Mint,
        kiosk: &mut Kiosk,
        kiosk_owner_cap: &KioskOwnerCap,
        policy: &TransferPolicy<PrimeMachin>,
        ctx: &mut TxContext,
    ) {
        admin::verify_admin_cap(cap, ctx);

        assert!(tx_context::epoch(ctx) > mint.claim_expiration_epoch, EMintClaimPeriodNotExpired);
        
        let destroy_mint_receipt_cap = DestroyMintReceiptCap {
            id: object::new(ctx),
            number: mint.number,
        };

        // Extract Prime Machin and payment from Mint.
        let pfp = option::extract(&mut mint.pfp);
        let payment = option::extract(&mut mint.payment);

        // Lock Prime Machin into ADMIN's kiosk.
        kiosk::lock(kiosk, kiosk_owner_cap, policy, pfp);

        // Transfer payment back to the original minter.
        transfer::public_transfer(payment, mint.minted_by);
        // Transfer cap object to destroy the mint receipt to the original minter.
        transfer::transfer(destroy_mint_receipt_cap, mint.minted_by);

        // Destroy the mint.
        destroy_mint_internal(mint);
    }

    public fun admin_reveal_mint(
        cap: RevealMintCap,
        mint: &mut Mint,
        attributes: Attributes,
        image: Image,
        rarity: Rarity,
    ) {
        assert!(cap.mint_id == object::id(mint), EInvalidRevealMintCapForMint);

        image::verify_image_chunks_registered(&image);

        let pfp = option::borrow_mut(&mut mint.pfp);

        factory::set_attributes(pfp, attributes);
        factory::set_image(pfp, image);
        factory::set_rarity(pfp, rarity);

        mint.is_revealed = true;

        let RevealMintCap {
            id,
            number: _,
            pfp_id: _,
            mint_id: _,
            create_attributes_cap_id: _,
            create_image_cap_id: _,
            create_rarity_cap_id: _,
        } = cap;
        object::delete(id);
    }

    fun mint_internal(
        pfp: PrimeMachin,
        payment: Coin<SUI>,
        ctx: &mut TxContext,
    ) {
        let mint = Mint {
            id: object::new(ctx),
            number: factory::number(&pfp),
            pfp: option::none(),
            payment: option::some(payment),
            is_revealed: false,
            minted_by: tx_context::sender(ctx),
            claim_expiration_epoch: tx_context::epoch(ctx) + EPOCHS_TO_CLAIM_MINT,
        };

        let receipt = MintReceipt {
            id: object::new(ctx),
            number: factory::number(&pfp),
            mint_id: object::id(&mint),
        };

        let create_attributes_cap = attributes::issue_create_attributes_cap(factory::number(&pfp), ctx);
        let create_image_cap = image::issue_create_image_cap(factory::number(&pfp), 0, object::id(&mint), ctx);
        let create_rarity_cap = rarity::issue_create_rarity_cap(factory::number(&pfp), ctx);
        
        let reveal_mint_cap = RevealMintCap {
            id: object::new(ctx),
            number: factory::number(&pfp),
            pfp_id: factory::id(&pfp),
            mint_id: object::id(&mint),
            create_attributes_cap_id: attributes::create_attributes_cap_id(&create_attributes_cap),
            create_image_cap_id: image::create_image_cap_id(&create_image_cap),
            create_rarity_cap_id: rarity::create_rarity_cap_id(&create_rarity_cap),
        };

        event::emit(
            MintEvent {
                mint_id: object::id(&mint),
                pfp_id: factory::id(&pfp),
                pfp_number: factory::number(&pfp),
                minted_by: tx_context::sender(ctx),
            }
        );

        factory::set_minted_by_address(&mut pfp, tx_context::sender(ctx));
        option::fill(&mut mint.pfp, pfp);
        
        transfer::transfer(receipt, tx_context::sender(ctx));
        transfer::transfer(reveal_mint_cap, @sm_api);

        transfer::public_transfer(create_attributes_cap, @sm_api);
        transfer::public_transfer(create_image_cap, @sm_api);
        transfer::public_transfer(create_rarity_cap, @sm_api);

        transfer::share_object(mint);
    }

    fun destroy_mint_internal(
        mint: Mint,
    ) {
        let Mint {
            id,
            number: _,
            pfp,
            payment,
            is_revealed: _,
            minted_by: _,
            claim_expiration_epoch: _,
        } = mint;
        
        option::destroy_none(pfp);
        option::destroy_none(payment);
        object::delete(id);
    }
}