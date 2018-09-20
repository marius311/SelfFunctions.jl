# SelfFunctions.jl

SelfFunctions.jl provides a macro, `@self`, which gives functions an implicit argument of a specified type, and lets you implicitly access the fields of that type from inside the function. It is quite similar to how C++ class member functions work. 

It is most useful when you have a struct storing "parameters" of a model, and then are writing many mathematical functions that use those parameters. SelfFunctions.jl lets you write those functions succinctly and without obscuring the mathematics. 

To install, 

```
add https://github.com/marius311/SelfFunctions.jl.git
```

An example, 

```julia

using SelfFunctions

# struct which stores parameters of a model
struct Rosenbrock{T}
    a::T
    b::T
end

# define some mathematical function
@self Rosenbrock rosen(x,y) = (a-x)^2 + b*(y-x^2)^2

# create model and call function
r = Rosenbrock(1, 2)
rosen(r, 3, 4) # returns 54
```

The magic is that the macro rewrites,

```julia
@self Rosenbrock rosen(x,y) = (a-x)^2 + b*(y-x^2)^2
```
to 
```julia
rosen(self::Rosenbrock,x,y) = (self.a-x)^2 + self.b*(y-x^2)^2
```

Note that because the fields of `Rosenbrock` are known, the macro knows to only modify `a` and `b`. It is moderately smart about which variables to modify; many, but not all, cases should work. Note also that inner calls to "self" functions do not explicitly need to pass the first argument, this is inserted automatically:

```julia
@self Rosenbrock shifted_rosen(x,y) = rosen(x+1, y+1)
shifted_rosen(r, 2, 3) # gives 54 as before
```

Thanks to @fcard for the cool trick which allows this to work with no performance overhead (see also https://github.com/fcard/SelfFunctions.jl which does basically the same thing but with different syntax, although as of this writing is not compatible with Julia 1.0).
