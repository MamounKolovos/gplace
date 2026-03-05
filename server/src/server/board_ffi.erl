-module(board_ffi).
-export([to_bit_array/1]).

-spec to_bit_array(atomics:atomics_ref()) -> binary().

to_bit_array(Board) -> to_bit_array(Board, 1, maps:get(size, atomics:info(Board)), <<>>).
to_bit_array(Board, Idx, Size, Acc) when Idx =< Size ->
  to_bit_array(Board, Idx+1, Size, <<Acc/bits, (atomics:get(Board, Idx)):64>>);
to_bit_array(_, _, _, Acc) -> Acc.