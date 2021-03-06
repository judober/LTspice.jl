# Only run coverage from linux nightly build on travis.
get(ENV, "TRAVIS_OS_NAME", "")       == "linux"   || exit()
get(ENV, "TRAVIS_JULIA_VERSION", "") == "nightly" || exit()

using Coverage

cd(joinpath(@__DIR__, "..","..")) do
    Coveralls.submit(Coveralls.process_folder())
end
