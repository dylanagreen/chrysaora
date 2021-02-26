import logging
import strutils
import tables

import arraymancer

import board
import engine

import train
import bootstrap

type
  UCI* = ref object
    # An internal representation of the board that will get passed to the
    # engine after it's setup.
    board*: Board

    engine*: Engine

    # A record of the previous "position" command. I use this to compare to the
    # current one, allowing the engine to only make the two new moves.
    # This avoids a slow down when the list of moves becomes unmanagably long.
    previous_cmd*: seq[string]

# Authorship information
const id = {"name": "Chrysaora Noctiluca beta-1", "author": "Dylan Green"}.toTable

proc send_command*(cmd: string) =
  # Logs the command we sent out.
  logging.debug("Output: ", cmd)

  # Writes the command to the stdout and then flushes the buffer.
  stdout.write(cmd, "\n")
  flushFile(stdout)


proc identify*() =
  # Sends all the identification commands.
  for key, value in id:
    send_command(["id", key, value].join(" "))

  # Id the options
  send_command("option name Hash type spin default 16 min 1 max 4096")
  send_command("option name Trust type spin default 85 min 0 max 100")
  send_command("option name Train type check default false")

  # Writes the ok command at the end.
  send_command("uciok")


proc set_option(parser: UCI, option: seq[string]) =
  if option[2] == "Hash":
    try:
      var size = parseFloat(option[^1])

      # Multiplying by 12.5 gets the number of entries. We multiply by 1000 to
      # convert megabytes to bytes, then divide by 80 (the number of bytes in
      # each transposition entry.)
      size = size * 12.5
      engine.tt = newSeq[Transposition](int(floor(size)))
    except:
      echo "Invalid hash size input, defaulting to 16."

  elif option[2] == "Trust":
    try:
      var trust_val = parseFloat(option[^1])

      assert trust_val >= 0
      assert trust_val <= 100

      engine.trust = trust_val / 100
    except:
      echo "Invalid trust value, defaulting to 85%"


  elif option[2] == "Train":
    if option[^1].toLowerAscii() == "true":
      set_up_training(parser.engine)
      logging.debug("Enabled training mode!")


proc set_up_position(parser: UCI, cmd: seq[string]) =
  var same = false
  # Checks that all the moves except the last two are identical to the previous
  # position command. If they are then we can start the moves from the last two.
  # Need to ensure the lengths of the two even match up to try.
  if len(parser.previous_cmd) == len(cmd) - 2:
    same = parser.previous_cmd.join(" ") == cmd[0..^3].join(" ")

  # If we load from a fen just load the board from the fen.
  # We don't want to load the fen again if we're skipping moves, hence not same
  if "fen" in cmd and not same:
    parser.board = load_fen(cmd[2..^1].join(" "))
  if "moves" in cmd:
    let start = cmd.find("moves")

    # Should be self explanatory
    if start + 1 >= len(cmd):
      raise newException(ValueError,
                         "Told to make moves, but no moves were passed")

    var moves_to_make = cmd[start + 1..^1]

    # This requires that there be at least two moves to make after the same
    # So that we can just make the last two moves.
    if same and start + 2 < len(cmd):
      moves_to_make = cmd[^2..^1]
    # Have to start over if there's more than two move difference.
    elif "fen" in cmd:
      parser.board = load_fen(cmd[2..^1].join(" "))
    else:
      parser.board = new_board()

    # Converts the moves to long algebraic to make them.
    for i, move in moves_to_make:
      # I can't believe I need a sanity check to ignore duplicated moves
      # but for some reason the lichess bot passed the same move twice.
      if i > 0 and move == moves_to_make[i - 1]:
        logging.debug("Skipped duplicate move", move)
        continue
      var converted = parser.board.uci_to_algebraic(move)
      parser.board.make_move(converted)

  # When the command is just start pos reset the board to the start pos.
  elif "startpos" in cmd:
    logging.debug("Reset Board")
    parser.board = new_board()

  parser.previous_cmd = @cmd


proc algebraic_to_uci*(parser: UCI, move: string): string =
  # Converts the castling moves.
  if "O-" in move:
    # Starting file
    result = "e"
    let rank = if parser.board.to_move == WHITE: 1 else: 8
    result = result & $rank

    # Kingside castling
    if move == "O-O":
      result = result & "g"
    # Queenside castling
    else:
      result = result & "c"

    # Adds the rank one more time.
    result = result & $rank

  else:
    # UCI is basically long algebraic with a few minor adjustments.
    result = parser.board.short_algebraic_to_long_algebraic(move)
    logging.debug("Long: ", result)
    # First we remove the capture "x"
    if 'x' in result:
      result = result.replace("x", "")

    # Promotions do not have an equal and the final char is lowercase.
    if '=' in result:
      result = result.replace("=", "")
      result = result.toLowerAscii()
    # Cuts off the en passant "e.p." at the end.
    elif "e.p." in result:
      result = result[0..^5]
    # Cuts off the piece character at the start.
    elif len(result) > 4:
      result = result[1..^1]


proc compute(parser: UCI, cmd: openArray[string]) =
  var parameters = {"wtime" : 0, "btime" : 0,
                    "winc" : 0, "binc" : 0}.toTable

  # Extracts the computation commands from the go command.
  # Things like wtime, btime, winc, binc.
  if len(cmd) > 1:

    for key, val in parameters:
      var new_val = -1
      try:
        let index = cmd.find(key)
        new_val = parseInt(cmd[index + 1])
      # The parameter wasn't passed if this except block runs
      except ValueError:
        logging.debug(key, " not passed.")

      parameters[key] = new_val

  # Sets the engines board to be the same as the parser.
  parser.engine.board = parser.board
  parser.engine.time_params = parameters

  let to_go = cmd.find("movestogo")
  parser.engine.moves_to_go = if to_go > -1: parseInt(cmd[to_go + 1]) else: 0

  parser.engine.compute = true

  logging.debug("Finding move.")
  let
    uci_move = parser.engine.find_move()

  logging.debug("Found move: ", uci_move)

  # Sends the move to the gui.
  send_command("bestmove " & uci_move)


proc decrypt_uci*(parser: UCI, cmd: string) =
  let
    fields = cmd.splitWhitespace()

    # The command that gets executed. Everything else is just args.
    to_exec = fields[0].toLowerAscii()

  # isready is most likely command to be passed.
  if to_exec == "isready":
    send_command("readyok")
  elif to_exec == "go":
    parser.compute(fields)
  elif to_exec == "position":
    parser.set_up_position(fields)
  elif to_exec == "quit":
    if training:
      # Update and save the weights before quitting.
      update_weights()
      save_weights()
    quit()
  elif to_exec == "ucinewgame":
    parser.board = new_board()
    parser.previous_cmd = @[]

    # Need to clear the transposition table
    engine.tt = newSeq[Transposition](engine.tt.len)

    if training:
      # Update all the weights
      update_weights()
  elif to_exec == "setoption":
    parser.set_option(fields)
  if training and to_exec == "bootstrap":
    try:
      if len(fields) > 1:
        var num_epoch = parseInt(fields[1])
        bootstrap(num_epoch)
      else:
        bootstrap()
    except ValueError:
      echo "Invalid number of training epochs"


proc receive_command*(): string =
  result = stdin.readLine
  logging.debug("Input: ", result)
