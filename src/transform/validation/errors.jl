
function printError(e :: ParsingErrorInfo, l :: String)
    p_red("[PARSING ERROR] ")
    print(e.name)
    println("")
    print("↪ At testset: $(l)")
    println("")
end

function num_errors(e :: VecErrorCollection) :: Int
    return length(e.errors)
end

function pushError!(error :: ParsingErrorInfo, collection :: VecErrorCollection, depth :: AbstractArray{DepthEntry})
    push!(collection.errors, error)
    push!(collection.loc, "| " * foldl(*, [e.set_name * " > " for e in depth]))
    addLog("general", error.name)
end

# Abbreviations for ASTRule
function throwParseError!(name, context)
	  pushError!(ParsingErrorInfo(name), context._global.errors, context._local.depth_record)
end
function throwParseError!(num, name, context)
	  pushError!(ParsingErrorInfo(num, name), context._global.errors, context._local.depth_record)
end

function printErrors(collection :: VecErrorCollection)
    for e in zip(collection.errors, collection.loc)
        printError(e...)
    end
end

function importErrors!(importer::VecErrorCollection, exporter::VecErrorCollection, path :: String)
    for e in zip(exporter.errors, exporter.loc)
        push!(importer.errors, e[1])
        push!(importer.loc, "INCLUDED: $path : " * e[2])
    end
end
