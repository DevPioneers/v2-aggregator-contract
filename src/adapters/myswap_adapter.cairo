use starknet::ContractAddress;

#[starknet::interface]
trait IMySwapRouter<TContractState> {
    fn swap(
        self: @TContractState,
        pool_id: felt252,
        token_from_addr: ContractAddress,
        amount_from: u256,
        amount_to_min: u256
    ) -> u256;
}

#[starknet::contract]
mod MyswapAdapter {
    use cairoswap::adapters::ISwapAdapter;
    use cairoswap::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use super::{IMySwapRouterDispatcher, IMySwapRouterDispatcherTrait};
    use starknet::ContractAddress;
    use array::ArrayTrait;

    #[storage]
    struct Storage {}

    #[external(v0)]
    impl MyswapAdapter of ISwapAdapter<ContractState> {
        fn swap(
            self: @ContractState,
            exchange_address: ContractAddress,
            token_from_amount: u256,
            token_to_min_amount: u256,
            path: Array<ContractAddress>,
            to: ContractAddress,
            additional_swap_params: Array<felt252>,
        ) {
            assert(additional_swap_params.len() == 1, 'Invalid swap params');
            assert(path.len() == 2, 'Invalid myswap v1 path');

            let pool_id = *additional_swap_params[0];
            let token_from_address = *path[0];
            IERC20Dispatcher { contract_address: token_from_address }
                .approve(exchange_address, token_from_amount);
            IMySwapRouterDispatcher { contract_address: exchange_address }
                .swap(pool_id, token_from_address, token_from_amount, token_to_min_amount);
        }
    }
}
