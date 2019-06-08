import logging
import os
import random
import selectors
import sequtils
import strformat
import strutils
import system
import tables
import terminal
import times

import arraymancer

import board
import bitboard
import movegen

type

  EvalMove = tuple[best_move: string, eval: int]

  Engine* = ref object
    # An internal representation of the board.
    board*: Board

    # Time parameters. I'll need this at some point.
    time_params*: Table[string, int]

    # Boolean for whether or not the engine should be computing right now
    compute*: bool

    # The maximum search depth of the engine.
    max_depth*: int

    # The current search depth of the engine.
    cur_depth: int

    # The color the engine is playing as.
    color*: Color

    # The number of nodes searched this search iteration.
    nodes: int

    # The Principal Variation we're currently studying.
    # I always think of Pressure-Volume plots when I see this.
    pv: seq[EvalMove]


# Piece-square tables. These tables are partially designed based on those on
# the chess programming wiki and partially self designed based on my own
# knowledge and understanding of the game.
let
  knight_table = @[[-4, -3, -2, -2, -2, -2, -3, -4],
                   [-3, -2, 0, 1, 1, 0, -2, -3],
                   [-2, 0, 1, 2, 2, 1, 0, -2],
                   [-2, 1, 2, 3, 3, 2, 1, -2],
                   [-2, 1, 2, 3, 3, 2, 1, -2],
                   [-2, 0, 1, 2, 2, 1, 0, -2],
                   [-3, -2, 0, 1, 1, 0, -2, -3],
                   [-4, -3, -2, -2, -2, -2, -3, -4]].toTensor

  rook_table = @[[0, 0, 0, 0, 0, 0, 0, 0],
                [1, 2, 2, 2, 2, 2, 2, 1],
                [-1, 0, 0, 0, 0, 0, 0, -1],
                [-1, 0, 0, 0, 0, 0, 0, -1],
                [-1, 0, 0, 0, 0, 0, 0, -1],
                [-1, 0, 0, 0, 0, 0, 0, -1],
                [-1, 0, 0, 0, 0, 0, 0, -1],
                [0, 0, 0, 1, 1, 0, 0, 0]].toTensor

  king_table = @[[0, 0, 0, 0, 0, 0, 0, 0],
                 [0, 0, 0, 0, 0, 0, 0, 0],
                 [0, 0, 0, 0, 0, 0, 0, 0],
                 [0, 0, 0, 0, 0, 0, 0, 0],
                 [0, 0, 0, 0, 0, 0, 0, 0],
                 [0, 0, 0, 0, 0, 0, 0, 0],
                 [0, 0, 0, 0, 0, 0, 0, 0],
                 [0, 0, 0, 0, 0, 0, 0, 0]].toTensor # TODO: Write this

  pawn_table = @[[0, 0, 0, 0, 0, 0, 0, 0],
                 [5, 5, 5, 5, 5, 5, 5, 5],
                 [2, 2, 3, 4, 4, 3, 2, 2],
                 [1, 1, 1, 4, 4, 1, 1, 1],
                 [0, 0, 0, 3, 3, 0, 0, 0],
                 [0, -1, -1, 2, 2, -1, -1, 0],
                 [1, 1, 1, -2, -2, 1, 1, 1],
                 [0, 0, 0, 0, 0, 0, 0, 0]].toTensor

  queen_table = @[[-2, -1, -1, -1, -1, -1, -1, -2],
                 [-1, 0, 0, 0, 0, 0, 0, -1],
                 [-1, 1, 1, 1, 1, 1, 1, -1],
                 [-1, 0, 0, 2, 2, 0, 0, -1],
                 [-1, 0, 0, 2, 2, 0, 0, -1],
                 [-1, 1, 1, 1, 1, 1, 1, -1],
                 [-1, 0, 1, 0, 0, 1, 0, -1],
                 [-2, -1, -1, -1, -1, -1, -1, -2]].toTensor

  bishop_table = @[[-2, -1, -1, -1, -1, -1, -1, -2],
                 [-1, 0, 0, 0, 0, 0, 0, -1],
                 [-1, 0, 1, 2, 2, 1, 0, -1],
                 [-1, 1, 1, 2, 2, 1, 1, -1],
                 [-1, 0, 2, 2, 2, 2, 0, -1],
                 [-1, 1, 1, 1, 1, 1, 1, -1],
                 [-1, 1, 0, 0, 0, 0, 1, -1],
                 [-2, -1, -1, -1, -1, -1, -1, -2]].toTensor

  value_table = {'N': knight_table, 'R': rook_table, 'K': king_table,
                 'P': pawn_table, 'Q': queen_table, 'B': bishop_table}.toTable


# Set up the selector
var selector: Selector[int] = newSelector[int]()
registerHandle(selector, int(getFileHandle(stdin)), {Event.READ}, 0)

proc check_for_stop(): bool =
  var events: seq[ReadyKey] = select(selector, 1)

  # The Selector waits for "ready to read" events so if there isn't one then
  # we can give up.
  if len(events) > 0:
    let cmd = stdin.readLine
    logging.debug("Input: ", cmd)
    if cmd == "stop":
      result = true


proc evaluate_move(engine: Engine, board: Board): int =
  # Starts by summing to get the straight piece value difference
  result = sum(board.current_state)

  # This loops over the pieces and gets their evaluations from the piece-square
  # tables up above and adds them to the table if they're white, or subtracts
  # if they're black.
  for piece in board.piece_list[WHITE]:
    result = result + value_table[piece.name][piece.pos.y, piece.pos.x] * 10

  for piece in board.piece_list[BLACK]:
    result = result + value_table[piece.name][7 - piece.pos.y, piece.pos.x] * -10


proc minimax_search(engine: Engine, search_board: Board, depth: int = 1,
                    alpha: int = -50000, beta: int = 50000, color: Color):
                    seq[EvalMove] =
  # If we recieve the stop command don't go any deeper just return best move.
  if check_for_stop():
    engine.compute = false

  # Initializes the result sequence.
  result = if color == engine.color: @[("", -50000)] else: @[("", 50000)]

  var
    cur_alpha = alpha
    cur_beta = beta

  if depth == 0:
    engine.nodes += 1
    result[0].eval = engine.evaluate_move(search_board)
    # Flip the sign for Black moves.
    if engine.color == BLACK: result[0].eval = result[0].eval * -1
    return
  else:
    let moves = search_board.generate_all_moves(search_board.to_move)

    #If there are no moves then someone either got checkmated or stalemated.
    if len(moves) == 0:
      let check = search_board.is_in_check(search_board.to_move)
      # In this situation we were the ones to get checkmated (or stalemated).
      # By multiplying by depth we consider closer checkmates worse/better.
      # Regardless of whether we're black or white the val will be negative if
      # we don't want it and positive if we do.
      if search_board.to_move == engine.color or not check:
        result[0].eval = -depth * 5000
      # Otherwise we found a checkmate and we really want this
      else:
        result[0].eval = depth * 5000
      return

    for m in moves:
      # Generate a new board state for move generation.
      search_board.make_move(m, skip=true)

        # Best move from the next lower ply.
      let best_lower = engine.minimax_search(search_board, depth - 1, cur_alpha,
                                             cur_beta, search_board.to_move)

      # Unmake the move
      search_board.unmake_move()

      # Updates the best found move so far. We look for the max if it's our
      # color and min if it's not (the guiding principle of minimax...)
      if color == engine.color:
        if best_lower[0].eval > result[0].eval:
          result = @[(m.uci, best_lower[0].eval)].concat(best_lower)

        # If we're doing alpha cut offs we're looking for the maximum on
        # this ply, so if the valuation is more than the highest we update it.
        cur_alpha = max([cur_alpha, result[0].eval])

      else:
        if best_lower[0].eval < result[0].eval:
          result = @[(m.uci, best_lower[0].eval)].concat(best_lower)

        # If we're doing beta cut offs we're looking for the minimum on
        # this ply, so if the valuation is less than the lowest we update it.
        cur_beta = min([cur_beta, result[0].eval])

      # Once alpha exceeds beta, i.e. once the minimum score that
      # the engine will receieve on a node (alpha) exceeds the
      # maximum score that the engine predicts for the opponent (beta)
      if cur_alpha >= cur_beta or not engine.compute:
        return


# I know this is duplicated from UCI but I didn't want to have to try and
# deal with the recursive dependency importing uci would cause.
proc send_command(cmd: string) =
  # Logs the command we sent out.
  logging.debug("Output: ", cmd)

  # Writes the command to the stdout and then flushes the buffer.
  stdout.write(cmd, "\n")
  flushFile(stdout)


proc search(engine: Engine, max_depth: int): EvalMove =
  var
    # Times for calculating nodes per second
    t1, t2: float
    time: int
    nps: int

  # Iterative deepening framework.
  for d in 1..max_depth:
    # Clear the number of nodes before starting.
    engine.nodes = 0
    # Makes sure the pv is the right length.
    engine.pv.add(("", 0))

    # Records the current depth.
    engine.cur_depth = d

    t1 = cpuTime()
    let moves = engine.minimax_search(engine.board, d, color = engine.color)
    t2 = cpuTime()
    # cpuTime is in seconds and we need milliseconds.
    time = int(floor((t2 - t1) * 1000))
    nps = int(float(engine.nodes) / (t2 - t1))
    result = moves[0]

    let pv = moves.map(proc(x: EvalMove): string = x.best_move).join(" ")
    send_command(&"info depth {d} seldepth {d} score cp {result.eval} nodes {engine.nodes} nps {nps} time {time} pv {pv}")


proc find_move*(engine: Engine): string =
  engine.color = engine.board.to_move
  let search_result = engine.search(engine.max_depth)

  return search_result.best_move
