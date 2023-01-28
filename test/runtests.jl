using Pipebraces: @pb
using Test

@testset "Pipebraces.jl" begin
    @test @pb(["hello", "world"] |> {
       first last
       }) == ("hello", "world")
    ex = @macroexpand @pb(["hello", "world"] |> {
        join(_, ", ") * '!', println(_[2]),
        uppercasefirst
        })
    @test ex.args[2].args[2] == "... "
    @test ex.args[2].args[3].head == :ref
    @test ex.args[2].args[3].args[1] == ex.args[1].args[1]
    @test @pb([1, 2] |> {@. 2*_; sum}) == 6
end
