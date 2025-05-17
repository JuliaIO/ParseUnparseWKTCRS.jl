# ParseUnparseWKTCRS

[![Build Status](https://github.com/JuliaIO/ParseUnparseWKTCRS.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/JuliaIO/ParseUnparseWKTCRS.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/JuliaIO/ParseUnparseWKTCRS.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/JuliaIO/ParseUnparseWKTCRS.jl)
[![Package version](https://juliahub.com/docs/General/ParseUnparseWKTCRS/stable/version.svg)](https://juliahub.com/ui/Packages/General/ParseUnparseWKTCRS)
[![Package dependencies](https://juliahub.com/docs/General/ParseUnparseWKTCRS/stable/deps.svg)](https://juliahub.com/ui/Packages/General/ParseUnparseWKTCRS?t=2)
[![PkgEval](https://JuliaCI.github.io/NanosoldierReports/pkgeval_badges/P/ParseUnparseWKTCRS.svg)](https://JuliaCI.github.io/NanosoldierReports/pkgeval_badges/P/ParseUnparseWKTCRS.html)
[![Aqua](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

Parse/unparse [WKT-CRS](https://en.wikipedia.org/wiki/Well-known_text_representation_of_coordinate_reference_systems), with perfect roundtripping. Type-stable.

## REPL example

```julia-repl
julia> using
           ParseUnparse.AbstractParserIdents,
           ParseUnparse.SymbolGraphs,
           ParseUnparseWKTCRS.GrammarSymbolKinds,
           ParseUnparseWKTCRS.ParserIdents
Precompiling ParseUnparseWKTCRS finished.
  1 dependency successfully precompiled in 1 seconds. 2 already precompiled.

julia> parser = get_parser(ParserIdent());

julia> (tree, error_status) = parser("a[3, 7]");

julia> isempty(error_status)  # the parser accepts simple WKT-CRS
true

julia> (tree, error_status) = parser("a[3, 7]]");

julia> isempty(error_status)  # the parser rejects malformed WKT-CRS
false

julia> using AbstractTrees: print_tree  # let's see a nontrivial parse tree!

julia> function print_tree_map(io::IO, tree)
           g = tree.graph
           kind = root_symbol_kind(g)
           if root_is_terminal(g)
               show(io, (kind, root_token(g)))  # a terminal symbol may have extra info (although it's just `nothing` in this example)
           else
               show(io, kind)  # a nonterminal symbol just has its symbol kind
           end
       end
print_tree_map (generic function with 1 method)

julia> str = """
       a[
           "b",
           3,
           c[7]
       ]
       """
"a[  \n    \"b\",\n    3,\n    c[7]\n]\n"

julia> print_tree(print_tree_map, stdout, graph_as_tree(parser(str)[1]); maxdepth = 100)
value
└─ keyword_with_optional_delimited_list
   ├─ (keyword, (1:1, "a"))
   └─ optional_delimited_list
      ├─ (list_delimiter_left, (2:9, "[  \n    "))
      ├─ list
      │  ├─ value
      │  │  └─ (string, (10:12, "\"b\""))
      │  └─ optional_incomplete_list
      │     ├─ (list_element_separator, (13:18, ",\n    "))
      │     ├─ value
      │     │  └─ (number, (19:19, "3"))
      │     └─ optional_incomplete_list
      │        ├─ (list_element_separator, (20:25, ",\n    "))
      │        ├─ value
      │        │  └─ keyword_with_optional_delimited_list
      │        │     ├─ (keyword, (26:26, "c"))
      │        │     └─ optional_delimited_list
      │        │        ├─ (list_delimiter_left, (27:27, "["))
      │        │        ├─ list
      │        │        │  ├─ value
      │        │        │  │  └─ (number, (28:28, "7"))
      │        │        │  └─ optional_incomplete_list
      │        │        └─ (list_delimiter_right, (29:30, "]\n"))
      │        └─ optional_incomplete_list
      └─ (list_delimiter_right, (31:32, "]\n"))
```
