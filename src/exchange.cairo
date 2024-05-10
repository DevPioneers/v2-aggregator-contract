use starknet::{ContractAddress, ClassHash};
use cairoswap::models::{Route};

#[starknet::interface]
trait IExchange<TContractState> {
    fn get_owner(self: @TContractState) -> ContractAddress;
    fn transfer_ownership(ref self: TContractState, new_owner: ContractAddress) -> bool;
    fn upgrade_class(ref self: TContractState, new_class_hash: ClassHash) -> bool;
    fn get_adapter_class_hash(
        self: @TContractState, exchange_address: ContractAddress
    ) -> ClassHash;
    fn set_adapter_class_hash(
        ref self: TContractState, exchange_address: ContractAddress, adapter_class_hash: ClassHash
    ) -> bool;
    fn get_fees_recipient(self: @TContractState) -> ContractAddress;
    fn set_fees_recipient(ref self: TContractState, recipient: ContractAddress) -> bool;
    fn get_aggregator_fee(self: @TContractState) -> u256;
    fn set_aggregator_fee(ref self: TContractState, bps: u256) -> bool;

    // the heart of CairoSwap 
    fn aggregator_swap(
        ref self: TContractState,
        token_in: ContractAddress,
        token_from_amount: u256,
        token_out: ContractAddress,
        token_to_amount: u256,
        amount: u256,
        routes: Array<Route>,
        trade_type: u64,
    ) -> bool;
}

#[starknet::contract]
mod Exchange {
    use array::ArrayTrait;
    use option::OptionTrait;
    use result::ResultTrait;
    use traits::{TryInto, Into};
    use zeroable::Zeroable;
    use super::IExchange;
    use starknet::{
        replace_class_syscall, ContractAddress, ClassHash, get_caller_address, get_contract_address
    };
    use cairoswap::adapters::{ISwapAdapterLibraryDispatcher, ISwapAdapterDispatcherTrait};
    use cairoswap::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use cairoswap::interfaces::locker::{
        ILocker, ISwapAfterLockLibraryDispatcher, ISwapAfterLockDispatcherTrait
    };
    use cairoswap::math::muldiv::muldiv;
    use cairoswap::models::Route;

    const MAX_cairoswap_FEES_BPS: u128 = 100;
    const MAX_INTEGRATOR_FEES_BPS: u128 = 500;
    const CONTRACT_BALANCE: u256 =
        57896044618658097711785492504343953926634992332820282019728792003956564819968_u256;


    #[storage]
    struct Storage {
        Ownable_owner: ContractAddress,
        AdapterClassHash: LegacyMap<ContractAddress, ClassHash>,
        aggregator_fee: u256,
        fees_recipient: ContractAddress,
        is_lock: bool,
    }

    #[event]
    #[derive(starknet::Event, Drop, PartialEq)]
    enum Event {
        Swap: Swap,
        OwnershipTransferred: OwnershipTransferred,
    }

    #[derive(Drop, starknet::Event, PartialEq)]
    struct Swap {
        taker_address: ContractAddress,
        sell_address: ContractAddress,
        sell_amount: u256,
        buy_address: ContractAddress,
        buy_amount: u256,
    }

    #[derive(starknet::Event, Drop, PartialEq)]
    struct OwnershipTransferred {
        previous_owner: ContractAddress,
        new_owner: ContractAddress,
    }

    #[external(v0)]
    impl ExchangeLocker of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Array<felt252>) -> Array<felt252> {
            let caller_address = get_caller_address();
            let exchange_address = (*data[0]).try_into().unwrap();

            // Only allow exchange's contract to call this method.
            assert(caller_address == exchange_address, 'UNAUTHORIZED_CALLBACK');

            // Get adapter class hash
            // and verify that `exchange_address` is known
            // `swap_after_lock` cannot be called by unknown contract address
            let class_hash = self.get_adapter_class_hash(exchange_address);
            assert(!class_hash.is_zero(), 'Unknown exchange');

            // Call adapter to execute the swap
            let adapter_dispatcher = ISwapAfterLockLibraryDispatcher { class_hash };
            adapter_dispatcher.swap_after_lock(data);

            ArrayTrait::new()
        }
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, owner: ContractAddress, fee_recipient: ContractAddress
    ) {
        // Set owner & fee collector address
        self._transfer_ownership(owner);
        self.fees_recipient.write(fee_recipient);
        self.aggregator_fee.write(0);
    }

    #[external(v0)]
    impl Exchange of IExchange<ContractState> {
        fn get_owner(self: @ContractState) -> ContractAddress {
            self.Ownable_owner.read()
        }

        fn transfer_ownership(ref self: ContractState, new_owner: ContractAddress) -> bool {
            self.assert_only_owner();
            assert(!new_owner.is_zero(), 'New owner is the zero address');
            self._transfer_ownership(new_owner);
            true
        }

        fn upgrade_class(ref self: ContractState, new_class_hash: ClassHash) -> bool {
            self.assert_only_owner();
            replace_class_syscall(new_class_hash);
            true
        }

        fn get_adapter_class_hash(
            self: @ContractState, exchange_address: ContractAddress
        ) -> ClassHash {
            self.AdapterClassHash.read(exchange_address)
        }

        fn set_adapter_class_hash(
            ref self: ContractState,
            exchange_address: ContractAddress,
            adapter_class_hash: ClassHash
        ) -> bool {
            self.assert_only_owner();
            self.AdapterClassHash.write(exchange_address, adapter_class_hash);
            true
        }

        fn get_fees_recipient(self: @ContractState) -> ContractAddress {
            self.fees_recipient.read()
        }

        fn set_fees_recipient(ref self: ContractState, recipient: ContractAddress) -> bool {
            self.assert_only_owner();
            self.fees_recipient.write(recipient);
            true
        }

        fn get_aggregator_fee(self: @ContractState) -> u256 {
            self.aggregator_fee.read()
        }

        fn set_aggregator_fee(ref self: ContractState, bps: u256) -> bool {
            self.assert_only_owner();
            self.aggregator_fee.write(bps);
            true
        }

        fn aggregator_swap(
            ref self: ContractState,
            token_in: ContractAddress,
            token_from_amount: u256,
            token_out: ContractAddress,
            token_to_amount: u256,
            amount: u256,
            routes: Array<Route>,
            trade_type: u64,
        ) -> bool {
            self.only_unlock();
            self.lock_contract();
            let caller_address = get_caller_address();
            let router_address = get_contract_address();

            let route_len = routes.len();
            let routes_span = routes.span();
            assert(route_len > 0, 'Routes is empty');
            let token_in_dispatcher = IERC20Dispatcher { contract_address: token_in };
            let token_out_dispatcher = IERC20Dispatcher { contract_address: token_out };

            // Transfer tokens to contract
            assert(token_from_amount > 0, 'Token from amount is 0');
            token_in_dispatcher.transferFrom(caller_address, router_address, token_from_amount);

            // First get balance of user and contract before swap
            let (_, balance_contract_before_out, balance_user_before_in, _) = self
                .get_balance_tokens_in_out(
                    token_in_dispatcher, token_out_dispatcher, caller_address, trade_type
                );

            self.apply_routes(routes, router_address, trade_type);

            let (_, balance_contract_after_out, balance_user_after_in, _) = self
                .get_balance_tokens_in_out(
                    token_in_dispatcher, token_out_dispatcher, caller_address, trade_type
                );
            let mut diff_balance = 0_u256;
            if trade_type == 0 {
                diff_balance = balance_contract_after_out - balance_contract_before_out;
                assert(diff_balance >= amount, 'less than min_amount_out');
                let mut contract_fee = diff_balance * self.aggregator_fee.read() / 10000_u256;
                if contract_fee > diff_balance - amount {
                    contract_fee = diff_balance - amount;
                }
                let user_received = diff_balance - contract_fee;
                token_out_dispatcher.transfer(self.fees_recipient.read(), contract_fee);
                token_out_dispatcher.transfer(caller_address, user_received);
            } else {
                diff_balance = balance_user_before_in - balance_user_after_in;
                assert(diff_balance <= amount, 'greater than max_amount_in');
                let mut contract_fee = diff_balance * self.aggregator_fee.read() / 10000_u256;
                if contract_fee > amount - diff_balance {
                    contract_fee = amount - diff_balance;
                }
                if contract_fee > 0 {
                    token_in_dispatcher
                        .transferFrom(caller_address, self.fees_recipient.read(), contract_fee);
                }
                token_out_dispatcher
                    .transfer(
                        caller_address, balance_contract_after_out - balance_contract_before_out
                    );
            }

            self.unlock_contract();
            true
        }
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn assert_only_owner(self: @ContractState) {
            let owner = self.get_owner();
            let caller = get_caller_address();
            assert(!caller.is_zero(), 'Caller is the zero address');
            assert(caller == owner, 'Caller is not the owner');
        }

        fn _transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
            let previous_owner = self.get_owner();
            self.Ownable_owner.write(new_owner);
            self.emit(OwnershipTransferred { previous_owner, new_owner });
        }
        fn apply_routes(
            ref self: ContractState,
            mut routes: Array<Route>,
            contract_address: ContractAddress,
            trade_type: u64
        ) {
            if (routes.len() == 0) {
                return;
            }

            let this_aggregator_address = get_contract_address();

            // Retrieve current route
            let route: Route = routes.pop_front().unwrap();
            let mut amountIn = route.amountIn;
            let adapter_class_hash = self.get_adapter_class_hash(route.exchange_address);
            assert(!adapter_class_hash.is_zero(), 'Unknown amm');

            // Call swap
            // Todo: check if amountIn is CONTRACT_BALANCE
            if (amountIn == CONTRACT_BALANCE) {
                let token_from_addr = *route.path[0];
                let token_from = IERC20Dispatcher { contract_address: token_from_addr };
                amountIn = token_from.balanceOf(this_aggregator_address);
            }

            if (trade_type == 0) {
                /// for exact in 
                ISwapAdapterLibraryDispatcher { class_hash: adapter_class_hash }
                    .swap(
                        route.exchange_address,
                        amountIn,
                        0,
                        route.path,
                        this_aggregator_address,
                        route.additional_swap_params,
                    );
            } else { /// for exact out
            /// TODO 
            }

            self.apply_routes(routes, contract_address, trade_type);
        }
        // start of reentrancy
        fn lock_contract(ref self: ContractState) {
            self.is_lock.write(true);
        }
        fn unlock_contract(ref self: ContractState) {
            self.is_lock.write(false);
        }
        fn only_unlock(ref self: ContractState) {
            assert(self.is_lock.read() == false, 'Reentrancy');
        }
        // end of reentrancy
        fn get_balance_tokens_in_out(
            ref self: ContractState,
            token_in_dispatcher: IERC20Dispatcher,
            token_out_dispatcher: IERC20Dispatcher,
            user: ContractAddress,
            trade_type: u64
        ) -> (u256, u256, u256, u256) {
            let mut balance_contract_token_in = 0;
            let mut balance_contract_token_out = 0;
            let mut balance_user_token_in = 0;
            let mut balance_user_token_out = 0;
            let router_address = get_contract_address();

            assert(trade_type == 0 || trade_type == 1, 'wrong trade type');
            balance_contract_token_in = token_in_dispatcher.balanceOf(router_address);
            balance_contract_token_out = token_out_dispatcher.balanceOf(router_address);
            balance_user_token_in = token_in_dispatcher.balanceOf(user);
            balance_user_token_out = token_out_dispatcher.balanceOf(user);

            (
                balance_contract_token_in,
                balance_contract_token_out,
                balance_user_token_in,
                balance_user_token_out
            )
        }
    }
}
