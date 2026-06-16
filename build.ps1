Write-Host "Starting Build"

odin test engine/core -vet -strict-style
odin build examples/testbed -collection:engine=engine -vet -strict-style
