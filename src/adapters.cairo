mod jediswap_adapter;
mod myswap_adapter;
mod sithswap_adapter;
mod tenkswap_adapter;

use starknet::ContractAddress;
use array::ArrayTrait;

#[starknet::interface]
trait ISwapAdapter<TContractState> {
    fn swap(
        self: @TContractState,
        exchange_address: ContractAddress,
        token_from_amount: u256,
        token_to_min_amount: u256,
        path: Array<ContractAddress>,
        to: ContractAddress,
        additional_swap_params: Array<felt252>,
    );
}
