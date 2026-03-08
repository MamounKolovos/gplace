-module(board_ffi).
-export([to_bit_array/1]).

-spec to_bit_array(atomics:atomics_ref()) -> binary().

to_bit_array(Storage) -> to_bit_array(Storage, 1, maps:get(size, atomics:info(Storage)), <<>>).
to_bit_array(Storage, Idx, Size, Acc) when Idx =< Size ->
  to_bit_array(Storage, Idx+1, Size, <<Acc/bits, (atomics:get(Storage, Idx)):64>>);
to_bit_array(_, _, _, Acc) -> Acc.