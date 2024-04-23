module prime_machin::mint {

    // === Imports ===

    use std::string;

    use sui::coin::{Self, Coin};
    use sui::display;
    use sui::event;
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
    use sui::object_table::{Self, ObjectTable};
    use sui::package;
    use sui::sui::SUI;
    use sui::table_vec::{Self, TableVec};
    use sui::transfer_policy::{TransferPolicy};

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

    public struct MINT has drop {}

    public struct DestroyMintReceiptCap has key {
        id: UID,
        number: u16,
    }

    public struct MigrationTicket has key, store {
        id: UID,
        number: u16,
    }

    public struct MigrationWarehouse has key {
        id: UID,
        pfps: ObjectTable<u16, PrimeMachin>,
        is_initialized: bool,
    }

    public struct Mint has key {
        id: UID,
        number: u16,
        pfp: Option<PrimeMachin>,
        payment: Option<Coin<SUI>>,
        is_revealed: bool,
        minted_by: address,
        claim_expiration_epoch: u64,
    }

    public struct MintReceipt has key {
        id: UID,
        number: u16,
        mint_id: ID,
    }

    public struct MintSettings has key {
        id: UID,
        price: u64,
        phase: u8,
        status: u8,
    }

    public struct MintWarehouse has key {
        id: UID,
        pfps: TableVec<PrimeMachin>,
        is_initialized: bool,
    }

    public struct RevealMintCap has key {
        id: UID,
        number: u16,
        pfp_id: ID,
        mint_id: ID,
        create_attributes_cap_id: ID,
        create_image_cap_id: ID,
        create_rarity_cap_id: ID,
    }

    public struct WhitelistTicket has key {
        id: UID,
        phase: u8,
    }

    // === Events ===

    public struct MintClaimedEvent has copy, drop {
        pfp_id: ID,
        pfp_number: u16,
        claimed_by: address,
        kiosk_id: ID,
    }

    public struct MintEvent has copy, drop {
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

        let mut migration_ticket_display = display::new<MigrationTicket>(&publisher, ctx);
        migration_ticket_display.add(b"name".to_string(), b"Prime Machin Migration Ticket #{number}".to_string());
        migration_ticket_display.add(b"description".to_string(), b"A ticket that can be used to migrate Prime Machin #{number} from ICON to Sui.".to_string());
        migration_ticket_display.add(b"number".to_string(), b"{number}".to_string());
        migration_ticket_display.add(b"image_url".to_string(), b"https://prime.nozomi.world/images/migration-ticket.webp".to_string());
        migration_ticket_display.update_version();
        transfer::public_transfer(migration_ticket_display, ctx.sender());

        let mut mint_receipt_display = display::new<MintReceipt>(&publisher, ctx);
        mint_receipt_display.add(b"name".to_string(), b"Prime Machin Mint Receipt #{number}".to_string());
        mint_receipt_display.add(b"description".to_string(), b"A receipt that can be used to claim Prime Machin #{number}.".to_string());
        mint_receipt_display.add(b"number".to_string(), b"{number}".to_string());
        mint_receipt_display.add(b"mint_id".to_string(), b"{mint_id}".to_string());
        mint_receipt_display.add(b"image_url".to_string(), b"https://prime.nozomi.world/images/mint-receipt.webp".to_string());
        mint_receipt_display.update_version();
        transfer::public_transfer(mint_receipt_display, ctx.sender());

        let mut wl_ticket_display = display::new<WhitelistTicket>(&publisher, ctx);
        wl_ticket_display.add(b"name".to_string(), b"Prime Machin Whitelist Ticket (Phase {phase})".to_string());
        wl_ticket_display.add(b"description".to_string(), b"A Phase {phase} whitelist ticket for the Prime Machin collection by Studio Mirai.".to_string());
        wl_ticket_display.add(b"phase".to_string(), b"{phase}".to_string());
        wl_ticket_display.add(b"image_url".to_string(), b"https://prime.nozomi.world/images/wl-ticket-phase-{phase}.webp".to_string());
        wl_ticket_display.update_version();
        transfer::public_transfer(wl_ticket_display, ctx.sender());

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
        mut mint: Mint,
        kiosk: &mut Kiosk,
        kiosk_owner_cap: &KioskOwnerCap,
        policy: &TransferPolicy<PrimeMachin>,
        ctx: &TxContext,
    ) {
        assert!(receipt.mint_id == object::id(&mint), EInvalidReceiptForMint);
        assert!(mint.is_revealed == true, EPrimeMachinNotRevealed);

        // Extract Prime Machin and payment from Mint.
        let pfp = mint.pfp.extract();
        let payment = mint.payment.extract();

        event::emit(
            MintClaimedEvent {
                pfp_id: pfp.id(),
                pfp_number: pfp.number(),
                claimed_by: ctx.sender(),
                kiosk_id: object::id(kiosk),
            }
        );

        // Lock Prime Machin into buyer's kiosk.
        kiosk.lock(kiosk_owner_cap, policy, pfp);

        // Transfer payment to SM.
        transfer::public_transfer(payment, @sm_treasury);

        // Destroy the mint.
        destroy_mint_internal(mint);

        // Destroy the mint receipt.
        let MintReceipt { id, number: _, mint_id: _ } = receipt;
        id.delete();
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
        id.delete();

        let MintReceipt { id, number: _, mint_id: _ } = receipt;
        id.delete();
    }

    /// Destroy a migration ticket.
    public fun destroy_migration_ticket(
        ticket: MigrationTicket,
    ) {
        let MigrationTicket { id, number: _ } = ticket;
        id.delete();
    }

    /// Destroy a whitelist ticket.
    public fun destroy_whitelist_ticket(
        ticket: WhitelistTicket,
    ) {
        let WhitelistTicket { id, phase: _ } = ticket;
        id.delete();
    }


    public fun migration_mint(
        ticket: MigrationTicket,
        warehouse: &mut MigrationWarehouse,
        settings: &MintSettings,
        ctx: &mut TxContext,
    ) {
        assert!(settings.status == 1, EMintNotLive);
        assert!(settings.phase != 0, EMintPhaseNotSet);

        let pfp = warehouse.pfps.remove(ticket.number);
        let payment = coin::zero<SUI>(ctx);

        let MigrationTicket {
            id,
            number: _,
        } = ticket;
        id.delete();

        mint_internal(pfp, payment, ctx);
    }

    public fun public_mint(
        payment: Coin<SUI>,
        warehouse: &mut MintWarehouse,
        settings: &MintSettings,
        ctx: &mut TxContext,
    ) {
        assert!(warehouse.pfps.length() > 0, EWarehouseIsEmpty);

        assert!(settings.status == 1, EMintNotLive);
        assert!(settings.phase == 3, ECurrentPhaseNotPhaseThree);

        assert!(payment.value() == settings.price, EInvalidPaymentAmount);

        let pfp = warehouse.pfps.pop_back();
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

        assert!(payment.value() == settings.price, EInvalidPaymentAmount);

        let pfp = warehouse.pfps.pop_back();
        mint_internal(pfp, payment, ctx);

        let WhitelistTicket { id, phase: _ } = ticket;
        id.delete();
    }

    /// Add Prime Machin PFPs to the mint warehouse.
    public fun admin_add_to_mint_warehouse(
        cap: &AdminCap,
        mut pfps: vector<PrimeMachin>,
        warehouse: &mut MintWarehouse,
        ctx: &TxContext,
    ) {
        cap.verify_admin_cap(ctx);

        assert!(warehouse.is_initialized == false, EMintWarehouseAlreadyInitialized);

        while (!pfps.is_empty()) {
            let pfp = pfps.pop_back();
            warehouse.pfps.push_back(pfp);
        };

        if ((warehouse.pfps.length() as u16) == TARGET_NEW_MINT_COUNT) {
            warehouse.is_initialized = true;
        };

        pfps.destroy_empty()
    }

    /// Add Prime Machin PFPs to the migration warehouse.
    public fun admin_add_to_migration_warehouse(
        cap: &AdminCap,
        mut pfps: vector<PrimeMachin>,
        warehouse: &mut MigrationWarehouse,
        ctx: &TxContext,
    ) {
        cap.verify_admin_cap(ctx);

        assert!(warehouse.is_initialized == false, EMigrationWarehouseAlreadyInitialized);

        while (!pfps.is_empty()) {
            let pfp = pfps.pop_back();
            warehouse.pfps.add(pfp.number(), pfp);
        };

        if ((warehouse.pfps.length() as u16) == TARGET_MIGRATION_MINT_COUNT) {
            warehouse.is_initialized = true;
        };

        pfps.destroy_empty();
    }

    /// Destroy an empty migration warehouse when it's no longer needed.
    public fun admin_destroy_migration_warehouse(
        cap: &AdminCap,
        warehouse: MigrationWarehouse,
        ctx: &TxContext,
    ) {
        cap.verify_admin_cap(ctx);

        assert!(warehouse.pfps.is_empty(), EMigrationWarehouseNotEmpty);
        assert!(warehouse.is_initialized == true, EMigrationWarehouseNotInitialized);

        let MigrationWarehouse {
            id,
            pfps,
            is_initialized: _,
        } = warehouse;

        pfps.destroy_empty();
        id.delete();
    }

    /// Destroy an empty mint warehouse when it's no longer needed.
    public fun admin_destroy_mint_warehouse(
        cap: &AdminCap,
        warehouse: MintWarehouse,
        ctx: &TxContext,
    ) {
        cap.verify_admin_cap(ctx);

        assert!(warehouse.pfps.is_empty(), EMintWarehouseNotEmpty);
        assert!(warehouse.is_initialized == true, EMintWarehouseNotInitialized);

        let MintWarehouse {
            id,
            pfps,
            is_initialized: _,
        } = warehouse;

        pfps.destroy_empty();
        id.delete();
    }

    /// Set phase and mint price.
    public fun admin_set_mint_phase(
        cap: &AdminCap,
        phase: u8,
        settings: &mut MintSettings,
        ctx: &TxContext,
    ) {
        cap.verify_admin_cap(ctx);

        assert!(phase >= 1 && phase <= 3, EInvalidPhaseNumber);
        settings.phase = phase;
    }

    public fun admin_set_mint_price(
        cap: &AdminCap,
        price: u64,
        settings: &mut MintSettings,
        ctx: &TxContext,
    ) {
        cap.verify_admin_cap(ctx);

        assert!(price > 0, EInvalidPrice);
        settings.price = price;
    }

    public fun admin_set_mint_status(
        cap: &AdminCap,
        status: u8,
        settings: &mut MintSettings,
        ctx: &TxContext,
    ) {
        cap.verify_admin_cap(ctx);

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
        cap.verify_admin_cap(ctx);

        assert!(warehouse.is_initialized == true, EMigrationMintWarehouseNotIntialized);
        assert!(warehouse.pfps.contains(number), EInvalidMigrationPfpNumber);

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
        cap.verify_admin_cap(ctx);

        assert!(phase == 1 || phase == 2, EInvalidWhitelistPhaseNumber);

        let wl_ticket = WhitelistTicket {
            id: object::new(ctx),
            phase: phase,
        };

        transfer::transfer(wl_ticket, beneficiary);
    }

    public fun admin_refund_mint(
        cap: &AdminCap,
        mut mint: Mint,
        kiosk: &mut Kiosk,
        kiosk_owner_cap: &KioskOwnerCap,
        policy: &TransferPolicy<PrimeMachin>,
        ctx: &mut TxContext,
    ) {
        cap.verify_admin_cap(ctx);

        assert!(ctx.epoch() > mint.claim_expiration_epoch, EMintClaimPeriodNotExpired);

        let destroy_mint_receipt_cap = DestroyMintReceiptCap {
            id: object::new(ctx),
            number: mint.number,
        };

        // Extract Prime Machin and payment from Mint.
        let pfp = mint.pfp.extract();
        let payment = mint.payment.extract();

        // Lock Prime Machin into ADMIN's kiosk.
        kiosk.lock(kiosk_owner_cap, policy, pfp);

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

        let pfp = mint.pfp.borrow_mut();

        pfp.set_attributes(attributes);
        pfp.set_image(image);
        pfp.set_rarity(rarity);

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
        id.delete();
    }

    fun mint_internal(
        mut pfp: PrimeMachin,
        payment: Coin<SUI>,
        ctx: &mut TxContext,
    ) {
        let mut mint = Mint {
            id: object::new(ctx),
            number: pfp.number(),
            pfp: option::none(),
            payment: option::some(payment),
            is_revealed: false,
            minted_by: ctx.sender(),
            claim_expiration_epoch: ctx.epoch() + EPOCHS_TO_CLAIM_MINT,
        };

        let receipt = MintReceipt {
            id: object::new(ctx),
            number: pfp.number(),
            mint_id: object::id(&mint),
        };

        let create_attributes_cap = attributes::issue_create_attributes_cap(pfp.number(), ctx);
        let create_image_cap = image::issue_create_image_cap(pfp.number(), 0, object::id(&mint), ctx);
        let create_rarity_cap = rarity::issue_create_rarity_cap(pfp.number(), ctx);

        let reveal_mint_cap = RevealMintCap {
            id: object::new(ctx),
            number: pfp.number(),
            pfp_id: pfp.id(),
            mint_id: object::id(&mint),
            create_attributes_cap_id: attributes::create_attributes_cap_id(&create_attributes_cap),
            create_image_cap_id: image::create_image_cap_id(&create_image_cap),
            create_rarity_cap_id: rarity::create_rarity_cap_id(&create_rarity_cap),
        };

        event::emit(
            MintEvent {
                mint_id: object::id(&mint),
                pfp_id: pfp.id(),
                pfp_number: pfp.number(),
                minted_by: ctx.sender(),
            }
        );

        pfp.set_minted_by_address(ctx.sender());
        mint.pfp.fill(pfp);

        transfer::transfer(receipt, ctx.sender());
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

        pfp.destroy_none();
        payment.destroy_none();
        id.delete();
    }
}
