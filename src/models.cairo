use starknet::ContractAddress;
#[derive(Drop, Serde)]
struct Route {
    exchange_address: ContractAddress,
    path: Array<ContractAddress>,
    amountIn: u256,
    additional_swap_params: Array<felt252>,
}
