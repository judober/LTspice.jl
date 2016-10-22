
function test1()
  filename = "C:/Users/Chris/.julia/v0.5/LTspice/test/test1.asc"
  sim = LTspiceSimulation(filename,executablepath="")
  show(IOBuffer(),sim)
  @test parameternames(sim) == ("vin","load")
  @test measurementnames(sim) == ("Current",)
  @test stepnames(sim) == ()
  @test parametervalues(sim) == [5.00, 2.00]
  @test measurementvalues(sim) == [2.50]
  @test stepvalues(sim) == ()
  @test sim["vin"] == 5
  @test sim["load"] == 2
  @test sim["Current"] == 2.5
  show(IOBuffer(),sim)
end
test1()
#=
test1 = LTspiceSimulation(filename,exc)
show(test1)
show(test1.circuitparsed)
show(LTspice.logparsed(test1))
loadlog!(test1)
@test test1["vin"] == 5
@test test1["load"] == 2
@test test1["current"] == 2.5
show(test1)
show(test1.circuitparsed)
show(LTspice.logparsed(test1))
@test measurementnames(test1) == ["current"]
@test logpath(test1) != ""
@test circuitpath(test1) != ""
@test typeof(parametervalues(test1)) == Array{Float64,1}
@test measurementvalues(test1)[1,1,1,1] == 2.5
@test ltspiceexecutablepath(test1) == ""
@test eltype(test1.circuitparsed) == Type(Float64)

t = try
  LTspiceSimulationTempDir(filename)
catch
  1  # LTspice is not inatalled on travis
end
#@test t == 1   # uncomment for travis

t = try
  LTspiceSimulation(filename)
catch
  1  # LTspice is not inatalled on travis
end
#@test t == 1   #uncomment for travis

t = try
  test1["this key is not valid"]
catch
  1
end
#@test t == 1    # uncomment for travis

keyss = ["vin","load","current","bad key"]
valuess = [5.0,2.0,2.5,1.0]
for (key,value) in zip(keyss,valuess)
  @test get(test1,key,1.0) == value
end

@test test1[1] == 2.5
@test test1[1,1,1,1] == 2.5

@test eltype(test1) == Type(Float64)

for (key,value) in LTspice.logparsed(test1)
  i = findfirst(keyss,key)
  @test value == valuess[i]
end
=#
