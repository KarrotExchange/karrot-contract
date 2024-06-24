use array::{ArrayTrait, SpanTrait, SpanCopy, SpanSerde};
use option::OptionTrait;
use integer::u256_sqrt;
use integer::{U256Add, U256Sub, U256Mul, U256Div};
use result::ResultTrait;
use serde::Serde;
use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::testing::{set_caller_address, set_contract_address};
use traits::{Into, TryInto, PartialEq};
use zeroable::Zeroable;

use karrot_exchange::tests::utils;
use karrot_exchange::factory::{IFactoryDispatcher, IFactoryDispatcherTrait};
use karrot_exchange::factory::Factory;
use karrot_exchange::pool::{IPoolDispatcher, IPoolDispatcherTrait};
use karrot_exchange::pool::Pool;
use karrot_exchange::pool::Pool::PoolImpl;
use karrot_exchange::pool::Pool::InternalImpl;
use karrot_exchange::erc20::ERC20;
use karrot_exchange::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};

const DECIMALS: u8 = 18;
const MINIMUM_LIQUIDITY: u256 = 1000;
const INITIAL_LIQUIDITY: u256 = 1_000_000_000;
const NAME: felt252 = 'FieldFi V1 LP';
const SYMBOL: felt252 = 'FLP';

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

//
// Getters
//

#[test]
#[available_gas(200_000_000)]
fn test_get_factory_address() {
    let mut state = setup();
    let factory = PoolImpl::get_factory(@state);
    assert(factory == FACTORY(), 'Factory address is incorrect');
}

#[test]
#[available_gas(200_000_000)]
fn test_minimum_liquidity() {
    let mut state = setup();
    let minimum_liquidity = PoolImpl::get_minimum_liquidity(@state);
    assert(minimum_liquidity == MINIMUM_LIQUIDITY, 'Minimum liquidity is incorrect');
}

//todo How to handle constructor of Parent in inheritance
#[test]
#[available_gas(200_000_000)]
fn test_get_name() {
    let mut state = setup();
    let name = PoolImpl::name(@state);
    assert(name == NAME, 'Name is incorrect');
}

//
// initialize and get token0 and token1
//

#[test]
#[available_gas(200_000_000)]
fn test_initialize_get_token_0_and_1() {
    let mut state = setup();
    set_caller_address(FACTORY());
    PoolImpl::initialize(ref state, TOKEN_A(), TOKEN_B());

    let (token0, token1) = PoolImpl::get_tokens(@state);
    assert(token0 == TOKEN_A(), 'Token0 is incorrect');
    assert(token1 == TOKEN_B(), 'Token1 is incorrect');
}

#[test]
#[available_gas(200_000_000)]
#[should_panic(expected: ('Should be called from factory',))]
fn test_initialize_should_be_called_from_factory() {
    let mut state = setup();
    set_caller_address(ZERO_ADDRESS());
    PoolImpl::initialize(ref state, TOKEN_A(), TOKEN_B());
}

#[test]
#[available_gas(200_000_000)]
fn test_get_reserves_with_zero_reserves() {
    let mut state = setup();
    set_caller_address(FACTORY());
    PoolImpl::initialize(ref state, TOKEN_A(), TOKEN_B());

    set_caller_address(ZERO_ADDRESS());
    let (reserve0, reserve1) = PoolImpl::get_reserves(@state);
    assert(reserve0 == 0, 'should be 0');
    assert(reserve1 == 0, 'should be 0');
}

#[test]
#[available_gas(200_000_000)]
fn test_get_k_last() {
    let mut state = setup();
    set_caller_address(FACTORY());
    PoolImpl::initialize(ref state, TOKEN_A(), TOKEN_B());

    set_caller_address(ZERO_ADDRESS());
    let k_last = PoolImpl::get_k_last(@state);
    assert(k_last == 0, 'should be 0');
}

// Below is tests with deployed contracts

//
// Mint
//

fn initialize_mint() -> (ContractAddress, ContractAddress, ContractAddress, ContractAddress) {
    // Assume factory contract is deployed
    set_contract_address(OWNER());
    let factory = deploy_factory();

    // Assume token_a and token_b are deployed
    let token_a = deploy_erc20_token('token_a');
    let token_b = deploy_erc20_token('token_b');

    // deploy pool contract, then initialize
    set_contract_address(factory);
    let pool = deploy_pool(factory);
    let pool_dispatcher = IPoolDispatcher { contract_address: pool };
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

#[test]
#[available_gas(200_000_000)]
fn test_mint() { // todo: IERC20Dispatcherのテストをどのように行うか。
    let (factory, pool, token_a, token_b) = initialize_mint();
    let a_amount = 30_000_000;
    let b_amount = 50_000_000;
    let (liquidity, total_supply, balance0, balance1, reserve0, reserve1) = process_mint(
        pool, token_a, token_b, a_amount, b_amount
    );
    assert(
        //todo ここでoverflowすることはないのか。-> overflowしたらmintできないという結果はそれでよし。
        liquidity == u256_sqrt(a_amount.into() * b_amount.into()).into() - MINIMUM_LIQUIDITY,
        'Liquidity is incorrect'
    );
    assert(total_supply == liquidity + MINIMUM_LIQUIDITY, 'Total supply is incorrect');
    assert(balance0 == a_amount && balance1 == b_amount, 'Balances are incorrect');
    assert(reserve0 == a_amount && reserve1 == b_amount, 'Reserves are incorrect');
}

#[test]
#[available_gas(200_000_000)]
fn test_mint_twice() {
    let (factory, pool, token_a, token_b) = initialize_mint();

    // first mint
    let a_amount = 30_000_000;
    let b_amount = 50_000_000;
    let (liquidity, total_supply, balance0, balance1, reserve0, reserve1) = process_mint(
        pool, token_a, token_b, a_amount, b_amount
    );

    // second mint
    let a_amount_2 = 70_000_000;
    let b_amount_2 = 90_000_000;
    let (liquidity_2, total_supply_2, balance0_2, balance1_2, reserve0_2, reserve1_2) =
        process_mint(
        pool, token_a, token_b, a_amount_2, b_amount_2
    );
    let liquidity_should_be_2 = if U256Div::div(
        U256Mul::mul(a_amount_2, total_supply_2), reserve0_2
    ) <= U256Div::div(U256Mul::mul(b_amount_2, total_supply_2), reserve1_2) {
        U256Div::div(U256Mul::mul(a_amount_2, total_supply_2), reserve0_2)
    } else {
        U256Div::div(U256Mul::mul(b_amount_2, total_supply_2), reserve1_2)
    };

    assert( //todo ここでoverflowすることはないのか。-> overflowしたらmintできないという結果はそれでよし。
        liquidity_2 == liquidity_should_be_2, 'liquidity2 is incorrect'
    );

    assert(total_supply_2 == total_supply + liquidity_should_be_2, 'Total supply is incorrect');

    assert(
        balance0_2 == a_amount + a_amount_2 && balance1_2 == b_amount + b_amount_2,
        'Balances are incorrect'
    );
    assert(
        reserve0_2 == a_amount + a_amount_2 && reserve1_2 == b_amount + b_amount_2,
        'Reserves are incorrect'
    );
}

// #[test]
// #[available_gas(200_000_000)]
// #[should_panic(expected: ('Should not mint to zero', ))]
// fn test_mint_from_zero_address() {
//     // Assume factory contract is deployed
//     let factory = deploy_factory();

//     // Assume token_a and token_b are deployed
//     let token_a = deploy_erc20_token('token_a');
//     let token_b = deploy_erc20_token('token_b');

//     // deploy pool contract, then initialize
//     let pool = deploy_pool();

//     set_contract_address(FACTORY());
//     let pool_dispatcher = IPoolDispatcher { contract_address: pool };
//     pool_dispatcher.initialize(token_a, token_b);

//     // tranfer token a and token b to pool contract
//     set_contract_address(OWNER());

//     let token_a_dispatcher = IERC20Dispatcher { contract_address: token_a };
//     let token_b_dispatcher = IERC20Dispatcher { contract_address: token_b };
//     let a_amount = 30_000_000;
//     let b_amount = 50_000_000;
//     token_a_dispatcher.transfer(pool, a_amount);
//     token_b_dispatcher.transfer(pool, b_amount);

//     // mint
//     set_contract_address(OWNER());
//     let liquidity = pool_dispatcher.mint(ZERO_ADDRESS());
// }

//
// Swap
//

#[test]
#[available_gas(200_000_000)]
fn test_swap() {
    set_contract_address(OWNER());
    let (factory, pool, token_a, token_b) = initialize_mint();
    let pool_dispatcher = IPoolDispatcher { contract_address: pool };

    // Mint
    let a_amount = 30_000_000;
    let b_amount = 50_000_000;
    let (liquidity, total_supply, balance0, balance1, reserve0, reserve1) = process_mint(
        pool, token_a, token_b, a_amount, b_amount
    );

    // Swap
    let token_a_dispatcher = IERC20Dispatcher { contract_address: token_a };
    token_a_dispatcher.transfer(pool, 100);
    let data = ArrayTrait::<felt252>::new().span();

    pool_dispatcher.swap(90, 0, data, OWNER());
}

// #[test]
// #[available_gas(200_000_000)]
// #[should_panic(expected: ('K should not decrease', ))]
// fn test_swap_with_excess_amount_out() {
//     set_contract_address(OWNER());
//     let (pool, token_a, token_b) = initialize_mint();
//     let pool_dispatcher = IPoolDispatcher { contract_address: pool };

//     // Mint
//     let a_amount = 30_000_000;
//     let b_amount = 50_000_000;
//     let (liquidity, total_supply, balance0, balance1, reserve0, reserve1) = process_mint(
//         pool, token_a, token_b, a_amount, b_amount
//     );

//     // Swap
//     let token_a_dispatcher = IERC20Dispatcher { contract_address: token_a };
//     token_a_dispatcher.transfer(pool, 1_000);
//     let data = ArrayTrait::<felt252>::new().span();

//     pool_dispatcher.swap(998, 0, data, OWNER());
// }
//
// Burn
//
#[test]
#[available_gas(200_000_000)]
fn test_burn() {
    // Mint
    let (factory, pool, token_a, token_b) = initialize_mint();
    let a_amount = 30_000_000;
    let b_amount = 60_000_000;
    let (liquidity, total_supply, balance0, balance1, reserve0, reserve1) = process_mint(
        pool, token_a, token_b, a_amount, b_amount
    );
    // Burn
    let liquidity_to_burn = 10_000_000;
    let pool_dispatcher = IPoolDispatcher { contract_address: pool };

    pool_dispatcher.approve(OWNER(), liquidity_to_burn);
    pool_dispatcher.transfer_from(OWNER(), pool, liquidity_to_burn);
    let (amount_a, amount_b) = pool_dispatcher.burn(OWNER());
    let token_a_dispatcher = IERC20Dispatcher { contract_address: token_a };
    let token_a_balance = token_a_dispatcher.balanceOf(pool);
    let token_b_dispatcher = IERC20Dispatcher { contract_address: token_b };
    let token_b_balance = token_b_dispatcher.balanceOf(pool);
    let rate: u256 = U256Div::div(token_a_balance, token_b_balance);
}

//
// Internal functions
//
#[test]
#[available_gas(200_000_000)]
fn _update() {
    let mut state = setup();
    set_caller_address(ZERO_ADDRESS());
    InternalImpl::_update(ref state, 400, 150, 300, 200);

    let (reserve0, reserve1) = PoolImpl::get_reserves(@state);
    assert(reserve0 == 400, 'Reserve0 is incorrect');
    assert(reserve1 == 150, 'Reserve1 is incorrect');
}
