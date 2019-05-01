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


proc flip_y(state: Tensor[int]): Tensor[int]=
  result = ones[int]([8, 8])
  for i in 0..<state.shape[0]:
    result[7-i, 0..^1] = state[i, 0..^1]


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


proc evaluate_moves(engine: Engine, board_state: Tensor[int],
                    color: Color): seq[int] =
  var eval = sum(board_state)

  for key, value in piece_numbers:
    var
      white_pieces = board_state.find_piece(value)
      black_pieces = board_state.find_piece(-value)
      white_table = value_table[key] * 10
      black_table = white_table.flip_y()

    for pos in white_pieces:
      eval += white_table[pos.y, pos.x]

    for pos in black_pieces:
      eval -= black_table[pos.y, pos.x]

  result = @[eval]


# Bypasses making a move using board.make_move by updating the castle dict
# manually and then setting the board state to state. We can do this since all
# the moves generated are legal, so we can skip the move legality checking which
# is a major roadblock.
proc bypass_make_move(engine: Engine, old_board: Board, move: string,
                      state: Tensor[int]): Board =
  let
    to_move = if old_board.to_move == WHITE: BLACK else: WHITE
    castle_move = "O-O" in move or "0-0" in move

  var
    new_castle = deepCopy(old_board.castle_rights)
    piece = 'P'

  for i, c in move:
    # If we have an = then this is the piece the pawn promotes to.
    # Pawns can promote to rooks which would fubar the dict.
    if c.isUpperAscii() and not ('=' in move):
      piece = c

  # Updates the castle table for castling rights.
  if piece == 'K' or castle_move:
    if old_board.to_move == WHITE:
      new_castle["WKR"] = false
      new_castle["WQR"] = false
    else:
      new_castle["BKR"] = false
      new_castle["BQR"] = false
  elif piece == 'R':
    # This line of code means that this method takes approximately the same
    # length of time as make_move for Rook moves only.
    # All other moves bypass going to long algebraic.
    let long = old_board.short_algebraic_to_long_algebraic(move)
    # We can get the position the rook started from using slicing in
    # the legal move, since legal returns a long algebraic move
    # which fully disambiguates and gives us the starting square.
    # So once the rook moves then we set it to false.
    if long[1..2] == "a8":
      new_castle["BQR"] = false
    elif long[1..2] == "h8":
      new_castle["BKR"] = false
    elif long[1..2] == "a1":
      new_castle["WQR"] = false
    elif long[1..2] == "h1":
      new_castle["WKR"] = false

  result = new_board()
  result.current_state = state
  result.castle_rights = new_castle
  result.to_move = to_move


proc minimax_search(engine: Engine, search_board: Board, depth: int = 1,
                    alpha: int = -10000, beta: int = 10000, color: Color):
                    tuple[best_move: string, val: int] =
  # If we recieve the stop command don't go any deeper just return best move.
  if check_for_stop():
    engine.compute = false

  let
    # The decision between if we are doing an alpha cutoff or a beta cutoff.
    cutoff_type = if color == engine.board.to_move: "alpha" else: "beta"

    moves = search_board.generate_moves(search_board.to_move)

  var
    cur_alpha = alpha
    cur_beta = beta

  # If there are no moves then someone either got checkmated or stalemated.
  if len(moves) == 0:
    let check = search_board.current_state.is_in_check(search_board.to_move)
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
    alg = moves.map(proc (x: DisambigMove): string = x.algebraic)
    states = moves.map(proc (x: DisambigMove): Tensor[int] = x.state)

  # Val is the evaluation of the best possible move.
  # These are some default values, start the best_move with the first move.
  result.val = if color == engine.board.to_move: -1000 else: 1000
  result.best_move = alg[0]

  if depth == 1:
    var
      run_color = color
      mult: int = if engine.board.to_move == BLACK: -1 else: 1
      net_vals: seq[int] = @[]

    for i, s in states:
      # The evaluations spit out by the network
      net_vals = engine.evaluate_moves(s, run_color)
      net_vals = net_vals.map(proc (x: int): int = x * mult)
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
      let
        new_board = engine.bypass_make_move(search_board, alg[i], states[i])

        # Best move from the next lower ply.
        best_lower = engine.minimax_search(new_board, depth - 1, cur_alpha,
                                           cur_beta, new_board.to_move)

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
