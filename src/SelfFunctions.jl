module SelfFunctions


using MacroTools: splitdef, combinedef, postwalk, isexpr, @capture, isdef, splitarg, @q, block
using Setfield

export @self

struct SelfFunction{F<:Function}
    name::Symbol
    typ::Type
    f::F
end
Base.show(io::IO, sf::SelfFunction) = print(io, "$(sf.name) (self function of type $(sf.typ))")
@inline (sf::SelfFunction)(args...; kwargs...) = sf.f(args...; kwargs...)
@inline selfcall(f::SelfFunction, t, args...; kwargs...) = f.f(t, args...; kwargs...)
@inline selfcall(f, t, args...; kwargs...) = f(args...; kwargs...)


macro self(typ, funcdef)
    @capture(typ, basetyp_{_} | basetyp_)
    fields = @eval __module__ fieldnames($basetyp)
    sfuncdef = splitdef(funcdef)
    mutating = occursin("!", string(sfuncdef[:name]))
    insert!(sfuncdef[:args],1,:(self::$typ))
    
    function visit(ex; inside_func_args=false, locals=[])
        rvisit(ex; kwargs...) = visit(ex; locals=locals, kwargs...)
        if ex isa Symbol
            # replace `x` with `self.x` where needed 
            if ex in fields && !(ex in locals) && !inside_func_args
                :(self.$ex)
            else
                ex
                # startswith(string(ex),"@") ? ex : esc(ex)
            end
        elseif mutating && isexpr(ex,:(=)) && (ex.args[1] isa Symbol) && (ex.args[1] in fields) && !(ex.args[1] in locals) && !inside_func_args
            # we're in a mutating function and trying to set one of self's fields, so use Setfield
            # the let-block avoids a possible Core.box if we're assigning a closure that uses `self`
            # :(SelfFunctions.@set! $(rvisit(ex.args[1])) = let self=self; $(map(rvisit,ex.args[2:end])...) end)
            :(SelfFunctions.@set! $(rvisit(ex.args[1])) = $(rvisit(ex.args[2])))
        elseif ex isa Expr
            if isexpr(ex,:kw)
                # in f(x=x) only the second `x` should (possibly) become self.x
                Expr(:kw, ex.args[1], rvisit(ex.args[2]))
            elseif @capture(ex, (f_(args__; kwargs__) | f_(args__; kwargs__)::T_ | f_(args__) | f_(args__)::T_))
                # function call
                if isa(f,Symbol) && (isdefined(__module__,f) || f==:ccall)
                    if Base.eval(__module__,f) isa SelfFunction
                        # is definitely a self function
                        ex = :($(Base.eval(__module__,f))(self, $(map(rvisit,args)...)))
                    else
                        # is definitely not a "self" function
                        ex = :($(rvisit(f))($(map(rvisit,args)...)))
                    end
                else
                    # we don't know since it isnt defined yet (use the selfcall machinery)
                    ex = :($selfcall($(rvisit(f)), self, $(map(rvisit,args)...)))
                end
                if kwargs != nothing; insert!(ex.args,2,Expr(:parameters,map(rvisit,kwargs)...)); end
                T == nothing ? ex : :($ex::$T)
            elseif isdef(ex)
                # inner function definition (note: need to be careful about scope here)
                sdef = splitdef(ex)
                func_args = append!((map(first,map(splitarg,sdef[k])) for k in (:args, :kwargs))...)
                for k in (:args, :kwargs)
                    map!(x->rvisit(x; inside_func_args=true), sdef[k], sdef[k])
                end
                sdef[:body] = block(visit(sdef[:body], locals=[locals; func_args]))
                combinedef(sdef)
            else
                # recurse
                Expr(ex.head, map(rvisit, ex.args)...)
            end
        else
            ex
        end
    end
    
    if mutating
        push!(sfuncdef[:body].args, :(return self))
    end
    sfuncdef[:body] = block(esc(visit(sfuncdef[:body])))
    fname = sfuncdef[:name]
    sfuncdef[:name] = esc(Symbol("self_", sfuncdef[:name]))
    for k in (:args, :kwargs, :params, :rtype, :whereparams)
        if k in keys(sfuncdef); sfuncdef[k] = esc.(sfuncdef[k]); end
    end

    @q begin
        $(__source__)
        $(combinedef(sfuncdef))
        Base.@__doc__ const $(esc(fname)) = SelfFunction($(QuoteNode(fname)), $(esc(basetyp)), $(sfuncdef[:name]))
    end
    
end

end
