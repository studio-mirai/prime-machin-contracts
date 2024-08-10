module prime_machin::attributes {

    // === Imports ===

    use std::string::String;

    // === Structs ===

    /// An object that holds a `AttributesData` object,
    /// assigned to the "attributes" field of a `PrimeMachin` object.
    public struct Attributes has key, store {
        id: UID,
        number: u16,
        data: AttributesData,
    }

    /// An object that holds a Prime Machin's attributes.
    public struct AttributesData has store {
        aura: String,
        background: String,
        clothing: String,
        decal: String,
        headwear: String,
        highlight: String,
        internals: String,
        mask: String,
        screen: String,
        skin: String,
    }

    /// A cap object that gives ADMIN the ability to create
    /// `Attributes` and `AttributesData` objects.
    public struct CreateAttributesCap has key, store {
        id: UID,
        number: u16,
    }

    /// Create an `Attributes` object with a `CreateAttributesCap`.
    public fun new(
        cap: CreateAttributesCap,
        aura: String,
        background: String,
        clothing: String,
        decal: String,
        headwear: String,
        highlight: String,
        internals: String,
        mask: String,
        screen: String,
        skin: String,
        ctx: &mut TxContext,
    ): Attributes {
        let attributes_data = AttributesData {
            aura: aura,
            background: background,
            clothing: clothing,
            decal: decal,
            headwear: headwear,
            highlight: highlight,
            internals: internals,
            mask: mask,
            screen: screen,
            skin: skin,
        };

        let attributes = Attributes {
            id: object::new(ctx),
            number: cap.number,
            data: attributes_data,
        };

        let CreateAttributesCap { id, number: _ } = cap;
        id.delete();

        attributes
    }

    /// Create a `CreateAttributesCap`.
    public(package) fun issue_create_attributes_cap(
        number: u16,
        ctx: &mut TxContext,
    ): CreateAttributesCap {
        let cap = CreateAttributesCap {
            id: object::new(ctx),
            number: number,
        };

        cap
    }

    /// Returns the number of the `Attributes` object.
    public(package) fun number(
        attributes: &Attributes,
    ): u16 {
        attributes.number
    }

    /// Returns the ID of the `CreateAttributesCap` object.
    public(package) fun create_attributes_cap_id(
        cap: &CreateAttributesCap,
    ): ID {
        object::id(cap)
    }
}
