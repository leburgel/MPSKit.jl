# should this just be a alias for AbstractVector{C} where C <: Cache ?
# const MultipleEnvironments = AbstractVector{C} where C <: Cache

struct MultipleEnvironments{C}
    envs::Vector{C}
end

Base.size(x::MultipleEnvironments) = size(x.envs)
Base.getindex(x::MultipleEnvironments,i) = x.envs[i]
Base.length(x::MultipleEnvironments) = prod(size(x))

Base.iterate(x::MultipleEnvironments) = iterate(x.envs)
Base.iterate(x::MultipleEnvironments,i) = iterate(x.envs,i)

# we need constructor, agnostic of particular MPS
environments(st,ham::SumOfOperators) = MultipleEnvironments( map(op->environments(st,op),ham.ops) )

# we need to define how to recalculate
"""
    Recalculate in-place each sub-env in MultipleEnvironments
"""
function recalculate!(env::MultipleEnvironments,args...)
    for subenv in env.envs
        recalculate!(subenv,args...)
    end
    env
end