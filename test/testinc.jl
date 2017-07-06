function testinc1()
  sim = LTspiceSimulation("testInc1.asc",executablepath="",tempdir=true)
  @test LTspice.does_circuitfilearray_file_match(sim)
  show(IOBuffer(),sim)
  @test measurementnames(sim) == ("incA","incB","incC","incD","incE","incF")
end
testinc1()
