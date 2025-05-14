using ParseUnparseWKTCRS
using Test
using Aqua

@testset "ParseUnparseWKTCRS.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(ParseUnparseWKTCRS)
    end
    # Write your tests here.
end
