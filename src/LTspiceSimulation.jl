export LTspiceSimulation
export circuitpath, logpath, executablepath
export parmeternames, parametervalues
export measurmentnames, measurementvalues
export stepnames, stepvalues
export run!

type Status
  ismeasurementsdirty :: Bool # true = need to run simulation
  timestamp :: DateTime; # timestamp from last simulation run
  duration :: Float64; # simulation time in seconds
  Status() = new(true,DateTime(),NaN)
end
type StepValues{Nstep}
  values ::NTuple{Nstep,Array{Float64,1}}
end
StepValues(Nstep::Int) = StepValues{Nstep}(ntuple(d->Array{Float64,1}(),Nstep))

"""
Access parameters and measurements of an LTspice simulation.  Runs simulation
as needed.

Access as a dictionary:
```julia
measurement_value = sim["measurement_name"]
parameter_value = sim["parameter_name"]
sim["parameter_name"] = new_parameter_value
```

Access as a function:
```julia
(m1,m2,m3) = sim(p1,p2,p3)  # simulation with three measurements and three parameters
```

Access as arrays:
```julia
pnames = parameternames(sim)
mnames = measurementnames(sim)
snames = stepnames(sim)
pvalues = parametervalues(sim)
mvalues = measurementvalues(sim)
svalues = stepvalues(sim)
```
"""
abstract LTspiceSimulation{Nparam,Nmeas,Nmdim,Nstep}

macro simulationcommonfields()
  return :(
  circuitpath :: String;
  logpath :: String;
  executablepath :: String;
  circuitfilearray :: Array{String,1}; # text of circuit file
  parameternames :: NTuple{Nparam,String};
  parametervalues :: ParameterValuesArray{Float64,1}; # values in units A,V,W
  parametermultiplier :: NTuple{Nparam,Float64}; # units
  parameterindex :: NTuple{Nparam,Int}; # index into circuitfilearray
  parameterdict  :: Dict{String,Int}; # index into name, value, multiplier, index arrays
  measurementnames :: NTuple{Nmeas,String};
  measurmentdict :: Dict{String,Int}; # index into measurmentnames
  status :: Status;
  )
end

immutable NonSteppedSimulation{Nparam,Nmeas,Nmdim,Nstep} <: LTspiceSimulation{Nparam,Nmeas,Nmdim,Nstep}
  @simulationcommonfields()
  measurementvalues :: MeasurementValuesArray{Float64,1} # result of simulation
end

immutable SteppedSimulation{Nparam,Nmeas,Nmdim,Nstep} <: LTspiceSimulation{Nparam,Nmeas,Nmdim,Nstep}
  @simulationcommonfields()
  measurmentvalues :: MeasurementValuesArray{Float64,Nmdim}
  stepnames :: NTuple{Nstep,String}
  stepvalues :: StepValues{Nstep}
end

"""
    parametervalues(sim)

Returns an array of the parameters of `sim` in the order they appear in the
circuit file
"""
parametervalues

"""
    parameternames(sim)

Returns an array of the parameters names of `sim` in the order they appear in the
circuit file.
"""
parameternames

"""

    circuitpath(sim)

Returns path to the circuit file.

This is the path to the working circuit file.  If `LTspiceSimulationTempDir` was used
or if running under wine, this will not be the path given to the constructor.
"""
circuitpath

"""
    logpath(sim)

Returns path to the log file.
"""
logpath

"""
    ltspiceexecutablepath(sim)

Returns path to the LTspice executable
"""
ltspiceexecutablepath

"""
    measurementnames(sim)

Returns an array of the measurement names of `sim` in the order they appear in the
circuit file.
"""
measurementnames

"""
    stepnames(sim)

Returns an array of step names of `sim`.
"""
stepnames

"""
    measurementvalues(sim)

Retruns measurements of `sim` as an a array of Float64
values.

```julia
value = measurementvalues(sim)[measurement_name, inner_step, middle_step,
                        outer_step] # 3 nested steps
```
"""
measurementvalues

"""
    stepvalues(sim)

Returns the steps of `sim` as a tuple of three arrays of
the step values.
"""
stepvalues

circuitpath(x::LTspiceSimulation) = x.circuitpath
logpath(x::LTspiceSimulation) = x.logpath
executablepath(x::LTspiceSimulation) = x.executablepath
parmeternames(x::LTspiceSimulation) = x.parameternames
parametervalues(x::LTspiceSimulation) = x.parametervalues
measurmentnames(x::LTspiceSimulation) = x.measurmentnames
function measurementvalues(x::LTspiceSimulation)
  run!(x)
  x.measurementvalues
end
stepnames(x::SteppedSimulation) = x.stepnames
function stepvalues(x::SteppedSimulation)
  run!(x) # step values can be a function of parameters
  x.stepvalues.values
end

function LTspiceSimulation(
    circuitpath::AbstractString,
    executablepath::AbstractString=defaultltspiceexecutable(),
    istempdir::Bool = false
  )
  if istempdir
    circuitpath = preparetempdir(circuitpath, executablepath)
  end
  @static if is_linux()
    circuitpath = linkintempdirectoryunderwine(circuitpath)
  end
  circuitparsed = parsecircuitfile(circuitpath)
  Nparam = length(circuitparsed.parameternames)
  Nmeas = length(circuitparsed.measurementnames)
  Nstep = length(circuitparsed.stepnames)
  Nmdim = Nstep + 1
  parameterdict = Dict{String,Int}()
  for i in eachindex(circuitparsed.parameternames)
    parameterdict[circuitparsed.parameternames[i]] = i
  end
  measurementdict = Dict{String,Int}()
  for i in eachindex(circuitparsed.measurementnames)
    measurementdict[circuitparsed.measurementnames[i]] = i
  end
  if length(circuitparsed.stepnames)==0
    return NonSteppedSimulation{Nparam,Nmeas,Nmdim,Nstep}(
      circuitpath,
      logpath(circuitpath),
      executablepath,
      circuitparsed.circuitfilearray,
      (circuitparsed.parameternames...),
      circuitparsed.parametervalues,
      (circuitparsed.parametermultiplier...),
      (circuitparsed.parameterindex...),
      parameterdict,
      (circuitparsed.measurementnames...),
      measurementdict,
      Status(),
      MeasurementValuesArray{Float64,1}(fill(NaN,Nmeas)), # measurmentvalues
    )
  else
    return SteppedSimulation{Nparam,Nmeas,Nmdim,Nstep}(
      circuitpath,
      logpath(circuitpath),
      executablepath,
      circuitparsed.circuitfilearray,
      (circuitparsed.parameternames...),
      circuitparsed.parametervalues,
      (circuitparsed.parametermultiplier...),
      (circuitparsed.parameterindex...),
      parameterdict,
      (circuitparsed.measurementnames...),
      measurementdict,
      Status(),
      MeasurementValuesArray{Float64,Nmdim}(fill(NaN,(Nmeas,ntuple(d->1,Nstep)...))), # measurementvalues
      (circuitparsed.stepnames...),
      StepValues(Nstep)
    )
  end
end

function preparetempdir(circuitpath::AbstractString, executablepath::AbstractString)
  td = mktempdir()
  atexit(()->ispath(td)&&rm(td,recursive=true)) # delete this on exit
  (d,f) = splitdir(circuitpath)
  workingcircuitpath = convert(AbstractString, joinpath(td,f))
  cp(circuitpath,workingcircuitpath)
  makecircuitfileincludeabsolutepath(circuitpath,workingcircuitpath,executablepath)
  return workingcircuitpath
end

LTspiceSimulation(circuitpath::AbstractString;
                  executablepath::AbstractString = defaultltspiceexecutable(),
                  tempdir::Bool = false) =
  LTspiceSimulation(circuitpath, executablepath, tempdir)

function Base.show(io::IO, x::NonSteppedSimulation)
  println(io,"NonSteppedSimulation:")
  showcircuitpath(io,x)
  showparameters(io,x)
  showmeasurements(io,x)
  showtimeduration(io,x)
end
function Base.show(io::IO, x::SteppedSimulation)
  println(io,"SteppedSimulation:")
  showcircuitpath(io,x)
  showparameters(io,x)
  showmeasurements(io,x)
  showsteps(io,x)
end

function showcircuitpath(io::IO, x::LTspiceSimulation)
  println(io,"circuit path = ",x.circuitpath)
end
function showparameters(io::IO, x::LTspiceSimulation)
  if length(x.parameternames)>0
    println(io)
    println(io,"Parameters")
    for i in eachindex(x.parameternames)
      println(io,rpad(x.parameternames[i],25,' ')," = ",x.parametervalues[i])
    end
  end
end
function showmeasurements(io::IO, x::NonSteppedSimulation)
  if length(x.measurementnames)>0
    println(io)
    println(io,"Measurements")
    for i in eachindex(x.measurementnames)
      print(io,rpad(x.measurementnames[i],25,' '))
      if x.status.ismeasurementsdirty
        println(io)
      elseif isnan(x.measurementvalues[i])
        println(io," = measurement failed")
      else
        println(io," = ",x.measurementvalues[i])
      end
    end
  end
end
function showtimeduration(io::IO, x::LTspiceSimulation)
  if ~isnan(x.status.duration) # simulation was run at least once
    println(io)
    println(io,"Last Run")
    println(io,"time = ",x.status.timestamp)
    println(io,"duration = ",x.status.duration)
  end
end
function showmeasurements(io::IO, x::SteppedSimulation)
  if length(x.measurementnames)>0
    println(io)
    println(io,"Measurements")
    totalsteps = length(x.measurementvalues[1,:,:,:])
    for i in eachindex(x.measurementnames)
      print(io,rpad(x.measurementnames[i],25,' '))
      if x.status.ismeasurementsdirty
        println(io)
      else
        println(io," ",totalsteps," values")
      end
    end
  end
end
function showsteps(io::IO, x::SteppedSimulation)
  if length(x.stepnames)>0
    println(io)
    println(io,"Steps")
    for i in eachindex(x.stepnames)
      print(io,rpad(x.stepnames[i],25,' '))
      if x.status.ismeasurementsdirty
        println(io)
      else
        println(" ",length(x.stepvalues[i])," steps")
      end
    end
  end
end

Base.haskey(x::LTspiceSimulation, key::AbstractString) =
  haskey(x.parameterdict,key) || haskey(x.measurementdict,key)
Base.keys(x::LTspiceSimulation) =
  vcat(collect(keys(x.parameterdict)),collect(keys(x.measurementdict)))
function Base.values(x::LTspiceSimulation)
  run!(x)
  allkeys = keys(x)
  allvalues = similar(allkeys, Float64)
  for i in eachindex(allkeys)
    allvalues[i] =  x[allkeys[i]]
  end
  return allvalues
end
function Base.getindex(x::LTspiceSimulation, key::AbstractString)
  if haskey(x.parameterdict,key)
    return x.parametervalues[x.parameterdict[key]]
  elseif haskey(x.measurementdict,key)
    run!(x)
    return x.measurementvalues[x.measurementdict[key],:,:,:]
  else
    throw(KeyError(key))
  end
end
function Base.get(x::LTspiceSimulation, key::AbstractString, default)
  if haskey(x,key)
    return(x[key])
  else
    return(default)
  end
end
function Base.setindex!(x::LTspiceSimulation, value::Float64, key::AbstractString)
  if haskey(x.parameterdict)
    x.parametervalues[x.parameterdict[key]] = value
  elseif haskey(x.measurementdict)
    error("measurements cannot be set.")
  else
    throw(KeyError(key))
  end
end
Base.eltype(x::LTspiceSimulation) = Float64
Base.length(x::LTspiceSimulation) = length(x.parametervalues) + length(x.measurementvalues)

(x::SteppedSimulation)(args...) = callsimulation(x,args...)
(x::NonSteppedSimulation)(args...) = callsimulation(x,args...)

function callsimulation(x::LTspiceSimulation, args...)
  if length(args) != length(x.parameternames)
    throw(ArgumentError("number of arguments must match number of parameters"))
  end
  for i in eachindex(args)
    x.parametervalues[i] = args[i]
  end
  measurementvalues(x)
end

"""
```julia
flush(sim)
```
Writes `sim`'s circuit file back to disk if any parameters have changed.  The
user does not usually need to call `flush`.  It will be called automatically
 when a measurement is requested and the log file needs to be updated.  It can be used
 to update a circuit file using julia for simulation with the LTspice GUI.
"""
function Base.flush(x::LTspiceSimulation; force=false)
	if x.parametervalues.ismodified || force
    updatecircuitfilearray!(x)
    writecircuitfilearray(x)
  	x.parametervalues.ismodified = false
    x.status.ismeasurementsdirty = true
  end
  return nothing
end
function updatecircuitfilearray!(x::LTspiceSimulation)
  for i in eachindex(x.parameternames)
    x.circuitfilearray[x.parameterindex[i]] =
      string(x.parametervalues[i]/x.parametermultiplier[i])
  end
end
function writecircuitfilearray(x::LTspiceSimulation)
  io = open(x.circuitpath,false,true,false,true,false)
  for text in x.circuitfilearray
    print(io,text)
  end
  close(io)
  return nothing
end

"""
```julia
run!(sim)
```
Writes circuit changes, calls LTspice to run `sim`, and reloads the log file.  The user
normally does not need to call this.
"""
function run!(x::LTspiceSimulation; force=false)
  flush(x,force)
  if x.status.ismeasurementsdirty || force
    if x.executablepath != ""  # so travis dosen't need to load LTspice
      @static if is_linux()
        drive_c = "/home/$(ENV["USER"])/.wine/drive_c"
        winecircuitpath = joinpath("C:",relpath(x.circuitpath,drive_c))
        run(`$(x.executablepath) -b -Run $winecircuitpath`)
      else
        run(`$(x.executablepath) -b -Run $(x.circuitpath)`)
      end
    end
    parselog!(x)
  end
end