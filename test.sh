#!/bin/zsh
# Compile SlimeCore together with the test harness and run it.
set -e
cd "$(dirname "$0")"
mkdir -p .build
swiftc Sources/SlimeCore/*.swift Tests/SlimeCoreTests/*.swift -o .build/slime-tests
.build/slime-tests
