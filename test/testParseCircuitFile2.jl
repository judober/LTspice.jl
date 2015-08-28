using LTspice
using Base.Test

PCF_test2file = "PCF_test2.asc"
exc = ""
PCF_test2 = LTspiceSimulation!(PCF_test2file,exc)

v1list = [1.0, 1.1487, 1.31951, 1.51572, 1.7411, 
          2.0, 2.2974, 2.63902, 3.03143, 3.4822,
          4.0, 4.59479, 5.27803, 6.06287, 6.9644,
          8.0, 9.18959, 10.5561, 12.1257, 13.9288,
          16, 18.3792, 20]
blist = [1.0, 3.0, 5.0, 7.0, 9.0, 10.0]
clist = [4.0, 5.0, 6.0]
stepnames = ["v1","b","c"]

@test getsteps(PCF_test2) == (v1list, blist, clist)
@test getmeasurementnames(PCF_test2) == []
@test getstepnames(PCF_test2) == stepnames
@test getstepnames(PCF_test2.log) == stepnames
@test getmeasurements(PCF_test2) == Array(Float64,0,0,0,0)