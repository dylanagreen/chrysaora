import logging
import os
import tables
import random
import system
import times

import uci
import engine
import board

var cmd = stdin.readLine()

# Makes the folder for the logs if it doesn't exist yet. For now just makes it
# in the folder the program is in.
let log_folder = os.joinPath(getAppDir(), "logs")
if not existsDir(log_folder):
    createDir(log_folder)

# Initiliazes the log.
let
  log_name = os.joinPath(log_folder, $(now()) & ".log")
  fileLog* = newFileLogger(log_name, levelThreshold = lvlDebug)
  cur_board = new_board()
  time_params = {"wtime" : -1, "btime" : -1, "winc" : -1, "binc" : -1}.toTable
  cur_engine = Engine(board: cur_board, time_params: time_params, compute: true,
                  max_depth: 3)
  interpreter = UCI(board: cur_board, previous_cmd: @[], engine: cur_engine)

addHandler(fileLog)
logging.debug("Input: ", cmd)

identify()

while true:
  cmd = receive_command()

  if cmd != "":
    interpreter.decrypt_uci(cmd)

  flushFile(fileLog.file)