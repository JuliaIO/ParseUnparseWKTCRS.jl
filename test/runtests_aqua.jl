module TestAqua
    using ParseUnparseWKTCRS
    using Test
    using Aqua: Aqua
    @testset "Aqua.jl" begin
        Aqua.test_all(ParseUnparseWKTCRS)
    end
end
