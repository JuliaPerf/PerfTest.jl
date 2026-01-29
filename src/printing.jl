# TODO BEGIN

mutable struct printingState
    print_width :: Int

    boxlevel::Int
    tab::Int
end

function pprint()
end

function openBox()
end

function closeBox()
end

function separator()
end

### TODO END

"""
  Macro that adds a space at the beggining of a string
"""
macro lpad(pad)
    return :(" " ^ $(esc(pad)))
end

"""
  Prints the element in color blue
"""
function p_blue(printable)
    printstyled(printable, color=:blue)
end

"""
  Prints the element in color red
"""
function p_red(printable)
    printstyled(printable, color=:red)
end

"""
  Prints the element in color yellow
"""
function p_yellow(printable)
    printstyled(printable, color=:yellow)
end


"""
  Prints the element in color green
"""
function p_green(printable)
	  printstyled(printable, color=:green)
end


