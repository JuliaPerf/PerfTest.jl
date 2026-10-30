module MyPackage

# Add [a[1],a[2],...a[end]] and [b[end], b[end-1],...,b[1]] elementwise
function addReversed(A :: Vector{<: Number}, B:: Vector{<: Number}) :: Vector{<:Number}
   return [a + b for (a,b) in zip(A, reverse(B))]
end

end