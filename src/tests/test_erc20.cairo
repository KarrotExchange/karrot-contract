use integer::BoundedInt;
use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::testing::set_caller_address;

use karrot_exchange::erc20::ERC20;
use karrot_exchange::erc20::ERC20::{ERC20Impl, InternalImpl};
//
// Constants
//

const NAME: felt252 = 111;
const SYMBOL: felt252 = 222;
const DECIMALS: u8 = 18_u8;
const INITIAL_SUPPLY: u256 = 1000;
const SUPPLY: u256 = 2000;
const VALUE: u256 = 300;

fn STATE() -> ERC20::ContractState {
    ERC20::contract_state_for_testing()
}
fn OWNER() -> ContractAddress {
    contract_address_const::<1>()
}
fn SPENDER() -> ContractAddress {
    contract_address_const::<2>()
}
fn RECIPIENT() -> ContractAddress {
    contract_address_const::<3>()
}

//
// Setup
//

fn setup() -> ERC20::ContractState {
    let mut state = STATE();
    ERC20::constructor(ref state, NAME, SYMBOL, DECIMALS, INITIAL_SUPPLY, OWNER());
    state
}

//
// initializer & constructor
//

#[test]
#[available_gas(2_000_000)]
fn test_constructor() {
    let mut state = STATE();
    ERC20::constructor(ref state, NAME, SYMBOL, DECIMALS, INITIAL_SUPPLY, OWNER());
    assert(ERC20Impl::name(@state) == NAME, 'Name should be NAME');
    assert(ERC20Impl::symbol(@state) == SYMBOL, 'Symbol should be SYMBOL');
    assert(ERC20Impl::decimals(@state) == DECIMALS, 'Decimals should be 18');
    assert(ERC20Impl::totalSupply(@state) == INITIAL_SUPPLY, 'Supply should eq 0');
    assert(ERC20Impl::balanceOf(@state, OWNER()) == INITIAL_SUPPLY, 'Balance should eq 0');
}

//
// Getters
//
#[test]
#[available_gas(2_000_000)]
fn test_allowance() {
    let mut state = setup();
    set_caller_address(OWNER());
    ERC20Impl::approve(ref state, SPENDER(), VALUE);
    assert(ERC20Impl::allowance(@state, OWNER(), SPENDER()) == VALUE, 'Should eq VALUE');
}
//
// approve & _approve
//
#[test]
#[available_gas(2_000_000)]
fn test_approve() {
    let mut state = setup();
    set_caller_address(OWNER());
    ERC20Impl::approve(ref state, SPENDER(), VALUE);
    assert(ERC20Impl::allowance(@state, OWNER(), SPENDER()) == VALUE, 'Should eq VALUE');
}

#[test]
#[available_gas(2_000_000)]
#[should_panic(expected: ('ERC20: approve from 0',))]
fn test_approve_from_zero() {
    let mut state = setup();
    ERC20Impl::approve(ref state, SPENDER(), VALUE);
}

#[test]
#[available_gas(2_000_000)]
#[should_panic(expected: ('ERC20: approve to 0',))]
fn test_approve_to_zero() {
    let mut state = setup();
    set_caller_address(OWNER());
    ERC20Impl::approve(ref state, Zeroable::zero(), VALUE);
}

//
// transfer
//
#[test]
#[available_gas(2_000_000)]
fn test_transfer() {
    let mut state = setup();
    set_caller_address(OWNER());
    assert(ERC20Impl::transfer(ref state, RECIPIENT(), VALUE), 'Should return true');
    assert(
        ERC20Impl::balanceOf(@state, OWNER()) == INITIAL_SUPPLY - VALUE, 'Should eq supply - value'
    );
    assert(ERC20Impl::balanceOf(@state, RECIPIENT()) == VALUE, 'Should eq value');
}

#[test]
#[available_gas(2_000_000)]
#[should_panic(expected: ('ERC20: transfer from 0',))]
fn test_transfer_from_zero() {
    let mut state = setup();
    InternalImpl::_transfer(ref state, Zeroable::zero(), RECIPIENT(), VALUE);
}

#[test]
#[available_gas(2_000_000)]
#[should_panic(expected: ('ERC20: transfer to 0',))]
fn test_transfer_helper_to_zero() {
    let mut state = setup();
    InternalImpl::_transfer(ref state, OWNER(), Zeroable::zero(), VALUE);
}

//
// transfer_from
//
#[test]
#[available_gas(2_000_000)]
fn test_transfer_from() {
    let mut state = setup();
    set_caller_address(OWNER());
    ERC20Impl::approve(ref state, SPENDER(), VALUE);

    set_caller_address(SPENDER());
    assert(ERC20Impl::transferFrom(ref state, OWNER(), RECIPIENT(), VALUE), 'Should return true');
    assert(
        ERC20Impl::balanceOf(@state, OWNER()) == INITIAL_SUPPLY - VALUE, 'Should eq supply - value'
    );
    assert(ERC20Impl::balanceOf(@state, RECIPIENT()) == VALUE, 'Should eq value');
    assert(ERC20Impl::allowance(@state, OWNER(), SPENDER()) == 0, 'Should eq 0');
    assert(ERC20Impl::totalSupply(@state) == INITIAL_SUPPLY, 'Should eq INITIAL_SUPPLY');
}

#[test]
#[available_gas(2_000_000)]
fn test_transfer_from_doesnt_consume_infinite_allowance() {
    let mut state = setup();
    set_caller_address(OWNER());
    ERC20Impl::approve(ref state, SPENDER(), BoundedInt::max());

    set_caller_address(SPENDER());
    ERC20Impl::transferFrom(ref state, OWNER(), SPENDER(), VALUE);
    assert(
        ERC20Impl::allowance(@state, OWNER(), SPENDER()) == BoundedInt::max(),
        'Allowance should not change'
    );
}

#[test]
#[available_gas(2_000_000)]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_transfer_from_greater_than_allowance() {
    let mut state = setup();
    set_caller_address(OWNER());
    ERC20Impl::approve(ref state, SPENDER(), VALUE);

    set_caller_address(SPENDER());
    ERC20Impl::transferFrom(ref state, OWNER(), RECIPIENT(), VALUE + 1);
}

#[test]
#[available_gas(2_000_000)]
fn test_increase_allowance() {
    let mut state = setup();
    set_caller_address(OWNER());
    ERC20Impl::approve(ref state, SPENDER(), VALUE);
    ERC20Impl::increaseAllowance(ref state, SPENDER(), VALUE);
    assert(ERC20Impl::allowance(@state, OWNER(), SPENDER()) == VALUE * 2, 'Should eq VALUE * 2');
}

#[test]
#[available_gas(2_000_000)]
#[should_panic(expected: ('ERC20: approve to 0',))]
fn test_increase_allowance_to_zero_address() {
    let mut state = setup();
    set_caller_address(OWNER());
    ERC20Impl::increaseAllowance(ref state, Zeroable::zero(), VALUE);
}

#[test]
#[available_gas(2_000_000)]
#[should_panic(expected: ('ERC20: approve from 0',))]
fn test_increase_allowance_from_zero_address() {
    let mut state = setup();
    ERC20Impl::increaseAllowance(ref state, SPENDER(), VALUE);
}

#[test]
#[available_gas(2000000)]
fn test_decrease_allowance() {
    let mut state = setup();
    set_caller_address(OWNER());
    ERC20Impl::approve(ref state, SPENDER(), VALUE);

    assert(ERC20Impl::decreaseAllowance(ref state, SPENDER(), VALUE), 'Should return true');
    assert(ERC20Impl::allowance(@state, OWNER(), SPENDER()) == VALUE - VALUE, 'Should be 0');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_decrease_allowance_to_zero_address() {
    let mut state = setup();
    set_caller_address(OWNER());
    ERC20Impl::decreaseAllowance(ref state, Zeroable::zero(), VALUE);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('u256_sub Overflow',))]
fn test_decrease_allowance_from_zero_address() {
    let mut state = setup();
    ERC20Impl::decreaseAllowance(ref state, SPENDER(), VALUE);
}
