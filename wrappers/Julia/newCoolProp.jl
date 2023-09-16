module CoolProp

import Markdown


# CONSTANTS


## name of dynamic library file
const LIBRARY = "libCoolProp"

## default length of character buffers
const CHARACTERBUFFERLENGTH = 2048


# INFORMATION FUNCTIONS


function getglobalparameterstring(parametername::AbstractString)
    # buffer for message output
    bufferlength::Cint = CHARACTERBUFFERLENGTH
    characterbuffer = Vector{Cchar}(undef, bufferlength)
    # get message
    value::Int = @ccall LIBRARY.get_global_param_string(parametername::Cstring, characterbuffer::Ref{Cchar}, bufferlength::Cint)::Clong
    # handle errors
    (value == 0) && error(geterrorstring())
    # ensure null-termination to interpret as C string
    characterbuffer[end] = 0
    # get message string
    message = GC.@preserve characterbuffer unsafe_string(pointer(characterbuffer))
end

function geterrormessage()
    getglobalparameterstring("errstring")
end

function getparameterindex(parametername::AbstractString)
    index::Int = @ccall LIBRARY.get_param_index(parametername::Cstring)::Clong
    # handle errors
    (index == -1) && error(geterrormessage())
    index
end

function getparameterinformation(parameterindex::Integer, informationlabel::AbstractString)
    # buffer for information output
    bufferlength::Cint = CHARACTERBUFFERLENGTH
    characterbuffer = Vector{Cchar}(undef, bufferlength)
    # get information
    value::Int = @ccall LIBRARY.get_parameter_information(parameterindex::Clong, informationlabel::Cstring, characterbuffer::Ref{Cchar}, bufferlength::Cint)::Clong
    # handle errors
    (value == 0) && error(geterrormessage())
    # ensure null-termination to interpret as C string
    characterbuffer[end] = 0
    # get information string
    information = GC.@preserve characterbuffer unsafe_string(pointer(characterbuffer))
end

function getparameterinformationstring(parametername::AbstractString, informationlabel::AbstractString)
    parameterindex = getparameterindex(parametername)
    information = getparameterinformation(parameterindex, informationlabel)
end

function istrivialparameter(parameterindex::Integer)
    value::Int = @ccall LIBRARY.is_trivial_parameter(parameterindex::Clong)::Cint
    # handle errors
    (value == -1) && error(geterrormessage())
    # convert to boolean
    istrivial::Bool = value
    istrivial
end


# WRAPPER ONLY UTILITIES


function gettableofinputs(; marktrivial::Bool = true, trivial::Bool = false)
    # all parameter names
    namelist = getglobalparameterstring("parameter_list")
    allnames = split(namelist, ",")
    # group different names of same parameter
    groups = foldl(allnames; init=Dict{Int, Vector{String}}()) do partialgroups, name
        index = getparameterindex(name)
        group = get!(partialgroups, index, Vector{String}())
        push!(group, name)
        partialgroups
    end |> collect
    # get information of parameters
    information = map(groups) do (index, group)
        namecodes = map(label -> "`$(label)`", group)
        names = join(namecodes, ", ")
        units = begin
            u = getparameterinformation(index, "units")
            # replace hyphens in non-empty units
            replace(u, r"(?<!^)-(?!$)" => " ")
        end
        io = getparameterinformation(index, "IO")
        description = getparameterinformation(index, "long")
        istrivial = istrivialparameter(index) ? "✓" : "✕"
        row = (; names = names, units = units, io = io, istrivial = istrivial, description = description)
    end
    # sort table information
    sort!(information; by = x -> x.names)
    sort!(information; by = x -> x.io)
    # labels for information
    labels = ["Parameter", "Unit", "Input/Output", "Trivial", "Description"]
    # restrict to only trivial inputs
    if trivial
        information = filter(row -> row.istrivial == "✓", information)
        # remove input/output information
        information = map(row -> row[filter(!=(:io), keys(row))], information)
        filter!(!=("Input/Output"), labels)
    end
    # remove marking trivial inputs
    if !marktrivial
        information = map(row -> row[filter(!=(:istrivial), keys(row))], information)
        filter!(!=("Trivial"), labels)
    end
    # create markdown table
    header = map(label -> "**$(label)**", labels)
    rows = [[header]; collect.(information)]
    alignment = fill(:l, length(header))
    table = Markdown.Table(rows, alignment) |> Markdown.plain |> Markdown.parse
end

## table of inputs in markdown
const tableofinputs = gettableofinputs()


# HIGH-LEVEL INTERFACE


@doc """
    Props1SI(fluidname::AbstractString, output::AbstractString)

Return a value that does not depend on the thermodynamic state.

This is a convenience function that does the call:

```julia
PropsSI(output, "", 0, "", 0, fluidname)
```

# Examples

```jldoctest
julia> Tc = Props1SI("Water", "Tcrit")
647.096
```

See also: [`PropsSI`](@ref)

# Extended help

List of trivial inputs:

$(gettableofinputs(; marktrivial = false, trivial = true))
"""
function Props1SI(fluidname::AbstractString, parametername::AbstractString)
    value::Float64 = @ccall LIBRARY.Props1SI(fluidname::Cstring, parametername::Cstring)::Cdouble
    # check for errors
    isfinite(value) || error(geterrormessage())
    value
end


# LOW LEVEL INTERFACE


module AbstractState

import ..CoolProp: LIBRARY, CHARACTERBUFFERLENGTH

## CONSTANTS

const DEFAULTBACKEND = "HEOS"

## INFORMATION FUNCTIONS

function geterrormessage(errorcode::Clong, characterbuffer::Vector{Cchar})
    local message::String
    if errorcode == 1
        # ensure null-termination to interpret as C string
        characterbuffer[end] = 0
        # get message string
        message = GC.@preserve characterbuffer unsafe_string(pointer(characterbuffer))
        return message
    end
    (errorcode == 2) && return message = "buffer too small for error message"
    (errorcode == 3) && return message = "unknown error"
    nothing
end

## STATE MANAGEMENT UTILITIES

function factory(backend::AbstractString, fluidname::AbstractString)
    # error code storage
    errorcodestore = Ref{Clong}(0)
    # buffer for message output
    bufferlength::Clong = CHARACTERBUFFERLENGTH
    characterbuffer = Vector{Cchar}(undef, bufferlength)
    # get state handle
    handle::Int = @ccall LIBRARY.AbstractState_factory(backend::Cstring, fluidname::Cstring, errorcodestore::Ref{Clong}, characterbuffer::Ref{Cchar}, bufferlength::Clong)::Clong
    # handle errors
    errorcode = errorcodestore[]
    (errorcode == 0) || error(geterrormessage(errorcode, characterbuffer))
    # state handle
    handle
end

function free(handle::Integer)
    # error code storage
    errorcodestore = Ref{Clong}(0)
    # buffer for message output
    bufferlength::Clong = CHARACTERBUFFERLENGTH
    characterbuffer = Vector{Cchar}(undef, bufferlength)
    # get state handle
    @ccall LIBRARY.AbstractState_free(handle::Clong, errorcodestore::Ref{Clong}, characterbuffer::Ref{Cchar}, bufferlength::Clong)::Nothing
    # handle errors
    errorcode = errorcodestore[]
    (errorcode == 0) || error(geterrormessage(errorcode, characterbuffer))
    nothing
end

mutable struct State
    handle::Int
    function State(handle::Integer)
        state = new(handle)
        # set finalizer to free handle
        freestate(state) = free(state.handle)
        finalizer(freestate, state)
    end
end

function State(backend::AbstractString, fluidname::AbstractString)
    handle = factory(backend, fluidname)
    state = State(handle)
end

State(fluidname::AbstractString) = State(DEFAULTBACKEND, fluidname)


end


# COMPATIBILITY 


@deprecate get_global_param_string(parametername::AbstractString) getglobalparameterstring(parametername)

@deprecate get_param_index(parametername::AbstractString) getparameterindex(parametername)

@deprecate get_parameter_information_string(parametername::AbstractString, informationlabel::AbstractString) getparameterinformationstring(parametername, informationlabel)

@deprecate PropsSI(fluidname::AbstractString, parametername::AbstractString) Props1SI(fluidname, parametername)


end

