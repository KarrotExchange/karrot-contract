use array::{ArrayTrait, SpanTrait};
use clone::Clone;
use integer::{U256Mul, U256Div};
use starknet::ContractAddress;
use starknet::{TryInto, Into};
use zeroable::Zeroable;

use karrot_exchange::pool::{IPoolDispatcher, IPoolDispatcherTrait};
use karrot_exchange::factory::{IFactoryDispatcher, IFactoryDispatcherTrait};

#[starknet::interface]
trait ICalleeContract<TContractState> {
    fn call_from_swap(
        ref self: TContractState,
        sender: ContractAddress,
        amount0: u256,
        amount1: u256,
        data: Span<felt252>,
    );
}

// returns sorted token addresses, used to handle return values from pairs sorted in this order
fn sort_tokens(
    token_a: ContractAddress, token_b: ContractAddress,
) -> (ContractAddress, ContractAddress) {
    assert(token_a != token_b, 'tokens are identical');
    //todo: Is it possible to convert to u256 directly witout going througn felt252
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

// given some amount of an asset and pair reserves, returns an equivalent value amount of the other asset
fn quote(amount_a: u256, reserve_a: u256, reserve_b: u256,) -> u256 {
    assert(amount_a > 0, 'Amount should be positive');
    assert(reserve_a > 0, 'reserve_a is zero');
    assert(reserve_b > 0, 'reserve_b is zero');
    U256Div::div(
        U256Mul::mul(amount_a, reserve_b), reserve_a
    ) // amount_b | 1 amount_a = (reserve_b - reserve_b) units of token_b
}


// given an input amount of an asset and pair reserves, returns the maximum out amount of the other asset. Fee is considered
fn get_amount_out(amount_in: u256, reserve_in: u256, reserve_out: u256,) -> u256 {
    assert(amount_in > 0, 'amount_in should be positive');
    assert(reserve_in > 0, 'reserve_in is zero');
    assert(reserve_out > 0, 'reserve_out is zero');
    // calc: K before swap: reserve_in * reserve_out = K after swap with fee subtracted: (reserve_in + amount_in - fee) * (reserve_out - amount_out)
    // amount_out = reserve_in * reserve_out / (reserve_in + amount_in - fee) + reserve_out
    let amount_in_with_fee = amount_in * 997;
    // in 追加量 * out reserve = inの取引だけが終わった時点でのkの増加量
    let numerator = U256Mul::mul(amount_in_with_fee, reserve_out);
    // swap実行後の in reserve: inの取引だけが終わった時点でのoutの減少量。ただし、正確には、out取引と同時に上記のout reserveが現象するため、分子が減少し、正確には、ここで得られるamount_outよりも小さなamount_outとなる。
    let denominator = reserve_in * 1000 + amount_in_with_fee;
    U256Div::div(numerator, denominator)
}


// given an output amount of an asset and pair reserves, returns a required amount of the other asset
fn get_amount_in(amount_out: u256, reserve_in: u256, reserve_out: u256,) -> u256 {
    assert(amount_out > 0, 'amount_out should be positive');
    assert(reserve_in > 0, 'reserve_in is zero');
    assert(reserve_out > 0, 'reserve_out is zero');
    // swap実行前の in reserveと、swap実行によるoutの減少量をかける = kの減少量近似。ただし、kの減少量は、実際には、outの実行後には、reserve_inが大きくなることにより、大きくなる。即ち、実際に必要なamount_inはこの関数で得られたものよりも大きくなり、この関数で得られたamount_inでは実際には取引が成立しない可能性がある。
    let numerator = U256Mul::mul(reserve_in, amount_out) * 1000;
    // swap実行後のreserveの量を Kの増加量を全ての取引実行後のreserveベースで。
    let denominator = (reserve_out - amount_out) * 997;
    (numerator / denominator) + 1
}

fn get_amounts_out(
    factory: ContractAddress, amount_in: u256, path: Span<ContractAddress>,
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
            let pool = IFactoryDispatcher { contract_address: factory }
                .get_pool_by_tokens(path[i].clone(), path[i + 1].clone());
            assert(pool.is_non_zero(), 'pool does not exist');
            // fix bug get reserve_in and reserve_out
            let (reserve_0, reserve_1) = IPoolDispatcher { contract_address: pool }.get_reserves();
            let (token0, _) = sort_tokens(path[i].clone(), path[i + 1].clone());

            let reserve_in = if token0 == path[i].clone() {
                reserve_0
            } else {
                reserve_1
            };
            let reserve_out = if token0 == path[i].clone() {
                reserve_1
            } else {
                reserve_0
            };

            // let (reserve_in, reserve_out) = IPoolDispatcher { contract_address: pool }
            //     .get_reserves();
            // 
            amounts.append(get_amount_out(amounts[i].clone(), reserve_in, reserve_out));
            i = i + 1;
        };
    };
    amounts.span()
}

fn get_amounts_in(
    factory: ContractAddress, amount_out: u256, path: Span<ContractAddress>,
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
            let pool = IFactoryDispatcher { contract_address: factory }
                .get_pool_by_tokens(path[i - 1].clone(), path[i].clone());
            assert(pool.is_non_zero(), 'pool does not exist');
            let (reserve_0, reserve_1) = IPoolDispatcher { contract_address: pool }.get_reserves();
            let (token0, _) = sort_tokens(path[i - 1].clone(), path[i].clone());

            let reserve_in = if token0 == path[i - 1].clone() {
                reserve_0
            } else {
                reserve_1
            };
            let reserve_out = if token0 == path[i - 1].clone() {
                reserve_1
            } else {
                reserve_0
            };

            // let (reserve_in, reserve_out) = IPoolDispatcher { contract_address: pool }
            //     .get_reserves();
            reverse_amounts
                .append(
                    get_amount_in(
                        reverse_amounts.at(path_length - i - 1).clone(), reserve_in, reserve_out
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
