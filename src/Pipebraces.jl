module Pipebraces

using Base: isexpr


function getargs(ex::Expr, idx)
    exarg = getfield(ex, :args) # args array
    length(idx) == 1 ? getindex(exarg, idx[1]) :
        getargs(exarg[idx[1]], idx[2:end])
end

function setargs!(ex::Expr, nex, idx)
    length(idx) == 1 ? setindex!(ex.args, nex, idx[1]) : 
        setindex!(getargs(ex, idx[1:end-1]).args, nex, idx[end])
end

"""
    scanargs(f, ex::Expr; isfirst=true)

find the first/all (isfirst=true/false) expr. arguments of an Expression `ex` 
for which `f` is true.
"""
function scanargs(f, ex::Expr; isfirst=true)
    # ex
    f(ex) && return [[0]]
    # ex.args
    checklst = [(ex, [1])]
    res = Vector{Int}[]
    while !isempty(checklst)
        for (e, i) in checklst, lambda_l in eachindex(e.args)
            if e.args[lambda_l] isa Expr && f(e.args[lambda_l])
                isfirst && return [[i;lambda_l]]
                push!(res, [i;lambda_l])
            end
        end
        newlst = Tuple{Expr, Vector{Int}}[]
        for (e, i) in checklst, lambda_l in eachindex(e.args)
            e.args[lambda_l] isa Expr && push!(newlst, (e.args[lambda_l], [i;lambda_l]))
        end
        checklst = newlst
    end
    return res
end

checkbraces(ex::Expr) = length(ex.args) > 2 && isexpr(ex.args[3], [:braces, :bracescat])

function pipebraces(ex::Expr)
    b = scanargs(checkbraces, ex)
    isempty(b) && return ex
    iszero(b)  && return transcallbraces(ex)
    setargs!(ex, transcallbraces(getargs(ex, b[1][2:end])), b[1][2:end])
    return ex
end

function have_nobraces(ex::Expr)
    all(isexpr(a, :braces) ? false : 
        isa(a, Expr) ? have_nobraces(a) : true for a=ex.args)
end

function transcallbraces(ex::Expr)
    if ex.head == :call && ex.args[1] == Symbol("|>")
        if isexpr(ex.args[2], :call) && ex.args[2].args[1] == Symbol("|>")
            return ifelse(have_nobraces(ex), ex, 
                :(println("Please combine multiple `|>` into one when using braces"))) 
        else
            return mapfoldl(mapfunc, pipex, ex.args[3].args, init=Expr(:block, ex.args[2]))
        end
    else
        return ex
    end
end

hasarg_(ex::Expr) = any(a isa Symbol && match(r"^_(\d*)$", string(a)) !== nothing for a in ex.args)

function lambda_(ex::Expr)
    v = String[]
    @inbounds for i in eachindex(ex.args)
        if ex.args[i] isa Symbol
            m = match(r"^_(\d*)$", string(ex.args[i]))
            m === nothing && continue
            push!(v, m[1])
            if m[1] == ""
                ex.args[i] = Symbol("_00")
            end
        elseif ex.args[i] isa Expr
                vv, = lambda_(ex.args[i])
                isempty(vv) && continue
                append!(v, vv)
        end
    end
    return v, ex
end

function fandr(ex)
    check00(x) = issubset(["", "00"], x) && throw(error("Cannot use `_` and `_00` simultaneously"))
    foundnothing(e) = (length(e.args) == 1 || insert!(e.args, 2, Symbol("__")); (e, [2]))
    ex_idx = scanargs(hasarg_, ex, isfirst=false)
    if isempty(ex_idx)
        length(ex.args) == 1 && return ex, [2]
        return Expr(ex.head, ex.args[1], Symbol("__"), ex.args[2:end]...), [2]
    end
    if iszero(ex_idx)
        ua, ue = lambda_(copy(ex))
        check00(ua)
        if length(ua) > 1
            uargs = map(x->Symbol("_", x), replace(unique(ua), ""=>"00"))
            return Expr(:call, :(($(uargs...),) -> $ue)), [2]
        else
            return ex, [findfirst(==(Symbol("_", ua[1])), ex.args)]
        end 
    end
    lambda_ex = copy(ex)
    foundi = findfirst(==(Symbol("__")), ex.args)
    if length(ex_idx) == 1 
        ua, ue = lambda_(copy(getargs(ex, ex_idx[1][2:end])))
        check00(ua)
        if length(ua) > 1
            uargs = map(x->Symbol("_", x), replace(unique(ua), ""=>"00"))
            setargs!(lambda_ex, :(($(uargs...),) -> $(getargs(lambda_ex, ex_idx[1][2:end]))), ex_idx[1][2:end])
            isnothing(foundi) && return foundnothing(lambda_ex)
            return lambda_ex, [foundi]
        else
            return ex, [ex_idx[1][2:end]; findfirst(==(Symbol("_")), getargs(ex, ex_idx[1][2:end]).args)]
        end
    end
    l = minimum(length, ex_idx)
    lambda_l = 2
    @inbounds while lambda_l <= l
        @views any(v[lambda_l] != ex_idx[1][lambda_l] for v = ex_idx[2:end]) && break
        lambda_l +=1
    end
    # ? [1,2,..], [1,3,...] more than 1 anonymous function
    # lambda_l == 1 && throw(error("Please note that shortcut could only apply to one anonymous function."))
    ua = String[]
    foreach(ex_idx) do v
        uav, uev = lambda_(copy(getargs(ex, v[2:end])))
        append!(ua, uav)
        setargs!(lambda_ex, uev, v[2:end])
    end
    check00(ua)
    uargs = map(x->Symbol("_", x), replace(unique(ua), ""=>"00"))
    if lambda_l == 2 
        lambda_ex = Expr(:call, :(($(uargs...),) -> $lambda_ex))
    else
        lambda_idx = ex_idx[1][2:lambda_l-1]
        setargs!(lambda_ex, :(($(uargs...),) -> $(getargs(lambda_ex, lambda_idx))), lambda_idx)
    end
    foundi = findfirst(==(Symbol("__")), ex.args)
    isnothing(foundi) && return foundnothing(lambda_ex)
    return lambda_ex, [foundi]
end

mapfunc(e::Symbol) = Expr(:call, e), [2]
function mapfunc(ex::Expr)
    head = ex.head
    args = ex.args

    head == :call && return fandr(ex)
    head == :row && return map(mapfunc, args)
    if head == :macrocall && args[2] isa LineNumberNode
        isa(args[3], Symbol) && 
            return Expr(:macrocall, setargs!(copy(ex), Expr(:call, args[3]), 3)...), [3, 2]
        if isexpr(args[3], :call)
            fex, idx = fandr(args[3])
            return Expr(:macrocall, setargs!(copy(ex), fex, 3)...), [3;idx]
        end
    elseif head == :(.)
        args[2] isa QuoteNode ? (Expr(:call, :broadcast, args[1]), [3]) :
            fandr(Expr(:call, :broadcast, args[1], args[2].args...))
    else
        try fandr(ex)
        catch 
            error("Sorry, but There is sth. in the braces that I can't get through")
        end
    end
end

function _pipex!(i2, e2copy, res)
    if length(i2) == 1
        i2[1] > length(e2copy.args) ? push!(e2copy.args, res.args[end]) : e2copy.args[i2[1]] = res.args[end]
        res.args[end] = e2copy
    else
        e = getargs(e2copy, i2[1:end-1])
        i2[end] > length(e.args) ? push!(e.args, res.args[end]) : setargs!(e2copy, res.args[end], i2)
        res.args[end] = e2copy
    end
    return nothing
end

function pipex(e1::Expr, (e2,i2)::Tuple{Expr, Vector{Int}})
    res = copy(e1)
    e2copy = copy(e2)
    if e2.args[1] == :println
        var = gensym("_pipe")
        res.args[end] = :(local $var = $(e1.args[end]))
        push!(res.args, :($var))
        _pipex!(i2, e2copy, res)
        insert!(e2copy.args, 2, "... ")
        push!(res.args, :($var))
    else
        e2copy = copy(e2)
        if e2.head == :macrocall
            var = gensym("_pipe")
            res.args[end] = :(local $var = $(e1.args[end]))
            push!(res.args, :($var))
        end
        _pipex!(i2, e2copy, res)
    end
    e2.head != :macrocall && return res
    v = gensym("_pipe")
    res.args[end] = :(local $v = $(res.args[end]))
    push!(res.args, :($v))
    return res
end

function pipex(e1, e2vec::Vector{Tuple{Expr, Vector{Int}}})
    e2copy = copy(e2vec)
    fgex = Expr(:tuple)
    foreach(e2copy) do (e, i)
        push!(fgex.args, pipex(e1, (e, i)).args...)
    end
    return Expr(:block, fgex)
end

macro pb(ex)
    ex isa Expr ? esc(pipebraces(ex)) : esc(ex)
end

function __init__()
    print("Piping directly (y) or using the macro `@pb` (otherwise) ? ")
    printstyled("[y] : ", bold=true)
    cond = Condition()
    Timer(x->notify(cond), 4)
    userinput = @async begin
        res = readline()
        notify(cond)
        res in ("", "y", "Y") ? true : false
    end
    wait(cond)
    userinput.state == :done ? 
        if !fetch(userinput)
            @info "If this is an existing REPL, you need use the macro to pipe."
            return nothing
        end :
        println("..no input")
    if isdefined(Base, :active_repl_backend)
        Base.active_repl_backend.ast_transforms[1] isa typeof(pipebraces) ||
            pushfirst!(Base.active_repl_backend.ast_transforms, pipebraces)
        @info """Piping directly with `|> {}` is ready in the REPL. 
                    To use the macro `@pb` instead, you may run 
                    `Pipebraces.usemacro!(@__MODULE__)`"""
    end
    return nothing
end

function usemacro!(destmodule)
    # byrepltool = try
    #     REPL.repl_ast_transforms[1] isa typeof(pipebraces) ? true : false
    # catch
    #     false
    # end
    # byrepltool && popfirst!(REPL.repl_ast_transforms)
    if isdefined(Base, :active_repl_backend) && 
        Base.active_repl_backend.ast_transforms[1] isa typeof(pipebraces) 
        popfirst!(Base.active_repl_backend.ast_transforms)
    end
    Core.eval(destmodule, :(using Pipebraces: @pb))
    @info "The macro `@pb` for piping is ready now."
    return nothing
end


end