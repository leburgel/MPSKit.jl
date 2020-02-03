"calculates the entropy of a given state"
entropy(state::MpsCenterGauged) = [sum([-j^2*2*log(j) for j in diag(convert(Array,svd(state.CR[i])[2]))]) for i in 1:length(state)]
"""
given a thermal state, you can map it to an mps by fusing the physical legs together
to prepare a gibbs ensemble, you need to evolve this state with H working on both legs
here we return the 'superhamiltonian' (H*id,id*H)
"""
function splitham(ham::MpoHamiltonian)
    pspaces=[fuse(p*p') for p in ham.pspaces]

    idham=Array{Union{Missing,eltype(ham.Os[1])},3}(missing,ham.period,ham.odim,ham.odim)
    hamid=Array{Union{Missing,eltype(ham.Os[1])},3}(missing,ham.period,ham.odim,ham.odim)

    for i in 1:ham.period
        for (k,l) in keys(ham,i)
            idt=TensorMap(LinearAlgebra.I,ham.pspaces[i],ham.pspaces[i])

            @tensor temp[-1 -2 -3;-4 -5 -6]:=ham[i,k,l][-1,-2,-4,-5]*idt[-6,-3]
            hamid[i,k,l]=TensorMap(temp.data,space(temp,1)*pspaces[i],space(temp,4)'*pspaces[i])

            @tensor temp[-1 -2 -3;-4 -5 -6]:=ham[i,k,l][-1,-6,-4,-3]*idt[-2,-5]
            idham[i,k,l]=TensorMap(temp.data,space(temp,1)*pspaces[i],space(temp,4)'*pspaces[i])
        end
    end

    return MpoHamiltonian(hamid),MpoHamiltonian(idham)
end

function mpo2mps(mpo)
    mpo=permuteind(mpo,(2,4),(1,3))
    mpo=TensorMap(mpo.data,fuse(codomain(mpo)),domain(mpo))
    mpo=permuteind(mpo,(2,1),(3,));
    return mpo
end

function mps2mpo(mps,ospace)
    mps=permuteind(mps,(1,2),(3,))
    mpo=TensorMap(mps.data,space(mps,1)*ospace*ospace',space(mps,3)')
    return permuteind(mpo,(1,2,),(4,3))
end
