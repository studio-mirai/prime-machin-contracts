module prime_machin::receive {

    // === Imports ===

    use std::type_name::{Self, TypeName};

    use sui::coin::Coin;
    use sui::event;
    use sui::kiosk::{KioskOwnerCap};
    use sui::transfer::Receiving;

    use prime_machin::admin::AdminCap;
    use prime_machin::coloring::{ColoringReceipt};
    use prime_machin::factory::PrimeMachin;
    use prime_machin::image::{ImageChunk, RegisterImageChunkCap};

    use koto::koto::KOTO;

    // === Errors ===

    const EIncorrectKotoFeeAmount: u64 = 1;
    const EInvalidReceiveType: u64 = 2;
    const EInvalidKioskOwnerCapForPromise: u64 = 3;
    const EInvalidKioskOwnerCapForPrimeMachin: u64 = 4;

    // === Constants ===

    const DEFAULT_RECEIVE_FEE: u64 = 100; // 100 KOTO

    // === Structs ===

    public struct RECEIVE has drop {}

    public struct ReceiveSettings has key {
        id: UID,
        // KOTO fee for receiving an object.
        fee: u64,
    }

    /// A hot potato struct that forces the caller to return the KioskOwnerCap back
    /// to the Prime Machin before completing a PTB.
    public struct ReturnKioskOwnerCapPromise {
        pfp_id: ID,
        kiosk_owner_cap_id: ID,
    }

    // === Events ===

    public struct ObjectReceivedEvent has copy, drop {
        pfp_id: ID,
        received_object_id: ID,
        received_object_type: TypeName,
    }

    fun init(
        _otw: RECEIVE,
        ctx: &mut TxContext,
    ) {
        let settings = ReceiveSettings {
            id: object::new(ctx),
            fee: DEFAULT_RECEIVE_FEE,
        };

        transfer::share_object(settings);
    }

    /// A catch-all function to receive objects that have been sent to the Prime Machin.
    /// This function can be used to receive any type except KioskOwnerCap and KOTO.
    public fun receive<T: key + store>(
        pfp: &mut PrimeMachin,
        obj_to_receive: Receiving<T>,
        fee: Coin<KOTO>,
        settings: &ReceiveSettings,
    ): T {
        // Assert catch-all receive function is not used to receive KioskOwnerCap or KOTO.
        assert!(type_name::get<T>() != type_name::get<ColoringReceipt>(), EInvalidReceiveType);
        assert!(type_name::get<T>() != type_name::get<KioskOwnerCap>(), EInvalidReceiveType);
        assert!(type_name::get<T>() != type_name::get<KOTO>(), EInvalidReceiveType);
        assert!(type_name::get<T>() != type_name::get<ImageChunk>(), EInvalidReceiveType);
        assert!(type_name::get<T>() != type_name::get<RegisterImageChunkCap>(), EInvalidReceiveType);

        // Assert KOTO fee is the correct amount.
        assert!(fee.value() == settings.fee, EIncorrectKotoFeeAmount);

        // Transfer the fee to SM.
        transfer::public_transfer(fee, @sm_treasury);

        // Receive the object.
        let received_object = transfer::public_receive(pfp.uid_mut(), obj_to_receive);

        event::emit(
            ObjectReceivedEvent {
                pfp_id: pfp.id(),
                received_object_id: object::id(&received_object),
                received_object_type: type_name::get<T>(),
            }
        );

        received_object
    }

    /// A function for receiving KOTO coin objects that have been sent to the Prime Machin.
    /// This function bypasses the KOTO fee on the catch-all function.
    public fun receive_koto(
        pfp: &mut PrimeMachin,
        koto_to_receive: Receiving<Coin<KOTO>>,
    ): Coin<KOTO> {
        transfer::public_receive(pfp.uid_mut(), koto_to_receive)
    }

    /// A function for receiving the Prime Machin's KioskOwnerCap.
    /// This function returns the KioskOwnerCap as well as a ReturnKioskOwnerCapPromise
    /// to return it back to the Prime Machin. In order for a PTB to execute successfully,
    /// the KioskOwnerCap and ReturnKioskOwnerCapPromise must be passed to return_kiosk_owner_cap().
    public fun receive_kiosk_owner_cap(
        pfp: &mut PrimeMachin,
        kiosk_owner_cap_to_receive: Receiving<KioskOwnerCap>,
    ): (KioskOwnerCap, ReturnKioskOwnerCapPromise) {
        // Assert the KioskOwnerCap to receive matches the KioskOwnerCap assigned to the Prime Machin.
        assert!(transfer::receiving_object_id(&kiosk_owner_cap_to_receive) == pfp.kiosk_owner_cap_id(), EInvalidKioskOwnerCapForPrimeMachin);

        let kiosk_owner_cap = transfer::public_receive(pfp.uid_mut(), kiosk_owner_cap_to_receive);

        let promise = ReturnKioskOwnerCapPromise {
            pfp_id: pfp.id(),
            kiosk_owner_cap_id: object::id(&kiosk_owner_cap),
        };

        (kiosk_owner_cap, promise)
    }

    /// Return the KioskOwnerCap back to the Prime Machin, and destroy the ReturnKioskOwnerCapPromise.
    public fun return_kiosk_owner_cap(
        kiosk_owner_cap: KioskOwnerCap,
        promise: ReturnKioskOwnerCapPromise,
    ) {
        assert!(promise.kiosk_owner_cap_id == object::id(&kiosk_owner_cap), EInvalidKioskOwnerCapForPromise);
        transfer::public_transfer(kiosk_owner_cap, promise.pfp_id.to_address());

        let ReturnKioskOwnerCapPromise { pfp_id: _, kiosk_owner_cap_id: _ } = promise;
    }

    // === Admin Functions ===

    /// Set the KOTO fee associated with catch-all receives.
    public fun admin_set_receive_fee(
        cap: &AdminCap,
        settings: &mut ReceiveSettings,
        amount: u64,
        ctx: &TxContext,
    ) {
        cap.verify_admin_cap(ctx);

        settings.fee= amount
    }
}
