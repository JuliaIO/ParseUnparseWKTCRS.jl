module TestParserIdents
    using
        ParseUnparse.SymbolGraphs,
        ParseUnparse.AbstractParserIdents,
        ParseUnparseWKTCRS.GrammarSymbolKinds,
        ParseUnparseWKTCRS.ParserIdents,
        Test
    const parsers = (get_parser(ParserIdent()), get_parser(ParserIdent{Nothing}()), get_parser(ParserIdent{Union{}}()))
    struct Acc
        s::String
        # tokenization::Vector{XXX}
        # leaves::Vector{GrammarSymbolKind}
        # preorder_dfs::Vector{GrammarSymbolKind}
        # postorder_dfs::Vector{GrammarSymbolKind}
    end
    struct Rej
        s::String
        # err::Tuple{SymbolGraphNodeIdentity, Vector{Tuple{Tuple{UnitRange{Int64}, String}, GrammarSymbolKind}}}
    end
    const data_accept = Acc[
        Acc(" a[\"\", b]"),
        Acc("a[\"z\", 11]"),
        Acc("a[\"z\", -1]"),
        Acc("a[\"z\", 1.]"),
        Acc("a[\"z\", .1]"),
        Acc("a[\"z\", .11]"),
        Acc("a[\"z\", .1E1]"),
        Acc("a[\"z\", .1E11]"),
        Acc("""
        a["z", "double quote: \"""]
        """),
    ]
    const data_reject = Rej[
        Rej(""),
        Rej("\""),
        Rej("-"),
        Rej("0z"),
        Rej("1z"),
        Rej("-z"),
        Rej("."),
        Rej(".z"),
        Rej("1E"),
        Rej("1Ez"),
        Rej("1E+"),
        Rej("1E+z"),
        Rej(","),
        Rej("["),
        Rej("]"),
        Rej("a[\"\""),
        Rej("a[.1"),
        Rej("a[.1E1"),
        Rej("a[1"),
    ]
    @testset "parser idents" begin
        @testset "accept" begin
            for data ∈ data_accept
                for parser ∈ parsers
                    @test isempty((@inferred parser(data.s))[2])
                end
            end
        end
        @testset "reject" begin
            for data ∈ data_reject
                for parser ∈ parsers
                    @test !isempty((@inferred parser(data.s))[2])
                end
            end
        end
    end
end
