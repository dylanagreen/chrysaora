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

    # The color the engine is playing as.
    color*: Color

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
                    tuple[best_move: string, val: int] =
  # If we recieve the stop command don't go any deeper just return best move.
  if check_for_stop():
    engine.compute = false

  result.val = if color == engine.color: -50000 else: 50000

  var
    cur_alpha = alpha
    cur_beta = beta

  if depth == 0:
    result.val = engine.evaluate_move(search_board)
    # Flip the sign for Black moves.
    if engine.color == BLACK: result.val = result.val * -1
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
        result.val = -depth * 5000
      # Otherwise we found a checkmate and we really want this
      else:
        result.val = depth * 5000
      return

    for m in moves:
      echo depth, " ", m.algebraic
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
        if best_lower.val > result.val:
          result.best_move = m.algebraic
          result.val = best_lower.val

        # If we're doing alpha cut offs we're looking for the maximum on
        # this ply, so if the valuation is more than the highest we update it.
        cur_alpha = max([cur_alpha, result.val])
      else:
        if best_lower.val < result.val:
          result.best_move = m.algebraic
          result.val = best_lower.val

        # If we're doing beta cut offs we're looking for the minimum on
        # this ply, so if the valuation is less than the lowest we update it.
        cur_beta = min([cur_beta, result.val])

      # Once alpha exceeds beta, i.e. once the minimum score that
      # the engine will receieve on a node (alpha) exceeds the
      # maximum score that the engine predicts for the opponent (beta)
      if cur_alpha >= cur_beta or not engine.compute:
        return


proc find_move*(engine: Engine): string =
  engine.color = engine.board.to_move
  let search_result = engine.minimax_search(engine.board, engine.max_depth,
                                            color = engine.color)

  return search_result.best_move
