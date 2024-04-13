
# Function that generates a test name if needed
function gen_test_name!(state::Context)
    v = (last(state.depth).depth_test_count += 1)
    return "Test $v"
end

function testset_update!(state::Context, name::String)
    push!(state.depth, ASTWalkDepthRecord(name))
end

### EXPRESSION LOADER
function load_file_as_expr(path ::AbstractString)
    file = open(path, "r")
    str = read(file, String)
    return Meta.parse("begin $str end")
end
