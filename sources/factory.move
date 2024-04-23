module prime_machin::factory {

    // === Imports ===

    use std::string;

    use sui::display;
    use sui::kiosk;
    use sui::math;
    use sui::object_table::{Self, ObjectTable};
    use sui::package;
    use sui::transfer_policy;

    use prime_machin::admin::{Self, AdminCap};
    use prime_machin::attributes::{Attributes};
    use prime_machin::collection;
    use prime_machin::image::{Self, Image, DeleteImagePromise};
    use prime_machin::rarity::{Rarity};
    use prime_machin::registry::{Self, Registry};

    // === Friends ===

    /* friend prime_machin::coloring; */
    /* friend prime_machin::mint; */
    /* friend prime_machin::receive; */

    // === Errors ===

    const EAttributesAlreadySet: u64 = 1;
    const EFactoryAlreadyInitialized: u64 = 2;
    const EFactoryNotEmpty: u64 = 3;
    const EFactoryNotInitialized: u64 = 4;
    const EImageAlreadySet: u64 = 5;
    const EImageNotSet: u64 = 6;
    const EImageNumberMismatch: u64 = 7;
    const ERarityAlreadySet: u64 = 8;


    // === Structs ===

    public struct FACTORY has drop {}

    public struct PrimeMachin has key, store {
        id: UID,
        number: u16,
        attributes: Option<Attributes>,
        image: Option<Image>,
        rarity: Option<Rarity>,
        lvl1_colored_by: Option<address>,
        lvl2_colored_by: Option<address>,
        minted_by: Option<address>,
        // ID of the Kiosk assigned to the Prime Machin.
        kiosk_id: ID,
        // ID of the KioskOwnerCap owned by the Prime Machin.
        kiosk_owner_cap_id: ID,
    }

    public struct Factory has key {
        id: UID,
        pfps: ObjectTable<u16, PrimeMachin>,
        is_initialized: bool,
    }

    // === Init Function ===

    #[allow(unused_variable, lint(share_owned))]
    fun init(
        otw: FACTORY,
        ctx: &mut TxContext,
    ) {
        let publisher = package::claim(otw, ctx);

        let factory = Factory {
            id: object::new(ctx),
            pfps: object_table::new(ctx),
            is_initialized: false,
        };

        let mut display = display::new<PrimeMachin>(&publisher, ctx);
        display.add(b"name".to_string(), b"Prime Machin #{number}".to_string());
        display.add(b"description".to_string(), b"Prime Machin #{number} manufactured by the Triangle Company.".to_string());
        display.add(b"image_url".to_string(), b"https://img.sm.xyz/{id}/".to_string());
        display.add(b"attributes".to_string(), b"{attributes}".to_string());
        display.add(b"rarity".to_string(), b"{rarity}".to_string());
        display.add(b"lvl1_colored_by".to_string(), b"{lvl1_colored_by}".to_string());
        display.add(b"lvl2_colored_by".to_string(), b"{lvl2_colored_by}".to_string());
        display.add(b"minted_by".to_string(), b"{minted_by}".to_string());
        display.add(b"kiosk_id".to_string(), b"{kiosk_id}".to_string());
        display.add(b"kiosk_owner_cap_id".to_string(), b"{kiosk_owner_cap_id}".to_string());
        display.update_version();

        let (policy, policy_cap) = transfer_policy::new<PrimeMachin>(&publisher, ctx);

        transfer::transfer(factory, tx_context::sender(ctx));

        transfer::public_transfer(policy_cap, @sm_treasury);
        transfer::public_transfer(publisher, @sm_treasury);
        transfer::public_transfer(display, @sm_treasury);

        transfer::public_share_object(policy);
    }

    // === Admin Functions ===

    public fun admin_destroy_factory(
        cap: &AdminCap,
        factory: Factory,
        ctx: &TxContext,
    ) {
        admin::verify_admin_cap(cap, ctx);

        assert!(factory.is_initialized == true, EFactoryNotInitialized);
        assert!(object_table::is_empty(&factory.pfps), EFactoryNotEmpty);

        let Factory {
            id,
            pfps,
            is_initialized: _,
        } = factory;

        pfps.destroy_empty();
        id.delete();
    }

    #[allow(lint(share_owned))]
    public fun admin_initialize_factory(
        cap: &AdminCap,
        factory: &mut Factory,
        registry: &mut Registry,
        ctx: &mut TxContext,
    ) {
        admin::verify_admin_cap(cap, ctx);

        assert!(factory.is_initialized == false, EFactoryAlreadyInitialized);

        let mut number = (object_table::length(&factory.pfps) as u16) + 1;
        let end_number = (math::min((number + 332 as u64), (collection::size() as u64)) as u16);

        while (number <= end_number) {

            let (mut kiosk, kiosk_owner_cap) = kiosk::new(ctx);

            let pfp = PrimeMachin {
                id: object::new(ctx),
                number: number,
                attributes: option::none(),
                image: option::none(),
                rarity: option::none(),
                lvl1_colored_by: option::none(),
                lvl2_colored_by: option::none(),
                minted_by: option::none(),
                kiosk_id: object::id(&kiosk),
                kiosk_owner_cap_id: object::id(&kiosk_owner_cap),
            };

            // Set the Kiosk's 'owner' field to the address of the Prime Machin.
            kiosk::set_owner_custom(&mut kiosk, &kiosk_owner_cap, object::id_address(&pfp));

            transfer::public_transfer(kiosk_owner_cap, object::id_to_address(&object::id(&pfp)));
            transfer::public_share_object(kiosk);

            // Add Prime Machin to registry.
            registry::add(number, object::id(&pfp), registry);

            // Add Prime Machin to factory.
            object_table::add(&mut factory.pfps, number, pfp);

            number = number + 1;
        };

        // Initialize factory if 3,333 Prime Machin have been created.
        if ((object_table::length(&factory.pfps) as u16) == collection::size()) {
            factory.is_initialized = true;
        };
    }

    public fun admin_remove_from_factory(
        cap: &AdminCap,
        mut numbers: vector<u16>,
        factory: &mut Factory,
        ctx: &TxContext,
    ): vector<PrimeMachin> {
        admin::verify_admin_cap(cap, ctx);

        assert!(factory.is_initialized == true, EFactoryNotInitialized);

        let mut pfps = vector::empty<PrimeMachin>();

        while (!vector::is_empty(&numbers)) {
            let number = vector::pop_back(&mut numbers);
            let pfp = object_table::remove(&mut factory.pfps, number);
            vector::push_back(&mut pfps, pfp);
        };

        pfps
    }

    // === Public Friend Functions ===

    public(package) fun id(
        pfp: &PrimeMachin,
    ): ID {
        object::id(pfp)
    }

    public(package) fun uid_mut(
        pfp: &mut PrimeMachin,
    ): &mut UID {
        &mut pfp.id
    }

    public(package) fun number(
        pfp: &PrimeMachin,
    ): u16 {
        pfp.number
    }

    public(package) fun image(
        pfp: &PrimeMachin,
    ): &Image {
        option::borrow(&pfp.image)
    }

    public(package) fun kiosk_id(
        pfp: &PrimeMachin,
    ): ID {
        pfp.kiosk_id
    }

    public(package) fun kiosk_owner_cap_id(
        pfp: &PrimeMachin,
    ): ID {
        pfp.kiosk_owner_cap_id
    }

    public(package) fun lvl1_colored_by(
        pfp: &PrimeMachin,
    ): Option<address> {
        pfp.lvl1_colored_by
    }

    public(package) fun lvl2_colored_by(
        pfp: &PrimeMachin,
    ): Option<address> {
        pfp.lvl2_colored_by
    }

    public(package) fun set_attributes(
        pfp: &mut PrimeMachin,
        attributes: Attributes,
    ) {
        assert!(option::is_none(&pfp.attributes), EAttributesAlreadySet);
        option::fill(&mut pfp.attributes, attributes);
    }

    public(package) fun set_image(
        pfp: &mut PrimeMachin,
        image: Image,
    ) {
        assert!(option::is_none(&pfp.image), EImageAlreadySet);
        option::fill(&mut pfp.image, image);
    }

    public(package) fun unset_image(
        pfp: &mut PrimeMachin,
    ): Image {
        assert!(option::is_some(&pfp.image), EImageNotSet);
        option::extract(&mut pfp.image)
    }

    public(package) fun set_lvl1_colored_by_address(
        pfp: &mut PrimeMachin,
        addr: address,
    ) {
        option::fill(&mut pfp.lvl1_colored_by, addr);
    }

    public(package) fun set_lvl2_colored_by_address(
        pfp: &mut PrimeMachin,
        addr: address,
    ) {
        option::fill(&mut pfp.lvl2_colored_by, addr);
    }

    public(package) fun set_minted_by_address(
        pfp: &mut PrimeMachin,
        addr: address,
    ) {
        option::fill(&mut pfp.minted_by, addr);
    }

    public(package) fun set_rarity(
        pfp: &mut PrimeMachin,
        rarity: Rarity,
    ) {
        assert!(option::is_none(&pfp.rarity), ERarityAlreadySet);
        option::fill(&mut pfp.rarity, rarity);
    }

    public(package) fun swap_image(
        pfp: &mut PrimeMachin,
        new_image: Image,
    ): (Image, DeleteImagePromise) {
        assert!(pfp.number == image::number(&new_image), EImageNumberMismatch);

        let old_image = option::swap(&mut pfp.image, new_image);
        let promise = image::issue_delete_image_promise(&old_image);

        (old_image, promise)
    }
}
