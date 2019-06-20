import os
import strutils

import uci

proc parse_log*(name: string, interpreter: UCI) =


  let loc = getCurrentDir() / name

  # Make sure the file exists
  if not fileExists(loc):
    raise newException(IOError, $loc & " Not Found")

  # Opens the loc, and sets the prefix for engine input lines.
  let
    data = open(loc)
    pre = "DEBUG Input: "

  for line in data.lines:
    if line.startsWith(pre):
      # We need a variable variable for remove prefix, and we need to convert
      # line from a TaintedString to a string, which we do in one line.
      var new_line = string(line)
      new_line.removePrefix(pre)
      echo new_line
      # We want to print out the identify line first.
      if new_line == "uci":
        identify()
      # Runs through and decrypts each input line.
      interpreter.decrypt_uci(new_line)
