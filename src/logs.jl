using Dates
using Base: Filesystem

struct Logger
    channels :: Vector{AbstractString}
    stdout_bindings :: Set{AbstractString}
    io_streams :: Dict{AbstractString, IOBuffer}
end

LOGS = Logger(String[
    "hierarchy",
    "metrics",
    "machine",
    "general"
], Set{AbstractString}(), Dict{AbstractString, IOBuffer}())

LOG_FOLDER_PREFIX = ".perftest/perftest_logs_"
LOG_FOLDER= ""

"""
  Creates temporal a directory for the logs of a specific execution
"""
function setLogFolder()
    global LOG_FOLDER = LOG_FOLDER_PREFIX * "$(mod(floor(Int,datetime2unix(now())), 2^25))"
    LOG_FOLDER = mktempdir(prefix=LOG_FOLDER)
    
    # Initialize IOBuffers for each channel
    for channel in LOGS.channels
        LOGS.io_streams[channel] = IOBuffer()
    end
end


"""
  Moves the temporal log directory to the persistent directory where results are saved
  and dumps all IOStream buffers to their respective log files
"""
function saveLogFolder()
    # Create the directory if it doesn't exist
    if !isdir(LOG_FOLDER)
        mkpath(LOG_FOLDER)
    end
    
    # Dump all IOStream buffers to their respective log files
    for (channel, buffer) in LOGS.io_streams
        logfile = "$LOG_FOLDER/logs_$channel.txt"
        open(logfile, "w") do file
            write(file, String(take!(copy(buffer))))
        end
    end
    
    mv(LOG_FOLDER, ".perftest\$LOG_FOLDER")
end

"""
  Creates and/or appends to a log channel, the message is saved in that channel
  depending on verbosity the message will be also sent to standard output.
"""
function addLog(channel::AbstractString, message::AbstractString, configuration :: Dict = Configuration.CONFIG)

    if !(configuration["general"]["logs_enabled"])
        return
    end
    if !(configuration["general"]["verbose"]) && !isempty(LOGS.stdout_bindings)
        empty!(LOGS.stdout_bindings)
    elseif configuration["general"]["verbose"] && isempty(LOGS.stdout_bindings)
        verboseOutput()
    end

    # If not added before the channel is pushed into the active channel set
    if !(channel in LOGS.channels)
        push!(LOGS.channels, channel)
        # Create a new IOBuffer for this channel
        LOGS.io_streams[channel] = IOBuffer()
    end
    
    # Ensure the channel has an IOBuffer
    if !haskey(LOGS.io_streams, channel)
        LOGS.io_streams[channel] = IOBuffer()
    end
    
    # Write to the IOBuffer
    log_entry = "$(now()) - $message\n"
    write(LOGS.io_streams[channel], log_entry)
    
    # Write to stdout if needed
    if channel in LOGS.stdout_bindings
        write(stdout, log_entry)
        flush(stdout)
    end
end

"""
  Prints the selected channel number on stdout
"""
function dumpLogs(channel::Int=0)
    if channel == 0
        for ch in LOGS.channels
            println("=== Channel: $ch ===")
            if haskey(LOGS.io_streams, ch)
                print(String(copy(LOGS.io_streams[ch].data)))
            end
        end
    elseif 1 <= channel <= length(LOGS.channels)
        ch = LOGS.channels[channel]
        if haskey(LOGS.io_streams, ch)
            print(String(copy(LOGS.io_streams[ch].data)))
        end
    end
end


"""
  Prints the selected channel number on a string
"""
function dumpLogsString(channel::Int=0)
    if channel == 0
        all = ""
        for ch in LOGS.channels
            all *= "=== Channel: $ch ===\n"
            if haskey(LOGS.io_streams, ch)
                all *= String(copy(LOGS.io_streams[ch].data))
            end
        end
        return all
    elseif 1 <= channel <= length(LOGS.channels)
        ch = LOGS.channels[channel]
        if haskey(LOGS.io_streams, ch)
            return String(copy(LOGS.io_streams[ch].data))
        end
    end
    return ""
end

"""
  Clears the IOBuffer of the specified channel
  if 0 all channels will be cleared.

  Unbinds the channels to stdout as well.
"""
function clearLogs(channel::Int=0)
    if channel == 0
        for ch in LOGS.channels
            if haskey(LOGS.io_streams, ch)
                LOGS.io_streams[ch] = IOBuffer()
            end
        end
        empty!(LOGS.stdout_bindings)
    elseif 1 <= channel <= length(LOGS.channels)
        ch = LOGS.channels[channel]
        if haskey(LOGS.io_streams, ch)
            LOGS.io_streams[ch] = IOBuffer()
        end
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
