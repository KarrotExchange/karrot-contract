use starknet::{ContractAddress};
use starknet::class_hash::ClassHash;

#[starknet::interface]
trait IFactory<TContractState> {
    //todo: only for test purpose as the function of create_pool does not work smoonthly when tested.
    fn _set_pool_by_tokens(
        ref self: TContractState,
        token_a: ContractAddress,
        token_b: ContractAddress,
        pool: ContractAddress
    );
    fn _set_pool_by_index(ref self: TContractState, index: u256, pool: ContractAddress);

    fn create_pool(
        ref self: TContractState, token_a: ContractAddress, token_b: ContractAddress
    ) -> ContractAddress;
    fn set_fee_to(ref self: TContractState, fee_to: ContractAddress);
    fn set_fee_to_setter(ref self: TContractState, fee_to_setter: ContractAddress);
    fn get_pool_class_hash(self: @TContractState) -> ClassHash;
    fn get_pool_by_tokens(
        self: @TContractState, token_a: ContractAddress, token_b: ContractAddress
    ) -> ContractAddress;
    fn get_fee_to(self: @TContractState) -> ContractAddress;
    fn get_fee_to_setter(self: @TContractState) -> ContractAddress;
    fn get_pool_length(self: @TContractState) -> u256;
    fn get_pool_by_index(self: @TContractState, index: u256) -> ContractAddress;
}

#[starknet::contract]
mod Factory {
    use array::{ArrayTrait, SpanTrait};
    use hash::LegacyHash;
    use serde::Serde;
    use starknet::class_hash::ClassHash;
    use starknet::ContractAddress;
    use starknet::{get_caller_address};
    use starknet::syscalls::{deploy_syscall};
    use traits::Into;
    use zeroable::Zeroable;
    use karrot_exchange::libraries::library;
    use karrot_exchange::pool::{IPoolDispatcher, IPoolDispatcherTrait};
    #[storage]
    struct Storage {
        pool_class_hash: ClassHash,
        fee_to: ContractAddress,
        fee_to_setter: ContractAddress,
        pool_by_tokens: LegacyMap::<(ContractAddress, ContractAddress), ContractAddress>,
        pool_length: u256,
        pool_by_index: LegacyMap::<u256, ContractAddress>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        PairCreated: PairCreated
    }

    #[derive(Drop, starknet::Event)]
    struct PairCreated {
        #[key]
        token0: ContractAddress,
        #[key]
        token1: ContractAddress,
        pool: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, pool_contract_class_hash: ClassHash, fee_to_setter: ContractAddress
    ) {
        self.pool_class_hash.write(pool_contract_class_hash);
        self.fee_to.write(Zeroable::zero());
        self.fee_to_setter.write(fee_to_setter);
        self.pool_length.write(0);
    }

    #[external(v0)]
    impl FactoryImpl of super::IFactory<ContractState> {
        //todo: only for test purpose as the function of create_pool does not work smoonthly when tested.
        fn _set_pool_by_tokens(
            ref self: ContractState,
            token_a: ContractAddress,
            token_b: ContractAddress,
            pool: ContractAddress
        ) {
            let (token0, token1) = library::sort_tokens(token_a, token_b);
            self.pool_by_tokens.write((token_a, token_b), pool);
        }

        fn _set_pool_by_index(ref self: ContractState, index: u256, pool: ContractAddress) {
            self.pool_by_index.write(index, pool);
        }

        //todo: should only allow authorized caller to invoke this function?
        fn create_pool(
            ref self: ContractState, token_a: ContractAddress, token_b: ContractAddress
        ) -> ContractAddress {
            assert(token_a != token_b, 'tokens should be different');
            let (token0, token1) = library::sort_tokens(token_a, token_b);
            assert(token0.is_non_zero(), 'token is zero addr');

            let class_hash = self.pool_class_hash.read();
            let mut pool: ContractAddress = self.pool_by_tokens.read((token0, token1));
            assert(pool.is_zero(), 'pool already exists');

            // arguments for pool deoloyment
            let contract_address_salt = LegacyHash::hash(token0.into(), token1);
            let calldata = ArrayTrait::<felt252>::new().span();
            let deploy_from_zero = false;

            // deoloy pool contract
            let (created_pool, returned_data) = deploy_syscall(
                class_hash, contract_address_salt, calldata, deploy_from_zero: false,
            )
                .unwrap();
            IPoolDispatcher { contract_address: created_pool }.initialize(token0, token1);
            let current_index: u256 = self.pool_length.read();
            self.pool_by_tokens.write((token0, token1), created_pool);
            self.pool_by_tokens.write((token1, token0), created_pool);
            self.pool_by_index.write(current_index + 1, created_pool);
            self.pool_length.write(current_index + 1);
            self.emit(Event::PairCreated(PairCreated { token0, token1, pool: created_pool }));
            created_pool
        }

        fn set_fee_to(ref self: ContractState, fee_to: ContractAddress) {
            assert(get_caller_address() == self.fee_to_setter.read(), 'Not authorized');
            self.fee_to.write(fee_to);
        }

        fn set_fee_to_setter(ref self: ContractState, fee_to_setter: ContractAddress) {
            assert(get_caller_address() == self.fee_to_setter.read(), 'Not authorized');
            self.fee_to_setter.write(fee_to_setter);
        }
        fn get_pool_class_hash(self: @ContractState) -> ClassHash {
            self.pool_class_hash.read()
        }

        fn get_pool_by_tokens(
            self: @ContractState, token_a: ContractAddress, token_b: ContractAddress
        ) -> ContractAddress {
            assert(token_a != token_b, 'tokens are identical');
            let (token0, token1) = library::sort_tokens(token_a, token_b);
            self.pool_by_tokens.read((token0, token1))
        }

        fn get_fee_to(self: @ContractState) -> ContractAddress {
            self.fee_to.read()
        }

        fn get_fee_to_setter(self: @ContractState) -> ContractAddress {
            self.fee_to_setter.read()
        }
        fn get_pool_length(self: @ContractState) -> u256 {
            self.pool_length.read()
        }
        fn get_pool_by_index(self: @ContractState, index: u256) -> ContractAddress {
            let current_index = self.pool_length.read();
            assert(index <= current_index, 'invalid pool index');
            self.pool_by_index.read(index)
        }
    }
}
