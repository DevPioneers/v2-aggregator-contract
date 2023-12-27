#[starknet::contract]
mod MockJediSwap {
    use avnu::adapters::jediswap_adapter::IJediSwapRouter;
    use starknet::contract_address_const;
    use array::ArrayTrait;

    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    struct Storage {}

    #[external(v0)]
    impl MockERC20Impl of IJediSwapRouter<ContractState> {
        fn swap_exact_tokens_for_tokens(
            self: @ContractState,
            amountIn: u256,
            amountOutMin: u256,
            path: Array<ContractAddress>,
            to: ContractAddress,
            deadline: u64
        ) -> Array<u256> {
            assert(amountIn == u256 { low: 1, high: 0 }, 'invalid amountIn');
            assert(amountOutMin == u256 { low: 2, high: 0 }, 'invalid amountOutMin');
            assert(path.len() == 2, 'invalid path');
            assert(to == contract_address_const::<0x4>(), 'invalid to');
            let mut amounts = ArrayTrait::new();
            amounts.append(u256 { low: 1, high: 0 });
            amounts
        }
    }
}

#[starknet::contract]
mod MockMySwap {
    use avnu::adapters::myswap_adapter::IMySwapRouter;
    use starknet::contract_address_const;
    use array::ArrayTrait;

    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    struct Storage {}

    #[external(v0)]
    impl MockERC20Impl of IMySwapRouter<ContractState> {
        fn swap(
            self: @ContractState,
            pool_id: felt252,
            token_from_addr: ContractAddress,
            amount_from: u256,
            amount_to_min: u256
        ) -> u256 {
            assert(pool_id == 0x9, 'invalid pool id');
            assert(amount_from == u256 { low: 1, high: 0 }, 'invalid amountIn');
            assert(amount_to_min == u256 { low: 2, high: 0 }, 'invalid amountOutMin');
            amount_to_min
        }
    }
}

#[starknet::contract]
mod MockSithSwap {
    use avnu::adapters::sithswap_adapter::{ISithSwapRouter, Route};
    use starknet::contract_address_const;
    use array::ArrayTrait;

    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    struct Storage {}

    #[external(v0)]
    impl MockERC20Impl of ISithSwapRouter<ContractState> {
        fn swapExactTokensForTokensSimple(
            self: @ContractState,
            amount_in: u256,
            amount_out_min: u256,
            token_from: ContractAddress,
            token_to: ContractAddress,
            to: ContractAddress,
            deadline: u64,
        ) -> Array<u256> {
            assert(amount_in == u256 { low: 1, high: 0 }, 'invalid amountIn');
            assert(amount_out_min == u256 { low: 2, high: 0 }, 'invalid amountOutMin');
            assert(to == contract_address_const::<0x4>(), 'invalid to');
            let mut amounts = ArrayTrait::new();
            amounts.append(u256 { low: 1, high: 0 });
            amounts
        }
    }
}

#[starknet::contract]
mod MockTenkSwap {
    use avnu::adapters::tenkswap_adapter::{ITenkSwapRouter, Route};
    use starknet::contract_address_const;
    use array::ArrayTrait;

    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    struct Storage {}

    #[external(v0)]
    impl MockERC20Impl of ITenkSwapRouter<ContractState> {
        fn swapExactTokensForTokens(
            self: @ContractState,
            amountIn: u256,
            amountOutMin: u256,
            path: Array<ContractAddress>,
            to: ContractAddress,
            deadline: u64
        ) -> Array<u256> {
            assert(amountIn == u256 { low: 1, high: 0 }, 'invalid amountIn');
            assert(amountOutMin == u256 { low: 2, high: 0 }, 'invalid amountOutMin');
            assert(path.len() == 2, 'invalid path');
            assert(to == contract_address_const::<0x4>(), 'invalid to');
            let mut amounts = ArrayTrait::new();
            amounts.append(u256 { low: 1, high: 0 });
            amounts
        }
    }
}

#[starknet::contract]
mod MockSwapAdapter {
    use core::array::ArrayTrait;
    use avnu::adapters::ISwapAdapter;
    use avnu::tests::mocks::mock_erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::{ContractAddress, get_contract_address};

    #[storage]
    struct Storage {}

    #[external(v0)]
    impl MockERC20Impl of ISwapAdapter<ContractState> {
        fn swap(
            self: @ContractState,
            exchange_address: ContractAddress,
            token_from_amount: u256,
            token_to_min_amount: u256,
            path: Array<ContractAddress>,
            to: ContractAddress,
            additional_swap_params: Array<felt252>,
        ) {
            let caller = get_contract_address();
            IERC20Dispatcher { contract_address: *path[0] }.burn(caller, token_from_amount);
            IERC20Dispatcher { contract_address: *path[path.len() - 1] }
                .mint(caller, token_from_amount);
        }
    }
}

