use starknet::ContractAddress;
#[derive(Drop, Serde)]
struct AmmRoute {
    token_from: ContractAddress,
    token_to: ContractAddress,
    exchange_address: ContractAddress,
    amountIn: u256,
    additional_swap_params: Array<felt252>,
}

#[derive(Drop, Serde)]
struct Route {
    token_from: ContractAddress,
    token_to: ContractAddress,
    path: Array<AmmRoute>,
    percent: u128,
    additional_swap_params: Array<felt252>,
}
