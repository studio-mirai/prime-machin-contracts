module prime_machin::collection {

    // === Imports ===

    use sui::tx_context::{TxContext};
    
    // === Friends ===

    friend prime_machin::factory;
    friend prime_machin::registry;

    // === Constants ===

    const COLLECTION_SIZE: u16 = 3333;

    // === Structs ===

    struct COLLECTION has drop {}
    
    // === Init Function ===

    #[allow(unused_function)]
    fun init(
        _otw: COLLECTION,
        _ctx: &mut TxContext,
    ) {}

    // == Public-Friend Functions ===

    public(friend) fun size(): u16 {
        COLLECTION_SIZE
    }
}