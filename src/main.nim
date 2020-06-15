import logging
import os
import system
import tables
import times

import board
import engine
import parselog
import uci

# Makes the folder for the logs if it doesn't exist yet. For now just makes it
# in the folder the program is in.
let log_folder = getAppDir() / "logs"
if not existsDir(log_folder):
    createDir(log_folder)

# Initiliazes the log.
let
  log_name = log_folder / $(now()) & ".log"
  fileLog* = newFileLogger(log_name, levelThreshold = lvlDebug)
  cur_board = new_board()
  time_params = {"wtime" : 0, "btime" : 0, "winc" : 0, "binc" : 0}.toTable
  cur_engine = Engine(board: cur_board, time_params: time_params, compute: true,
                      max_depth: 15, color: cur_board.to_move)
  interpreter = UCI(board: cur_board, previous_cmd: @[], engine: cur_engine)

var
  # Whether the network was initiated and whether or not a log was parsed,
  # respectively.
  init, parse: bool
  cmd: string

addHandler(fileLog)
# If any command line parameters are passed we enter this first code block.
if paramCount() > 0:
  let params = commandLineParams()

  for i in 0 ..< params.len:
    let p = params[i]
    if p == "--parselog":
      logging.debug("Log parse mode active.")
      # Need to init this first so we don't run with random weights
      initialize_network()
      parse = true
      parse_log(params[i + 1], interpreter)
    elif p == "--weightsfile":
      init = true
      initialize_network(params[i + 1])

if not parse:
  if not init:
    initialize_network()
  # Gets the first command (usually "uci" but really could be anything)
  cmd = stdin.readLine()
  logging.debug("Input: ", cmd)

  # Sends the identifying strings
  identify()

# Core running loop. Receives commands, decrypts them, and then flushes the
# log to the file at the end of each iteration.
while true:
  cmd = receive_command()

  if cmd != "":
    interpreter.decrypt_uci(cmd)

  flushFile(fileLog.file)