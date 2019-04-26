import logging
import os
import times
import logging

import uci
import board

var cmd = stdin.readLine()

# Makes the folder for the logs if it doesn't exist yet. For now just makes it
# in the folder the program is in.
let log_folder = os.joinPath(getCurrentDir(), "logs")
if not existsDir(log_folder):
    createDir(log_folder)

# Initiliazes the log.
let
  log_name = os.joinPath(log_folder, $(now()) & ".log")
  fileLog = newFileLogger(log_name, levelThreshold = lvlDebug)
  interpreter = UCI(board: new_board(), previous_pos: @[])

addHandler(fileLog)
logging.debug("Input: ", cmd)

identify()

while true:
  cmd = receive_command()

  if cmd != "":
    interpreter.decrypt_uci(cmd)