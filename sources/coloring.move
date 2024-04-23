module prime_machin::coloring {

    // === Imports ===

    use sui::coin::Coin;
    use sui::display;
    use sui::package;
    use sui::sui::SUI;
    use sui::transfer::Receiving;
    use sui::table::{Self, Table};

    use prime_machin::admin::AdminCap;
    use prime_machin::factory::{Self , PrimeMachin};
    use prime_machin::image::{Self, Image, DeleteImagePromise};

    use koto::koto::KOTO;

    // === Errors ===

    const EAlreadyLvl1Colored: u64 = 1;
    const EAlreadyLvl2Colored: u64 = 2;
    const ECapImageLevelMismatch: u64 = 3;
    const ECapImageNumberMismatch: u64 = 4;
    const EColoringNotFulfilledYet: u64 = 5;
    const EInvalidCapForStudio: u64 = 6;
    const EInvalidColoringLevel: u64 = 7;
    const EInvalidKotoPaymentAmount: u64 = 8;
    const EInvalidReceiptForPrimeMachin: u64 = 9;
    const EInvalidReceiptForStudio: u64 = 10;
    const EInvalidSuiPaymentAmount: u64 = 11;
    const ENotLvl1Colored: u64 = 12;

    // === Constants ===

    const DEFAULT_LVL1_COLORING_PRICE_KOTO: u64 = 2_000; // 2,000 KOTO
    const DEFAULT_LVL1_COLORING_PRICE_SUI: u64 = 5_000_000_000; // 5 SUI
    const DEFAULT_LVL2_COLORING_PRICE_KOTO: u64 = 10_000; // 10,000 KOTO
    const DEFAULT_LVL2_COLORING_PRICE_SUI: u64 = 150_000_000_000; // 150 SUI

    // === Structs ===

    public struct COLORING has drop {}

    /// An owned object issued to holders who purchase a coloring.
    public struct ColoringReceipt has key {
        id: UID,
        number: u16,
        pfp_id: ID,
        studio_id: ID,
        level: u8,
    }

    /// A shared object that stores settings related to coloring.
    public struct ColoringSettings has key {
        id: UID,
        lvl1_price_koto: u64,
        lvl1_price_sui: u64,
        lvl2_price_koto: u64,
        lvl2_price_sui: u64,
    }

    /// A shared object that maps a Prime Machin's number to a
    /// coloring studio ID. This registry is used to ensure that only one
    /// coloring studio can exist for a Prime Machin at any given time.
    public struct ColoringStudioRegistry has key {
        id: UID,
        studios: Table<u16, ID>,
    }

    /// A shared object for fulfilling coloring orders.
    public struct ColoringStudio has key {
        id: UID,
        number: u16,
        // The coloring level. 1 is color, 2 is custom.
        level: u8,
        image: Option<Image>,
        is_fulfilled: bool,
    }

    /// An owned object that lets the holder submit a coloring request.
    public struct ColoringTicket has key, store {
        id: UID,
        level: u8,
    }

    /// An owned object issued to ADMIN. Allows user to insert a finished
    /// image into a coloring studio.
    public struct FulfillColoringCap has key {
        id: UID,
        number: u16,
        level: u8,
        studio_id: ID,
        create_image_cap_id: ID,
    }

    // === Init Function ===

    #[allow(unused_function)]
    fun init(
        otw: COLORING,
        ctx: &mut TxContext,
    ) {
        let publisher = package::claim(otw, ctx);

        let mut coloring_receipt_display = display::new<ColoringReceipt>(&publisher, ctx);
        coloring_receipt_display.add(b"name".to_string(), b"Prime Machin #{number} Coloring Receipt".to_string());
        coloring_receipt_display.add(b"description".to_string(), b"A receipt to claim a Level {level} coloring for Prime Machin #{number}.".to_string());
        coloring_receipt_display.add(b"number".to_string(), b"{number}".to_string());
        coloring_receipt_display.add(b"studio_id".to_string(), b"{studio_id}".to_string());
        coloring_receipt_display.add(b"level".to_string(), b"{level}".to_string());
        coloring_receipt_display.add(b"image_url".to_string(), b"https://prime.nozomi.world/images/coloring-receipt.webp".to_string());
        coloring_receipt_display.update_version();
        transfer::public_transfer(coloring_receipt_display, ctx.sender());

        let mut coloring_ticket_display = display::new<ColoringTicket>(&publisher, ctx);
        coloring_ticket_display.add(b"name".to_string(), b"Prime Machin Coloring Ticket (Level {level})".to_string());
        coloring_ticket_display.add(b"description".to_string(), b"A ticket that can be used to Level {level} color a Prime Machin.".to_string());
        coloring_ticket_display.add(b"level".to_string(), b"{level}".to_string());
        coloring_ticket_display.add(b"image_url".to_string(), b"https://prime.nozomi.world/images/coloring-ticket-level-{level}.webp".to_string());
        coloring_ticket_display.update_version();

        let registry = ColoringStudioRegistry {
            id: object::new(ctx),
            studios: table::new(ctx),
        };

        let settings = ColoringSettings {
            id: object::new(ctx),
            lvl1_price_koto: DEFAULT_LVL1_COLORING_PRICE_KOTO,
            lvl2_price_koto: DEFAULT_LVL2_COLORING_PRICE_KOTO,
            lvl1_price_sui: DEFAULT_LVL1_COLORING_PRICE_SUI,
            lvl2_price_sui: DEFAULT_LVL2_COLORING_PRICE_SUI,
        };

        transfer::public_transfer(publisher, @sm_treasury);
        transfer::public_transfer(coloring_ticket_display, @sm_treasury);

        transfer::share_object(registry);
        transfer::share_object(settings);
    }

    // === Public-Mutative Functions ===

    public fun buy_coloring_ticket(
        level: u8,
        koto_payment: Coin<KOTO>,
        sui_payment: Coin<SUI>,
        settings: &ColoringSettings,
        ctx: &mut TxContext,
    ): ColoringTicket {
        assert!(level == 1 || level == 2, EInvalidColoringLevel);

        if (level == 1) {
            assert!(koto_payment.value() == settings.lvl1_price_koto, EInvalidKotoPaymentAmount);
            assert!(sui_payment.value() == settings.lvl1_price_sui, EInvalidSuiPaymentAmount);
        } else if (level == 2) {
            assert!(koto_payment.value() == settings.lvl2_price_koto, EInvalidKotoPaymentAmount);
            assert!(sui_payment.value() == settings.lvl2_price_sui, EInvalidSuiPaymentAmount);
        };

        let ticket = create_coloring_ticket_internal(level, ctx);

        transfer::public_transfer(koto_payment, @sm_treasury);
        transfer::public_transfer(sui_payment, @sm_treasury);

        ticket
    }

    /// Receive an image from a studio and attach it to a Prime Machin.
    /// This function returns the old image and a promise to delete the old image.
    /// In order for a PTB to succeed, the old image must be passed repeatedly to
    /// image::receive_and_destroy_image_chunk() until all chunks have been destroyed.
    /// Once all chunks have been destroyed, the old image and promise must be passed
    /// to image::delete_image(), which will destroy the image and associated promise.
    public fun claim_coloring(
        pfp: &mut PrimeMachin,
        receipt_to_receive: Receiving<ColoringReceipt>,
        mut studio: ColoringStudio,
        registry: &mut ColoringStudioRegistry,
        ctx: &mut TxContext,
    ): (Image, DeleteImagePromise) {
        // Receive receipt and verify that the receipt's number matches the Prime Machin's number.
        let receipt = transfer::receive(pfp.uid_mut(), receipt_to_receive);
        assert!(receipt.number == pfp.number(), EInvalidReceiptForPrimeMachin);

        // Verify the coloring has been fulfilled.
        assert!(studio.is_fulfilled == true, EColoringNotFulfilledYet);
        // Verify the studio ID matches the receipt's studio ID.
        assert!(object::id(&studio) == receipt.studio_id, EInvalidReceiptForStudio);

        // Unset the existing image, and put it into a DeleteImagePromise,
        // a hot potato struct which must be resolved in order for a PTB to succeed.
        let old_image = pfp.unset_image();
        let promise = image::issue_delete_image_promise(&old_image);

        // Remove new image from studio, and attach it to the Prime Machin.
        let new_image = studio.image.extract();
        pfp.set_image(new_image);

        // Set colored by address.
        if (studio.level == 1) {
            pfp.set_lvl1_colored_by_address(ctx.sender());
        } else if (studio.level == 2) {
            pfp.set_lvl2_colored_by_address(ctx.sender());
        };

        // Remove studio from the registry.
        let _studio_id = registry.studios.remove(receipt.number);

        // Destroy receipt.
        let ColoringReceipt {
            id,
            number: _,
            pfp_id: _,
            studio_id: _,
            level: _,
        } = receipt;

        id.delete();

        // Destroy studio.
        let ColoringStudio {
            id,
            number: _,
            level: _,
            image,
            is_fulfilled:_,
        } = studio;

        image.destroy_none();
        id.delete();

        (old_image, promise)
    }

    /// Destroy a coloring ticket.
    public fun destroy_coloring_ticket(
        ticket: ColoringTicket,
    ) {
        let ColoringTicket { id, level: _ } = ticket;
        id.delete()
    }

    /// Request a coloring with a coloring ticket.
    public fun request_coloring(
        pfp: &PrimeMachin,
        ticket: ColoringTicket,
        registry: &mut ColoringStudioRegistry,
        ctx: &mut TxContext,
    ) {
        // Assert there isn't already an active studio for this Prime Machin.
        assert!(!table::contains(&registry.studios, factory::number(pfp)), 1);

        if (ticket.level == 1) {
            assert!(pfp.lvl1_colored_by().is_none(), EAlreadyLvl1Colored);
        } else if (ticket.level == 2) {
            assert!(pfp.lvl1_colored_by().is_some(), ENotLvl1Colored);
            assert!(pfp.lvl2_colored_by().is_none(), EAlreadyLvl2Colored);
        };

        let studio = ColoringStudio {
            id: object::new(ctx),
            number: pfp.number(),
            level: ticket.level,
            image: option::none(),
            is_fulfilled: false,
        };

        let receipt = ColoringReceipt {
            id: object::new(ctx),
            number: pfp.number(),
            pfp_id: pfp.id(),
            studio_id: object::id(&studio),
            level: 1,
        };

        let create_image_cap = image::issue_create_image_cap(
            pfp.number(),
            ticket.level,
            object::id(&studio),
            ctx,
        );

        let fulfill_coloring_cap = FulfillColoringCap {
            id: object::new(ctx),
            number: pfp.number(),
            level: ticket.level,
            studio_id: object::id(&studio),
            create_image_cap_id: image::create_image_cap_id(&create_image_cap),
        };

        transfer::transfer(receipt, pfp.id().to_address());

        transfer::public_transfer(create_image_cap, @sm_api);
        transfer::transfer(fulfill_coloring_cap, @sm_api);

        registry.studios.add(pfp.number(), object::id(&studio));
        transfer::share_object(studio);

        // Destroy coloring ticket.
        let ColoringTicket {
            id,
            level: _,
        } = ticket;
        id.delete()
    }

    // === Admin Functions ===

    public fun admin_fulfill_coloring(
        cap: FulfillColoringCap,
        image: Image,
        studio: &mut ColoringStudio,
    ) {
        image::verify_image_chunks_registered(&image);

        assert!(cap.studio_id == object::id(studio), EInvalidCapForStudio);
        assert!(cap.number == image.number(), ECapImageNumberMismatch);
        assert!(cap.level == image.level(), ECapImageLevelMismatch);

        studio.image.fill(image);
        studio.is_fulfilled = true;

        let FulfillColoringCap {
            id,
            number: _,
            level: _,
            studio_id:_ ,
            create_image_cap_id: _,
        } = cap;
        id.delete()
    }

    public fun admin_issue_coloring_ticket(
        cap: &AdminCap,
        level: u8,
        beneficiary: address,
        ctx: &mut TxContext,
    ) {
        cap.verify_admin_cap(ctx);

        let ticket = create_coloring_ticket_internal(level, ctx);
        transfer::transfer(ticket, beneficiary);
    }

    public fun admin_set_coloring_prices(
        cap: &AdminCap,
        lvl1_price_koto: u64,
        lvl1_price_sui: u64,
        lvl2_price_koto: u64,
        lvl2_price_sui: u64,
        settings: &mut ColoringSettings,
        ctx: &mut TxContext,
    ) {
        cap.verify_admin_cap(ctx);

        settings.lvl1_price_koto = lvl1_price_koto;
        settings.lvl1_price_sui = lvl1_price_sui;
        settings.lvl2_price_koto = lvl2_price_koto;
        settings.lvl2_price_sui = lvl2_price_sui;
    }

    //=== Private Functions ===

    fun create_coloring_ticket_internal(
        level: u8,
        ctx: &mut TxContext,
    ): ColoringTicket {
        let ticket = ColoringTicket {
            id: object::new(ctx),
            level: level,
        };

        ticket
    }
}
