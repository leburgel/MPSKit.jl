#=
    An mpo hamiltonian h is
        - a sparse collection of dense mpo's
        - often contains the identity on te diagonal (maybe up to a constant)

    when we query h[i,j,k], the following logic is followed
        j == k?
            h.scalars[i,j] assigned?
                identity * h.scalars[i,j]
            elseif h.Os[i,j,k] assigned?
                h.Os[i,j,k]
            else
                zeros
        else
            h.Os[i,j,k] assigned?
                h.Os[i,j,k]
            else
                zeros


    we make the distinction between non-idenity fields and identity field for two reasons
        - speed (can optimize contractions)
        - requires vastly different approaches when doing thermodynamic limit (rescaling)

    both h.scalars and h.Os are periodic, allowing us to represent both place dependent and periodic hamiltonians

    h.domspaces and h.pspaces are needed when h.Os[i,j,k] is unassigned, to know what kind of zero-mpo we need to return

    the convention is that we start left with [1,0,0,0,...,0]; right [0,0,....,0,1]

    I didn't want to use union{T,E} because identity is impossible away from diagonal
=#
"
    MpoHamiltonian

    represents a general periodic quantum hamiltonian
"
struct MpoHamiltonian{S,T<:MpoType,E<:Number}<:Hamiltonian
    scalars::Periodic{Array{Union{Missing,E},1},1}
    Os::Periodic{Array{Union{Missing,T},2},1}

    domspaces::Periodic{Array{S,1},1}
    pspaces::Periodic{S,1}
end

function Base.getproperty(h::MpoHamiltonian,f::Symbol)
    if f==:odim
        return length(h.domspaces[1])::Int
    elseif f==:period
        return size(h.pspaces,1)
    elseif f==:imspaces
        return circshift(Periodic([adjoint.(d) for d in h.domspaces.data]),-1)
    else
        return getfield(h,f)
    end
end

#dense representation of mpohamiltonian -> the actual mpohamiltonian
function MpoHamiltonian(ox::Array{T,3}) where T<:Union{Missing,M} where M<:MpoType
    x = fillmissing(ox);

    len = size(x,1);E = eltype(M);
    @assert size(x,2)==size(x,3)

    #Os and scalars
    tOs = Matrix{Union{Missing,T}}[Matrix{Union{Missing,M}}(missing,size(x,2),size(x,3)) for i in 1:len]
    tSs = Vector{Union{Missing,E}}[Vector{Union{Missing,E}}(missing,size(x,2)) for i in 1:len]

    for (i,j,k) in Iterators.product(1:size(x,1),1:size(x,2),1:size(x,3))
        if norm(x[i,j,k])>1e-12
            ii,sc = isid(x[i,j,k]) #is identity; if so scalar = sc
            if ii && j==k
                tSs[i][j] = sc
            else
                tOs[i][j,k] = x[i,j,k]
            end

        end
    end

    pspaces=[space(x[i,1,1],2) for i in 1:len]
    domspaces=[[space(y,1) for y in x[i,:,1]] for i in 1:len]

    return MpoHamiltonian(Periodic(tSs),Periodic(tOs),Periodic(domspaces),Periodic(pspaces))
end

#allow passing in 2leg mpos
MpoHamiltonian(x::Array{T,3}) where T<:MpsVecType = MpoHamiltonian(map(t->permuteind(add_util_leg(t),(1,2),(4,3)),x))

#allow passing in regular tensormaps
MpoHamiltonian(t::TensorMap) = MpoHamiltonian(decompose_localmpo(add_util_leg(t)));

#a very simple utility constructor; given our "localmpo", constructs a mpohamiltonian
function MpoHamiltonian(x::Array{T,1}) where T<:MpoType
    domspaces=[space(y,1) for y in x]
    push!(domspaces,space(x[end],3)')

    pspaces=[space(x[1],2)]

    nOs=Array{Union{Missing,T},2}(missing,length(x)+1,length(x)+1)
    for (i,t) in enumerate(x)
        nOs[i,i+1]=t
    end

    nSs = Array{Union{Missing,eltype(T)},1}(missing,length(x)+1)
    nSs[1] = 1
    nSs[end] = 1

    return MpoHamiltonian(Periodic([nSs]),Periodic([nOs]),Periodic([domspaces]),Periodic(pspaces))
end

#utility functions for finite mpo
function Base.getindex(x::MpoHamiltonian{S,T,E},a::Int,b::Int,c::Int) where {S,T,E}
    if b == c && !ismissing(x.scalars[a][b])
        return x.scalars[a][b]*TensorMap(I,eltype(T),x.domspaces[a][b]*x.pspaces[a],x.imspaces[a][c]'*x.pspaces[a])::T
    elseif !ismissing(x.Os[a][b,c])
        return x.Os[a][b,c]::T
    else
        return TensorMap(zeros,eltype(T),x.domspaces[a][b]*x.pspaces[a],x.imspaces[a][c]'*x.pspaces[a])::T
    end
end
Base.eltype(x::MpoHamiltonian) = typeof(x[1,1,1])

keys(x::MpoHamiltonian) = Iterators.filter(a->contains(x,a[1],a[2],a[3]),Iterators.product(1:x.period,1:x.odim,1:x.odim))
keys(x::MpoHamiltonian,i::Int) = Iterators.filter(a->contains(x,i,a[1],a[2]),Iterators.product(1:x.odim,1:x.odim))
contains(x::MpoHamiltonian,a::Int,b::Int,c::Int) = !ismissing(x.Os[a][b,c]) || (b==c && !ismissing(x.scalars[a][b]))
isscal(x::MpoHamiltonian,a::Int,b::Int) = !ismissing(x.scalars[a][b])

"
checks if the given 4leg tensor is the identity (needed for infinite mpo hamiltonians)
"
function isid(x::MpoType)
    id = TensorMap(I,eltype(x),space(x,1)*space(x,2),space(x,3)'*space(x,4)')
    scal = dot(id,x)/dot(id,id)
    diff = x-scal*id
    return norm(diff)<1e-12,scal
end
isid(ham::MpoHamiltonian,i::Int) = reduce((a,b) -> a && isscal(ham,b,i) && abs(ham.scalars[b][i]-1)<1e-12,1:ham.period,init=true)

"
to be valid in the thermodynamic limit, these hamiltonians need to have a peculiar structure
"
function sanitycheck(ham::MpoHamiltonian)
    for i in 1:ham.period

        @assert isid(ham[i,1,1])[1]
        @assert isid(ham[i,ham.odim,ham.odim])[1]

        for j in 1:ham.odim
            for k in 1:(j-1)
                if contains(ham,i,j,k)
                    return false
                end
            end
        end
    end

    return true
end

#when there are missing values in an input mpo, we will fill them in with 0s
function fillmissing(x::Array{T,3}) where T<:Union{Missing,M} where M<:MpoType{Sp} where Sp
    @assert size(x,2) == size(x,3);

    #fill in Domspaces and pspaces
    Domspaces = Array{Union{Missing,Sp},2}(missing,size(x,1),size(x,2))
    pspaces = Array{Union{Missing,Sp},1}(missing,size(x,1))
    for (i,j,k) in Iterators.product(1:size(x,1),1:size(x,2),1:size(x,3))
        if !ismissing(x[i,j,k])
            dom = space(x[i,j,k],1)
            im = space(x[i,j,k],3)
            p = space(x[i,j,k],2)

            if ismissing(pspaces[i])
                pspaces[i] = p;
            else
                @assert pspaces[i] == p
            end

            if ismissing(Domspaces[i,j])
                Domspaces[i,j] = dom
            else
                @assert Domspaces[i,j] == dom
            end

            if ismissing(Domspaces[mod1(i+1,end),k])
                Domspaces[mod1(i+1,end),k] = im'
            else
                @assert Domspaces[mod1(i+1,end),k] == im'
            end
        end
    end

    #otherwise x[n,:,:] is empty somewhere
    @assert sum(ismissing.(pspaces))==0
    Domspaces = map(x-> ismissing(x) ? oneunit(Sp) : x,Domspaces) #missing domspaces => oneunit

    nx = Array{T,3}(undef,size(x,1),size(x,2),size(x,3)) # the filled in version of x
    for (i,j,k) in Iterators.product(1:size(x,1),1:size(x,2),1:size(x,3))
        if ismissing(x[i,j,k])
            nx[i,j,k] = TensorMap(zeros,eltype(M),Domspaces[i,j]*pspaces[i],Domspaces[mod1(i+1,end),k]*pspaces[i])
        else
            nx[i,j,k] = x[i,j,k]
        end
    end
    return nx
end

include("caches/simplecache.jl")
include("caches/autocache.jl")

include("utility.jl")
include("actions.jl")
include("mpohamexcitations.jl")
