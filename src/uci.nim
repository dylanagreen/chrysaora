import logging
import re
import strutils
import tables
import terminal

import arraymancer

import board
import bitboard
import engine

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
const id = {"name": "Chrysaora 0.005", "author": "Dylan Green"}.toTable


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

  # Don't have any options to send yet!

  # Writes the ok command at the end.
  send_command("uciok")


proc uci_to_algebraic(parser: UCI, move: string): string =
  # Promotions are in the form say a7a8q so length 5
  if len(move) == 5:
    result = move[0..^2] & '=' & toUpperAscii(move[^1])
  else:
    # Uses regex to find the rank/file combinations.
    let locs = findAll(move, loc_finder)

    # Gets the starting Position and puts into a constant
    var
      dest = locs[0]
      file = ascii_lowercase.find(dest[0]) # File = x
      rank = 8 - parseInt($dest[1]) # Rank = y

    let
      start: Position = (rank, file)

      # Finds the piece that's being moved so we can prepend it to the move.
      piece = parser.board.current_state[start.y, start.x]
      piece_name = piece_names[abs(piece)]

    # If the piece is a king check if this is a castling move.
    if piece_name == 'K' and dest[0] == 'e':
      # Only need this for checking for castling.
      dest = locs[1]

      # Kingside castling
      if dest[0] == 'g':
        return "O-O"
      # Queenside castling
      elif dest[0] == 'c':
        return "O-O-O"

    if piece_name == 'P':
      result = move
    else:
      result = $piece_name & move


#proc set_option(option: openArray[string]) =


proc set_up_position(parser: UCI, cmd: openArray[string]) =
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

    var moves_to_make = cmd[start+1..^1]

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
    for move in moves_to_make:
      var converted = parser.uci_to_algebraic(move)
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
  var parameters = {"wtime" : -1, "btime" : -1,
                    "winc" : -1, "binc" : -1}.toTable

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
    quit()
  elif to_exec == "ucinewgame":
    parser.board = new_board()
    parser.previous_cmd = @[]
  elif to_exec == "setoption":
    echo "temp"
    #set_option(fields)


proc receive_command*(): string =
  result = stdin.readLine
  logging.debug("Input: ", result)
