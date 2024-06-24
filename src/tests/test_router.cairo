use array::{ArrayTrait, SpanTrait, SpanCopy, SpanSerde};
use clone::Clone;
use debug::PrintTrait;
use integer::u256_sqrt;
use integer::{U256Add, U256Sub, U256Mul, U256Div};
use integer::BoundedInt;
use option::OptionTrait;
use result::ResultTrait;
use serde::Serde;
use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::testing::{set_caller_address, set_contract_address};
use traits::{Into, TryInto, PartialEq};
use zeroable::Zeroable;


use karrot_exchange::erc20::ERC20;
use karrot_exchange::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use karrot_exchange::factory::{IFactoryDispatcher, IFactoryDispatcherTrait};
use karrot_exchange::factory::Factory;
use karrot_exchange::libraries::library;
use karrot_exchange::pool::{IPoolDispatcher, IPoolDispatcherTrait};
use karrot_exchange::pool::Pool;
use karrot_exchange::pool::Pool::PoolImpl;
use karrot_exchange::router::Router;
use karrot_exchange::router::Router::RouterImpl;
use karrot_exchange::router::Router::InternalImpl;
use karrot_exchange::router::{IRouterDispatcher, IRouterDispatcherTrait};
use karrot_exchange::tests::utils;

const DECIMALS: u8 = 18;
const MINIMUM_LIQUIDITY: u256 = 1000;
const INITIAL_LIQUIDITY: u256 = 1_000_000_000;

fn POOL_STATE() -> Pool::ContractState {
    Pool::contract_state_for_testing()
}

fn ERC20_STATE() -> ERC20::ContractState {
    ERC20::contract_state_for_testing()
}

fn ZERO_ADDRESS() -> ContractAddress {
    contract_address_const::<0>()
}

fn OWNER() -> ContractAddress {
    contract_address_const::<1>()
}

fn FACTORY() -> ContractAddress {
    contract_address_const::<2>()
}

fn TOKEN_A() -> ContractAddress {
    contract_address_const::<11>()
}

fn TOKEN_B() -> ContractAddress {
    contract_address_const::<12>()
}

//
// Setup
//

fn setup() -> Pool::ContractState {
    let mut state = POOL_STATE();
    set_caller_address(FACTORY());
    Pool::constructor(ref state);
    state
}

fn setup_erc20_tokens() -> (ERC20::ContractState, ERC20::ContractState) {
    let mut token_a_state = ERC20_STATE();
    let mut token_b_state = ERC20_STATE();
    (token_a_state, token_b_state)
}

//
// deploy setup
//

fn deploy_erc20_token(name: felt252) -> ContractAddress {
    set_caller_address(OWNER());

    let mut calldata = ArrayTrait::new();
    name.serialize(ref output: calldata);
    'ERC'.serialize(ref output: calldata);
    DECIMALS.serialize(ref output: calldata);
    INITIAL_LIQUIDITY.serialize(ref output: calldata);
    OWNER().serialize(ref output: calldata);

    let contract_address = utils::deploy(ERC20::TEST_CLASS_HASH, calldata);
    contract_address
}

fn deploy_factory() -> ContractAddress {
    set_caller_address(OWNER());
    let mut calldata = ArrayTrait::new();
    Pool::TEST_CLASS_HASH.serialize(ref output: calldata);
    OWNER().serialize(ref output: calldata);

    let contract_address = utils::deploy(Factory::TEST_CLASS_HASH, calldata);
    contract_address
}

fn deploy_pool(factory: ContractAddress) -> ContractAddress {
    set_caller_address(factory);
    let mut calldata = ArrayTrait::new();

    let contract_address = utils::deploy(Pool::TEST_CLASS_HASH, calldata);
    contract_address
}

fn deploy_pool_from_factory_contract(factory: ContractAddress) -> ContractAddress {
    set_caller_address(OWNER());
    let factory_dispatcher = IFactoryDispatcher { contract_address: factory };
    set_contract_address(factory);
    let pool = factory_dispatcher.create_pool(TOKEN_A(), TOKEN_B());
    'pool'.print();
    pool.print();
    pool
}

fn deploy_router(factory: ContractAddress) -> ContractAddress {
    set_caller_address(ZERO_ADDRESS()); // anyone can deploy router contract
    let mut calldata = ArrayTrait::new();
    factory.serialize(ref output: calldata);
    let contract_address = utils::deploy(Router::TEST_CLASS_HASH, calldata);
    contract_address
}

fn initialize_mint() -> (ContractAddress, ContractAddress, ContractAddress, ContractAddress) {
    // Assume factory contract is deployed
    let factory = deploy_factory();

    // Assume token_a and token_b are deployed
    let token_a = deploy_erc20_token('token_a');
    let token_b = deploy_erc20_token('token_b');

    // deploy pool contract, then initialize
    let pool = deploy_pool(factory);
    set_contract_address(factory);
    let pool_dispatcher = IPoolDispatcher { contract_address: pool };

    // for testing purposes, _set_pool_by_tokens in factory contract
    let factory_dispatcher = IFactoryDispatcher { contract_address: factory };
    factory_dispatcher._set_pool_by_tokens(token_a, token_b, pool);

    pool_dispatcher.initialize(token_a, token_b);
    (factory, pool, token_a, token_b)
}

fn process_mint(
    pool: ContractAddress,
    token_a: ContractAddress,
    token_b: ContractAddress,
    a_amount: u256,
    b_amount: u256
) -> (u256, u256, u256, u256, u256, u256) {
    // tranfer token a and token b to pool contract
    set_contract_address(OWNER());
    let pool_dispatcher = IPoolDispatcher { contract_address: pool };

    let token_a_dispatcher = IERC20Dispatcher { contract_address: token_a };
    let token_b_dispatcher = IERC20Dispatcher { contract_address: token_b };

    token_a_dispatcher.transfer(pool, a_amount);
    token_b_dispatcher.transfer(pool, b_amount);

    // mint
    set_contract_address(OWNER());
    let liquidity = pool_dispatcher.mint(OWNER());
    let total_supply = pool_dispatcher.total_supply();
    let balance0 = token_a_dispatcher.balanceOf(pool);
    let balance1 = token_b_dispatcher.balanceOf(pool);
    let (reserve0, reserve1) = pool_dispatcher.get_reserves();

    (liquidity, total_supply, balance0, balance1, reserve0, reserve1)
}

//*
//* constructor
//* 
#[test]
#[available_gas(200_000_000)]
fn test_constructor() {
    set_caller_address(ZERO_ADDRESS()); // anyone can deploy router contract
    let mut calldata = ArrayTrait::new();
    FACTORY().serialize(ref output: calldata);
    let contract_address = utils::deploy(Router::TEST_CLASS_HASH, calldata);
    let factory = IRouterDispatcher { contract_address: contract_address }.get_factory();
    assert(factory == FACTORY(), 'factory address is incorrect');
}

//
// Getters
//
#[test]
#[available_gas(200_000_000)]
fn test_quote() {
    assert(library::quote(100, 500, 100) == 20, 'amount_b is not equivalent');
}

#[test]
#[available_gas(200_000_000)]
fn test_sort_tokens() {
    let (token0, token1) = library::sort_tokens(TOKEN_B(), TOKEN_A());
    assert(token0 == TOKEN_A() && token1 == TOKEN_B(), 'tokens are not sorted (reverse)');
}

#[test]
#[available_gas(200_000_000)]
fn test_get_amount_out() {
    let amount_out = library::get_amount_out(50000, 50000, 50000);
    'amount_out'.print();
    amount_out.print();
}

#[test]
#[available_gas(200_000_000)]
fn test_get_amount_in() {
    let amount_in = library::get_amount_in(24962, 50000, 50000);
    'amount_in'.print();
    amount_in.print();
}

#[test]
#[available_gas(200_000_000)]
fn test_get_amounts_out() {
    set_contract_address(OWNER());
    let (factory, pool, token_a, token_b) = initialize_mint();
    let pool_dispatcher = IPoolDispatcher { contract_address: pool };

    // Mint
    let a_amount = 30_000_000;
    let b_amount = 50_000_000;

    let (liquidity, total_supply, balance0, balance1, reserve0, reserve1) = process_mint(
        pool, token_a, token_b, a_amount, b_amount
    );
    let mut path = ArrayTrait::<ContractAddress>::new();
    path.append(token_a);
    path.append(token_b);
    'path_0'.print();
    let path_0 = *path.at(0);
    path_0.print();
    'path_1'.print();
    let path_1 = *path.at(1);
    path_1.print();

    let amounts_out = library::get_amounts_out(factory, 10_000_00, path.span());

    let first_amount = amounts_out.at(0);
    let second_amount = amounts_out.at(1);
    'first_amount'.print();
    (*first_amount).print();
    'second_amount'.print();
    (*second_amount).print();
}

#[test]
#[available_gas(200_000_000)]
fn test_get_amounts_in() {
    set_contract_address(OWNER());
    let (factory, pool, token_a, token_b) = initialize_mint();
    let pool_dispatcher = IPoolDispatcher { contract_address: pool };

    // Mint
    let a_amount = 30_000_000;
    let b_amount = 50_000_000;
    let (liquidity, total_supply, balance0, balance1, reserve0, reserve1) = process_mint(
        pool, token_a, token_b, a_amount, b_amount
    );
    let mut path = ArrayTrait::<ContractAddress>::new();
    path.append(token_a);
    path.append(token_b);
    let amounts_in = library::get_amounts_in(factory, 1000, path.span());
}

#[test]
#[available_gas(200_000_000)]
fn test_add_liquidity() {
    set_contract_address(OWNER());
    let (factory, pool, token_a, token_b) = initialize_mint();
    let pool_dispatcher = IPoolDispatcher { contract_address: pool };

    // Mint
    let a_amount = 30_000_000;
    let b_amount = 50_000_000;

    let router = deploy_router(factory);
    let router_dispatcher = IRouterDispatcher { contract_address: router };

    set_caller_address(OWNER());
    let token_a_dispatcher = IERC20Dispatcher { contract_address: token_a };
    let token_b_dispatcher = IERC20Dispatcher { contract_address: token_b };

    set_contract_address(OWNER());
    'router'.print();
    router.print();
    token_a_dispatcher.approve(router, 5000);
    token_b_dispatcher.approve(router, 5000);
    router_dispatcher.add_liquidity(token_a, token_b, 5_000, 5_000, 0, 0, OWNER(), 166633333);
}

#[test]
#[available_gas(200_000_000)]
fn test_swap_exact_tokens_for_tokens() {
    set_contract_address(OWNER());
    let (factory, pool, token_a, token_b) = initialize_mint();
    let pool_dispatcher = IPoolDispatcher { contract_address: pool };

    // Mint
    let a_amount = 30_000_000;
    let b_amount = 50_000_000;

    let router = deploy_router(factory);
    let router_dispatcher = IRouterDispatcher { contract_address: router };

    set_caller_address(OWNER());
    let token_a_dispatcher = IERC20Dispatcher { contract_address: token_a };
    let token_b_dispatcher = IERC20Dispatcher { contract_address: token_b };

    set_contract_address(OWNER());
    'router'.print();
    router.print();
    token_a_dispatcher.approve(router, BoundedInt::max());
    token_b_dispatcher.approve(router, BoundedInt::max());
    router_dispatcher.add_liquidity(token_a, token_b, 5_000, 5_000, 0, 0, OWNER(), 166633333);

    let mut path = ArrayTrait::<ContractAddress>::new();
    path.append(token_a);
    path.append(token_b);
    set_contract_address(OWNER());
    router_dispatcher.swap_exact_tokens_for_tokens(2000, 0, path, OWNER(), 166633333);
}
#[test]
#[available_gas(200_000_000)]
fn test_swap_tokens_for_exact_tokens() {
    set_contract_address(OWNER());
    let (factory, pool, token_a, token_b) = initialize_mint();
    let pool_dispatcher = IPoolDispatcher { contract_address: pool };

    // Mint
    let a_amount = 30_000_000;
    let b_amount = 50_000_000;

    let router = deploy_router(factory);
    let router_dispatcher = IRouterDispatcher { contract_address: router };

    set_caller_address(OWNER());
    let token_a_dispatcher = IERC20Dispatcher { contract_address: token_a };
    let token_b_dispatcher = IERC20Dispatcher { contract_address: token_b };

    set_contract_address(OWNER());
    token_a_dispatcher.approve(router, BoundedInt::max());
    token_b_dispatcher.approve(router, BoundedInt::max());
    router_dispatcher.add_liquidity(token_a, token_b, 5_000, 5_000, 0, 0, OWNER(), 166633333);

    let mut path = ArrayTrait::<ContractAddress>::new();
    path.append(token_a);
    path.append(token_b);
    set_contract_address(OWNER());
    router_dispatcher.swap_tokens_for_exact_tokens(1000, 10000, path, OWNER(), 166633333);
}
#[test]
#[available_gas(200_000_000)]
fn test_remove_liquidity() {
    set_contract_address(OWNER());
    let (factory, pool, token_a, token_b) = initialize_mint();
    let pool_dispatcher = IPoolDispatcher { contract_address: pool };

    // Mint
    let a_amount = 30_000_000;
    let b_amount = 50_000_000;

    let router = deploy_router(factory);
    let router_dispatcher = IRouterDispatcher { contract_address: router };

    set_caller_address(OWNER());
    let token_a_dispatcher = IERC20Dispatcher { contract_address: token_a };
    let token_b_dispatcher = IERC20Dispatcher { contract_address: token_b };

    set_contract_address(OWNER());
    'router'.print();
    router.print();
    token_a_dispatcher.approve(router, BoundedInt::max());
    token_b_dispatcher.approve(router, BoundedInt::max());
    router_dispatcher.add_liquidity(token_a, token_b, 5_000, 5_000, 0, 0, OWNER(), 166633333);

    let mut path = ArrayTrait::<ContractAddress>::new();
    path.append(token_a);
    path.append(token_b);
    set_contract_address(OWNER());
    router_dispatcher.swap_exact_tokens_for_tokens(2000, 0, path, OWNER(), 166633333);
    let liquidity_held = pool_dispatcher.balance_of(OWNER());
    pool_dispatcher.approve(router, BoundedInt::max());
    let (amount_a, amount_b) = router_dispatcher
        .remove_liquidity(token_a, token_b, liquidity_held, 0, 0, OWNER(), 166633333);
    'amount_a'.print();
    amount_a.print();
    'amount_b'.print();
    amount_b.print();
}
//todo: add test_pool_not_exist


