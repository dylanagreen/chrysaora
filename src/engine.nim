import logging
import os
import random
import selectors
import sequtils
import strutils
import system
import tables
import terminal

import arraymancer

import board
import bitboard
import movegen

type
  Engine* = ref object
    # An internal representation of the board.
    board*: Board

    time_params*: Table[string, int]

    # Boolean for whether or not the engine should be computing right now
    compute*: bool

    # The maximum search depth of the engine.
    max_depth*: int

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
                 [0, 0, 0, 0, 0, 0, 0, 0]].toTensor

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


proc evaluate_moves(engine: Engine, board: Board, color: Color): seq[int] =
  # Starts by summing to get the straight piece value difference
  var eval = sum(board.current_state)

  # This loops over the pieces and gets their evaluations from the piece-square
  # tables up above and adds them to the table if they're white, or subtracts
  # if they're black.
  for key, value in piece_numbers:
    var
      white_pieces = board.find_piece(WHITE, key)
      black_pieces = board.find_piece(BLACK, key)
      white_table = value_table[key] * 10

    for pos in white_pieces:
      eval += white_table[pos.y, pos.x]

    for pos in black_pieces:
      eval -= white_table[7 - pos.y, pos.x]

  result = @[eval]


proc minimax_search(engine: Engine, search_board: Board, depth: int = 1,
                    alpha: int = -10000, beta: int = 10000, color: Color):
                    tuple[best_move: string, val: int] =
  # If we recieve the stop command don't go any deeper just return best move.
  if check_for_stop():
    engine.compute = false

  let
    # The decision between if we are doing an alpha cutoff or a beta cutoff.
    cutoff_type = if color == engine.board.to_move: "alpha" else: "beta"

    moves = search_board.generate_all_moves(search_board.to_move)

  var
    cur_alpha = alpha
    cur_beta = beta

  # If there are no moves then someone either got checkmated or stalemated.
  if len(moves) == 0:
    let check = search_board.is_in_check(search_board.to_move)
    # In this situation we were the ones to get checkmated (or stalemated) so
    # set the eval to 0 cuz we really don't want this. If it's not us to move,
    # but we found a stalemate we don't want that either.
    # By multiplying by depth we consider closer checkmates worse/better
    # depending if its against us or for us.
    if search_board.to_move == engine.board.to_move or not check:
      result.val = -depth*1000
    # Otherwise we found a checkmate and we really want this
    else:
      result.val = depth*1000

    # Since for black we look for negatives we need to flip the evaluations.
    if engine.board.to_move == BLACK:
      result.val = result.val * -1
    return

  # Strips out the short algebraic moves from the sequence.
  let
    alg = moves.map(proc (x: Move): string = x.algebraic)

  # Val is the evaluation of the best possible move.
  # These are some default values, start the best_move with the first move.
  result.val = if color == engine.board.to_move: -1000 else: 1000
  result.best_move = alg[0]

  if depth == 1:
    var
      run_color = color
      mult: int = if engine.board.to_move == BLACK: -1 else: 1
      net_vals: seq[int] = @[]

    for i, m in moves:
      search_board.make_move(m)
      # The evaluations spit out by the network
      net_vals = engine.evaluate_moves(search_board, run_color)
      net_vals = net_vals.map(proc (x: int): int = x * mult)
      search_board.unmake_move()
      # J is an index, v refers to the current val.
      for j, v in net_vals:
        # Updates alpha or beta variable depending on which cutoff to use.
        if cutoff_type == "alpha":
          # If we're doing alpha cut offs we're looking for the maximum on
          # this ply, so if the valuation is more than the highest so far
          # we update it.
          if result.val < v:
            result.best_move = alg[j+i]
            result.val = v
          cur_alpha = max([cur_alpha, result.val])
        else:
          # If we're doing beta cut offs we're looking for the minimum on
          # this ply, so if the valuation is less than the lowest so far
          # we update it.
          if result.val > v:
            result.best_move = alg[j+i]
            result.val = v
          cur_beta = min([cur_beta, result.val])

        # Once alpha exceeds beta, i.e. once the minimum score that the engine
        # will receieve on a node (alpha) exceeds the maximum score that the
        # engine predicts for the opponent (beta)
        if cur_alpha >= cur_beta:
          return
  else:
    for i, m in moves:
      # Generate a new board state for move generation.
      search_board.make_move(m, skip=true)

        # Best move from the next lower ply.
      let best_lower = engine.minimax_search(search_board, depth - 1, cur_alpha,
                                             cur_beta, search_board.to_move)
      search_board.unmake_move()
      var cur_val = best_lower.val# * -1

      # Updates alpha or beta variable depending on which cutoff to use.
      if cutoff_type == "alpha":
        # If we're doing alpha cut offs we're looking for the maximum on
        # this ply, so if the valuation is more than the highest so far
        # we update it.
        if result.val < cur_val:
          result.best_move = alg[i]
          result.val = cur_val
        cur_alpha = max([cur_alpha, result.val])
      else:
        # If we're doing beta cut offs we're looking for the minimum on
        # this ply, so if the valuation is less than the lowest so far
        # we update it.
        if result.val > cur_val:
          result.best_move = alg[i]
          result.val = cur_val
        cur_beta = min([cur_beta, result.val])

      # Once alpha exceeds beta, i.e. once the minimum score that
      # the engine will receieve on a node (alpha) exceeds the
      # maximum score that the engine predicts for the opponent (beta)
      if cur_alpha >= cur_beta or not engine.compute:
        return


proc find_move*(engine: Engine): string =
  let search_result = engine.minimax_search(engine.board, engine.max_depth,
                                            color = engine.board.to_move)

  return search_result.best_move
