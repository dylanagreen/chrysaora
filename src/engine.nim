import algorithm
import logging
import marshal
import math
import os
import selectors
import sequtils
import streams
import strformat
import strutils
import system
import tables
import times # Why not just import everything at this point

import arraymancer

import board
import movegen
include net
import train

type

  EvalMove = tuple[best_move: string, eval: float]

  # Object for transposition table entries.
  Transposition* = ref object
    # Zobrist hash for the board position represented by this entry.
    zobrist*: uint64

    # The score and score type. Score type is used for if the score returned
    # on an alpha-beta cutoff in which case it's an approximation and not
    # the true score and we need to know that.
    eval*: float
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
    root_evals: seq[tuple[move: Move, eval: float]]

    # Number of moves to get into the remaining time, for time control.
    moves_to_go*: int

    # Starting time of the search, we use this for time management.
    start_time: float
    time_per_move: float

    # Cumulative time spent searching
    time: int

    # The actual network we use to evaluate
    network*: ChessNet

    # Storing this for training purposes
    pv: string

var
  tt* = newSeq[Transposition](200)
  # Whether or not we're in training mode
  training* = false


# Piece-square tables. These tables are partially designed based on those on
# the chess programming wiki and partially self designed based on my own
# knowledge and understanding of the game.
let
  knight_table = [[-4, -3, -2, -2, -2, -2, -3, -4],
                   [-3, -2, 0, 1, 1, 0, -2, -3],
                   [-2, 0, 1, 2, 2, 1, 0, -2],
                   [-2, 1, 2, 3, 3, 2, 1, -2],
                   [-2, 1, 2, 3, 3, 2, 1, -2],
                   [-2, 0, 1, 2, 2, 1, 0, -2],
                   [-3, -2, 0, 1, 1, 0, -2, -3],
                   [-4, -3, -2, -2, -2, -2, -3, -4]].toTensor * 10

  rook_table = [[0, 0, 0, 0, 0, 0, 0, 0],
                [1, 2, 2, 2, 2, 2, 2, 1],
                [-1, 0, 0, 0, 0, 0, 0, -1],
                [-1, 0, 0, 0, 0, 0, 0, -1],
                [-1, 0, 0, 0, 0, 0, 0, -1],
                [-1, 0, 0, 0, 0, 0, 0, -1],
                [-1, 0, 0, 0, 0, 0, 0, -1],
                [0, 0, 0, 1, 1, 0, 0, 0]].toTensor * 10

  king_table = [[0, 0, 0, 0, 0, 0, 0, 0],
                 [0, 0, 0, 0, 0, 0, 0, 0],
                 [0, 0, 0, 0, 0, 0, 0, 0],
                 [0, 0, 0, 0, 0, 0, 0, 0],
                 [0, 0, 0, 0, 0, 0, 0, 0],
                 [0, 0, 0, 0, 0, 0, 0, 0],
                 [0, 0, 0, 0, 0, 0, 0, 0],
                 [0, 0, 0, 0, 0, 0, 0, 0]].toTensor * 10 # TODO: Write this

  pawn_table = [[0, 0, 0, 0, 0, 0, 0, 0],
                 [5, 5, 5, 5, 5, 5, 5, 5],
                 [2, 2, 3, 4, 4, 3, 2, 2],
                 [1, 1, 1, 4, 4, 1, 1, 1],
                 [0, 0, 0, 3, 3, 0, 0, 0],
                 [0, -1, -1, 2, 2, -1, -1, 0],
                 [1, 1, 1, -2, -2, 1, 1, 1],
                 [0, 0, 0, 0, 0, 0, 0, 0]].toTensor * 10

  queen_table = [[-2, -1, -1, -1, -1, -1, -1, -2],
                 [-1, 0, 0, 0, 0, 0, 0, -1],
                 [-1, 1, 1, 1, 1, 1, 1, -1],
                 [-1, 0, 0, 2, 2, 0, 0, -1],
                 [-1, 0, 0, 2, 2, 0, 0, -1],
                 [-1, 1, 1, 1, 1, 1, 1, -1],
                 [-1, 0, 1, 0, 0, 1, 0, -1],
                 [-2, -1, -1, -1, -1, -1, -1, -2]].toTensor * 10

  bishop_table = [[-2, -1, -1, -1, -1, -1, -1, -2],
                 [-1, 0, 0, 0, 0, 0, 0, -1],
                 [-1, 0, 1, 2, 2, 1, 0, -1],
                 [-1, 1, 1, 2, 2, 1, 1, -1],
                 [-1, 0, 2, 2, 2, 2, 0, -1],
                 [-1, 1, 1, 1, 1, 1, 1, -1],
                 [-1, 1, 0, 0, 0, 0, 1, -1],
                 [-2, -1, -1, -1, -1, -1, -1, -2]].toTensor * 10

  value_table = {'N': knight_table, 'R': rook_table, 'K': king_table,
                 'P': pawn_table, 'Q': queen_table, 'B': bishop_table}.toTable


proc initialize_network*(name: string = "default.txt") =
  var weights_name: string
  # Searches for the most developed weights file with the current version name.
  # Since this will be sorted this will be in general in order the weights file
  # with the longest stack trace, and then among those with the same stack trace
  # the one with the most training games.
  if name == "default.txt":
    for f in walkFiles(getAppDir() / "*.txt"):
      let file_name = f.splitPath().tail
      if file_name.startsWith(base_version) and not f.endsWith("bootstrap.txt"):
        weights_name = file_name
  else:
    weights_name = name

  let weights_loc = getAppDir() / weights_name
  # Idiot proofing.
  if not fileExists(weights_loc):
    logging.error("Weights File not found!")
    logging.error(&"Attempted to load {weights_name}")
    raise newException(IOError, "Weights File not found!")

  logging.debug("Let's Plant!")
  sleep(500)
  var strm = newFileStream(weights_loc, fmRead)
  strm.load(model)
  strm.close()
  # Need to make sure we're all good on contexts
  ctx = engine.model.fc1.weight.context

  # For future reference so we know what weights file was loaded.
  logging.debug(&"Loaded weights file: {weights_name}")


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


proc handcrafted_eval*(board: Board): float =
  # Starts by summing to get the straight piece value difference
  result = float(sum(board.current_state))

  # This loops over the pieces and gets their evaluations from the piece-square
  # tables up above and adds them to the table if they're white, or subtracts
  # if they're black.
  # for piece in board.piece_list[WHITE]:
  #   result += float(value_table[piece.name][piece.pos.y, piece.pos.x])

  # for piece in board.piece_list[BLACK]:
  #   result -= float(value_table[piece.name][7 - piece.pos.y, piece.pos.x])

proc network_eval(board: Board): float =
  let x = ctx.variable(board.prep_board_for_network().reshape(1, D_in))
  # Don't want to track this forward operation for changing gradients
  no_grad_mode ctx:
    result = model.forward(x).value[0, 0]

  # Converts network output to centipawns.
  # result = arctanh(result) * 100


proc minimax_search(engine: Engine, search_board: Board, depth: int = 1,
                    alpha: float = -50000.0, beta: float = 50000.0, color: Color):
                    seq[EvalMove] =

  if (epochTime() - engine.start_time) * 1000 > engine.time_per_move:
    engine.compute = false

  # Initializes the result sequence.
  let
    min_eval = -50000.0
    max_eval = -min_eval
  result = if color == engine.color: @[("", min_eval)] else: @[("", max_eval)]

  var
    cur_alpha = alpha
    cur_beta = beta

  if depth == 0:
    engine.nodes += 1
    result[0].eval = network_eval(search_board)

    # Just in case my network exploded.
    if result[0].eval == NegInf:
      result[0].eval = min_eval
    elif result[0].eval == Inf:
        result[0].eval = max_eval
    # Flip the sign for Black moves.
    if engine.color == BLACK: result[0].eval = result[0].eval * -1
    return
  else:
    var
      moves = if depth == engine.cur_depth: engine.root_moves
              else: search_board.generate_all_moves(search_board.to_move)
      best_move: Move

    # If there are no moves then someone either got checkmated or stalemated.
    if len(moves) == 0:
      let check = search_board.is_in_check(search_board.to_move)
      # In this situation we were the ones to get checkmated (or stalemated).
      # By multiplying by depth we consider closer checkmates worse/better.
      # Regardless of whether we're black or white the val will be negative if
      # we don't want it and positive if we do.
      if search_board.to_move == engine.color or not check:
        # We need closer checkmates to be worse, so we compare depth against
        # the current depth.
        result[0].eval = -float((engine.cur_depth - depth) * 1500)
      # Otherwise we found a checkmate and we really want this
      else:
        result[0].eval = float(depth * 1500)
      return

    # Prevents bugs when we return "" if the first move is the best.
    result[0].best_move = moves[0].uci
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
      # This is required to check that the refutation is legal. We check to see
      # if the UCI is in the list of UCI, and if it is we delete the move
      # And move it up to the front.
      let index = moves.find(hit.refutation)
      # If the current depth is less than the tt one then we can use it, as
      # the tt one will be more "accurate." If we are searching a deeper
      # depth than the table, then we don't use the table, since we will
      # get a better measure of how good the move is. In this case we
      # search the previously best found refutation first.
      # We only want to do anything if the refutation move is actually legal
      if index > -1:
        if depth < hit.depth:
          # If we pull the eval out of the TT we still evaluated that node.
          engine.nodes += 1
          return @[(hit.refutation.uci, hit.eval)]
        else:
          moves.delete(index)
          moves.insert(hit.refutation)

    for m in moves:
      # Generate a new board state for move generation.
      search_board.make_move(m, skip=true)

      # Best move from the next lower ply
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
        engine.root_evals.add((m, best_lower[0].eval))

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
    # I put the things in different orders so the tabbing would be nice.
    tt[index] = Transposition(refutation: best_move, eval: result[0].eval,
                              zobrist: search_board.zobrist, score_type: "pure",
                              depth: depth)


# Sorts the root moves to put the highest evaluated one first to try and proc
# more cutoffs.
proc sort_root_moves(engine: Engine) =
  # Comparison where lower eval is ranked lower
  proc comparison(x, y: tuple[move: Move, eval: float]): int =
    if x.eval < y.eval: -1 else: 1

  engine.root_evals.sort(comparison, order=SortOrder.Descending)

  # Extracts the new sorted root moves from the sorted evals.
  engine.root_moves = engine.root_evals.map(proc(x: tuple[move: Move, eval: float]): Move = x.move)


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

    remaining_time = if engine.color == WHITE: engine.time_params["wtime"]
                     else: engine.time_params["btime"]
    increment = if engine.color == WHITE: engine.time_params["winc"]
                else: engine.time_params["binc"]

  engine.time = 0

  if engine.moves_to_go > 0:
    engine.time_per_move = float(remaining_time div engine.moves_to_go + increment)
  # In cases where a moves to go wasn't passed the engine defaults to trying
  # to fit 30 moves into that span of time. In the future this can be more
  # advanced and the number can vary over the course of the game.
  else:
    engine.time_per_move = float(remaining_time div 30 + increment)

  # We only want to calculate for 4/5 of the calculated time, to give some
  # buffer for reporting and to give us a little extra time later.
  engine.time_per_move = engine.time_per_move * (4/5)

  # If the time is less than 1 ms default to 10 seconds.
  if engine.time_per_move < 1:
    engine.time_per_move = 10 * 1000
  # This is a contingency for if we're searching for more time than is left.
  # The increment only gets added if we actually complete the move so we need
  # To finish in the time that's actually left.
  elif engine.time_per_move > float(remaining_time):
    # Search for remaining time left minus 1 second if we are searching too
    # long. If there's less than a 1.5 seconds left search for 0.5 seconds.
    if remaining_time > 1500:
      engine.time_per_move = float(remaining_time - 1000)
    else:
      engine.time_per_move = 500

  # Generates our root node moves.
  engine.root_moves = engine.board.generate_all_moves(engine.board.to_move)

  # Iterative deepening framework.
  for d in 1..max_depth:
    # If we recieve the stop command don't go any deeper just return best move.
    if not engine.compute or check_for_stop():
      break

    # Accidentally deleted these next two lines at some point, turns out without
    # them the entire engine blows up. Who knew?
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

    engine.pv = moves.map(proc(x: EvalMove): string = x.best_move).join(" ")
    let temp_eval = int(arctanh(float(result.eval)) * 100)
    send_command(&"info depth {d} seldepth {d} score cp {temp_eval} nodes {engine.nodes} nps {nps} time {engine.time} pv {engine.pv}")

    # Use the magic of iterative deepning to sort moves for more cutoffs.
    # Resort every odd ply in case we found a checkmate and need to search
    # non checkmate lines first.
    if (d mod 2) == 1:
      engine.sort_root_moves()


proc find_move*(engine: Engine): string =
  engine.color = engine.board.to_move
  let search_result = engine.search(engine.max_depth)

  if training:
      update_training_parameters(engine.board, search_result.eval, engine.pv, engine.color == BLACK)

  return search_result.best_move
