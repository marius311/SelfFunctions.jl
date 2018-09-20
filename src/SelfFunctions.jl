module SelfFunctions

using MacroTools: splitdef, combinedef, postwalk, isexpr, @capture, isdef, splitarg

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
    fields = @eval __module__ fieldnames($typ)
    sfuncdef = splitdef(funcdef)
    
    insert!(sfuncdef[:args],1,:(self::$typ))
    
    function visit(ex; inside_func_args=false, locals=[])
        rvisit(ex; kwargs...) = visit(ex; locals=locals, kwargs...)
        if ex isa Symbol
            # replace `x` with `self.x` where needed 
            if ex in fields && !(ex in locals) && !inside_func_args
                esc(:(self.$ex))
            else
                startswith(string(ex),"@") ? ex : esc(ex)
            end
        elseif ex isa Expr
            if isexpr(ex,:kw)
                # in f(x=x) only the second `x` should (possibly) become self.x
                Expr(:kw, esc(ex.args[1]), rvisit(ex.args[2]))
            elseif @capture(ex, ((f_(args__; kwargs__)) | (f_(args__; kwargs__)::T_) | (f_(args__)) | (f_(args__)::T_)))
                # pass `self` argument implicitly when calling other "self" functions
                ex = :(selfcall($(rvisit(f)), $(esc(:self)), $(rvisit.(args == nothing ? [] : args)...);  $(rvisit.(kwargs == nothing ? [] : kwargs)...)))
                T == nothing ? ex : :($ex::$(esc(T)))
            elseif isdef(ex)
                # inner function definition, need to be careful about scope here
                sdef = splitdef(ex)
                func_args = append!((map(first,map(splitarg,sdef[k])) for k in (:args, :kwargs))...)
                for k in (:args, :kwargs)
                    map!(x->rvisit(x; inside_func_args=true), sdef[k], sdef[k])
                end
                sdef[:body] = visit(sdef[:body], locals=[locals; func_args])
                for k in (:params, :name, :rtype, :whereparams)
                    if k in keys(sdef); sdef[k] = esc.(sdef[k]); end
                end
                combinedef(sdef)
            else
                # recurse
                Expr(ex.head, map(rvisit, ex.args)...)
            end
        else
            ex
        end
    end

    sfuncdef[:body] = visit(sfuncdef[:body])
    fname = sfuncdef[:name]
    sfuncdef[:name] = esc(Symbol("self_", sfuncdef[:name]))
    for k in (:args, :kwargs, :params, :rtype, :whereparams)
        if k in keys(sfuncdef); sfuncdef[k] = esc.(sfuncdef[k]); end
    end

    quote
        $(combinedef(sfuncdef))
        Base.@__doc__ const $(esc(fname)) = SelfFunction($(QuoteNode(fname)), $(esc(typ)), $(sfuncdef[:name]))
    end
    
end

end
