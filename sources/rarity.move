module prime_machin::rarity {

    // === Imports ===

    use std::string::String;

    // === Friends ===

    /* friend prime_machin::mint; */
    /* friend prime_machin::factory; */

    // === Structs ===

    /// An object that holds a `RarityData` object,
    /// assigned to the "rarity" field of a `PrimeMachin` object.
    public struct Rarity has key, store {
        id: UID,
        number: u16,
        data: RarityData,
    }

    /// An object that holds class, rank, and score for a Prime Machin.
    public struct RarityData has store {
        class: String,
        rank: u16,
        score: u64,
    }

    /// A cap object that gives ADMIN the ability to create
    /// `Rarity` and `RarityData` objects.
    public struct CreateRarityCap has key, store {
        id: UID,
        number: u16,
    }

    /// Create a `Rarity` object with a `CreateRarityCap`.
    public fun create_rarity(
        cap: CreateRarityCap,
        class: String,
        rank: u16,
        score: u64,
        ctx: &mut TxContext,
    ): Rarity {
        let rarity_data = RarityData {
            class: class,
            rank: rank,
            score: score,
        };

        let rarity = Rarity {
            id: object::new(ctx),
            number: cap.number,
            data: rarity_data,
        };

        let CreateRarityCap { id, number: _ } = cap;
        object::delete(id);

        rarity
    }

    /// Create a `CreateRarityCap`.
    public(package) fun issue_create_rarity_cap(
        number: u16,
        ctx: &mut TxContext,
    ): CreateRarityCap {
        let cap = CreateRarityCap {
            id: object::new(ctx),
            number: number,
        };

        cap
    }

    /// Returns the number of the `Rarity` object.
    public(package) fun number(
        rarity: &Rarity,
    ): u16 {
        rarity.number
    }

    /// Returns the ID of the `CreateRarityCap` object.
    public(package) fun create_rarity_cap_id(
        cap: &CreateRarityCap,
    ): ID {
        object::id(cap)
    }
}
