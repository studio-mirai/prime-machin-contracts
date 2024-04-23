module prime_machin::collection {

    // === Friends ===

    /* friend prime_machin::factory; */
    /* friend prime_machin::registry; */

    // === Constants ===

    const COLLECTION_SIZE: u16 = 3333;

    // === Structs ===

    public struct COLLECTION has drop {}

    // === Init Function ===

    #[allow(unused_function)]
    fun init(
        _otw: COLLECTION,
        _ctx: &mut TxContext,
    ) {}

    // == Public-Friend Functions ===

    public(package) fun size(): u16 {
        COLLECTION_SIZE
    }
}
