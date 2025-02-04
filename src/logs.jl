using Dates

struct Logger
    channels :: Vector{AbstractString}
    stdout_bindings :: Set{AbstractString}
end

LOGS = Logger(String[
    "hierarchy",
    "metrics",
    "machine",
    "general"
], Set{AbstractString}())

"""
  Creates and/or appends to a log channel, the message is saved in that channel
  depending on verbosity the message will be also sent to standard output.
"""
function addLog(channel::AbstractString, message::AbstractString, context :: Context = ctx)
    if !(context._global.configuration["general"]["logs_enabled"])
        return
    end
    if !(channel in LOGS.channels)
        push!(LOGS.channels, channel)
    end
    logfile = "logs_$channel.txt"
    open(logfile, "a") do file
        log_entry = "$(now()) - $message\n"
        write(file, log_entry)
        if channel in LOGS.stdout_bindings
            write(stdout, log_entry)
            flush(stdout)
        end
    end
end

"""
  Prints the selected channel number on stdout
"""
function dumpLogs(channel::Int=0)
    if channel == 0
        for ch in LOGS.channels
            println("=== Channel: $ch ===")
            logfile = "logs_$ch.txt"
            if isfile(logfile)
                print(read(logfile, String))
            end
        end
    elseif 1 <= channel <= length(LOGS.channels)
        ch = LOGS.channels[channel]
        logfile = "logs_$ch.txt"
        if isfile(logfile)
            print(read(logfile, String))
        end
    end
end

"""
  Removes the logfile of the specified channel and the channel itself
  if 0 all channels will be prone.

  Unbinds the channels to stdout as well.
"""
function clearLogs(channel::Int=0)
    if channel == 0
        for ch in LOGS.channels
            logfile = "logs_$ch.txt"
            isfile(logfile) && rm(logfile)
        end
        empty!(LOGS.stdout_bindings)
    elseif 1 <= channel <= length(LOGS.channels)
        ch = LOGS.channels[channel]
        logfile = "logs_$ch.txt"
        isfile(logfile) && rm(logfile)
        delete!(LOGS.stdout_bindings, ch)
    end
end

"""
  Binds a channel to the standard output
"""
function verboseOutput(channel::AbstractString)
    if channel in LOGS.channels
        if channel in LOGS.stdout_bindings
            delete!(LOGS.stdout_bindings, channel)
        else
            push!(LOGS.stdout_bindings, channel)
        end
    end
end

function verboseOutput()
    for channel in LOGS.channels
        if channel in LOGS.stdout_bindings
        else
            push!(LOGS.stdout_bindings, channel)
        end
    end
end
