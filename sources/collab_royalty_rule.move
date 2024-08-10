module prime_machin::collab_royalty_rule {

    use sui::table::{Self, Table};

    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::transfer_policy::{
        Self as policy,
        TransferPolicy,
        TransferPolicyCap,
        TransferRequest
    };

    use prime_machin::admin::{AdminCap};

    public struct Rule has drop {}

    const EMaxBpsExceeded: u64 = 0;
    const EIncorrectPaymentAmount: u64 = 1;

    const MAX_BPS: u16 = 10_000;

    public struct Royalty has drop, store {
        amount_bp: u16,
        recipient: address,
    }

    public struct Registry has key {
        id: UID,
        collaborations: Table<ID, Royalty>
    }

    public struct Config has store, drop {
        registry_id: ID,
    }

    public fun admin_add_collaboration(
        cap: &AdminCap,
        registry: &mut Registry,
        pfp_id: ID,
        amount_bp: u16,
        recipient: address,
        ctx: &TxContext,
    ) {
        cap.verify_admin_cap(ctx);
        
        assert!(amount_bp <= MAX_BPS, EMaxBpsExceeded);

        let royalty = Royalty {
            amount_bp: amount_bp,
            recipient: recipient,
        };
        registry.collaborations.add(pfp_id, royalty);
    }

    public fun admin_remove_collaboration(
        cap: &AdminCap,
        registry: &mut Registry,
        pfp_id: ID,
        ctx: &TxContext,
    ) {
        cap.verify_admin_cap(ctx);
        registry.collaborations.remove(pfp_id);
    }

    public fun add<T: key + store>(
        policy: &mut TransferPolicy<T>,
        cap: &TransferPolicyCap<T>,
        ctx: &mut TxContext,
    ) {
        let registry = Registry {
            id: object::new(ctx),
            collaborations: table::new(ctx),
        };
        policy::add_rule(Rule {}, policy, cap, Config { registry_id: registry.id.to_inner() });
        transfer::share_object(registry);
    }

    public fun pay<T: key + store>(
        policy: &mut TransferPolicy<T>,
        request: &mut TransferRequest<T>,
        payment: Coin<SUI>,
        registry: &Registry,
    ) {
        let paid = policy::paid(request);
        let amount = fee_amount(
            policy, 
            paid, 
            request.item(), 
            registry,
        );
        assert!(coin::value(&payment) == amount, EIncorrectPaymentAmount);
        policy::add_to_balance(Rule {}, policy, payment);
        policy::add_receipt(Rule {}, request)
    }

    public fun fee_amount<T: key + store>(
        policy: &TransferPolicy<T>,
        paid: u64,
        item_id: ID,
        registry: &Registry,
    ): u64 {
        let config: &Config = policy::get_rule(Rule {}, policy);
        assert!(registry.id.to_inner() == config.registry_id, 1);
        let royalty = registry.collaborations.borrow(item_id);  
        let amount = (((paid as u128) * (royalty.amount_bp as u128) / 10_000) as u64);
        amount
    }
}