module TestTokenUtil
    using ParseUnparseWKTCRS.TokenUtil, Test
    @testset "`TokenUtil`" begin
        @test "z" == (@inferred sprint(decode_string, """ "z" """))::AbstractString
        @test '"'^2 == (@inferred sprint(encode_string, ""))::AbstractString
        @test '"'^4 == (@inferred sprint(encode_string, "\""))::AbstractString
        for s ∈ ("", " ", "z", " z", "z ", " z ", "\"", "\"\"", "\"z\"")
            @test s == sprint(decode_string, sprint(encode_string, s))
        end
    end
end
