use starknet::ContractAddress;

#[starknet::interface]
trait IRouter<TContractState> {
    fn get_factory(self: @TContractState) -> ContractAddress;
    fn quote(self: @TContractState, amount_a: u256, reserve_a: u256, reserve_b: u256,) -> u256;
    fn get_amounts_out(
        self: @TContractState, amount_in: u256, path: Span<ContractAddress>,
    ) -> Span<u256>;
    fn get_amounts_in(
        self: @TContractState, amount_out: u256, path: Span<ContractAddress>,
    ) -> Span<u256>;
    fn add_liquidity(
        ref self: TContractState,
        token_a: ContractAddress,
        token_b: ContractAddress,
        amount_a_desired: u256,
        amount_b_desired: u256,
        amount_a_min: u256,
        amount_b_min: u256,
        to: ContractAddress,
        deadline: u64,
    ) -> (u256, u256, u256);
    fn remove_liquidity(
        ref self: TContractState,
        token_a: ContractAddress,
        token_b: ContractAddress,
        liquidity: u256,
        amount_a_min: u256,
        amount_b_min: u256,
        to: ContractAddress,
        deadline: u64,
    ) -> (u256, u256);
    fn swap_exact_tokens_for_tokens(
        ref self: TContractState,
        amount_in: u256,
        amount_out_min: u256,
        path: Array<ContractAddress>,
        to: ContractAddress,
        deadline: u64,
    ) -> Span<u256>;
    fn swap_tokens_for_exact_tokens(
        ref self: TContractState,
        amount_out: u256,
        amount_in_max: u256,
        path: Array<ContractAddress>,
        to: ContractAddress,
        deadline: u64,
    ) -> Span<u256>;
}

#[starknet::contract]
mod Router {
    use array::{ArrayTrait, SpanTrait};
    use clone::Clone;
    use integer::{U256Add, U256Sub, U256Mul, U256Div};
    use serde::Serde;
    use starknet::ContractAddress;
    use starknet::get_block_timestamp;
    use starknet::get_caller_address;
    use starknet::get_contract_address;
    use traits::Into;
    use zeroable::Zeroable;

    use karrot_exchange::libraries::library;
    use karrot_exchange::erc20::IERC20Dispatcher;
    use karrot_exchange::erc20::IERC20DispatcherTrait;
    use karrot_exchange::pool::{IPoolDispatcher, IPoolDispatcherTrait};
    use karrot_exchange::factory::{IFactoryDispatcher, IFactoryDispatcherTrait};

    #[storage]
    struct Storage {
        factory: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, factory: ContractAddress) {
        self.factory.write(factory);
    }

    #[external(v0)]
    impl RouterImpl of super::IRouter<ContractState> {
        fn get_factory(self: @ContractState) -> ContractAddress {
            self.factory.read()
        }

        // given some amount of an asset and pair reserves, returns an equivalent value amount of the other asset
        fn quote(self: @ContractState, amount_a: u256, reserve_a: u256, reserve_b: u256,) -> u256 {
            assert(amount_a > 0, 'Amount should be positive');
            assert(reserve_a > 0, 'reserve_a is zero addr');
            assert(reserve_b > 0, 'reserve_b is zero addr');
            U256Div::div(U256Mul::mul(amount_a, reserve_b), reserve_a)
        }


        fn get_amounts_out(
            self: @ContractState, amount_in: u256, path: Span<ContractAddress>,
        ) -> Span<u256> {
            let path_length = path.len();
            assert(path_length >= 2, 'path should be 2 or longer');
            let mut amounts = ArrayTrait::<u256>::new();
            amounts.append(amount_in);

            let mut i: usize = 0;
            loop {
                if (i >= path_length - 1) {
                    break;
                } else {
                    let pool = IFactoryDispatcher { contract_address: self.factory.read() }
                        .get_pool_by_tokens(path[i].clone(), path[i + 1].clone());
                    assert(pool.is_non_zero(), 'pool does not exist');
                    let (reserve_in, reserve_out) = IPoolDispatcher { contract_address: pool }
                        .get_reserves();
                    amounts.append(_get_amount_out(amounts[i].clone(), reserve_in, reserve_out));
                    i = i + 1;
                };
            };
            amounts.span()
        }

        fn get_amounts_in(
            self: @ContractState, amount_out: u256, path: Span<ContractAddress>,
        ) -> Span<u256> {
            let path_length = path.len();
            assert(path_length >= 2, 'path should be 2 or longer');
            let mut reverse_amounts = ArrayTrait::<u256>::new();
            reverse_amounts.append(amount_out);

            let mut i: usize = path_length - 1;
            loop {
                if (i <= 0) {
                    break;
                } else {
                    let pool = IFactoryDispatcher { contract_address: self.factory.read() }
                        .get_pool_by_tokens(path[i - 1].clone(), path[i].clone());
                    assert(pool.is_non_zero(), 'pool does not exist');
                    let (reserve_in, reserve_out) = IPoolDispatcher { contract_address: pool }
                        .get_reserves();
                    reverse_amounts
                        .append(
                            _get_amount_in(
                                reverse_amounts.at(path_length - i - 1).clone(),
                                reserve_in,
                                reserve_out
                            )
                        );
                    i = i - 1;
                };
            };
            let mut amounts = ArrayTrait::<u256>::new();
            let mut j: usize = path_length;

            loop {
                if (j <= 0) {
                    break;
                } else {
                    let element = reverse_amounts.at(j - 1);
                    amounts.append(*element);
                    j = j - 1;
                };
            };
            amounts.span()
        }


        fn add_liquidity(
            ref self: ContractState,
            token_a: ContractAddress,
            token_b: ContractAddress,
            amount_a_desired: u256,
            amount_b_desired: u256,
            amount_a_min: u256,
            amount_b_min: u256,
            to: ContractAddress,
            deadline: u64,
        ) -> (u256, u256, u256) {
            deadline >= get_block_timestamp();
            let caller = get_caller_address();
            let contract = get_contract_address();
            let pool = IFactoryDispatcher { contract_address: self.factory.read() }
                .get_pool_by_tokens(token_a, token_b);
            assert(pool.is_non_zero(), 'pool does not exist');
            let (amount_a, amount_b) = self
                ._add_liquidity(
                    pool,
                    token_a,
                    token_b,
                    amount_a_desired,
                    amount_b_desired,
                    amount_a_min,
                    amount_b_min,
                );
            let token_a_dispatcher = IERC20Dispatcher { contract_address: token_a };
            token_a_dispatcher.transferFrom(caller, pool, amount_a);

            let token_b_dispatcher = IERC20Dispatcher { contract_address: token_b };
            token_b_dispatcher.transferFrom(caller, pool, amount_b);

            let liquidity = IPoolDispatcher { contract_address: pool, }.mint(to);
            (amount_a, amount_b, liquidity)
        }

        fn remove_liquidity(
            ref self: ContractState,
            token_a: ContractAddress,
            token_b: ContractAddress,
            liquidity: u256,
            amount_a_min: u256,
            amount_b_min: u256,
            to: ContractAddress,
            deadline: u64,
        ) -> (u256, u256) {
            deadline >= get_block_timestamp();
            let caller = get_caller_address();
            let pool = IFactoryDispatcher { contract_address: self.factory.read() }
                .get_pool_by_tokens(token_a, token_b);
            assert(pool.is_non_zero(), 'pool does not exist');
            IPoolDispatcher { contract_address: pool }.transfer_from(caller, pool, liquidity);
            let (amount0, amount1) = IPoolDispatcher { contract_address: pool }.burn(to);
            let (token0, token1) = _sort_tokens(token_a, token_b);
            let (amount_a, amount_b) = if token_a == token0 {
                (amount0, amount1)
            } else {
                (amount1, amount0)
            };
            assert(amount_a >= amount_a_min, 'amount_a is insufficient');
            assert(amount_b >= amount_b_min, 'amount_b is insufficient');
            (amount_a, amount_b)
        }

        fn swap_exact_tokens_for_tokens(
            ref self: ContractState,
            amount_in: u256,
            amount_out_min: u256,
            path: Array<ContractAddress>,
            to: ContractAddress,
            deadline: u64,
        ) -> Span<u256> {
            deadline >= get_block_timestamp();
            let amounts = library::get_amounts_out(self.factory.read(), amount_in, path.span());
            assert(*amounts.at(amounts.len() - 1) >= amount_out_min, 'output too low');
            let pool = IFactoryDispatcher { contract_address: self.factory.read() }
                .get_pool_by_tokens(*path.at(0), *path.at(1));
            IERC20Dispatcher { contract_address: *path.at(0) }
                .transferFrom(get_caller_address(), pool, *amounts.at(0));
            self._swap(amounts, path.span(), to);
            amounts
        }

        fn swap_tokens_for_exact_tokens(
            ref self: ContractState,
            amount_out: u256,
            amount_in_max: u256,
            path: Array<ContractAddress>,
            to: ContractAddress,
            deadline: u64,
        ) -> Span<u256> {
            deadline >= get_block_timestamp();
            let amounts = library::get_amounts_in(self.factory.read(), amount_out, path.span());
            assert(amounts[0].clone() <= amount_in_max, 'requested too much');
            let pool = IFactoryDispatcher { contract_address: self.factory.read() }
                .get_pool_by_tokens(*path.at(0), *path.at(1));

            IERC20Dispatcher { contract_address: *path.at(0) }
                .transferFrom(get_caller_address(), pool, *amounts.at(0));
            self._swap(amounts, path.span(), to);
            let amounts = ArrayTrait::<u256>::new().span();
            amounts
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        // This function caluculates the amount of tokenA and tokenB to be added to the pool.
        fn _add_liquidity(
            ref self: ContractState,
            pool: ContractAddress,
            token_a: ContractAddress,
            token_b: ContractAddress,
            amount_a_desired: u256,
            amount_b_desired: u256,
            amount_a_min: u256,
            amount_b_min: u256,
        ) -> (u256, u256) {
            let factory: ContractAddress = self.factory.read();
            assert(
                IFactoryDispatcher { contract_address: factory }
                    .get_pool_by_tokens(token_a, token_b)
                    .is_non_zero(),
                'pool does not exist'
            );

            let (reserve_a, reserve_b) = IPoolDispatcher { contract_address: pool }.get_reserves();
            // if reserve=0, the raw values of amount_a_desired and amount_b_desired will be passed to as amount_a and amount_b.
            // Otherwise, the lager amount among amount_a and amount_b will be lowered to the amount being optional, and the other side of amount desired will be passed to as amount_a or amount_b.
            let (amount_a, amount_b) = if reserve_a == 0 && reserve_b == 0 {
                (amount_a_desired, amount_b_desired)
            } else {
                let amount_b_optimal = library::quote(amount_a_desired, reserve_a, reserve_b);
                if amount_b_optimal <= amount_b_desired {
                    assert(amount_b_optimal >= amount_b_min, 'amount_b is insufficient');
                    (amount_a_desired, amount_b_optimal)
                } else {
                    let amount_a_optimal = library::quote(amount_b_desired, reserve_b, reserve_a);
                    assert(amount_a_optimal <= amount_a_desired, 'amount_a is insufficient');
                    assert(amount_a_optimal >= amount_a_min, 'amount_a is insufficient');
                    (amount_a_optimal, amount_b_desired)
                }
            };
            (amount_a, amount_b)
        }

        // requires the initial amount to have already been sent to the first pair
        fn _swap(
            self: @ContractState,
            amounts: Span<u256>,
            path: Span<ContractAddress>,
            to: ContractAddress,
        ) {
            let path_length = path.len();
            let mut i: usize = 0;
            loop {
                if (i >= path_length - 1) {
                    break;
                } else {
                    let (input, output) = (path[i].clone(), path[i + 1].clone());
                    let amount_out = amounts.at(i + 1);
                    let (token0, _token1) = _sort_tokens(input, output);
                    // todo: requires further review about using snapshot
                    let (amount0_out, amount1_out) = if input == token0 {
                        (@0.into(), amount_out)
                    } else {
                        (amount_out, @0.into())
                    };
                    let pool = IFactoryDispatcher { contract_address: self.factory.read() }
                        .get_pool_by_tokens(input, output);
                    let data = ArrayTrait::<felt252>::new().span();
                    let to_for_each_swap = if i < path_length - 2 {
                        IFactoryDispatcher { contract_address: self.factory.read() }
                            .get_pool_by_tokens(output, path.at(i + 2).clone())
                    } else {
                        to
                    };
                    IPoolDispatcher { contract_address: pool }
                        .swap(amount0_out.clone(), amount1_out.clone(), data, to_for_each_swap);
                    i = i + 1;
                };
            };
        }
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order 
    fn _sort_tokens(
        token_a: ContractAddress, token_b: ContractAddress,
    ) -> (ContractAddress, ContractAddress) {
        assert(token_a != token_b, 'tokens should be different');
        //todo: To review whether it is possible to convert to u256 directly witout going througn felt252
        let token_a_as_felt: felt252 = token_a.into();
        let token_b_as_felt: felt252 = token_b.into();
        let token_a_as_u256: u256 = token_a_as_felt.into();
        let token_b_as_u256: u256 = token_b_as_felt.into();
        let sorted_tokens = if token_a_as_u256 < token_b_as_u256 {
            (token_a, token_b)
        } else {
            (token_b, token_a)
        };
        sorted_tokens
    }

    // given an input amount of an asset and pair reserves, returns the maximum out amount of the other asset. 
    // Fee is considered
    fn _get_amount_out(amount_in: u256, reserve_in: u256, reserve_out: u256,) -> u256 {
        assert(amount_in > 0, 'amount_in should be positive');
        assert(reserve_in > 0, 'reserve_in is zero');
        assert(reserve_out > 0, 'reserve_out is zero');
        let amount_in_with_fee = amount_in * 997;
        let numerator = U256Mul::mul(amount_in_with_fee, reserve_out);
        let denominator = reserve_in * 1000 + amount_in_with_fee;
        U256Div::div(numerator, denominator)
    }

    // given an output amount of an asset and pair reserves, returns a required amount of the other asset
    fn _get_amount_in(amount_out: u256, reserve_in: u256, reserve_out: u256,) -> u256 {
        assert(amount_out > 0, 'amount_out should be positive');
        assert(reserve_in > 0, 'reserve_in is zero');
        assert(reserve_out > 0, 'reserve_out is zero');
        let numerator = U256Mul::mul(reserve_in, amount_out) * 1000;
        let denominator = (reserve_out - amount_out) * 997;
        (numerator / denominator) + 1
    }
}
