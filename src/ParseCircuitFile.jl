mutable struct CircuitParsed{T<:AbstractString}
  circuitfilearray :: Array{T,1}
  parameternames :: Array{T,1}
  parametervalues :: ParameterValuesArray{Float64,1}
  parametermultiplier :: Array{Float64,1}
  parameterindex :: Array{Int,1}
  measurementnames :: Array{T,1}
  stepnames :: Array{T,1}
  circuitfileencoding
  cardlist
  circuitpath::T
  workingcircuitpath::T
  executablepath::T
  includesearchpath::Array{T,1}
  librarysearchpath::Array{T,1}
  CircuitParsed{T}() where T =
    new{T}([],[],[],[],[],[],[],nothing,standardcardlist,"","","",[],[])
end

# LTspice allows multiple directives (cards) in a single block
# in the GUI, ctrl-M is used to create a new line.
# this puts a backslash n in the file, NOT a newline character.
#
# EachCard is an iterator that separates the lines around the backslash n

#=
Base.start(::EachCard) = 1
function Base.next(ec::EachCard, state)
    p = first(something(findnext("\\n", ec.line, state), 0:-1))
    if p!=0 && p!=lastindex(ec.line)
        card = ec.line[state:p+1]
        state = p+2
    else
        card = ec.line[state:end]
        state = lastindex(ec.line)
    end
    return (card, state)
end
Base.done(ec::EachCard, state) = state>=lastindex(ec.line)
=#
struct EachCard{T<:AbstractString}
    line :: T
end
function Base.iterate(ec::EachCard, state=1)
    if state>=lastindex(ec.line)
        return nothing
    end
    p = first(something(findnext("\\n", ec.line, state), 0:-1))
    if p!=0 && p!=lastindex(ec.line)
        card = ec.line[state:p+1]
        state = p+2
    else
        card = ec.line[state:end]
        state = lastindex(ec.line)
    end
    return (card, state)
end



abstract type Card end
struct Parameter<:Card end
struct Measure<:Card end
struct Step<:Card end
struct Other<:Card end
struct Include<:Card end
struct Library<:Card end
const standardcardlist = [Parameter(), Measure(), Step(), Other()]
const tempdircardlist = [Parameter(), Measure(), Step(),
                         Include(), Library(), Other()]

const parameterregex = r"[.](?:parameter|param)[ ]+()"ix
const parametercaptureregex =
          r"""
          ([^\d ][^ =]*)
          ([ ]*={0,1}[ ]*)
          ([-+]{0,1}[0-9.]+e{0,1}[-+0-9]*)(k|meg|g|t|m|u|μ|n|p|f){0,1}
          (
          [^-+*/ ]*
          (?:\s|\\n|\r|$)
          (?![-+*/])
          )()
          """ix
#=
parametercaptureregex offsets
1 - name
2 - after name
3 - value
4 - unit
5 - everything to the end
6 - index after match
=#
function parsecard!(cp::CircuitParsed, ::Parameter, card::AbstractString)
  m = match(parameterregex, card)
  m == nothing && return false
  currentposition = m.offsets[1]
  push!(cp.circuitfilearray,card[1:currentposition-1])
  while currentposition<lastindex(card) && m!=nothing
#    println("      parameter: ",card[currentposition:end])
    m = match(parametercaptureregex,card,currentposition)
    if m!=nothing
      pushnamevalue!(cp,m,currentposition,card)
      currentposition = m.offsets[6]
    else
      push!(cp.circuitfilearray,card[currentposition:end])
    end
  end
  return true
end
function pushnamevalue!(cp::CircuitParsed,
                        m::RegexMatch,
                        currentposition::Int,
                        card::AbstractString)
  name = m.captures[1]
  after_name = m.captures[2]
  value = m.captures[3]
  unit = m.captures[4]
  to_end = m.captures[5]
  push!(cp.circuitfilearray,card[currentposition:m.offsets[1]-1])
  push!(cp.circuitfilearray,name)
  push!(cp.circuitfilearray,after_name)
  push!(cp.circuitfilearray,value)
  if haskey(units,unit)
      multiplier = units[unit]
  else
      multiplier = 1.0
  end
  valuenounit = parse(Float64,value)
  push!(cp.parameternames, name)
  index_parameternames = length(cp.parameternames)
  push!(cp.parametervalues.values, valuenounit * multiplier)
  push!(cp.parametermultiplier, multiplier)
  index_circuitfilearray = length(cp.circuitfilearray)
  push!(cp.parameterindex, index_circuitfilearray)
  unit != nothing && push!(cp.circuitfilearray,unit)
  push!(cp.circuitfilearray,to_end)
end

const measureregex = r"[.](?:measure|meas)[ ]+(?:ac |dc |op |tran |tf |noise ){0,1}[ ]*([^\d ][^ =]*)[ ]+"ix
function parsecard!(cp::CircuitParsed, ::Measure, card::AbstractString)
    m = match(measureregex, card)
    if m == nothing # exit if not a measure card
        return false
    end
    name = m.captures[1]
    push!(cp.measurementnames, name)
    push!(cp.circuitfilearray, card)
    return true
end
const step1regex = r"[.](?:step)[ ]+(?:oct |param ){0,1}[ ]*([^\d ][^ =]*)[ ]+(?:list ){0,1}[ ]*[0-9.e+-]+[a-z]*[ ]+"ix
const step2regex = r"[.](?:step)[ ]+(?:\w+)[ ]+(\w+[(]\w+[)])[ ]+"ix
function parsecard!(cp::CircuitParsed, ::Step, card::AbstractString)
    m = match(step1regex, card)
    if m == nothing
        m = match(step2regex, card)
        if m == nothing
            return false # exit if not a step card
        end
    end
    name = m.captures[1] #lowercase(m.captures[1])
    push!(cp.stepnames, name)
    push!(cp.circuitfilearray, card)
    return true
end
const includeregex = r"""(?:.include|.inc)[ ]+
                          [\"]{0,1}(.*?)[\"]{0,1}(?:\\n|\r|$)"""ix
function parsecard!(cp::CircuitParsed, ::Include, card::AbstractString)
  m = match(includeregex, card)
  m == nothing && return false
  incabspath = absolutepath(cp.includesearchpath,m.captures[1])
  push!(cp.circuitfilearray,replace(card,m.captures[1] => incabspath))
  return true
end
const libraryregex = r"""(?:.lib)[ ]+
                          [\"]{0,1}(.*?)[\"]{0,1}(?:\\n|\r|$)"""ix
function parsecard!(cp::CircuitParsed, ::Library, card::AbstractString)
  m = match(libraryregex, card)
  m == nothing && return false
  libabspath = absolutepath(cp.librarysearchpath,m.captures[1])
  push!(cp.circuitfilearray,replace(card,m.captures[1] => libabspath))
  return true
end
function absolutepath(patharray, file)
  for path in patharray
    testfile = joinpath(path,file)
    isfile(testfile) && return testfile
  end
end
function parsecard!(cp::CircuitParsed, ::Other, card::AbstractString)
    push!(cp.circuitfilearray, card)
    return true
end
function parsecard!(cp::CircuitParsed, card::AbstractString)
    for cardtype in cp.cardlist
        if parsecard!(cp,cardtype,card)
          break
        end
    end
end

iscomment(line::AbstractString) = occursin(r"^TEXT .* ;",line)
function parsecircuitfile(circuitpath::AbstractString,
                          workingcircuitpath::AbstractString,
                          executablepath::AbstractString,
                          librarysearhpaths)
  cp = CircuitParsed{String}()
  cp.circuitpath = abspath(circuitpath)
  cp.workingcircuitpath = abspath(workingcircuitpath)
  cp.executablepath = abspath(executablepath)
  if abspath(circuitpath) != abspath(workingcircuitpath)
    cp.cardlist = tempdircardlist
    executabledir = abspath(dirname(executablepath))
    originalcircuitdir = abspath(dirname(circuitpath))
    cp.includesearchpath = [joinpath(executabledir,"lib\\sub"),
                            originalcircuitdir]
    cp.librarysearchpath = [joinpath(executabledir,"lib\\cmp"),
                        joinpath(executabledir,"lib\\sub"),
                        originalcircuitdir]
    append!(cp.librarysearchpath,librarysearhpaths)
    cp.parametervalues.ismodified = true
  else
    cp.parametervalues.ismodified = false
  end
  cp.circuitfileencoding = circuitfileencoding(circuitpath)
#  println(circuitpath,"  ",cp.circuitfileencoding)
  open(circuitpath,cp.circuitfileencoding) do io
    for line in eachline(io, keep=true)
#      print("line: ",line)
      if iscomment(line)
        push!(cp.circuitfilearray, line)
      else
        for card in EachCard(line) # might be multi-line directive(s) created with Ctrl-M
#          println("  card: ",card)
          parsecard!(cp, card)
        end
      end
    end
  end
  return cp
end

function circuitfileencoding(path::AbstractString)
  function checkencoding(i)
    open(path,encodings[i]) do io
      if occursin(r"^Version",readline(io, keep=true))
        correct_i = i
      end
    end
  end
  firstwordshouldbe = "Version"
  encodings = [enc"windows-1252",enc"UTF-16LE",enc"UTF-8"] #enc"windows-1252",
  correct_i = 0
  for i in eachindex(encodings)
    try checkencoding(i) catch nothing end
    correct_i !=0 && break
  end
  correct_i == 0 && error("invalid LTspice circuit file")
#  println(path," ",encodings[correct_i])
  return encodings[correct_i]
end

# units as defined in LTspice
const units = Dict("K" => 1.0e3,
                   "k" => 1.0e3,
                   "MEG" => 1.0e6,
                   "meg" => 1.0e6,
                   "G" => 1.0e9,
                   "g" => 1.0e9,
                   "T" => 1.0e12,
                   "t" => 1.0e12,
                   "M" => 1.0e-3,
                   "m" => 1.0e-3,
                   "U" => 1.0e-6,
                   "u" => 1.0e-6,
                   "μ" => 1.0e-6,
                   "N" => 1.0e-9,
                   "n" => 1.0e-9,
                   "P" => 1.0e-12,
                   "p" => 1.0e-12,
                   "F" => 1.0e-15,
                   "f" => 1.0e-15,
                   )
