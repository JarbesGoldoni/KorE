# Erlang OTP Standard Library — Complete Module Reference

**Version: OTP 29 / stdlib 8.0**

---

## 1. `lists` — List Processing

**Category:** Collections / Sequences
**App:** stdlib

The foundational list-processing module. All functions are purely functional; lists are singly-linked.

**Functions:**

| Function | Description |
|---|---|
| `all/2` | Returns `true` if predicate holds for every element |
| `any/2` | Returns `true` if predicate holds for at least one element |
| `append/1` | Concatenates a list of lists |
| `append/2` | Concatenates two lists (equivalent to `++`) |
| `concat/1` | Concatenates text representations of atoms/integers/floats/strings |
| `delete/2` | Removes first matching element |
| `droplast/1` | Removes last element |
| `dropwhile/2` | Drops elements while predicate is true, returns rest |
| `duplicate/2` | Returns list of N copies of a term |
| `enumerate/1,2,3` | Pairs each element with its index |
| `filter/2` | Keeps elements satisfying predicate |
| `filtermap/2` | Filter + transform in one pass |
| `flatlength/1` | Length of flattened deep list |
| `flatmap/2` | Map then flatten one level |
| `flatten/1,2` | Fully flatten a deep list |
| `foldl/3` | Left fold (tail-recursive) |
| `foldr/3` | Right fold |
| `foreach/2` | Iterate for side effects |
| `join/2` | Inserts separator between elements |
| `keydelete/3` | Delete by key in Nth position of tuple list |
| `keyfind/3` | Find tuple by key in Nth position |
| `keymap/3` | Map over Nth element of tuple list |
| `keymember/3` | Test membership by key |
| `keymerge/3` | Merge two key-sorted tuple lists |
| `keyreplace/4` | Replace tuple by key |
| `keysearch/3` | Find tuple by key (legacy; prefer `keyfind`) |
| `keysort/2` | Sort tuple list by Nth element (stable) |
| `keystore/4` | Replace or append tuple by key |
| `keytake/3` | Extract tuple by key, returns rest |
| `last/1` | Last element |
| `map/2` | Transform every element |
| `mapfoldl/3` | Map + left fold in one pass |
| `mapfoldr/3` | Map + right fold in one pass |
| `max/1` | Maximum element by `>=` |
| `member/2` | Test element membership |
| `merge/1,2,3` | Merge pre-sorted lists |
| `merge3/3` | Merge three pre-sorted lists |
| `min/1` | Minimum element |
| `nth/2` | Nth element (1-indexed) |
| `nthtail/2` | Tail starting at position N+1 |
| `partition/2` | Split into {Satisfying, NotSatisfying} |
| `prefix/2` | Test if List1 is prefix of List2 |
| `reverse/1,2` | Reverse (optionally with tail) |
| `search/2` | Find first matching element |
| `seq/2,3` | Generate integer sequence |
| `sort/1,2` | Sort (optionally with custom comparator) |
| `split/2` | Split at position N |
| `splitwith/2` | Split at first element failing predicate |
| `sublist/2,3` | Extract sub-sequence |
| `subtract/2` | List difference (remove first occurrences) |
| `suffix/2` | Test if List1 is suffix of List2 |
| `sum/1` | Sum of numeric list |
| `takewhile/2` | Take elements while predicate holds |
| `ukeymerge/3` | Unique merge by key |
| `ukeysort/2` | Sort + deduplicate by key |
| `umerge/1,2,3` | Merge + deduplicate |
| `uniq/1,2` | Remove duplicates (stable order) |
| `unzip/1` | Split list of pairs into two lists |
| `unzip3/1` | Split list of 3-tuples into three lists |
| `usort/1,2` | Sort + deduplicate |
| `zip/2,3` | Zip two lists into pairs |
| `zip3/3,4` | Zip three lists into 3-tuples |
| `zipwith/3,4` | Zip with combining function |
| `zipwith3/4,5` | Zip three lists with combining function |

```erlang
%% Basic operations
lists:map(fun(X) -> X * 2 end, [1,2,3]).      % [2,4,6]
lists:foldl(fun(X, Acc) -> X + Acc end, 0, [1,2,3,4,5]). % 15
lists:filter(fun(X) -> X rem 2 =:= 0 end, [1,2,3,4,5]).  % [2,4]
lists:partition(fun(X) -> X > 3 end, [1,2,3,4,5]).        % {[4,5],[1,2,3]}
lists:keysort(2, [{a,3},{b,1},{c,2}]).         % [{b,1},{c,2},{a,3}]
lists:seq(1, 10, 2).                           % [1,3,5,7,9]
lists:enumerate([a,b,c]).                      % [{1,a},{2,b},{3,c}]
lists:uniq([1,2,1,3,2]).                       % [1,2,3]
lists:zipwith(fun(A,B) -> A+B end, [1,2,3], [4,5,6]). % [5,7,9]
```

---

## 2. `maps` — Hash Map / Dictionary

**Category:** Collections / Key-Value
**App:** stdlib (since OTP 17)

The primary key-value store. Implemented as hash array mapped tries (HAMT). Keys compared by match (`=:=`).

**Functions:**

| Function | Description |
|---|---|
| `new/0` | Empty map |
| `put/3` | Insert or replace key |
| `get/2` | Get value (raises `{badkey,K}` if missing) |
| `get/3` | Get value with default |
| `find/2` | Get as `{ok, V} \| error` |
| `update/3` | Update existing key (raises if missing) |
| `update_with/3` | Update with fun (raises if missing) |
| `update_with/4` | Update with fun or insert default |
| `remove/2` | Remove key (no-op if absent) |
| `take/2` | Remove + return value |
| `is_key/2` | Membership test |
| `keys/1` | List of all keys |
| `values/1` | List of all values |
| `size/1` | Number of associations (O(1)) |
| `merge/2` | Merge two maps (Map2 wins on conflict) |
| `merge_with/3` | Merge with combiner fun |
| `intersect/2` | Keep only common keys (Map2 value wins) |
| `intersect_with/3` | Intersection with combiner |
| `filter/2` | Keep pairs matching predicate |
| `filtermap/2` | Filter + transform |
| `map/2` | Transform all values |
| `fold/3` | Fold over all pairs |
| `foreach/2` | Iterate for side effects |
| `from_list/1` | Build from `[{K,V}]` |
| `from_keys/2` | Build from key list, all same value |
| `to_list/1` | Convert to `[{K,V}]` |
| `with/2` | Subset by key list |
| `without/2` | Remove keys by list |
| `iterator/1,2` | Create iterator (optionally ordered/reversed/custom) |
| `next/1` | Advance iterator |
| `groups_from_list/2,3` | Partition list into map of groups |

```erlang
M = #{name => alice, age => 30},
maps:get(name, M),                        % alice
maps:get(missing, M, default),            % default
maps:update_with(age, fun(V) -> V+1 end, M), % #{name=>alice, age=>31}
maps:filter(fun(K,_) -> is_atom(K) end, M),  % #{name=>alice,age=>30}

%% Grouping
maps:groups_from_list(
  fun(X) -> X rem 2 end,
  [1,2,3,4,5]).
% #{0=>[2,4], 1=>[1,3,5]}

%% Ordered iteration
I = maps:iterator(#{b=>2, a=>1}, ordered),
maps:to_list(I). % [{a,1},{b,2}]
```

---

## 3. `sets` — Hash Set

**Category:** Collections / Set
**App:** stdlib

Unordered set with no duplicates. Default implementation since OTP 28 is a hash-based structure (version 2). Elements compared by match (`=:=`). Compatible interface with `ordsets` and `gb_sets`.

**Functions:**

| Function | Description |
|---|---|
| `new/0,1` | Empty set (optionally specify version 1 or 2) |
| `add_element/2` | Insert element |
| `del_element/2` | Remove element |
| `is_element/2` | Membership test |
| `is_empty/1` | Empty test |
| `is_set/1` | Type check |
| `size/1` | Cardinality |
| `union/1,2` | Set union |
| `intersection/1,2` | Set intersection |
| `subtract/2` | Set difference |
| `is_disjoint/2` | True if no common elements |
| `is_subset/2` | Subset test |
| `is_equal/2` | Equality test (works across versions) |
| `from_list/1,2` | Build from list |
| `to_list/1` | Convert to list (unordered) |
| `filter/2` | Keep elements matching predicate |
| `filtermap/2` | Filter + transform |
| `map/2` | Transform all elements |
| `fold/3` | Fold over elements |

```erlang
S1 = sets:from_list([1,2,3,4]),
S2 = sets:from_list([3,4,5,6]),
sets:to_list(sets:union(S1, S2)),        % [1,2,3,4,5,6] (any order)
sets:to_list(sets:intersection(S1, S2)), % [3,4]
sets:to_list(sets:subtract(S1, S2)),     % [1,2]
sets:is_subset(sets:from_list([3,4]), S1). % true
```

---

## 4. `ordsets` — Ordered Set (sorted list)

**Category:** Collections / Set
**App:** stdlib

Sets represented as sorted lists. Elements compared by `==` (not `=:=`). O(N) operations but ordered and list-interoperable.

**Functions:** (same interface as `sets`)

`new/0`, `add_element/2`, `del_element/2`, `is_element/2`, `is_empty/1`, `is_set/1`, `size/1`, `union/1,2`, `intersection/1,2`, `subtract/2`, `is_disjoint/2`, `is_subset/2`, `is_equal/2`, `from_list/1`, `to_list/1`, `filter/2`, `filtermap/2`, `map/2`, `fold/3`

```erlang
S = ordsets:from_list([3,1,4,1,5,9,2,6]),
ordsets:to_list(S). % [1,2,3,4,5,6,9]  -- sorted, deduplicated

%% Note: ordsets uses == not =:=
ordsets:is_element(1.0, ordsets:from_list([1])). % true (1.0 == 1)
sets:is_element(1.0, sets:from_list([1])).        % false (1.0 =/= 1)
```

---

## 5. `gb_sets` — General Balanced Tree Set

**Category:** Collections / Set
**App:** stdlib

Sets backed by AVL-like balanced binary trees. O(log N) operations. Elements compared by `==`. Good for ordered traversal and range queries.

**Functions:**

| Function | Description |
|---|---|
| `new/0` | Empty set |
| `empty/0` | Alias for `new/0` |
| `add/2`, `add_element/2` | Insert |
| `delete/2`, `del_element/2` | Remove (raises if absent) |
| `delete_any/2` | Remove (no-op if absent) |
| `is_element/2`, `is_member/2` | Membership |
| `is_empty/1` | Empty test |
| `size/1` | Cardinality |
| `union/1,2` | Union |
| `intersection/1,2` | Intersection |
| `subtract/2`, `difference/2` | Difference |
| `is_disjoint/2` | Disjoint test |
| `is_subset/2` | Subset test |
| `from_list/1`, `from_ordset/1` | Build from list/ordset |
| `to_list/1`, `to_ordset/1` | Convert to sorted list |
| `filter/2` | Keep matching elements |
| `fold/3` | Fold in ascending order |
| `next/1` | Iterator step |
| `iterator/1` | Iterator (ascending) |
| `iterator_from/2` | Iterator starting at element |
| `largest/1` | Maximum element |
| `smallest/1` | Minimum element |
| `take_largest/1` | Remove and return max |
| `take_smallest/1` | Remove and return min |
| `balance/1` | Rebalance tree |

```erlang
S = gb_sets:from_list([5,3,8,1,9,2]),
gb_sets:smallest(S),      % 1
gb_sets:largest(S),       % 9
gb_sets:to_list(S),       % [1,2,3,5,8,9]  -- sorted

%% Ordered iteration
I0 = gb_sets:iterator(S),
{V1, I1} = gb_sets:next(I0), % {1, ...}
{V2, I2} = gb_sets:next(I1), % {2, ...}

%% Range: all elements >= 4
I = gb_sets:iterator_from(4, S),
gb_sets:next(I). % {5, ...}
```

---

## 6. `gb_trees` — General Balanced Tree Map

**Category:** Collections / Key-Value (ordered)
**App:** stdlib

Key-value store backed by AVL-like balanced trees. O(log N) all ops. Keys compared by `<` (Erlang term order). Ordered traversal available.

**Functions:**

| Function | Description |
|---|---|
| `empty/0` | Empty tree |
| `insert/3` | Insert (raises if key exists) |
| `enter/3` | Insert or replace |
| `update/3` | Update existing key (raises if absent) |
| `delete/2` | Delete (raises if absent) |
| `delete_any/2` | Delete (no-op if absent) |
| `lookup/2` | Find as `{value, V} \| none` |
| `get/2` | Find (raises if absent) |
| `is_defined/2` | Membership test |
| `keys/1` | Sorted list of keys |
| `values/1` | List of values in key order |
| `to_list/1` | List of `{K,V}` in key order |
| `from_orddict/1` | Build from orddict |
| `size/1` | Number of entries |
| `is_empty/1` | Empty test |
| `map/2` | Transform values |
| `iterator/1` | Iterator (ascending) |
| `iterator_from/2` | Iterator starting at key |
| `next/1` | Iterator step → `{K, V, Iter} \| none` |
| `largest/1` | `{MaxKey, Value}` |
| `smallest/1` | `{MinKey, Value}` |
| `take_largest/1` | Remove and return max |
| `take_smallest/1` | Remove and return min |
| `balance/1` | Rebalance |

```erlang
T0 = gb_trees:empty(),
T1 = gb_trees:insert(b, 2, T0),
T2 = gb_trees:insert(a, 1, T1),
T3 = gb_trees:enter(c, 3, T2),
gb_trees:to_list(T3),        % [{a,1},{b,2},{c,3}]
gb_trees:get(b, T3),         % 2
gb_trees:smallest(T3),       % {a, 1}
gb_trees:keys(T3).           % [a,b,c]
```

---

## 7. `queue` — Double-Ended FIFO Queue

**Category:** Collections / Queue
**App:** stdlib

Efficient amortized O(1) enqueue and dequeue from both ends. Implemented as a pair of lists.

**Functions (three APIs coexist):**

**Original API:**
| Function | Description |
|---|---|
| `new/0` | Empty queue |
| `in/2` | Enqueue at rear |
| `in_r/2` | Enqueue at front |
| `out/1` | Dequeue from front → `{{value,V}, Q} \| {empty, Q}` |
| `out_r/1` | Dequeue from rear |
| `peek/1` | Inspect front without removing |
| `peek_r/1` | Inspect rear |
| `is_empty/1` | Empty test |
| `len/1` | Length (O(N)) |
| `member/2` | Membership test |
| `to_list/1` | Convert to list |
| `from_list/1` | Build from list |
| `reverse/1` | Reverse queue |
| `join/2` | Concatenate two queues |
| `split/2` | Split at position N |
| `filter/2` | Keep elements matching predicate |
| `filtermap/2` | Filter + transform |
| `fold/3` | Fold front to back |

**Okasaki API:** `cons/2`, `head/1`, `tail/1`, `snoc/2`, `last/1`, `daeh/1`/`liat/1`

```erlang
Q0 = queue:new(),
Q1 = queue:in(a, Q0),
Q2 = queue:in(b, Q1),
Q3 = queue:in(c, Q2),
{{value, a}, Q4} = queue:out(Q3),
queue:to_list(Q4).  % [b, c]

%% Dequeue from both ends
Q = queue:from_list([1,2,3,4,5]),
queue:peek(Q),   % {value, 1}
queue:peek_r(Q). % {value, 5}
```

---

## 8. `array` — Functional Array

**Category:** Collections / Array
**App:** stdlib

Functional (persistent) array with O(log N) access. Can be sparse (default value for unset indices). Fixed or extendible size.

**Functions:**

| Function | Description |
|---|---|
| `new/0,1,2` | New array (options: size, fixed, default) |
| `set/3` | Set element at index |
| `get/2` | Get element at index |
| `size/1` | Current size |
| `sparse_size/1` | Index of last set element + 1 |
| `reset/2` | Reset index to default value |
| `default/1` | Get default value |
| `is_array/1` | Type check |
| `is_fix/1` | Fixed-size test |
| `fix/1` | Make fixed-size |
| `relax/1` | Make extendible |
| `resize/1,2` | Resize |
| `to_list/1` | Convert to list (includes defaults) |
| `sparse_to_list/1` | List of only set elements |
| `to_orddict/1` | To `[{Index,Value}]` |
| `sparse_to_orddict/1` | Only set elements as orddict |
| `from_list/1,2` | Build from list |
| `from_orddict/1,2` | Build from orddict |
| `map/2` | Map over all indices |
| `sparse_map/2` | Map over only set indices |
| `foldl/3`, `foldr/3` | Fold left/right over all |
| `sparse_foldl/3`, `sparse_foldr/3` | Fold over set only |

```erlang
A0 = array:new(10, {default, 0}),
A1 = array:set(3, hello, A0),
array:get(3, A1),   % hello
array:get(7, A1),   % 0  (default)
array:size(A1),     % 10

%% Sparse usage
A = array:new([{default, undefined}]),
A2 = array:set(1000, value, A),
array:sparse_to_orddict(A2). % [{1000, value}]
```

---

## 9. `dict` — Key-Value Dictionary (deprecated)

**Category:** Collections / Key-Value
**App:** stdlib

Hash-based key-value store. **Largely superseded by `maps`**. Keys compared by `==`. Still in OTP for compatibility.

**Functions:**

`new/0`, `store/3`, `fetch/2`, `find/2`, `fetch_keys/1`, `is_key/2`, `erase/2`, `update/3`, `update/4`, `update_counter/3`, `append/3`, `append_list/3`, `merge/3`, `filter/2`, `map/2`, `fold/3`, `size/1`, `is_empty/1`, `to_list/1`, `from_list/1`

```erlang
D = dict:from_list([{a,1},{b,2},{c,3}]),
dict:fetch(b, D),                    % 2
dict:update_counter(a, 10, D),       % #{a=>11,...}
dict:merge(fun(_K,V1,_V2)->V1 end, D, dict:from_list([{b,99},{d,4}])).
```

---

## 10. `orddict` — Ordered Dictionary (sorted list)

**Category:** Collections / Key-Value
**App:** stdlib

Key-value store as a sorted list of `{Key, Value}` pairs. Keys compared by `==`. O(N) operations but ordered.

**Functions:** Same as `dict`: `new/0`, `store/3`, `fetch/2`, `find/2`, `fetch_keys/1`, `is_key/2`, `erase/2`, `update/3,4`, `update_counter/3`, `append/3`, `append_list/3`, `merge/3`, `filter/2`, `map/2`, `fold/3`, `size/1`, `is_empty/1`, `to_list/1`, `from_list/1`

```erlang
D = orddict:from_list([{c,3},{a,1},{b,2}]),
orddict:to_list(D).  % [{a,1},{b,2},{c,3}]  -- always sorted
```

---

## 11. `proplists` — Property Lists

**Category:** Collections / Association List
**App:** stdlib

Utilities for working with property lists — lists of `{Key, Value}` or bare atom keys. Common for option lists in OTP APIs.

**Functions:**

| Function | Description |
|---|---|
| `get_value/2,3` | Get value by key (with optional default) |
| `get_all_values/2` | All values for key |
| `get_keys/1` | List of all keys |
| `lookup/2` | Find first entry → `{Key,Value} \| none` |
| `lookup_all/2` | All entries for key |
| `is_defined/2` | Membership test |
| `delete/2` | Remove all entries for key |
| `append_values/2` | Append values for key across list |
| `compact/1` | Remove `false` entries, normalize booleans |
| `expand/2` | Expand abbreviations |
| `normalize/2` | Apply normalization operations |
| `unfold/1` | Expand `{K,true}` → `K` |

```erlang
Opts = [{debug, true}, {timeout, 5000}, verbose],
proplists:get_value(timeout, Opts),    % 5000
proplists:get_value(debug, Opts),      % true
proplists:is_defined(verbose, Opts),   % true
proplists:get_value(missing, Opts, default). % default
```

---

## 12. `sofs` — Sets of Sets

**Category:** Collections / Set Theory
**App:** stdlib

Mathematical set operations including relations, functions, and set families. Uses a typed representation.

**Key functions:**

`set/1,2`, `from_term/1,2`, `to_external/1`, `type/1`, `is_set/1`, `is_empty_set/1`, `is_equal/2`, `union/1,2`, `intersection/1,2`, `difference/2`, `symmetric_difference/2`, `is_subset/2`, `is_disjoint/2`, `product/1,2`, `relation/1,2`, `domain/1`, `range/1`, `field/1`, `inverse/1`, `composition/2`, `image/2`, `inverse_image/2`, `restriction/2`, `drestriction/2`, `join/4`, `projection/2`, `partition/1,2,3`, `family/1`, `family_union/1`, `family_intersection/1`, `relation_to_family/1`, `family_to_relation/1`

```erlang
S1 = sofs:set([1,2,3]),
S2 = sofs:set([2,3,4]),
sofs:to_external(sofs:union(S1, S2)),        % [1,2,3,4]
sofs:to_external(sofs:intersection(S1, S2)), % [2,3]

%% Relation example
R = sofs:relation([{a,1},{b,2},{a,3}]),
sofs:to_external(sofs:image(R, sofs:set([a]))).  % [1,3]
```

---

## 13. `string` — Unicode String Processing

**Category:** String / Binary
**App:** stdlib

Modern string module (OTP 20+). Handles Unicode grapheme clusters correctly. Operates on both `string()` (list of codepoints) and `binary()`.

**Functions:**

| Function | Description |
|---|---|
| `length/1` | Number of grapheme clusters (not bytes/codepoints) |
| `nth_grapheme/2` | Nth grapheme cluster |
| `to_upper/1`, `to_lower/1` | Case conversion (Unicode-aware) |
| `uppercase/1`, `lowercase/1` | Alias for above |
| `casefold/1` | Unicode case folding (for comparison) |
| `equal/2,3` | Compare strings (optionally ignoring case) |
| `find/2,3` | Find substring (leading/trailing) |
| `split/2,3` | Split on pattern (all/leading/trailing) |
| `replace/3,4` | Replace pattern |
| `trim/1,2,3` | Trim whitespace or characters |
| `chomp/1` | Remove trailing newline |
| `strip/1,2,3` | Trim both ends (legacy) |
| `prefix/2` | Strip matching prefix → rest \| nomatch |
| `slice/2,3` | Extract substring by grapheme position |
| `pad/2,3,4` | Pad to length |
| `reverse/1` | Reverse grapheme cluster sequence |
| `tokens/2` | Tokenize by separators |
| `join/2` | Join list of strings with separator |
| `concat/1` | Concatenate list of strings |
| `lexemes/2` | Like `tokens` but merges separators |
| `nth_grapheme/2` | Get specific grapheme |
| `next_codepoint/1` | Step through codepoints |
| `next_grapheme/1` | Step through grapheme clusters |
| `to_integer/1` | Parse integer, returns `{Int, Rest}` |
| `to_float/1` | Parse float, returns `{Float, Rest}` |
| `is_empty/1` | Empty test |
| `jaro_similarity/2` | Jaro string similarity (0.0–1.0) |

```erlang
%% Unicode-correct length
string:length("hello").      % 5
string:length(<<"héllo"/utf8>>). % 5 (é is one grapheme)

%% Split/trim
string:split("a,b,,c", ",", all). % ["a","b","","c"]
string:trim("  hello  "),         % "hello"
string:trim("xxhelloxx", both, "x"). % "hello"

%% Case
string:to_upper("héllo"). % "HÉLLO"
string:casefold("Straße"). % "strasse"

%% Find
string:find("hello world", "world").    % "world"
string:prefix("hello world", "hello"). % " world"

%% Jaro similarity
string:jaro_similarity("kitten", "sitting"). % ~0.746
```

---

## 14. `binary` — Binary Data

**Category:** String / Binary
**App:** stdlib

Low-level binary manipulation. Efficient due to Erlang's binary sharing semantics.

**Functions:**

| Function | Description |
|---|---|
| `at/2` | Byte at position |
| `bin_to_list/1,2,3` | Binary to byte list |
| `list_to_bin/1` | Byte list to binary |
| `copy/1,2` | Copy binary (optionally N times) |
| `decode_unsigned/1,2` | Binary to unsigned integer (big/little endian) |
| `encode_unsigned/1,2` | Unsigned integer to binary |
| `first/1` | First byte |
| `last/1` | Last byte |
| `longest_common_prefix/1` | Longest common prefix length |
| `longest_common_suffix/1` | Longest common suffix length |
| `match/2,3` | Find first occurrence of pattern |
| `matches/2,3` | Find all occurrences |
| `part/2,3` | Extract sub-binary |
| `referenced_byte_size/1` | Size of underlying allocation |
| `replace/3,4` | Replace pattern |
| `split/2,3` | Split on pattern |
| `compile_pattern/1` | Pre-compile pattern for repeated use |

```erlang
B = <<"hello world">>,
binary:split(B, <<" ">>),              % [<<"hello">>, <<"world">>]
binary:split(B, <<" ">>, [global]),   % [<<"hello">>, <<"world">>]
binary:match(B, <<"world">>),          % {6, 5}
binary:part(B, 6, 5),                  % <<"world">>
binary:replace(B, <<"world">>, <<"there">>). % <<"hello there">>

%% Numeric encoding
binary:encode_unsigned(1024),          % <<4, 0>>
binary:decode_unsigned(<<4, 0>>).      % 1024
```

---

## 15. `unicode` — Unicode Encoding/Conversion

**Category:** String / Binary
**App:** stdlib

Encode/decode between Unicode representations: UTF-8, UTF-16, UTF-32, and Erlang's internal codepoint list format.

**Functions:**

| Function | Description |
|---|---|
| `characters_to_binary/1,2,3` | Convert to UTF-8 binary (or specified encoding) |
| `characters_to_list/1,2` | Convert to codepoint list |
| `bom_to_encoding/1` | Detect BOM and return encoding |
| `encoding_to_bom/1` | Get BOM bytes for encoding |

Returns `{incomplete, Converted, Rest}` or `{error, Converted, Rest}` on failure.

```erlang
unicode:characters_to_binary("héllo"),    % <<"héllo"/utf8>>
unicode:characters_to_list(<<"héllo"/utf8>>), % [104,233,108,108,111]

%% Explicit encoding
unicode:characters_to_binary("hello", utf8, utf16).
% <<0,104,0,101,0,108,0,108,0,111>>  (UTF-16 big-endian)

%% BOM detection
unicode:bom_to_encoding(<<16#EF, 16#BB, 16#BF, "rest"/utf8>>).
% {utf8, 3}  -- BOM is 3 bytes
```

---

## 16. `io_lib` — I/O Formatting Library

**Category:** String / I/O
**App:** stdlib

String formatting and parsing, used internally by `io:format/2` and `io:fwrite/2`. Returns deep character lists (iolists).

**Functions:**

| Function | Description |
|---|---|
| `format/2` | Format string like `printf` → iolist |
| `fwrite/2` | Alias for `format/2` |
| `print/1,4` | Pretty-print a term |
| `write/1,2` | Write term as Erlang syntax |
| `write_atom/1` | Write atom with quoting if needed |
| `write_string/1,2` | Write string with escaping |
| `write_char/1,2` | Write single character |
| `read/2` | Read Erlang term from char list |
| `fread/2,3` | Formatted read (scanf-like) |
| `scan_format/2` | Scan format control sequences |
| `unscan_format/1` | Inverse of `scan_format` |
| `build_text/1` | Build iolist from scanned format |
| `deep_char_list/1` | Test if deep character list |
| `printable_list/1` | Test if printable character list |
| `printable_unicode_list/1` | Test if printable Unicode list |
| `nl/0` | Newline iolist |
| `tab/1` | Tab iolist |
| `char_list/1` | Type check |
| `flatten/1,2` | Flatten iolist to string |

**Format directives:** `~w` (write), `~p` (print), `~s` (string), `~d` (integer), `~f` (float), `~e` (scientific), `~g` (shortest float), `~i` (ignore), `~n` (newline), `~N` (platform newline), `~t` (unicode), `~lp` (limit depth)

```erlang
io_lib:format("Hello ~s, you are ~p years old~n", ["Alice", 30]).
% [72,101,108,108,111,32,65,108,105,99,101,44,32,...]

%% Useful pattern: flatten to string
lists:flatten(io_lib:format("~w", [{a,b,c}])). % "{a,b,c}"

%% fread (scanf-style)
io_lib:fread("~d-~d-~d", "2024-01-15").
% {ok, [2024, 1, 15], ""}
```

---

## 17. `io` — I/O Server Interface

**Category:** I/O
**App:** stdlib

All terminal and file I/O in Erlang goes through I/O server processes. `io` is the API to these servers.

**Functions:**

| Function | Description |
|---|---|
| `format/1,2,3` | Formatted output (to device or stdout) |
| `fwrite/1,2,3` | Alias for `format` |
| `write/1,2` | Write term |
| `print/1,2` | Pretty-print term |
| `nl/0,1` | Write newline |
| `put_chars/1,2` | Write raw characters/binary |
| `get_chars/2,3` | Read N characters |
| `get_line/1,2` | Read line |
| `read/1,2,3` | Read and parse Erlang term |
| `scan_erl_exprs/1,2,3,4` | Tokenize Erlang expressions |
| `scan_erl_form/1,2,3,4` | Tokenize a complete Erlang form |
| `parse_erl_exprs/1,2,3,4` | Parse Erlang expressions |
| `parse_erl_form/1,2,3,4` | Parse a complete Erlang form |
| `setopts/1,2` | Set I/O device options (e.g., `binary`, `unicode`) |
| `getopts/1` | Get I/O device options |
| `rows/0,1` | Terminal row count |
| `columns/0,1` | Terminal column count |
| `request/2` | Low-level I/O request |
| `requests/2` | Multiple I/O requests |

```erlang
io:format("~p~n", [{hello, world}]).     % prints {hello,world}\n
io:format(standard_error, "Error: ~s~n", ["oops"]).

%% Reading
{ok, Term, _} = io:read("Enter term: ").

%% I/O to a string (via string device)
{ok, Dev} = file:open([], [write, read]),  % not ideal; use io_lib instead
```

---

## 18. `file` — File System Interface

**Category:** I/O / File System
**App:** kernel

All file system operations. Returns `ok | {ok, Result} | {error, Reason}`.

**Functions:**

| Function | Description |
|---|---|
| `open/2` | Open file, returns `{ok, IoDevice}` |
| `close/1` | Close file |
| `read/2` | Read N bytes/chars |
| `read_line/1` | Read one line |
| `write/2` | Write data |
| `pread/2,3` | Positional read |
| `pwrite/2,3` | Positional write |
| `position/2` | Seek (bof/cur/eof relative) |
| `truncate/1` | Truncate at current position |
| `sync/1` | Flush to disk |
| `read_file/1` | Read entire file to binary |
| `write_file/2,3` | Write binary to file |
| `read_file_info/1,2` | File metadata (`#file_info{}`) |
| `write_file_info/2,3` | Set file metadata |
| `read_link/1` | Read symbolic link target |
| `make_symlink/2` | Create symlink |
| `make_link/2` | Create hard link |
| `rename/2` | Rename/move |
| `copy/2,3` | Copy file |
| `delete/1,2` | Delete file |
| `del_dir/1` | Delete empty directory |
| `del_dir_r/1` | Delete directory recursively |
| `make_dir/1` | Create directory |
| `list_dir/1` | List directory entries |
| `list_dir_all/1` | List all (including raw names) |
| `get_cwd/0,1` | Get working directory |
| `set_cwd/1` | Set working directory |
| `native_name_encoding/0` | Atom: `latin1` or `utf8` |
| `consult/1` | Read Erlang terms from file |
| `path_consult/2` | Consult on search path |
| `eval/1,2` | Eval Erlang expressions from file |
| `script/1,2` | Run Erlang script file |
| `format_error/1` | POSIX error to string |
| `pid2name/1` | Get filename from I/O PID |

**Open modes:** `read`, `write`, `append`, `exclusive`, `raw`, `binary`, `{encoding, unicode}`, `compressed`, `{read_ahead, Size}`, `{delayed_write, Size, Delay}`

```erlang
%% Read entire file
{ok, Bin} = file:read_file("/etc/hostname"),

%% Write file
file:write_file("/tmp/test.txt", <<"hello\n">>),

%% Open and stream
{ok, Fd} = file:open("/tmp/test.txt", [read, binary]),
{ok, Data} = file:read(Fd, 1024),
file:close(Fd),

%% Consult Erlang terms
%% File contains: {key, value}. [1,2,3].
{ok, Terms} = file:consult("data.erl"),
% Terms = [{key, value}, [1,2,3]]

%% File info
{ok, Info} = file:read_file_info("/tmp"),
Info#file_info.type,  % directory
Info#file_info.size.
```

---

## 19. `filename` — Path Manipulation

**Category:** I/O / File System
**App:** stdlib

Platform-neutral filename and path manipulation. Handles both Unix (`/`) and Windows (`\`) separators.

**Functions:**

| Function | Description |
|---|---|
| `absname/1,2` | Absolute path |
| `absname_join/2` | Absolute path + join |
| `basename/1,2` | Last path component (optionally strip extension) |
| `dirname/1` | All but last component |
| `extension/1` | File extension including `.` |
| `rootname/1,2` | Strip extension |
| `join/1,2` | Join path components |
| `split/1` | Split into components |
| `pathtype/1` | `absolute \| relative \| volumerelative` |
| `flatten/1` | Flatten deep path iolist |
| `nativename/1` | Platform-native separator |
| `safe_relative_path/2` | Guard against directory traversal |
| `find_src/1,2` | Find Erlang source file |
| `find_file/2,3` | Find file in path list |

```erlang
filename:join(["/usr", "local", "bin", "erl"]). % "/usr/local/bin/erl"
filename:basename("/usr/local/bin/erl"),          % "erl"
filename:basename("/foo/bar.txt", ".txt"),        % "bar"
filename:dirname("/usr/local/bin/erl"),           % "/usr/local/bin"
filename:extension("file.beam"),                  % ".beam"
filename:rootname("file.beam"),                   % "file"
filename:split("/a/b/c"),                         % ["/","a","b","c"]
```

---

## 20. `filelib` — File Utilities

**Category:** I/O / File System
**App:** stdlib

Higher-level file utilities: wildcard matching, directory traversal.

**Functions:**

| Function | Description |
|---|---|
| `wildcard/1,2` | Glob files (supports `*`, `**`, `?`, `{a,b}`) |
| `is_file/1` | Test if path is a regular file |
| `is_dir/1` | Test if path is a directory |
| `is_regular/1` | Test if path is a regular file (not dir/link) |
| `ensure_dir/1` | Create all parent directories |
| `ensure_path/1` | Create full path including final dir |
| `file_size/1` | File size in bytes |
| `last_modified/1` | Last modification time |
| `fold_files/5` | Fold over files matching pattern in directory tree |
| `find_file/2,3` | Find file in path list |
| `find_source/1,2,3` | Find source file for compiled module |

```erlang
filelib:wildcard("*.erl"),            % ["foo.erl", "bar.erl", ...]
filelib:wildcard("**/*.beam"),        % all .beam files recursively
filelib:ensure_dir("/tmp/a/b/c.txt"), % creates /tmp/a/b/

filelib:fold_files(".", "\.erl$", true,
  fun(F, Acc) -> [F|Acc] end, []).   % all .erl files
```

---

## 21. `math` — Mathematical Functions

**Category:** Math / Numbers
**App:** stdlib

Thin wrapper over C math library. All functions take and return floats.

**Functions:**

| Function | Description |
|---|---|
| `pi/0` | π constant |
| `sin/1`, `cos/1`, `tan/1` | Trig functions (radians) |
| `asin/1`, `acos/1`, `atan/1`, `atan2/2` | Inverse trig |
| `sinh/1`, `cosh/1`, `tanh/1` | Hyperbolic |
| `asinh/1`, `acosh/1`, `atanh/1` | Inverse hyperbolic |
| `exp/1` | e^x |
| `log/1` | Natural logarithm |
| `log2/1` | Base-2 logarithm |
| `log10/1` | Base-10 logarithm |
| `pow/2` | x^y |
| `sqrt/1` | Square root |
| `fmod/2` | Floating-point modulo |
| `ceil/1` | Ceiling (since OTP 20) |
| `floor/1` | Floor (since OTP 20) |
| `tau/0` | τ = 2π (since OTP 26) |

```erlang
math:pi(),           % 3.141592653589793
math:sqrt(2.0),      % 1.4142135623730951
math:pow(2.0, 10.0), % 1024.0
math:log(math:exp(1.0)), % 1.0
math:atan2(1.0, 1.0) * 4.0. % pi
```

---

## 22. `rand` — Pseudo-Random Number Generation

**Category:** Math / Numbers
**App:** stdlib

Multiple PRNG algorithms. State can be process-local (implicit) or explicit. **Thread-safe when using explicit state.**

**Algorithms:** `exsss` (default, Xorshift116**), `exsp`, `exs1024s`, `exro928ss`, `splitmix64`, `mwc59`

**Functions:**

| Function | Description |
|---|---|
| `seed/1,2` | Seed the process PRNG |
| `seed_s/1,2` | Seed and return explicit state |
| `export_seed/0` | Export current state for serialization |
| `export_seed_s/1` | Export explicit state |
| `uniform/0` | Float in `[0.0, 1.0)` |
| `uniform/1` | Integer in `[1, N]` |
| `uniform_s/1,2` | Explicit-state versions |
| `uniform_real/0` | Float with full mantissa precision |
| `uniform_real_s/1` | Explicit-state version |
| `integer/1` | Integer in `[0, N-1]` (since OTP 26) |
| `bytes/1` | Random binary of N bytes |
| `bytes_s/2` | Explicit-state version |
| `normal/0,2` | Normal distribution |
| `normal_s/1,3` | Explicit-state normal |
| `jump/0,1` | Jump ahead in sequence |

```erlang
rand:uniform(),          % e.g. 0.7421
rand:uniform(100),       % e.g. 42  (integer 1..100)
rand:bytes(16),          % 16-byte random binary

%% Reproducible: explicit state
S0 = rand:seed_s(exsss, {1,2,3}),
{V1, S1} = rand:uniform_s(100, S0),
{V2, _S2} = rand:uniform_s(100, S1),

%% Normal distribution
rand:normal(0.0, 1.0).  % mean=0, stddev=1
```

---

## 23. `erlang` — BIFs and Built-In Operations

**Category:** Process / Concurrency / Term Manipulation / System
**App:** erts

The most important module in all of Erlang. Contains built-in functions (BIFs) implemented in the runtime. Most are auto-imported.

### Process BIFs

| Function | Description |
|---|---|
| `self/0` | Current process PID |
| `spawn/1,3` | Spawn new process |
| `spawn_link/1,3` | Spawn + link |
| `spawn_monitor/1,3` | Spawn + monitor |
| `spawn_opt/2,4` | Spawn with options (`{priority, high}`, `{min_heap_size, N}`, etc.) |
| `exit/1` | Raise exit signal (terminates calling process) |
| `exit/2` | Send exit signal to process |
| `process_flag/2` | Set flag (`trap_exit`, `priority`, `sensitive`, etc.) |
| `process_info/1,2` | Process introspection |
| `processes/0` | List of all PIDs |
| `is_process_alive/1` | Liveness check |
| `register/2` | Register PID under name |
| `unregister/1` | Remove name registration |
| `registered/0` | List registered names |
| `whereis/1` | PID for name (or `undefined`) |
| `link/1` | Create link |
| `unlink/1` | Remove link |
| `monitor/2,3` | Monitor process/port/resource |
| `demonitor/1,2` | Remove monitor |
| `send/2,3` | Send message (with options) |
| `send_after/3,4` | Send message after timeout |
| `cancel_timer/1,2` | Cancel timer |
| `read_timer/1,2` | Time remaining |
| `start_timer/3,4` | Send `{timeout, Ref, Msg}` after timeout |
| `garbage_collect/0,1` | Force GC |
| `hibernate/3` | Deep sleep until message |
| `yield/0` | Voluntary scheduler yield |
| `group_leader/0,2` | Get/set group leader |

### Term Manipulation BIFs

| Function | Description |
|---|---|
| `term_to_binary/1,2` | Serialize term to binary (External Term Format) |
| `binary_to_term/1,2` | Deserialize from ETF binary |
| `term_to_iovec/1,2` | Serialize to iovec |
| `size/1` | Tuple or binary size |
| `tuple_size/1` | Tuple size |
| `byte_size/1` | Binary size in bytes |
| `bit_size/1` | Binary size in bits |
| `length/1` | List length |
| `map_size/1` | Map entry count |
| `element/2` | Tuple element at index |
| `setelement/3` | Tuple with element replaced |
| `make_tuple/2,3` | Create tuple of size N |
| `list_to_tuple/1` | List to tuple |
| `tuple_to_list/1` | Tuple to list |
| `hd/1` | Head of list |
| `tl/1` | Tail of list |
| `append_element/2` | Add element to end of tuple |
| `split_binary/2` | Split binary at position |
| `list_to_binary/1` | Iolist/charlist to binary |
| `binary_to_list/1,3` | Binary to byte list |
| `atom_to_list/1` | Atom name to char list |
| `list_to_atom/1` | Char list to atom (interned) |
| `list_to_existing_atom/1` | Char list to atom (only if exists) |
| `atom_to_binary/1,2` | Atom to binary |
| `binary_to_atom/1,2` | Binary to atom |
| `integer_to_list/1,2` | Integer to string (optional base) |
| `list_to_integer/1,2` | String to integer |
| `float_to_list/1,2` | Float to string |
| `list_to_float/1` | String to float |
| `number_to_binary/1` | Number to binary |
| `binary_to_integer/1,2` | Binary to integer |
| `binary_to_float/1` | Binary to float |
| `integer_to_binary/1,2` | Integer to binary |
| `float_to_binary/1,2` | Float to binary |
| `atom_to_binary/2` | Atom to binary with encoding |
| `is_atom/1`, `is_binary/1`, `is_bitstring/1`, `is_boolean/1`, `is_float/1`, `is_function/1,2`, `is_integer/1`, `is_list/1`, `is_map/1`, `is_map_key/2`, `is_number/1`, `is_pid/1`, `is_port/1`, `is_record/2,3`, `is_reference/1`, `is_tuple/1` | Type guards |
| `abs/1` | Absolute value |
| `trunc/1` | Truncate float to integer |
| `round/1` | Round float to integer |
| `ceil/1` | Ceiling |
| `floor/1` | Floor |
| `min/2`, `max/2` | Min/max |
| `rem/2`, `div/2` | Integer remainder/quotient |
| `band/2`, `bor/2`, `bxor/2`, `bnot/1`, `bsl/2`, `bsr/2` | Bitwise operations |
| `phash2/1,2` | Portable hash |

### System / Node BIFs

| Function | Description |
|---|---|
| `node/0,1` | Current node name or node of PID/port/ref |
| `nodes/0,1` | Connected nodes |
| `disconnect_node/1` | Disconnect from node |
| `get/0,1` | Process dictionary get |
| `put/2` | Process dictionary put |
| `erase/0,1` | Process dictionary erase |
| `get_keys/0,1` | Process dictionary keys |
| `now/0` | Deprecated: use `os:timestamp/0` |
| `timestamp/0` | `{MegaSecs, Secs, MicroSecs}` |
| `system_time/0,1` | System time in given unit |
| `monotonic_time/0,1` | Monotonic clock |
| `time_offset/0,1` | Offset between monotonic and system time |
| `unique_integer/0,1` | Monotonic unique integer |
| `make_ref/0` | Unique reference |
| `make_ref/1` | Alias ref (OTP 24) |
| `error/1,2,3` | Raise error exception |
| `throw/1` | Raise throw exception |
| `halt/0,1,2` | Halt VM |
| `memory/0,1` | Memory usage info |
| `system_info/1` | Runtime system info |
| `system_flag/2` | Set runtime flag |
| `statistics/1` | Runtime statistics |
| `check_process_code/2,3` | Check if module loaded in process |
| `purge_module/1` | Remove module code |
| `load_module/2` | Load module binary |
| `delete_module/1` | Mark module as deleted |
| `fun_to_list/1` | Fun to string description |
| `fun_info/1,2` | Fun metadata |

### Port BIFs

| Function | Description |
|---|---|
| `open_port/2` | Open a port (OS process, driver, etc.) |
| `port_command/2,3` | Send data to port |
| `port_close/1` | Close port |
| `port_control/3` | Synchronous control call |
| `port_info/1,2` | Port metadata |
| `ports/0` | All open ports |
| `port_call/2,3` | Call port driver function |
| `port_connect/2` | Change port owner |

```erlang
%% Serialization
B = erlang:term_to_binary({hello, [1,2,3], #{a => 1}}),
erlang:binary_to_term(B). % {hello,[1,2,3],#{a=>1}}

%% Process operations
Pid = spawn(fun() -> receive stop -> ok end end),
Pid ! stop,
erlang:is_process_alive(Pid).  % false (eventually)

%% Introspection
erlang:process_info(self(), [memory, message_queue_len, status]).

%% Monotonic timer
T1 = erlang:monotonic_time(millisecond),
timer:sleep(100),
T2 = erlang:monotonic_time(millisecond),
T2 - T1. % ~100

%% Port
Port = erlang:open_port({spawn, "cat"}, [binary]),
port_command(Port, <<"hello">>),
receive {Port, {data, Data}} -> Data end. % <<"hello">>
```

---

## 24. `timer` — Timer Utilities

**Category:** Process / Concurrency
**App:** stdlib

Convenience wrappers around `erlang:send_after/3` and `erlang:start_timer/3`. Uses a gen_server internally.

**Functions:**

| Function | Description |
|---|---|
| `sleep/1` | Block current process for N milliseconds |
| `tc/1,2,3` | Measure execution time → `{MicrosecondTime, Result}` |
| `send_after/2,3` | Send message after N ms |
| `send_interval/2,3` | Send message every N ms |
| `apply_after/3,4` | Call MFA after N ms |
| `apply_interval/3,4` | Call MFA every N ms |
| `cancel/1` | Cancel timer |
| `start/0` | Start timer server (called automatically) |
| `hours/1` | N hours in milliseconds |
| `minutes/1` | N minutes in milliseconds |
| `seconds/1` | N seconds in milliseconds |

```erlang
timer:sleep(1000),  % sleep 1 second

{Time, Result} = timer:tc(lists, sort, [[3,1,2]]),
% Time = microseconds, Result = [1,2,3]

Ref = timer:send_after(5000, self(), timeout),
timer:cancel(Ref),

%% Periodic
timer:apply_interval(timer:seconds(30), io, format, ["tick~n", []]).
```

---

## 25. `calendar` — Date and Time

**Category:** Time
**App:** stdlib

Date and time arithmetic. Erlang's native datetime format is `{{Year,Month,Day},{Hour,Minute,Second}}`.

**Functions:**

| Function | Description |
|---|---|
| `local_time/0` | Local datetime |
| `universal_time/0` | UTC datetime |
| `now_to_local_time/1` | `erlang:now()` timestamp to local datetime |
| `now_to_universal_time/1` | Timestamp to UTC datetime |
| `local_time_to_universal_time/1,2` | Local to UTC |
| `universal_time_to_local_time/1` | UTC to local |
| `datetime_to_gregorian_seconds/1` | Datetime to seconds since year 0 |
| `gregorian_seconds_to_datetime/1` | Inverse |
| `date_to_gregorian_days/1,3` | Date to days since year 0 |
| `gregorian_days_to_date/1` | Inverse |
| `time_to_seconds/1` | Time tuple to seconds since midnight |
| `seconds_to_time/1` | Inverse |
| `day_of_the_week/1,3` | Day number (1=Monday..7=Sunday) |
| `is_leap_year/1` | Leap year test |
| `last_day_of_the_month/2` | Days in month |
| `valid_date/1,3` | Validate date |
| `iso_week_number/0,1` | ISO 8601 week number |
| `rfc3339_to_system_time/1,2` | Parse RFC3339 → system time |
| `system_time_to_rfc3339/1,2` | System time → RFC3339 string |
| `system_time_to_universal_time/2` | System time to datetime |

```erlang
calendar:local_time().  % {{2024,1,15},{10,30,0}}
calendar:universal_time().

%% Difference in seconds
T1 = calendar:datetime_to_gregorian_seconds({{2024,1,1},{0,0,0}}),
T2 = calendar:datetime_to_gregorian_seconds({{2024,1,15},{12,0,0}}),
T2 - T1.  % 1252800 seconds

calendar:day_of_the_week(2024, 1, 15). % 1 = Monday
calendar:is_leap_year(2024).           % true

%% RFC3339
calendar:system_time_to_rfc3339(
  os:system_time(second), [{unit, second}]).
% "2024-01-15T10:30:00+00:00"
```

---

## 26. `ets` — Erlang Term Storage (In-Memory)

**Category:** ETS / Storage
**App:** stdlib (implemented in erts)

In-memory term storage shared across processes within a node. O(1) average lookup for `set`/`bag` types.

**Table types:** `set` (unique keys), `ordered_set` (sorted, unique), `bag` (duplicate values per key), `duplicate_bag` (full duplicates)

**Functions:**

| Function | Description |
|---|---|
| `new/2` | Create table |
| `delete/1,2` | Delete table or specific key |
| `delete_all_objects/1` | Clear table |
| `delete_object/2` | Delete specific tuple |
| `insert/2` | Insert tuple(s) |
| `insert_new/2` | Insert only if key absent |
| `lookup/2` | Get all tuples with key |
| `lookup_element/3,4` | Get specific field of matching tuple |
| `member/2` | Key existence test |
| `update_element/3,4` | Update specific field in-place |
| `update_counter/3,4` | Atomic counter increment |
| `select/2,3` | Match with match spec |
| `select_count/2` | Count matches |
| `select_delete/2` | Delete matches |
| `select_replace/2` | Replace matches |
| `match/2,3` | Pattern matching (returns variable bindings) |
| `match_object/2,3` | Return matching objects |
| `match_delete/2` | Delete matching objects |
| `first/1`, `last/1` | First/last key (ordered_set) |
| `next/2`, `prev/2` | Key navigation (ordered_set) |
| `tab2list/1` | All tuples as list |
| `foldl/3`, `foldr/3` | Fold over all tuples |
| `safe_fixtable/2` | Fix table for safe iteration |
| `info/1,2` | Table metadata |
| `rename/2` | Rename table |
| `give_away/3` | Transfer ownership |
| `setopts/2` | Set table options |
| `slot/2` | Direct slot access |
| `tab2file/2,3` | Serialize to file |
| `file2tab/1,2` | Deserialize from file |
| `from_dets/2` | Load from DETS |
| `to_dets/2` | Dump to DETS |
| `fun2ms/1` | Transform fun to match spec (parse transform) |

**Creation options:** `named_table`, `public`/`protected`/`private`, `{keypos, N}`, `{heir, Pid, Data}`, `compressed`, `{read_concurrency, true}`, `{write_concurrency, true}`

```erlang
%% Create and use a set
T = ets:new(my_table, [set, public, named_table]),
ets:insert(T, {alice, 30}),
ets:insert(T, {bob, 25}),
ets:lookup(T, alice),            % [{alice, 30}]
ets:lookup_element(T, alice, 2), % 30
ets:member(T, carol),            % false

%% Atomic counter
ets:insert(T, {counter, 0}),
ets:update_counter(T, counter, 1),  % 1
ets:update_counter(T, counter, 1),  % 2

%% Match spec (using ms_transform)
-include_lib("stdlib/include/ms_transform.hrl").
MS = ets:fun2ms(fun({Name, Age}) when Age > 20 -> Name end),
ets:select(T, MS). % [alice, bob]

%% Ordered set navigation
OT = ets:new(ot, [ordered_set]),
[ets:insert(OT, {N, N*N}) || N <- lists:seq(1,5)],
ets:first(OT),       % 1
ets:next(OT, 3),     % 4
ets:last(OT).        % 5
```

---

## 27. `dets` — Disk-Based Term Storage

**Category:** ETS / Storage
**App:** stdlib

Disk-persistent term storage with an ETS-like API. Slower than ETS; max 2GB per file. Used for durable small datasets.

**Functions:**

| Function | Description |
|---|---|
| `open_file/1,2` | Open or create DETS file |
| `close/1` | Close and flush |
| `insert/2` | Insert tuple(s) |
| `insert_new/2` | Insert if key absent |
| `delete/2` | Delete by key |
| `delete_object/2` | Delete specific tuple |
| `delete_all_objects/1` | Clear table |
| `lookup/2` | Lookup by key |
| `member/2` | Key existence |
| `update_element/3` | Update field |
| `update_counter/3` | Atomic counter |
| `select/2,3` | Match with match spec |
| `match/2,3` | Pattern matching |
| `match_object/2,3` | Object matching |
| `match_delete/2` | Delete matching |
| `first/1`, `next/2` | Key iteration |
| `foldl/3`, `foldr/3` | Fold |
| `info/1,2` | File metadata |
| `sync/1` | Flush to disk |
| `repair_continuation/2` | Repair select continuation |
| `to_ets/2` | Copy to ETS |
| `from_ets/2` | Load from ETS |
| `table/1,2` | QLC table handle |

```erlang
{ok, Ref} = dets:open_file(my_store, [{file, "/tmp/my.dets"}, {type, set}]),
dets:insert(Ref, {user, alice, 30}),
dets:lookup(Ref, user),  % [{user, alice, 30}]
dets:sync(Ref),
dets:close(Ref).
```

---

## 28. `mnesia` — Distributed Database

**Category:** ETS / Storage / Distribution
**App:** mnesia

Distributed, fault-tolerant, in-memory/disk DBMS with transactions. Records are Erlang tuples. Tables can be replicated across nodes.

**Key functions:**

| Function | Description |
|---|---|
| `start/0`, `stop/0` | Start/stop Mnesia |
| `create_schema/1` | Initialize schema on nodes |
| `delete_schema/1` | Remove schema |
| `create_table/2` | Create table with attributes |
| `delete_table/1` | Delete table |
| `add_table_copy/3` | Add replica on node |
| `transaction/1,3` | Execute fun in transaction |
| `sync_transaction/1,3` | Synchronous transaction |
| `dirty_read/2` | Read without transaction |
| `dirty_write/1` | Write without transaction |
| `dirty_delete/2` | Delete without transaction |
| `read/2,3` | Transactional read |
| `write/1` | Transactional write |
| `delete/3` | Transactional delete |
| `delete_object/1` | Delete specific record |
| `index_read/3` | Read by secondary index |
| `match_object/1,3` | Pattern-match read |
| `select/2,4` | Match spec query |
| `foldl/3,4` | Fold over table |
| `all_keys/1` | All keys in table |
| `first/1`, `last/1`, `next/2`, `prev/2` | Key traversal |
| `table/1,2` | QLC table handle |
| `wait_for_tables/2` | Wait for tables to load |
| `change_table_copy_type/3` | Change `ram_copies`/`disc_copies`/`disc_only_copies` |
| `info/0,1` | System information |
| `system_info/1` | Specific system info |
| `subscribe/1` | Subscribe to table events |
| `activity/2,4` | Run activity in context |

```erlang
%% Define record
-record(person, {name, age, email}).

%% Setup
mnesia:create_schema([node()]),
mnesia:start(),
mnesia:create_table(person, [
  {attributes, record_info(fields, person)},
  {disc_copies, [node()]}
]),

%% Transactional write/read
mnesia:transaction(fun() ->
  mnesia:write(#person{name=alice, age=30, email="alice@example.com"}),
  mnesia:read(person, alice)
end).
% {atomic, [{person, alice, 30, "alice@example.com"}]}
```

---

## 29. `os` — Operating System Interface

**Category:** System
**App:** kernel

Interface to the underlying OS for time, environment variables, system commands, etc.

**Functions:**

| Function | Description |
|---|---|
| `type/0` | `{OsFamily, OsName}` e.g. `{unix, linux}` |
| `version/0` | OS version string/tuple |
| `cmd/1,2` | Execute OS command, return stdout as string |
| `getenv/0,1,2` | Get environment variable(s) |
| `putenv/2` | Set environment variable |
| `unsetenv/1` | Remove environment variable |
| `system_time/0,1` | System time in native units or given unit |
| `timestamp/0` | `{MegaSecs, Secs, MicroSecs}` (wall clock) |
| `perf_counter/0,1` | High-resolution performance counter |
| `get_pid/0` | OS PID of Erlang runtime as string |
| `find_executable/1,2` | Find program in PATH |
| `set_signal/2` | Configure OS signal handling |

```erlang
os:type().              % {unix, linux}
os:cmd("uname -r"),     % "6.1.0-13-amd64\n"
os:getenv("HOME"),      % "/home/user"
os:getenv("MISSING", "default"), % "default"
os:system_time(millisecond), % milliseconds since epoch
os:find_executable("erl").   % "/usr/bin/erl"
```

---

## 30. `application` — OTP Application Management

**Category:** System / OTP
**App:** kernel

Start, stop, and query OTP applications. Also manages application environment (configuration parameters).

**Functions:**

| Function | Description |
|---|---|
| `start/1,2` | Start application |
| `stop/1` | Stop application |
| `ensure_started/1,2` | Start if not already running |
| `ensure_all_started/1,2,3` | Start application and all dependencies |
| `load/1,2` | Load without starting |
| `unload/1` | Unload application |
| `takeover/2` | Failover takeover |
| `which_applications/0,1` | List running applications |
| `loaded_applications/0` | List loaded applications |
| `info/0` | All application info |
| `get_env/1,2,3` | Get config parameter |
| `set_env/3,4` | Set config parameter |
| `unset_env/2,3` | Remove config parameter |
| `get_all_env/0,1` | All config params for application |
| `get_key/1,2` | Get application metadata key |
| `get_all_key/0,1` | All metadata |
| `set_key/3` | Set metadata key |
| `permit/2` | Allow/disallow application on node |
| `spec/1,2` | Application spec |
| `format_error/1` | Error formatting |

```erlang
application:start(crypto),
application:ensure_all_started(ssl),

%% Config (from sys.config or application:set_env)
application:get_env(myapp, timeout),          % {ok, 5000} or undefined
application:get_env(myapp, timeout, 5000),    % 5000 (with default)
application:set_env(myapp, timeout, 10000),

application:which_applications(). % [{stdlib,"ERTS  ..."},...]
```

---

## 31. `sys` — System Message Interface

**Category:** System / OTP
**App:** stdlib

Introspection and control of OTP-compliant processes (gen_server, gen_statem, etc.) via system messages.

**Functions:**

| Function | Description |
|---|---|
| `get_state/1,2` | Get process state |
| `replace_state/2,3` | Replace process state with fun |
| `get_status/1,2` | Get full status (state + callbacks info) |
| `suspend/1,2` | Suspend process (stops processing messages) |
| `resume/1,2` | Resume suspended process |
| `change_code/4,5` | Hot code upgrade trigger |
| `statistics/2,3` | Enable/disable/get statistics |
| `log/2,3` | Enable/disable/get message log |
| `trace/2,3` | Enable/disable tracing |
| `no_debug/1,2` | Remove all debug options |
| `install/2,3` | Install debug function |
| `remove/2,3` | Remove debug function |

```erlang
%% Inspect a running gen_server
sys:get_state(my_server),      % the state term
sys:get_status(my_server),     % full status report

%% Suspend for live debugging
sys:suspend(my_server),
sys:get_state(my_server),      % state frozen
sys:replace_state(my_server, fun(S) -> S#{debug => true} end),
sys:resume(my_server).
```

---

## 32. `code` — Code Server Interface

**Category:** System
**App:** kernel

Interface to the Erlang code server process that manages loaded modules and the code path.

**Functions:**

| Function | Description |
|---|---|
| `add_path/1`, `add_pathz/1` | Add to end of code path |
| `add_patha/1` | Add to front of code path |
| `del_path/1` | Remove from code path |
| `set_path/1` | Set entire path |
| `get_path/0` | Get current path |
| `load_file/1` | Load module from file |
| `load_binary/3` | Load from binary |
| `load_abs/1` | Load by absolute path |
| `ensure_loaded/1` | Load if not already |
| `ensure_modules_loaded/1` | Load list of modules |
| `purge/1` | Remove old code |
| `soft_purge/1` | Remove old code if no processes using it |
| `delete/1` | Mark module for deletion |
| `is_loaded/1` | Check if loaded → `{file, File} \| false` |
| `all_loaded/0` | All loaded modules |
| `all_available/0` | All available modules |
| `which/1` | File path for module |
| `root_dir/0` | OTP root directory |
| `lib_dir/0,1,2` | Library directory |
| `priv_dir/1` | priv/ dir for application |
| `compiler_dir/0` | Compiler directory |
| `objfile_extension/0` | `.beam` |
| `module_status/1` | `not_loaded`, `loaded`, `modified`, `removed` |
| `modified_modules/0` | Modules changed since load |
| `get_mode/0` | `embedded` or `interactive` |
| `is_sticky/1` | Check if sticky (protected from purge) |
| `stick_mod/1`, `unstick_mod/1` | Mark/unmark sticky |

```erlang
code:add_path("/opt/myapp/ebin"),
code:load_file(my_module),
code:is_loaded(lists),    % {file, preloaded}
code:which(lists),        % preloaded
code:priv_dir(ssl).       % "/usr/lib/erlang/lib/ssl-11.x/priv"
```

---

## 33. `init` — System Initialization

**Category:** System
**App:** erts

Manages the startup, restart, and shutdown of the Erlang runtime.

**Functions:**

| Function | Description |
|---|---|
| `get_argument/1` | Get command-line flag value |
| `get_arguments/0` | All command-line flags |
| `get_plain_arguments/0` | Non-flag command-line args |
| `stop/0,1` | Graceful shutdown (exit code) |
| `restart/0,1` | Restart OTP (keep VM) |
| `reboot/0` | Restart entire VM process |
| `boot/1` | Start boot script |
| `get_status/0` | `{InternalStatus, ProvidedStatus}` |
| `notify_when_started/1` | Notify PID when init is done |
| `wait_until_started/0` | Block until init finishes |
| `script_id/0` | Boot script identifier |
| `fetch_loaded/0` | All loaded modules at boot |

```erlang
init:get_argument(name).       % {ok, [["mynode"]]}
init:get_plain_arguments().    % ["arg1", "arg2"]
init:stop().                   % shutdown with exit code 0
init:stop(1).                  % shutdown with exit code 1
```

---

## 34. `crypto` — Cryptographic Functions

**Category:** Crypto / Hashing
**App:** crypto (links to OpenSSL)

Comprehensive cryptographic operations. Requires OpenSSL.

**Functions:**

| Function | Description |
|---|---|
| `hash/2` | One-shot hash (md5, sha, sha256, sha512, blake2b, etc.) |
| `hash_init/1`, `hash_update/2`, `hash_final/1` | Streaming hash |
| `hash_info/1` | Hash algorithm info |
| `hmac/3,4` | HMAC (keyed hash) |
| `hmac_init/2`, `hmac_update/2`, `hmac_final/1` | Streaming HMAC |
| `mac/4` | General MAC (hmac, cmac, poly1305) |
| `mac_init/3`, `mac_update/2`, `mac_final/1` | Streaming MAC |
| `crypto_one_time/4,5` | One-shot symmetric encryption/decryption |
| `crypto_one_time_aead/6,7` | One-shot AEAD (GCM, CCM, Chacha20-Poly1305) |
| `crypto_init/4,5` | Init streaming cipher |
| `crypto_update/2` | Update streaming cipher |
| `crypto_final/1` | Finalize streaming cipher |
| `crypto_dyn_iv_init/3` | Init with dynamic IV |
| `crypto_dyn_iv_update/3` | Update with dynamic IV |
| `sign/4,5` | Digital signature |
| `verify/5,6` | Signature verification |
| `generate_key/2,3` | Generate key pair (rsa, dh, ec, eddsa, etc.) |
| `compute_key/4` | ECDH/DH shared secret |
| `public_encrypt/4` | RSA public encrypt |
| `private_decrypt/4` | RSA private decrypt |
| `private_encrypt/4` | RSA private encrypt |
| `public_decrypt/4` | RSA public decrypt |
| `strong_rand_bytes/1` | Cryptographically secure random bytes |
| `rand_seed/0,1` | Seed Erlang PRNG from crypto |
| `rand_seed_s/0,1` | Seed explicit state |
| `exor/2` | XOR two equal-length binaries |
| `hash_equals/2` | Timing-safe hash comparison |
| `pbkdf2_hmac/5` | Password-Based Key Derivation |
| `supports/1` | Query supported algorithms |
| `info_lib/0` | Linked crypto library info |
| `ec_curves/0` | List supported EC curves |

```erlang
%% Hashing
crypto:hash(sha256, <<"hello">>).
% <<44,242,77,186,...>> (32 bytes)

%% HMAC
crypto:mac(hmac, sha256, <<"key">>, <<"message">>).

%% AES-GCM encryption
Key = crypto:strong_rand_bytes(32),
IV  = crypto:strong_rand_bytes(12),
{Ciphertext, Tag} = crypto:crypto_one_time_aead(
  aes_256_gcm, Key, IV, <<"plaintext">>, <<"aad">>, true),

%% Decrypt
crypto:crypto_one_time_aead(
  aes_256_gcm, Key, IV, Ciphertext, <<"aad">>, Tag, false).
% <<"plaintext">>

%% Random bytes
crypto:strong_rand_bytes(16). % 16 cryptographically secure bytes

%% RSA
{Pub, Priv} = crypto:generate_key(rsa, {2048, 65537}),
Sig = crypto:sign(rsa, sha256, <<"data">>, Priv),
crypto:verify(rsa, sha256, <<"data">>, Sig, Pub). % true
```

---

## 35. `net_kernel` — Distribution Kernel

**Category:** Distribution
**App:** kernel

Manages Erlang distribution: node naming, connections, monitors.

**Functions:**

| Function | Description |
|---|---|
| `start/1,2` | Start distribution (give node a name) |
| `stop/0` | Stop distribution |
| `connect_node/1` | Force connection to node |
| `disconnect_node/1` | Disconnect from node |
| `monitor_nodes/1,2` | Subscribe to `{nodeup,N}` / `{nodedown,N}` |
| `allow/1` | Whitelist nodes |
| `get_net_ticktime/0` | Get tick interval |
| `set_net_ticktime/1,2` | Set tick interval |
| `setopts/2` | Set distribution options |
| `getopts/2` | Get distribution options |

```erlang
net_kernel:start([mynode, shortnames]),
net_kernel:connect_node('other@host'),
net_kernel:monitor_nodes(true),
receive
  {nodeup, Node} -> io:format("~p connected~n", [Node])
end.
```

---

## 36. `net_adm` — Network Administration

**Category:** Distribution
**App:** kernel

Utilities for exploring and connecting to nodes.

**Functions:**

| Function | Description |
|---|---|
| `ping/1` | Test if node is reachable → `pong \| pang` |
| `world/0,1` | Ping all nodes known via EPMD |
| `world_list/1,2` | Ping nodes on list of hosts |
| `dns_hostname/1` | Official DNS hostname |
| `host_file/0` | Read `.hosts.erlang` file |
| `names/0,1` | List registered names via EPMD |

```erlang
net_adm:ping('other@host').  % pong or pang
net_adm:names().             % {ok, [{"mynode", 52731},...]}
net_adm:world().             % pings all in .hosts.erlang
```

---

## 37. `rpc` — Remote Procedure Call

**Category:** Distribution
**App:** kernel

Synchronous and asynchronous calls to functions on remote nodes.

**Functions:**

| Function | Description |
|---|---|
| `call/4,5` | Synchronous RPC (blocks, returns result) |
| `cast/4` | Asynchronous RPC (fire and forget) |
| `async_call/4` | Async RPC → Key, retrieve with `yield` |
| `yield/1` | Retrieve async result |
| `nb_yield/1,2` | Non-blocking yield |
| `multicall/3,4,5` | Call on multiple nodes |
| `abcast/2,3` | Broadcast cast to registered name |
| `sbcast/2,3` | Broadcast, returns successful nodes |
| `eval_everywhere/2,3` | Evaluate expression on all nodes |
| `pinfo/1,2` | Process info on remote node |
| `pmap/3` | Parallel map across nodes |
| `server_call/4` | Call gen_server-like process on remote node |

```erlang
rpc:call('other@host', lists, sort, [[3,1,2]]).  % [1,2,3]
rpc:cast('other@host', io, format, ["hello~n", []]),

%% Async
Key = rpc:async_call('other@host', lists, sort, [[3,1,2]]),
%% ... do other work ...
rpc:yield(Key).  % [1,2,3]

%% Multicall
{Results, BadNodes} = rpc:multicall([n1@h, n2@h], os, type, []).
```

---

## 38. `erpc` — Enhanced RPC

**Category:** Distribution
**App:** kernel (since OTP 23)

Improved RPC with better error handling. Distinguishes between node failures, process exits, and throws.

**Functions:**

`call/2,3,4`, `cast/2,3,4`, `send_request/2,3,4`, `receive_response/1,2`, `wait_response/1,2`, `check_response/2`, `multicall/2,3,4,5`, `multicast/2,3,4`, `reqids_new/0`, `reqids_add/3`, `reqids_size/1`

```erlang
erpc:call(Node, Mod, Fun, Args),

%% Async with request ID
ReqId = erpc:send_request(Node, Mod, Fun, Args),
erpc:receive_response(ReqId). % waits for response
```

---

## 39. `global` — Global Name Registration

**Category:** Distribution
**App:** kernel

Globally unique name registration across a cluster of connected nodes.

**Functions:**

| Function | Description |
|---|---|
| `register_name/2,3` | Register name globally |
| `unregister_name/1` | Remove global name |
| `re_register_name/2,3` | Register (replacing existing) |
| `whereis_name/1` | Lookup global name → `Pid \| undefined` |
| `send/2` | Send message to globally named process |
| `trans/2,3,4` | Distributed mutex transaction |
| `set_lock/1,2,3` | Set a distributed lock |
| `del_lock/1,2` | Release distributed lock |
| `registered_names/0` | List all globally registered names |
| `notify_all_name/3` | Conflict resolution: notify both |
| `random_notify_name/3` | Conflict resolution: random winner |
| `random_exit_name/3` | Conflict resolution: kill one |
| `sync/0` | Sync global state |

```erlang
global:register_name(my_service, self()),
global:whereis_name(my_service),  % self()

%% Distributed lock
global:set_lock({my_lock, self()}),
%% ... critical section ...
global:del_lock({my_lock, self()}).
```

---

## 40. `pg` — Distributed Process Groups

**Category:** Distribution
**App:** kernel (since OTP 23, replaces `pg2`)

Scalable distributed process group membership. Groups are local by default, can be global.

**Functions:**

| Function | Description |
|---|---|
| `start/0,1` | Start pg scope |
| `start_link/0,1` | Start supervised scope |
| `join/2,3` | Join a group |
| `leave/2,3` | Leave a group |
| `get_members/1,2` | All members of group |
| `get_local_members/1,2` | Local node members only |
| `which_groups/0,1` | All non-empty groups |
| `which_local_groups/0,1` | Groups with local members |

```erlang
pg:start_link(),
pg:join(my_group, self()),
pg:get_members(my_group),        % [self()]
pg:get_local_members(my_group),  % [self()]

%% Publish-subscribe pattern
Pids = pg:get_members(topic_updates),
[Pid ! {update, Data} || Pid <- Pids].
```

---

## 41. `gen_server` — Generic Server Behaviour

**Category:** OTP Behaviours
**App:** stdlib

The most-used OTP behaviour. Implements the client-server pattern with synchronous calls and asynchronous casts.

**Callbacks required:** `init/1`, `handle_call/3`, `handle_cast/2`, `handle_info/2`, `terminate/2`, `code_change/3`

**API Functions:**

| Function | Description |
|---|---|
| `start/3,4` | Start unlinked |
| `start_link/3,4` | Start linked (usual in supervisors) |
| `start_monitor/3,4` | Start + monitor |
| `stop/1,2,3` | Stop server |
| `call/2,3` | Synchronous request |
| `cast/2` | Asynchronous message |
| `multi_call/2,3,4` | Synchronous call to multiple servers |
| `abcast/2,3` | Async cast to multiple servers |
| `reply/2` | Send reply from `handle_call` |
| `enter_loop/3,4,5,6` | Enter gen_server loop from existing process |

```erlang
-module(counter).
-behaviour(gen_server).
-export([start_link/0, increment/1, get/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, 0, []).
increment(N) -> gen_server:cast(?MODULE, {increment, N}).
get()        -> gen_server:call(?MODULE, get).

init(Init)          -> {ok, Init}.
handle_call(get, _From, State) -> {reply, State, State}.
handle_cast({increment, N}, State) -> {noreply, State + N}.
handle_info(_Msg, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.
```

---

## 42. `gen_statem` — Generic State Machine

**Category:** OTP Behaviours
**App:** stdlib (since OTP 19, replaces gen_fsm)

Flexible state machine behaviour supporting callback modes `state_functions` and `handle_event_function`. Supports internal events, postpone, state timeouts, and more.

**Callbacks required:** `callback_mode/0`, `init/1`, state-specific handlers or `handle_event/4`, optionally `terminate/3`, `code_change/4`, `format_status/1`

**Key API:**

`start/3,4`, `start_link/3,4`, `start_monitor/3,4`, `stop/1,2,3`, `call/2,3`, `cast/2`, `send_request/2,3`, `receive_response/1,2`

**Callback return actions:** `{next_state, State, Data}`, `{keep_state, Data}`, `{keep_state_and_data}`, `{repeat_state, Data}`, `{stop, Reason}`, `{reply, From, Reply}`, `{next_event, Type, Event}`, `{postpone}`, `{timeout, T, Msg}`, `{state_timeout, T, Msg}`, `{hibernate}`

```erlang
-module(lock).
-behaviour(gen_statem).
-export([start_link/1, push/1]).
-export([callback_mode/0, init/1, locked/3, open/3]).

start_link(Code) -> gen_statem:start_link({local,?MODULE}, ?MODULE, Code, []).
push(Button)     -> gen_statem:cast(?MODULE, {push, Button}).

callback_mode() -> state_functions.

init(Code) -> {ok, locked, #{code => Code, acc => []}}.

locked(cast, {push, Button}, #{code := Code, acc := Acc} = Data) ->
  NewAcc = Acc ++ [Button],
  case lists:suffix(Code, NewAcc) of
    true  -> {next_state, open,   Data#{acc := []}, [{state_timeout, 10000, lock}]};
    false -> {keep_state, Data#{acc := NewAcc}}
  end.

open(state_timeout, lock, Data) -> {next_state, locked, Data};
open(cast, {push, _}, Data)     -> {keep_state, Data}.
```

---

## 43. `supervisor` — Supervisor Behaviour

**Category:** OTP Behaviours
**App:** stdlib

Manages child processes. Restarts them on failure according to configured strategy.

**Strategies:** `one_for_one`, `one_for_all`, `rest_for_one`, `simple_one_for_one`

**Callbacks:** `init/1` → `{ok, {SupFlags, [ChildSpec]}}`

**API Functions:**

| Function | Description |
|---|---|
| `start_link/2,3` | Start supervisor |
| `start_child/2` | Dynamically add child |
| `restart_child/2` | Restart stopped child |
| `terminate_child/2` | Stop child |
| `delete_child/2` | Remove child spec |
| `count_children/1` | Counts by type and state |
| `which_children/1` | List `{Id, Child, Type, Modules}` |
| `get_childspec/2` | Get child specification |
| `check_childspecs/1` | Validate child specs |

```erlang
-module(my_sup).
-behaviour(supervisor).
-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  SupFlags = #{strategy => one_for_one, intensity => 5, period => 10},
  ChildSpec = #{
    id       => my_worker,
    start    => {my_worker, start_link, []},
    restart  => permanent,
    shutdown => 5000,
    type     => worker,
    modules  => [my_worker]
  },
  {ok, {SupFlags, [ChildSpec]}}.
```

---

## 44. `gen_event` — Generic Event Manager

**Category:** OTP Behaviours
**App:** stdlib

Event manager implementing the event handler pattern. Multiple handlers can be added dynamically to one manager.

**Manager API:** `start/0,1`, `start_link/0,1`, `start_monitor/0,1`, `stop/1,2,3`, `add_handler/3`, `add_sup_handler/3`, `delete_handler/3`, `swap_handler/3`, `swap_sup_handler/3`, `notify/2`, `sync_notify/2`, `call/3,4`, `which_handlers/1`

**Handler callbacks:** `init/1`, `handle_event/2`, `handle_call/2`, `handle_info/2`, `terminate/2`, `code_change/3`

```erlang
{ok, Mgr} = gen_event:start_link(),
gen_event:add_handler(Mgr, my_handler, []),
gen_event:notify(Mgr, {some_event, data}),
gen_event:sync_notify(Mgr, important_event).
```

---

## 45. `proc_lib` — Process Library

**Category:** Process / OTP
**App:** stdlib

Utilities for starting OTP-compatible processes and handling startup synchronization. Used internally by all `gen_*` behaviours.

**Functions:**

| Function | Description |
|---|---|
| `start/3,4,5` | Synchronous start (waits for `init_ack`) |
| `start_link/3,4,5` | Start + link |
| `start_monitor/3,4,5` | Start + monitor |
| `spawn/1,3`, `spawn_link/1,3` | Spawn with OTP-compatible setup |
| `init_ack/1,2` | Signal ready to parent |
| `initial_call/1` | Get initial MFA for PID |
| `format/1,2,3` | Format crash report |
| `crash_report/2` | Send crash report |
| `translate_initial_call/1` | Human-readable initial call |
| `stop/1,2,3` | Stop process |

```erlang
%% Start a process and wait for it to be ready
start_link() ->
  proc_lib:start_link(?MODULE, init, [self()]).

init(Parent) ->
  %% ... initialization ...
  proc_lib:init_ack(Parent, {ok, self()}),
  loop().
```

---

## 46. `logger` — Logging Framework

**Category:** System / Logging
**App:** kernel (since OTP 21, replaces `error_logger`)

Structured logging with levels, metadata, filters, formatters, and handlers.

**Log levels (severity order):** `emergency`, `alert`, `critical`, `error`, `warning`, `notice`, `info`, `debug`

**Functions:**

| Function | Description |
|---|---|
| `emergency/1,2,3` ... `debug/1,2,3` | Log at specific level |
| `log/2,3` | Log at dynamic level |
| `add_handler/3` | Add log handler |
| `remove_handler/1` | Remove handler |
| `add_handler_filter/3` | Add filter to handler |
| `remove_handler_filter/2` | Remove filter |
| `add_primary_filter/2` | Add primary filter |
| `remove_primary_filter/1` | Remove primary filter |
| `set_handler_config/2,3` | Configure handler |
| `get_handler_config/0,1` | Get handler config |
| `set_primary_config/1,2` | Set primary config |
| `get_primary_config/0` | Get primary config |
| `get_config/0` | Full config |
| `update_formatter_config/2,3` | Update formatter |
| `allow/2` | Test if message would be logged |
| `compare_levels/2` | Level comparison |
| `format_report/1` | Format report map |
| `timestamp/0` | Current timestamp |

```erlang
logger:info("Server started on port ~p", [Port]),
logger:error(#{what => connection_failed, reason => Reason}),

%% Configure logger
logger:set_primary_config(level, debug),
logger:add_handler(my_file_handler, logger_std_h, #{
  config => #{file => "/var/log/myapp.log"},
  level  => warning
}).
```

---

## 47. `re` — Regular Expressions (PCRE)

**Category:** String / Pattern Matching
**App:** stdlib

Full PCRE (Perl Compatible Regular Expressions) support.

**Functions:**

| Function | Description |
|---|---|
| `compile/1,2` | Compile pattern (reuse for performance) |
| `run/2,3` | Match (returns position + captures) |
| `split/2,3` | Split string on pattern |
| `replace/3,4` | Replace matches |
| `inspect/2` | Get info about compiled pattern |

**Options (partial):** `unicode`, `caseless`, `multiline`, `dotall`, `extended`, `global`, `{capture, all \| none \| first \| all_but_first \| list_of_names, binary \| list \| index}`

```erlang
re:run("hello world", "\\w+").
% {match, [{0,5}]}  -- first match position+length

re:run("hello world", "\\w+", [global]).
% {match, [[{0,5}], [{6,5}]]}

{ok, RE} = re:compile("(\\w+)@(\\w+)"),
re:run("user@host", RE, [{capture, all, list}]).
% {match, ["user@host", "user", "host"]}

re:split("a,b,,c", ",", [{return, list}]).
% ["a","b","","c"]

re:replace("hello world", "world", "there", [{return, list}]).
% "hello there"
```

---

## 48. `base64` — Base64 Encoding

**Category:** String / Encoding
**App:** stdlib

RFC 4648 Base64 encoding/decoding.

**Functions:**

`encode/1,2`, `decode/1,2`, `encode_to_string/1,2`, `decode_to_string/1,2`, `mime_decode/1,2`, `mime_decode_to_string/1,2`

Options: `{mode, standard | urlsafe}`, `{padding, true | false}`

```erlang
base64:encode(<<"hello">>).         % <<"aGVsbG8=">>
base64:decode(<<"aGVsbG8=">>).      % <<"hello">>
base64:encode(<<"hello">>, #{padding => false}). % <<"aGVsbG8">>
base64:encode(<<"\xFF\xFE">>, #{mode => urlsafe}). % URL-safe alphabet
```

---

## 49. `uri_string` — URI Processing

**Category:** String / URI
**App:** stdlib (since OTP 21)

RFC 3986 URI parsing and manipulation.

**Functions:**

`parse/1`, `compose_query/1,2`, `dissect_query/1`, `recompose/1`, `resolve_uri_string/2,3`, `normalize/1,2`, `transcode/2`, `percent_encode/1`, `percent_decode/1`, `quote/1,2`, `unquote/1`

```erlang
uri_string:parse("https://user:pass@host:8080/path?q=1#frag").
% #{scheme => "https", userinfo => "user:pass",
%   host => "host", port => 8080,
%   path => "/path", query => "q=1", fragment => "frag"}

uri_string:compose_query([{"q", "hello world"}, {"n", "1"}]).
% "q=hello+world&n=1"

uri_string:percent_encode(<<"hello world">>). % <<"hello%20world">>
```

---

## 50. `json` — JSON Encoding/Decoding

**Category:** String / Serialization
**App:** stdlib (since OTP 27)

Fast JSON encoder/decoder with push-based and pull-based APIs.

**Functions:**

`encode/1,2`, `decode/1,2`, `decode_start/2`, `decode_continue/2`, `format/1,2`, `format_value/2`

```erlang
json:encode(#{name => <<"alice">>, age => 30}).
% <<"{"name":"alice","age":30}">>

json:decode(<<"{\"x\":1,\"y\":[1,2,3]}">>).
% #{<<"x">> => 1, <<"y">> => [1,2,3]}

%% Streaming decode
json:decode(<<"[1,2,">>, fun(Event, Acc) -> [Event|Acc] end, []).
```

---

## 51. `persistent_term` — Global Persistent Terms

**Category:** System / Storage
**App:** erts (since OTP 21)

Store terms that are set rarely and read very frequently (near-zero read overhead — no copying). Writing triggers a global GC scan.

**Functions:**

`put/2`, `get/1,2`, `erase/1`, `info/0`, `get/0`

```erlang
persistent_term:put(config, #{host => "localhost", port => 5432}),
persistent_term:get(config),          % #{host=>"localhost",...}
persistent_term:get(missing, default). % default
```

---

## 52. `atomics` — Atomic Integer Arrays

**Category:** System / Concurrency
**App:** erts (since OTP 21)

Mutable atomic 64-bit integer arrays. Lock-free, shared between processes.

**Functions:**

`new/2`, `get/2`, `put/3`, `add/3`, `add_get/3`, `sub/3`, `sub_get/3`, `exchange/3`, `compare_exchange/4`, `info/1`

```erlang
Ref = atomics:new(10, [{signed, true}]),
atomics:put(Ref, 1, 0),
atomics:add(Ref, 1, 1),   % increment
atomics:get(Ref, 1).       % 1

%% Compare-and-swap
atomics:compare_exchange(Ref, 1, 1, 100). % ok (1 -> 100)
atomics:compare_exchange(Ref, 1, 1, 200). % 100 (expected 1, got 100)
```

---

## 53. `counters` — Shared Counters

**Category:** System / Concurrency
**App:** erts (since OTP 21)

Simpler array of counters optimized for high-frequency increments. Can be write-concurrent (distributed counters, no global atomicity guarantee) or atomics-backed.

**Functions:**

`new/2`, `get/2`, `add/3`, `sub/3`, `put/3`, `info/1`

```erlang
C = counters:new(8, [write_concurrency]),
counters:add(C, 1, 1),
counters:get(C, 1).  % ~1 (eventually consistent under write_concurrency)
```

---

## 54. `qlc` — Query List Comprehension

**Category:** ETS / Database
**App:** stdlib

SQL-like query interface over ETS, DETS, Mnesia, and custom data sources. Uses a parse transform.

**Functions:**

`q/1,2` (parse transform), `eval/1,2`, `cursor/1,2`, `fold/3,4`, `next_answers/1,2`, `delete_cursor/1`, `info/1,2`, `append/1,2`, `sort/1,2`, `keysort/2,3`, `table/2`

```erlang
-include_lib("stdlib/include/qlc.hrl").

T = ets:new(t, [bag]),
ets:insert(T, [{a,1},{b,2},{a,3}]),

Q = qlc:q([V || {K,V} <- ets:table(T), K =:= a]),
qlc:eval(Q).  % [1,3]
```

---

## 55. `erl_tar` — Tar Archive

**Category:** I/O / Archives
**App:** stdlib

Read and write POSIX tar archives (including compressed with gzip/bzip2/zstd).

**Functions:**

`open/2`, `close/1`, `add/3,4`, `extract/1,2`, `table/1,2`, `format_error/1`, `create/2,3`

```erlang
erl_tar:create("archive.tar.gz",
  [{"file1.txt", <<"contents">>},
   {"dir/file2.txt", <<"/path/to/actual/file">>}],
  [compressed]),

erl_tar:extract("archive.tar.gz", [compressed, {cwd, "/tmp"}]),
erl_tar:table("archive.tar.gz", [compressed]). % list filenames
```

---

## 56. `digraph` / `digraph_utils` — Directed Graphs

**Category:** Collections / Graph
**App:** stdlib

Mutable directed labeled graphs using ETS internally. `digraph_utils` provides algorithms.

**`digraph` functions:** `new/0,1`, `add_vertex/1,2,3`, `add_edge/3,4,5`, `del_vertex/2`, `del_edge/2`, `del_path/3`, `vertex/2`, `edge/2`, `vertices/1`, `edges/1`, `out_edges/2`, `in_edges/2`, `out_neighbours/2`, `in_neighbours/2`, `get_path/3`, `get_cycle/2`, `get_short_path/3`, `get_short_cycle/2`, `source_vertices/1`, `sink_vertices/1`, `info/1`, `delete/1`

**`digraph_utils` functions:** `components/1`, `strong_components/1`, `cyclic_strong_components/1`, `reachable/2`, `reachable_neighbours/2`, `reaching/2`, `reaching_neighbours/2`, `topsort/1`, `is_acyclic/1`, `is_arborescence/1`, `is_tree/1`, `loop_vertices/1`, `subgraph/2,3`, `condensation/1`, `postorder/1`, `preorder/1`

```erlang
G = digraph:new(),
digraph:add_vertex(G, a),
digraph:add_vertex(G, b),
digraph:add_vertex(G, c),
digraph:add_edge(G, a, b),
digraph:add_edge(G, b, c),
digraph_utils:topsort(G),    % [a,b,c]
digraph:get_path(G, a, c),   % [a,b,c]
digraph_utils:is_acyclic(G). % true
```

---

## Summary Table

| Module | Category | Key Capability |
|---|---|---|
| `lists` | Collections | List manipulation, sort, search, fold |
| `maps` | Collections | Hash map, O(1) ops |
| `sets` | Collections | Hash set |
| `ordsets` | Collections | Sorted set (list-based) |
| `gb_sets` | Collections | Balanced tree set, ordered iteration |
| `gb_trees` | Collections | Balanced tree map, ordered |
| `queue` | Collections | O(1) amortized double-ended queue |
| `array` | Collections | Functional sparse array |
| `dict` | Collections | Hash dict (prefer `maps`) |
| `orddict` | Collections | Sorted dict (list-based) |
| `proplists` | Collections | Property list utilities |
| `sofs` | Collections | Set-of-sets, mathematical relations |
| `string` | String | Unicode-correct string ops |
| `binary` | String | Binary data manipulation |
| `unicode` | String | UTF-8/16/32 encode/decode |
| `io_lib` | String/I/O | Formatting, printf-style |
| `io` | I/O | Terminal/device I/O |
| `file` | I/O | File system operations |
| `filename` | I/O | Path manipulation |
| `filelib` | I/O | Wildcard glob, dir utilities |
| `math` | Math | Float math functions |
| `rand` | Math | PRNG, multiple algorithms |
| `erlang` | Core BIFs | Everything: process, term, system |
| `timer` | Concurrency | Sleep, measure, delayed send |
| `calendar` | Time | Date/time arithmetic, RFC3339 |
| `ets` | Storage | In-memory term tables |
| `dets` | Storage | Disk-persistent tables |
| `mnesia` | Storage | Distributed DBMS |
| `os` | System | OS interface, env, time |
| `application` | System | OTP app management |
| `sys` | System | OTP process introspection |
| `code` | System | Code loading, path |
| `init` | System | VM startup/shutdown |
| `crypto` | Crypto | Hashing, encryption, signing |
| `net_kernel` | Distribution | Node naming, connections |
| `net_adm` | Distribution | Node discovery, ping |
| `rpc` | Distribution | Remote calls |
| `erpc` | Distribution | Enhanced remote calls |
| `global` | Distribution | Global name registration |
| `pg` | Distribution | Process groups |
| `gen_server` | OTP | Client-server processes |
| `gen_statem` | OTP | State machine processes |
| `supervisor` | OTP | Process supervision |
| `gen_event` | OTP | Event handler pattern |
| `proc_lib` | OTP | Process lifecycle utilities |
| `logger` | Logging | Structured logging |
| `re` | String | PCRE regex |
| `base64` | Encoding | Base64 encode/decode |
| `uri_string` | Encoding | RFC3986 URI parsing |
| `json` | Encoding | JSON encode/decode (OTP 27+) |
| `persistent_term` | Storage | Near-zero-cost global read |
| `atomics` | Concurrency | Atomic integer arrays |
| `counters` | Concurrency | Shared counters |
| `qlc` | Query | SQL-like queries over tables |
| `erl_tar` | Archives | Tar read/write |
| `digraph`/`digraph_utils` | Graph | Directed graphs, algorithms |