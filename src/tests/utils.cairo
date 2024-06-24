use array::{ArrayTrait, SpanTrait, SpanCopy, SpanSerde};
use debug::PrintTrait;
use option::OptionTrait;
use serde::Serde;
use starknet::ContractAddress;
use starknet::class_hash::Felt252TryIntoClassHash;
use starknet::class_hash::ClassHash;
use starknet::deploy_syscall;
use starknet::SyscallResultTrait;
use traits::TryInto;


fn deploy(class_hash: felt252, calldata: Array<felt252>) -> ContractAddress {
    let (contract_address, _) = deploy_syscall(
        class_hash.try_into().unwrap(), 0, calldata.span(), false
    )
        .unwrap_syscall();
    contract_address.print();
    contract_address
}
