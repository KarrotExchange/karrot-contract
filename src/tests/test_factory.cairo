use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use result::ResultTrait;
use serde::Serde;
use starknet::class_hash::ClassHash;
use starknet::class_hash_const;
use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::testing::{set_caller_address, set_contract_address};
use traits::{Into, TryInto};
use zeroable::Zeroable;

use karrot_exchange::factory::{IFactoryDispatcher, IFactoryDispatcherTrait};
use karrot_exchange::factory::Factory;
use karrot_exchange::factory::Factory::FactoryImpl;
use karrot_exchange::pool::Pool;
use karrot_exchange::tests::utils;

fn STATE() -> Factory::ContractState {
    Factory::contract_state_for_testing()
}
fn OWNER() -> ContractAddress {
    contract_address_const::<1>()
}

fn NEW_OWNER() -> ContractAddress {
    contract_address_const::<2>()
}

fn FEE_RECEIVER() -> ContractAddress {
    contract_address_const::<3>()
}

fn POOL_CLASS_HASH() -> ClassHash {
    class_hash_const::<0x020a3f9f75016417a0a86a8a13e7ce75bb8a0021db689108268db28eb5c2b818>()
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
fn setup() -> Factory::ContractState {
    let mut state = STATE();
    let owner = OWNER();
    let class_hash = POOL_CLASS_HASH();
    Factory::constructor(ref state, class_hash, owner);
    state
}

fn deploy_factory() -> ContractAddress {
    set_caller_address(OWNER());

    let mut calldata = ArrayTrait::new();
    Pool::TEST_CLASS_HASH.serialize(ref output: calldata);
    OWNER().serialize(ref output: calldata);

    let contract_address = utils::deploy(Factory::TEST_CLASS_HASH, calldata);
    contract_address
}

//
// Getters
//

#[test]
#[available_gas(20_000_000)]
fn test_get_fee_to_setter() {
    let mut state = setup();
    let fee_to_setter = FactoryImpl::get_fee_to_setter(@state);
    assert(fee_to_setter == OWNER(), 'fee_to_setter should be zero');
}

#[test]
#[available_gas(20_000_000)]
fn test_get_fee_to() {
    let mut state = setup();
    let fee_to = FactoryImpl::get_fee_to(@state);
    assert(fee_to.is_zero(), 'fee_to should be zero');
}

//
// set fee-related states
//

#[test]
#[available_gas(20_000_000)]
fn test_set_fee_to() {
    let mut state = setup();
    set_caller_address(OWNER());
    FactoryImpl::set_fee_to(ref state, FEE_RECEIVER());

    let fee_to = FactoryImpl::get_fee_to(@state);
    assert(fee_to == FEE_RECEIVER(), 'fee_to should be FEE_RECEIVER');
}

#[test]
#[available_gas(20_000_000)]
#[should_panic(expected: ('Not authorized',))]
fn test_set_fee_to_from_zero() {
    let mut state = setup();
    FactoryImpl::set_fee_to(ref state, FEE_RECEIVER());
}

#[test]
#[available_gas(20_000_000)]
fn test_set_fee_to_setter() {
    let mut state = setup();
    set_caller_address(OWNER());
    FactoryImpl::set_fee_to_setter(ref state, NEW_OWNER());

    let fee_to_setter = FactoryImpl::get_fee_to_setter(@state);
    assert(fee_to_setter == NEW_OWNER(), 'fee_to_setter should NEW_OWNER');

    set_caller_address(NEW_OWNER());
    FactoryImpl::set_fee_to(ref state, FEE_RECEIVER());
    let fee_to = FactoryImpl::get_fee_to(@state);
    assert(fee_to == FEE_RECEIVER(), 'fee_to should be FEE_RECEIVER');
}

#[test]
#[available_gas(20_000_000)]
#[should_panic(expected: ('Not authorized',))]
fn test_set_fee_to_setter_from_zero() {
    let mut state = setup();
    FactoryImpl::set_fee_to(ref state, NEW_OWNER());
}

//
// test upon deployment
//
#[test]
#[available_gas(20_000_000)]
fn test_create_pair() {
    set_contract_address(OWNER());
    let factory = deploy_factory();
    let factory_dispatcher = IFactoryDispatcher { contract_address: factory };
    let pool = factory_dispatcher.create_pool(TOKEN_A(), TOKEN_B());
    'pool address'.print();
    pool.print();
}

//todo: test case for create_pair twice with the same token pair

#[test]
#[available_gas(20_000_000)]
fn test_get_pool_by_tokens() {
    set_contract_address(OWNER());
    let factory = deploy_factory();
    let factory_dispatcher = IFactoryDispatcher { contract_address: factory };
    let pool = factory_dispatcher.create_pool(TOKEN_A(), TOKEN_B());
    'pool address'.print();
    pool.print();

    assert(
        factory_dispatcher.get_pool_by_tokens(TOKEN_A(), TOKEN_B()) == pool,
        'pool address should be equal'
    );
}

