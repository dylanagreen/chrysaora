import algorithm
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

  # Object for transposition table entries.
  Transposition* = ref object
    # Zobrist hash for the board position represented by this entry.
    zobrist*: uint64

    # The score and score type. Score type is used for if the score returned
    # on an alpha-beta cutoff in which case it's an approximation and not
    # the true score and we need to know that.
    eval*: int
    score_type*: string

    # The previously found best refutation move, to search first from this pos
    refutation*: Move

    # The depth at which we put this entry in.
    depth*: int

  Engine* = ref object
    # An internal representation of the board.
    board*: Board

    # Time parameters.
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

    # The moves at the root node and their corresponding evals for move ordering
    root_moves: seq[Move]
    root_evals: seq[tuple[move: Move, eval: int]]

    # Number of moves to get into the remaining time, for time control.
    moves_to_go*: int

    # Starting time of the search, we use this for time management.
    start_time: float
    time_per_move: float

    # Cumulative time spent searching
    time: int


var tt* = newSeq[Transposition](200)


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

  if (epochTime() - engine.start_time) * 1000 > engine.time_per_move:
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
    var
      moves = if depth == engine.cur_depth: engine.root_moves
              else: search_board.generate_all_moves(search_board.to_move)
      best_move: Move

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

    # Before we start the search let's see if we can cut it off early with
    # Transposition hit
    let
      # We use mod as our hash function. Partially because it's easy.
      index = search_board.zobrist mod uint64(tt.len())
      hit = tt[index]
    # We only want to access the table if the full state is the same. With
    # small tables collisions are more likely so this resolves them.
    # Is nil checks that the index has even been filled before.
    if not hit.isNil and hit.zobrist == search_board.zobrist and engine.cur_depth > 1:
      # If the current depth is less than the tt one then we can use it, as
      # the tt one will be more "accurate." If we are searching a deeper
      # depth than the table, then we don't use the table, since we will
      # get a better measure of how good the move is. In this case we
      # search the previously best found refutation first.
      if depth < hit.depth:
        return @[(hit.refutation.uci, hit.eval)]
      else:
        moves.insert(hit.refutation)

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
          best_move = m
          result = @[(m.uci, best_lower[0].eval)].concat(best_lower)

        # If we're doing alpha cut offs we're looking for the maximum on
        # this ply, so if the valuation is more than the highest we update it.
        cur_alpha = max([cur_alpha, result[0].eval])

      else:
        if best_lower[0].eval < result[0].eval:
          best_move = m
          result = @[(m.uci, best_lower[0].eval)].concat(best_lower)

        # If we're doing beta cut offs we're looking for the minimum on
        # this ply, so if the valuation is less than the lowest we update it.
        cur_beta = min([cur_beta, result[0].eval])

      if depth == engine.cur_depth:
        engine.root_evals.add((m, result[0].eval))

      # Once alpha exceeds beta, i.e. once the minimum score that
      # the engine will receieve on a node (alpha) exceeds the
      # maximum score that the engine predicts for the opponent (beta)
      if cur_alpha >= cur_beta or not engine.compute:
        let cutoff_type = if color == engine.color: "alpha"
                          else: "beta"
        tt[index] = Transposition(refutation: m, zobrist: search_board.zobrist,
                                  eval: result[0].eval, score_type: cutoff_type,
                                  depth: depth)
        return

    # Adds the score to the transposition table.
    # I put the things in different orders to the tabbing would be nice.
    tt[index] = Transposition(refutation: best_move, eval: result[0].eval,
                              zobrist: search_board.zobrist, score_type: "pure",
                              depth: depth)



# Sorts the root moves to put the highest evaluated one first to try and proc
# more cutoffs.
proc sort_root_moves(engine: Engine) =
  # Comparison where lower eval is ranked lower
  proc comparison(x, y: tuple[move: Move, eval: int]): int =
    if x.eval < y.eval: -1 else: 1

  engine.root_evals.sort(comparison, order=SortOrder.Descending)

  # Extracts the new sorted root moves from the sorted evals.
  engine.root_moves = engine.root_evals.map(proc(x: tuple[move: Move, eval: int]): Move = x.move)


# I know this is duplicated from UCI but I didn't want to have to try and
# deal with the recursive dependency importing uci would cause.
proc send_command(cmd: string) =
  # Logs the command we sent out.
  logging.debug("Output: ", cmd)

  # Writes the command to the stdout and then flushes the buffer.
  stdout.write(cmd, "\n")
  flushFile(stdout)


proc search(engine: Engine, max_depth: int): EvalMove =
  # Start the clock!
  engine.start_time = epochTime()

  var
    # Times for calculating nodes per second
    t1, t2: float
    nps: int

  engine.time = 0

  if engine.color == WHITE:
    if engine.moves_to_go > 0:
      engine.time_per_move = float(engine.time_params["wtime"] div engine.moves_to_go +
                                   engine.time_params["winc"])
    # In cases where a moves to go wasn't passed the engine defaults to trying
    # to fit 30 moves into that span of time. In the future this can be more
    # advanced and the number can vary over the course of the game.
    else:
      engine.time_per_move = float(engine.time_params["wtime"] div 30 +
                                   engine.time_params["winc"])
  else:
    if engine.moves_to_go > 0:
      engine.time_per_move = float(engine.time_params["btime"] div engine.moves_to_go +
                                   engine.time_params["binc"])
    else:
      engine.time_per_move = float(engine.time_params["btime"] div 30 +
                                   engine.time_params["binc"])

  # We only want to calculate for 4/5 of the calculated time, to give some
  # buffer for reporting and to give us a little extra time later.
  engine.time_per_move = engine.time_per_move * (4/5)

  # If the time is less than 1 ms default to 10 seconds.
  if engine.time_per_move < 1:
    engine.time_per_move = 10000

  # Generates our route node moves.
  engine.root_moves = engine.board.generate_all_moves(engine.board.to_move)

  # Iterative deepening framework.
  for d in 1..max_depth:
    if not engine.compute:
      break
    # If we recieve the stop command don't go any deeper just return best move.
    elif check_for_stop():
     break
    engine.root_evals = @[]
    # Clear the number of nodes before starting.
    engine.nodes = 0

    # Records the current depth.
    engine.cur_depth = d

    t1 = cpuTime()
    let moves = engine.minimax_search(engine.board, d, color = engine.color)
    t2 = cpuTime()
    # cpuTime is in seconds and we need milliseconds.
    engine.time += int(floor((t2 - t1) * 1000))
    nps = int(float(engine.nodes) / (t2 - t1))
    result = moves[0]

    let pv = moves.map(proc(x: EvalMove): string = x.best_move).join(" ")
    send_command(&"info depth {d} seldepth {d} score cp {result.eval} nodes {engine.nodes} nps {nps} time {engine.time} pv {pv}")

    # Use the magic of iterative deepning to sort moves for more cutoffs.
    # Not much of a reason to sort this after depth 1.
    if d == 1:
      engine.sort_root_moves()


proc find_move*(engine: Engine): string =
  engine.color = engine.board.to_move
  let search_result = engine.search(engine.max_depth)

  return search_result.best_move
