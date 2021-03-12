# Package

version       = "0.1.0"
author        = "Dylan Green"
description   = "Experimental neural network chess engine."
license       = "GPL-3.0"

bin = @["chrysaora"]
srcDir = "src"
installExt = @["nim"]

requires "arraymancer == 0.6.1"
