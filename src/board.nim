import math
import os
import re
import sequtils
import strutils
import system
import tables
import times


import arraymancer

type
  Color* = enum
    WHITE, BLACK


  Status = enum
    IN_PROGRESS, DRAW, WHITE_VICTORY, BLACK_VICTORY


  Board* = ref object
    to_move*: Color
    half_move_clock*: int
    game_states*: seq[Tensor[int]]
    current_state*: Tensor[int]
    castle_rights*: Table[string, bool]
    move_list*: seq[string]
    status*: Status
    headers*: Table[string, string]

    # A square behind a pawn that moves two, i.e. the square a pawn taking
    # en passant would end on.
    ep_square*: Table[Color, string]

    # Whether every move should return the long algebraic regardles of whether
    # it needs to or not. This helps when checking en passant and rook
    # moves for updating the castling dict as we can short circuit and avoid
    # finding the long algebraic form.
    long*: bool


  # Custom Position type.
  Position* = tuple[y, x: int]

  # Custom move list types
  DisambigMove* = tuple[algebraic: string, state: Tensor[int]]
  ShortAndLongMove* = tuple[short: string, long: string, state: Tensor[int]]


# The piece number -> piece name table.
const
  # These values are centipawn versions of values taken from "Beginner's Guide
  # to Winning Chess" the book that basically taught me all  my chess skills.
  piece_names* = {100: 'P', 500: 'R', 310: 'N', 300: 'B', 900: 'Q', 1000: 'K'}.toTable

var temp: seq[tuple[key: char, val: int]] = @[]
for key, value in piece_names:
  temp.add((value, key))

let
  # The lowercase ascii alphabet.
  ascii_lowercase* = toSeq 'a'..'z'

  # Table of algebraic squares.
  alg_table = @[["a8", "b8", "c8", "d8", "e8", "f8", "g8", "h8"],
                ["a7", "b7", "c7", "d7", "e7", "f7", "g7", "h7"],
                ["a6", "b6", "c6", "d6", "e6", "f6", "g6", "h6"],
                ["a5", "b5", "c5", "d5", "e5", "f5", "g5", "h5"],
                ["a4", "b4", "c4", "d4", "e4", "f4", "g4", "h4"],
                ["a3", "b3", "c3", "d3", "e3", "f3", "g3", "h3"],
                ["a2", "b2", "c2", "d2", "e2", "f2", "g2", "h2"],
                ["a1", "b1", "c1", "d1", "e1", "f1", "g1", "h1"]].toTensor

  flat_alg_table = alg_table.reshape(64)

  # The reverse piece name -> piece number table.
  piece_numbers* = temp.toTable

  # Regular expressions for finding strings in algebraic moves.
  loc_finder* = re"[a-h]\d+"
  rank_finder = re"\d+"
  file_finder = re"[a-h]"
  piece_finder = re"[PRNQKB]"
  illegal_piece_finder = re"[A-Z]"

# Forward declarations for use of this later.
proc new_board*(): Board
proc new_board*(start_board: Tensor[int]): Board

# Finds the piece in the board state.
proc find_piece*(state: Tensor[int], piece: int): seq[Position] =
  # Loop through and find the required piece Positions.
  for coords, piece_num in state:
    if piece_num == piece:
      result.add((coords[0], coords[1]))


# Convert the row and column Positions to an algebraic chess move.
# Use open arrays here since finish or start may be passed as a fixed length
# array or as a sequence as created by find_piece.
proc row_column_to_algebraic*(board: Board, start: Position, finish: Position,
                             piece: int, promotion: int = 0):
                             tuple[short: string, long: string] =
  var
    alg1: string = ""
    alg2: string = ""

  # Adds the piece for non pawn moves.
  if abs(piece) > piece_numbers['P']:
    alg2.add(piece_names[abs(piece)])

  # Add the starting Position to the fully disambiguated move.
  alg2.add(alg_table[start.y, start.x])

  # The x for captures
  if board.current_state[finish.y, finish.x] != 0:
    alg2.add("x")

  # We here append the ending Position to the move.
  alg2.add(alg_table[finish.y, finish.x])

  if promotion != 0:
    alg2.add("=")
    alg2.add(piece_names[abs(promotion)])

  if piece == piece_numbers['P']:
    if 'x' in alg2:
      alg1 = alg2[0] & alg2[2..^1]
    else:
      alg1 = alg2[2..^1]
  else:
    alg1 = alg2[0] & alg2[3..^1]

  result = (alg1, alg2)


proc long_algebraic_to_board_state*(board: Board, move: string): Tensor[int] =
  result = clone(board.current_state)

  var piece: char = 'P'       # Default to pawn, this generally is changed.
  for i, c in move:
    # A [piece] character
    # If we have an = then this is the piece the pawn promotes to.
    if c.isUpperAscii():
      piece = c

  # Uses regex to find the rank/file combinations.
  let locs = findAll(move, loc_finder)

  # Gets the starting Position and puts into a constant
  var
    dest = locs[0]
    file = ascii_lowercase.find(dest[0]) # File = x
    rank = 8 - parseInt($dest[1]) # Rank = y

  let start: Position = (rank, file)

  # Gets the ending Position.
  dest = locs[1]
  file = ascii_lowercase.find(dest[0]) # File = x
  rank = 8 - parseInt($dest[1]) # Rank = y

  let finish: Position = (rank, file)

  # Gets the value of the piece that's moving.
  var end_piece: int = board.current_state[start.y, start.x]

  # In case of promotions we want the pice to change upon moving.
  if "=" in move:
    end_piece = piece_numbers[piece] * sgn(end_piece)

  result[start.y, start.x] = 0
  result[finish.y, finish.x] = end_piece

  # Turns the pawn that gets taken en passant to 0. This pawn is on the
  # same rank as the pawn moving, and the same file as where the pawn ends.
  if "e.p." in move:
    result[start.y, finish.x] = 0


proc castle_algebraic_to_board_state(board: Board, move: string,
                                     color: Color): Tensor[int] =
  result = clone(board.current_state)

  var
    # Piece numbers for placing.
    king_num = piece_numbers['K']
    rook_num = piece_numbers['R']

  # The rank that the king and rook are on.
  let rank = if color == WHITE: 7 else: 0

  # Flips the piece to negative if we're castling for black.
  if not (color == WHITE):
    king_num = king_num * -1
    rook_num = rook_num * -1

  # Kingside castling
  if move == "O-O" or move == "0-0":
    result[rank, 7] = 0       # The rook
    result[rank, 4] = 0       # The king
    result[rank, 6] = king_num
    result[rank, 5] = rook_num

  # Queenside castling
  elif move == "O-O-O" or move == "0-0-0":
    result[rank, 0] = 0       # The rook
    result[rank, 4] = 0       # The king
    result[rank, 2] = king_num
    result[rank, 3] = rook_num


proc can_make_move(board: Board, start: Position, fin: Position,
                   piece: char): bool =
  var
    mult = if board.to_move == WHITE: 1 else: -1
    state = clone(board.current_state * mult)

  if piece == 'P':
    var
      # Direction opposite that which the color's pawns move.
      # So 1 is downwards, opposite White's pawns going upwards.
      d = if board.to_move == WHITE: -1 else: 1

      opp_color = if board.to_move == WHITE: BLACK else: WHITE

      # The starting file for the pawn row, for double move checking
      pawn_start = if board.to_move == WHITE: 6 else: 1

      # The file the pawn needs to be on to take en passant.
      ep_file = if board.to_move == WHITE: 3 else: 4

      # Ensures that this pawn would actually have to move forward and not
      # backward to get to the ending square. This is true if the pawn
      # moves backwards.
      direc = if board.to_move == WHITE: start.y < fin.y
              else: start.y > fin.y

    if direc:
      return

    # First check where the ending Position is empty
    # Second condition is that the pawn is on the same rank
    if start.x == fin.x and state[fin.y, fin.x] == 0:
      # If this pawn can move forward 1 and end on the end it's good.
      if start.y + d == fin.y:
        return true

      # Need to check the space between one move and two is empty.
      var empty = state[start.y + d, fin.x] == 0
      if start.y + 2 * d == fin.y and start.y == pawn_start and empty:
        return true

    # This is the case for where the ending state isn't empty, which
    # means that the pawn needs to travel diagonally to take this piece.
    if state[fin.y, fin.x] < 0:
      let
        take_left = start.y + d == fin.y and start.x - 1 == fin.x
        take_right = start.y + d == fin.y and start.x + 1 == fin.x

      if take_left or take_right:
        return true

    if start.y == epfile:
      if alg_table[fin.y, fin.x] == board.ep_square[opp_color]:
        return true

  elif piece == 'N':
    var
      slope: Position = (abs(fin.y - start.y), abs(fin.x - start.x))

    # Avoids a divide by 0 error. If it's on the same rank or file
    # the knight can't get the king anyway.
    if slope.x == 0 or slope.y == 0:
      return
    if slope == (1, 2) or slope == (2, 1):
      return true

  elif piece == 'R' or piece == 'Q':
    # If we only move one space then we found the piece already.
    if start.y == fin.y and abs(start.x - fin.x) == 1:
      return true
    elif start.x == fin.x and abs(start.y - fin.y) == 1:
      return true
    else:
      # The slide a start would have to take to get to the end.
      var slide = @[0].toTensor

      if start.y == fin.y:
        # Slides from the start to the fin, left to right.
        if start.x < fin.x:
          slide = state[fin.y, start.x + 1 ..< fin.x]
        # Slides from the fin to the start, left to right.
        else:
          slide = state[fin.y, fin.x + 1 ..< start.x]
        slide = abs(slide)
        if sum(slide) == 0:
          return true

      if start.x == fin.x:
        # Slides from the start to the fin, top down.
        if start.y < fin.y:
          slide = state[start.y + 1 ..< fin.y, fin.x]
        # Slides from the fin to the start, top down.
        else:
          slide = state[fin.y + 1 ..< start.y, fin.x]
        slide = abs(slide)
        if sum(slide) == 0:
          return true

  if piece == 'B' or piece == 'Q':
    # First we check that the piece is even on a diagonal from the fin.
    # The following code finds the absolute value of the slope as well
    # as the slope value from the start to the fin.
    var
      slope: tuple[y, x: float] = (float(start.y - fin.y),
                                   float(start.x - fin.x))
      abs_slope: tuple[y, x: float] = (abs(slope.y), abs(slope.x))
      max = max([abs_slope.y, abs_slope.x])

    slope = (slope[0] / max, slope[1] / max)
    abs_slope = (abs_slope[0] / max, abs_slope[1] / max)

    # If the absolute slope is 1,1 then it's a diagonal.
    if abs_slope.x == 1.0 and abs_slope.y == 1.0:
      var cur_pos: Position = start
      # Now we have to check that the space between the two is empty.
      for i in 1..7:
        cur_pos = (fin.y + i * int(slope.y), fin.x + i * int(slope.x))

        if not (state[cur_pos.y, cur_pos.x] == 0):
          break
      # This will execute if the Position that caused the for loop to
      # break is the start itboard, otherwise this does not execute.
      # Or the queen. Same thing.
      if cur_pos == start:
        return true

  if piece == 'K':
    let diff = [abs(start.y - fin.y), abs(start.x - fin.x)]
    if sum(diff) == 1 or diff == [1, 1]:
      return true


proc is_in_check*(state: Tensor[int], color: Color): bool =
  let
    # The direction a pawn must travel to take this color's king.
    # I.e. Black pawns must travel in the positive y (downward) direction
    # To take a white king.
    d = if color == WHITE: 1 else: -1

    # Color flipping for black instead of white.
    mult = if color == WHITE: -1 else: 1

    # The king's number
    king_num = if color == WHITE: piece_numbers['K']
               else: -piece_numbers['K']
    # Check pawns first because they're the easiest.
    pawn_num = if color == WHITE: -piece_numbers['P']
               else: piece_numbers['P']

    # For this I'll assume there's only one king.
    king = state.find_piece(king_num)[0]

  # Need to ensure that the king is on any rank but the last one.
  # No pawns can put you in check in the last rank anyway.
  if king.y - d in 0..7:
    if king.x - 1 >= 0 and state[king.y - d, king.x - 1] == pawn_num:
      return true
    elif king.x + 1 < 8 and state[king.y - d, king.x + 1] == pawn_num:
      return true

  for key, val in piece_names:
    # We already did pawns, don't need overkill checking for those.
    if val == 'P': continue

    var attackers = find_piece(state*mult, key)
    for pos in attackers:
      if can_make_move(new_board(state), pos, king, val):
        return true


proc short_algebraic_to_long_algebraic*(board: Board, move: string): string =
  var new_move = move
  # A move is minimum two characters (a rank and a file for pawns)
  # so if it's shorter it's not a good move.
  if len(move) < 2:
    return

  # You're not allowed to castle out of check.
  var check = board.current_state.is_in_check(board.to_move)
  if ("O-O" in move or "0-0" in move) and check:
    return

  # Slices off the checkmate character for parsing. This is largely so that
  # castling into putting the opponent in check parses correctly.
  if move.endsWith('+') or move.endsWith('#'):
    new_move = new_move[0 ..< ^1]

  # Castling is the easiest to check for legality.
  let
    # The rank the king is on.
    king_rank = if board.to_move == WHITE: 7 else: 0

    # The king's number representation
    king_num = if board.to_move == WHITE: piece_numbers['K']
               else: -piece_numbers['K']

  # Kingside castling
  if new_move == "O-O" or new_move == "0-0":
    var
      check_side = if board.to_move == WHITE: "WKR" else: "BKR"
      # The two spaces between the king and rook.
      between = board.current_state[king_rank, 5..6]

    if board.castle_rights[check_side] and sum(abs(between)) == 0:
      # Need to check that we don't castle through check here.
      var new_state = clone(board.current_state)
      new_state[king_rank, 4] = 0
      new_state[king_rank, 5] = king_num

      check = new_state.is_in_check(board.to_move)
      if not check:
        return new_move
      else:
        return
    else:
      return
  # Queenside castling
  elif new_move == "O-O-O" or new_move == "0-0-0":
    var
      check_side = if board.to_move == WHITE: "WQR" else: "BQR"
      # The three spaces between the king and rook.
      between = board.current_state[king_rank, 1..3]

    if board.castle_rights[check_side] and sum(abs(between)) == 0:
      # Need to check that we don't castle through check here.
      var new_state = clone(board.current_state)
      new_state[king_rank, 4] = 0
      new_state[king_rank, 3] = king_num

      check = new_state.is_in_check(board.to_move)
      if not check:
        return new_move
      else:
        return
    else:
      return

  # Use regex to extract the Positions as well as the singular ranks
  # and files and the pieces (for finding the piece and pawn promotion)
  let
    locs = findAll(move, loc_finder)
    ranks = findAll(move, rank_finder)
    files = findAll(move, file_finder)
    pieces = findAll(move, piece_finder)
    illegal_piece = findAll(move, illegal_piece_finder)

  # If you passed too few or too many locations bail
  if len(locs) == 0 or len(locs) >= 3:
    return

  # If you didn't pass a valid piece then bail
  if len(pieces) == 0 and len(illegal_piece) > 0:
    return

  # Disallows promotions to pawns or kings.
  if ("P" in pieces or "K" in pieces) and '=' in new_move:
    return

  # Ensures your move stays within the 8 ranks of the board.
  for r in ranks:
    if not (parseInt(r) in 1..8):
      return

  # Gets the ending Position and puts into a constant
  var
    dest = locs[^1]
    file = ascii_lowercase.find(dest[0]) # File = x
    rank = 8 - parseInt($dest[1]) # Rank = y

  let fin: Position = (rank, file)

  # Defults everything to pawn.
  var
    mult = if board.to_move == WHITE: 1 else: -1
    piece_char = 'P'
    piece_num = piece_numbers['P'] * mult
    promotion_char = 'P'
    promotion_piece = piece_numbers['P'] * mult

  # If a piece was passed in we set the piece_char to that piece.
  if len(pieces) > 0 and not ('=' in new_move):
    piece_char = pieces[0][0]
  elif len(pieces) > 0 and '=' in new_move:
    promotion_char = pieces[^1][0]

  # Puts the found piece number into either piece_num or promotion_piece
  # Depending what piece is moving.
  if '=' in new_move:
    promotion_piece = piece_numbers[promotion_char] * mult
  else:
    piece_num = piece_numbers[piece_char] * mult

  var found_pieces = board.current_state.find_piece(piece_num)

  # If we have any sort of disambiguation use that as our starting point.
  # This allows us to trim the pieces we search through and find the
  # correct correct one rather than the "first one allowed to make this move."
  var start: Position = (-1, -1)

  if len(locs) == 2:
    dest = locs[0]
    start.x = ascii_lowercase.find(dest[0]) # File = x
    start.y = 8 - parseInt($dest[1]) # Rank = y
  elif len(files) == 2:
    start.x = ascii_lowercase.find(files[0][0])
  elif len(ranks) == 2:
    start.y = 8 - parseInt($ranks[0])

  # This trims the list of found pieces only down to the pieces that could
  # make this move according to disamgibuation.
  if start != (-1, -1):
    var good: seq[Position] = @[]
    for loc in found_pieces:
      # File disambiguation
      if start.y == -1 and loc.x == start.x:
        good.add(loc)
      # Rank disambiguation
      elif start.x == -1 and loc.y == start.y:
        good.add(loc)
      # Full disambiguation
      elif loc == start:
        good.add(loc)

    found_pieces = good

  var
    # Direction opposite that which the color's pawns move.
    # So 1 is downwards, opposite White's pawns going upwards.
    d = if board.to_move == WHITE: -1 else: 1

    # The file the pawn needs to be on to take en passant.
    ep_file = if board.to_move == WHITE: 3 else: 4

    # The ending rank for pawn promotion
    pawn_end = if board.to_move == WHITE: 0 else: 7

    state = clone(board.current_state * mult)

  # This requires that the pawn promote upon reaching the end.
  if piece_char == 'P' and fin.y == pawn_end and not ('=' in new_move):
    return

  # This handy line of code prevents you from taking your own pieces.
  if state[fin.y, fin.x] > 0:
    return

  # An inner proc to remove code duplication that checks if moving the piece
  # would end with you in check. This exists in case you try to move a piece
  # that's pinned.
  proc good_move(start: Position, fin: Position, piece_num: int,
                 ep: bool = false): bool =
    var s = clone(board.current_state)
    s[start.y, start.x] = 0
    s[fin.y, fin.x] = piece_num

    if ep:
      s[start.y, fin.x] = 0

    result = not s.is_in_check(board.to_move)
    return

  for pos in found_pieces:
    var ep = false
    var promotion: bool = fin.y == pawn_end and piece_char == 'P'
    # Checks if we need to add en passant to the move.
    if piece_char == 'P' and pos.y == ep_file:
      # Bools check that we are adjacent to a pawn of the opposite color which
      # is a requirement of en_passant.
      let
        opposite_pawn = if board.to_move == WHITE: -piece_numbers['P']
                        else: piece_numbers['P']
        ep_left = pos.x == fin.x - 1 and
                  board.current_state[pos.y, fin.x] == opposite_pawn
        ep_right = pos.x == fin.x + 1 and
                   board.current_state[pos.y, fin.x] == opposite_pawn

        # Makes sure the ending far enough from the edge for a good en passant.
        good_end = fin.y in 1..6

      # Can't en passant on turn 1 (or anything less than turn 3 I think)
      # so if you got this far it's not a legal pawn move.
      if len(board.game_states) > 1:
        let previous_state = clone(board.game_states[^1])
        if (ep_left or ep_right) and state[fin.y, fin.x] == 0:
          # Checks that in the previous state the pawn actually
          # moved two spaces. This prevents trying an en passant
          # move three moves after the pawn moved.
          if good_end and previous_state[fin.y + d, fin.x] == opposite_pawn:
            ep = true
    let
      can_make = can_make_move(board, pos, fin, piece_char)
      no_check = good_move(pos, fin, piece_num, ep)

    if can_make and no_check:
      if promotion:
        result = board.row_column_to_algebraic(pos, fin, piece_num,
                                               promotion_piece)[1]
      else:
        result = board.row_column_to_algebraic(pos, fin, piece_num)[1]
      if ep:
        result = result & "e.p."
      return


proc check_move_legality*(board: Board, move: string):
                          tuple[legal: bool, alg: string] =
  # Tries to get the long version of the move. If there is not piece that could
  # make thismove the long_move is going to be the empty string.
  let long_move = board.short_algebraic_to_long_algebraic(move)
  if long_move == "":
    return

  var check: bool

  # Only need to check if you castle into check since short_algebraic_to_long
  # already checks to see if the move ends in check and if it does it returns
  # "".  Doesn't check castling ending in check, however, hence why this
  # is here. Castling shortcuts in short_algebraic.
  if "O-O" in long_move or "0-0" in long_move:
    var end_state = board.castle_algebraic_to_boardstate(long_move,
                                                         board.to_move)
    check = end_state.is_in_check(board.to_move)

  if check:
    return

  result = (true, long_move)


proc remove_moves_in_check(board: Board, moves: openArray[ShortAndLongMove],
                           color: Color): seq[DisambigMove] =
  # Shortcut for if there's no possible moves being disambiguated.
  if len(moves) == 0:
    return

  # Strips out the short algebraic moves from the sequence.
  let all_short = moves.map(proc (x: ShortAndLongMove): string = x.short)

  # Loop through the move/board state sequence.
  for i, m in moves:
    var check = m[2].is_in_check(color)

    if not check:
      # If the number of times that the short moves appears is more than 1 we
      # want to append the long move.
      if all_short.count(m[0]) > 1 or board.long:
        result.add((m[1], m[2]))
      else:
        result.add((m[0], m[2]))


# I hate pawns.
proc generate_pawn_moves*(board: Board, color: Color): seq[DisambigMove] =
  let
    # Color flipping for black instead of white.
    mult = if color == WHITE: 1 else: -1

    # Opposite color for ep
    opp_color = if color == WHITE: BLACK else: WHITE

    # Direction of travel, reverse for black and white. Positive is going
    # downwards, negative is going upwards.
    d = -1 * mult
    state = board.current_state * mult

    # Find the pawns
    pawn_num = piece_numbers['P']
    pawns = state.find_piece(pawn_num)

    # The ending file for pawn promotions
    endfile = if color == WHITE: 0 else: 7
    # The starting file for moving two spaces
    startfile = if color == WHITE: 6 else: 1

    # File to be on for en passant
    epfile = if color == WHITE: 3 else: 4

  var
    # The ending Position, this will change throughout the method.
    fin: Position = (0, 0)

    # End_states will be a sequence of tuples returned by row_column_to_algebraic
    end_states: seq[tuple[short: string, long: string]] = @[]

  for pos in pawns:
    # En Passant first since we can take En Passant if there is a piece
    # directly in front of our pawn.
    if pos.y == epfile:
      fin = (pos.y + d, 0)
      # Check the two diagonals.
      for x in [pos.x + 1, pos.x - 1]:
        fin.x = x
        if alg_table[fin.y, fin.x] == board.ep_square[opp_color]:
          var temp_move = board.row_column_to_algebraic(pos, fin, pawn_num)
          temp_move.long  = temp_move.long & "e.p."
          end_states.add(temp_move)

    # Makes sure the space in front of us is clear
    if state[pos.y + d, pos.x] == 0:
      # Pawn promotion
      # We do this first because pawns have to promote so we can't
      # just "move one forward" in this Position
      if pos.y + d == endfile:
        for key, val in piece_numbers:
          if not (key == 'P') and not (key == 'K'):
            fin = (pos.y + d, pos.x)
            end_states.add(board.row_column_to_algebraic(pos, fin,
                                                         pawn_num, val))
      else:
        # Add one move forward
        fin = (pos.y + d, pos.x)
        end_states.add(board.row_column_to_algebraic(pos, fin, pawn_num))
      # This is for moving two forward. Ensures that the space 2 ahead is clear
      if pos.y == startfile and state[pos.y + 2 * d, pos.x] == 0:
        fin = (pos.y + 2 * d, pos.x)
        end_states.add(board.row_column_to_algebraic(pos, fin, pawn_num))

    # Takes to the left
    # First condition ensures that we remain within the bounds of the board.
    if pos.x - 1 > -1 and state[pos.y + d, pos.x - 1] < 0:
      fin = (pos.y + d, pos.x - 1)

      # Promotion upon taking
      if pos.y + d == endfile:
        for key, val in piece_numbers:
          if not (key == 'P') and not (key == 'K'):
            end_states.add(board.row_column_to_algebraic(pos, fin,
                                                         pawn_num, val))
      else:
        end_states.add(board.row_column_to_algebraic(pos, fin, pawn_num))

    # Takes to the right
    # First condition ensures that we remain within the bounds of the board.
    if pos.x + 1 < 8 and state[pos.y + d, pos.x + 1] < 0:
      fin = (pos.y + d, pos.x + 1)

      # Promotion upon taking
      if pos.y + d == endfile:
        for key, val in piece_numbers:
          if not (key == 'P') and not (key == 'K'):
            end_states.add(board.row_column_to_algebraic(pos, fin,
                                                         pawn_num, val))
      else:
        end_states.add(board.row_column_to_algebraic(pos, fin, pawn_num))

  # Build a sequence of new_states that will get pruned by remove_moves_in_check
  var new_states: seq[ShortAndLongMove] = @[]
  for i, move in end_states:
    var s = board.long_algebraic_to_boardstate(move[1])
    new_states.add((move[0], move[1], s))

  # Removes the illegal moves that leave you in check.
  result = board.remove_moves_in_check(new_states, color)


proc generate_knight_moves*(board: Board, color: Color): seq[DisambigMove] =
  let
    # Color flipping for black instead of white.
    mult = if color == WHITE: 1 else: -1
    state = board.current_state * mult

    # All possible knight moves, ignore flips.
    moves: array[4, Position] = [(2, 1), (2, -1), (-2, 1), (-2, -1)]
    # Find the knights
    knight_num = piece_numbers['N']
    knights = state.find_piece(knight_num)

  var
    # End_states will be a sequence of tuples returned by row_column_to_algebraic
    end_states: seq[tuple[short: string, long: string]] = @[]

  for pos in knights:
    for m in moves:
      var
        end1: Position = (pos.y + m.y, pos.x + m.x)
        end2: Position = (pos.y + m.x, pos.x + m.y) # Flip m

        # Boolean conditions to ensure ending is within the bounds of the board.
        legal1: bool = end1.x in 0..7 and end1.y in 0..7
        legal2: bool = end2.x in 0..7 and end2.y in 0..7

      # This adds to the condition that the end square must not be occupied by
      # a piece of the same color. Since white is always >0 we require the end
      # square to be empty (==0) or occupied by black (<0)
      legal1 = legal1 and state[end1.y, end1.x] <= 0
      legal2 = legal2 and state[end2.y, end2.x] <= 0

      # The following code blocks only run if the ending Positions are actually
      # on the board.
      if legal1:
        end_states.add(board.row_column_to_algebraic(pos, end1, knight_num))

      if legal2:
        end_states.add(board.row_column_to_algebraic(pos, end2, knight_num))

  # Build a sequence of new_states that will get pruned by remove_moves_in_check
  var new_states: seq[ShortAndLongMove] = @[]
  for i, move in end_states:
    var s = board.long_algebraic_to_boardstate(move[1])
    new_states.add((move[0], move[1], s))

  # Removes the illegal moves that leave you in check.
  result = board.remove_moves_in_check(new_states, color)


proc generate_straight_moves(board: Board, color: Color, starts: seq[Position],
                             queen: bool = false): seq[ShortAndLongMove] =
  let
    # Color flipping for black instead of white.
    mult = if color == WHITE: 1 else: -1
    state = board.current_state * mult

    # Get the piece num for the algebraic move.
    piece_num = if queen: piece_numbers['Q'] else: piece_numbers['R']

  var
    # End_states will be a sequence of tuples returned by row_column_to_algebraic
    end_states: seq[tuple[short: string, long: string]] = @[]

    # The ending Position, this will change throughout the method.
    fin: Position = (0, 0)

  # We here loop through each rook starting Position.
  for pos in starts:
    # Loop through the two possible axes
    for axis in ['x', 'y']:
      # Loop through the two possible directions along each axis
      for dir in [-1, 1]:
        # This loops outward until the loop hits another piece that isn't the
        # piece we started with.
        for i in 1..7:
          # The two x directions.
          if axis == 'x':
            fin = (pos.y, pos.x + i * dir)
          # The two y directions.
          else:
            fin = (pos.y + i * dir, pos.x)

          # If this happens we went outside the bounds of the board.
          if not (fin.y in 0..7) or not (fin.x in 0..7):
            break

          # This is the break for if we get blocked by a piece of our own color
          if state[fin.y, fin.x] > 0:
            break
          # If the end piece is of the opposite color we can take it, but then
          # we break since we can't go beyond it.
          elif state[fin.y, fin.x] < 0:
            end_states.add(board.row_column_to_algebraic(pos, fin, piece_num))
            break
          else:
            end_states.add(board.row_column_to_algebraic(pos, fin, piece_num))

  # Build a sequence of new_states that will get pruned by remove_moves_in_check
  for i, move in end_states:
    var s = board.long_algebraic_to_boardstate(move[1])
    result.add((move[0], move[1], s))


proc generate_rook_moves*(board: Board, color: Color): seq[DisambigMove] =
  let
    # Color flipping for black instead of white.
    mult = if color == WHITE: 1 else: -1
    state = board.current_state * mult

    # Find the rooks
    rook_num = piece_numbers['R']
    rooks = state.find_piece(rook_num)
    new_states = generate_straight_moves(board, color, rooks, queen = false)

  result = board.remove_moves_in_check(new_states, color)


proc generate_diagonal_moves(board: Board, color: Color, starts: seq[Position],
                             queen: bool = false): seq[ShortAndLongMove] =
  let
    # Color flipping for black instead of white.
    mult = if color == WHITE: 1 else: -1
    state = board.current_state * mult

    # Get the piece num for the algebraic move.
    piece_num = if queen: piece_numbers['Q'] else: piece_numbers['B']

  var
    # End_states will be a sequence of tuples returned by row_column_to_algebraic
    end_states: seq[tuple[short: string, long: string]] = @[]

    # The ending Position, this will change throughout the method.
    fin: Position = (0, 0)

  for pos in starts:
    # We loop through the x and y dirs here since bishops move diagonally
    # so we need directions like [1, 1] and [-1, -1] etc.
    for xdir in [-1, 1]:
      for ydir in [-1, 1]:
        # Start at 1 since 0 represents the Position the bishop is at.
        for i in 1..7:
          fin = (pos.y + ydir * i, pos.x + xdir * i)

          # If this happens we went outside the bounds of the board.
          if not (fin.y in 0..7) or not (fin.x in 0..7):
            break

          # This is the break for if we get blocked by a piece of our own color
          if state[fin.y, fin.x] > 0:
            break
          # If the end piece is of the opposite color we can take it, but then
          # we break since we can't go beyond it.
          elif state[fin.y, fin.x] < 0:
            end_states.add(board.row_column_to_algebraic(pos, fin, piece_num))
            break
          else:
            end_states.add(board.row_column_to_algebraic(pos, fin, piece_num))

  # Build a sequence of new_states that will get pruned by remove_moves_in_check
  for i, move in end_states:
    var s = board.long_algebraic_to_boardstate(move[1])
    result.add((move[0], move[1], s))


proc generate_bishop_moves*(board: Board, color: Color): seq[DisambigMove] =
  let
    # Color flipping for black instead of white.
    mult = if color == WHITE: 1 else: -1
    state = board.current_state * mult

    # Find the rooks
    bishop_num = piece_numbers['B']
    bishops = state.find_piece(bishop_num)
    new_states = generate_diagonal_moves(board, color, bishops, queen = false)

  result = board.remove_moves_in_check(new_states, color)


proc generate_queen_moves*(board: Board, color: Color): seq[DisambigMove] =
  let
    # Color flipping for black instead of white.
    mult = if color == WHITE: 1 else: -1
    state = board.current_state * mult

    # Find the rooks
    queen_num = piece_numbers['Q']
    queens = state.find_piece(queen_num)

    diags = generate_diagonal_moves(board, color, queens, queen = true)
    straights = generate_straight_moves(board, color, queens, queen = true)

    new_states = concat(diags, straights)

  result = board.remove_moves_in_check(new_states, color)


proc generate_king_moves*(board: Board, color: Color): seq[DisambigMove] =
  let
    # Color flipping for black instead of white.
    mult = if color == WHITE: 1 else: -1
    state = board.current_state * mult

    # Find the kings
    king_num = piece_numbers['K']
    kings = state.find_piece(king_num)

    # All possible king moves
    moves: array[8, Position] = [(-1, -1), (-1, 0), (-1, 1), (0, -1),
                                (0, 1), (1, -1), (1, 0), (1, 1)]

  var
    # End_states will be a sequence of tuples returned by row_column_to_algebraic
    end_states: seq[tuple[short: string, long: string]] = @[]

  for pos in kings:
    for m in moves:
      var fin: Position = (pos.y + m.y, pos.x + m.x)

      # Ensures that the ending Position is inside the board and that we
      # don't try to take our own piece.
      if fin.x in 0..7 and fin.y in 0..7 and state[fin.y, fin.x] <= 0:
        end_states.add(board.row_column_to_algebraic(pos, fin, king_num))

  # Build a sequence of new_states that will get pruned by remove_moves_in_check
  var new_states: seq[ShortAndLongMove] = @[]
  for i, move in end_states:
    var s = board.long_algebraic_to_boardstate(move[1])
    new_states.add((move[0], move[1], s))

  # Removes the illegal moves that leave you in check.
  result = board.remove_moves_in_check(new_states, color)


proc generate_castle_moves*(board: Board, color: Color): seq[DisambigMove] =
  # Hardcoded because you can only castle from starting Positions.
  # Basically just need to check that the files between the king and
  # the rook are clear, then return the castling algebraic (O-O or O-O-O)
  let
    # The rank that castling takes place on.
    rank = if color == WHITE: 7 else: 0

    # The king's number on the board.
    king_num = if color == WHITE: piece_numbers['K']
               else: -1 * piece_numbers['K']

    # Key values to check in the castling table for castling rights.
    kingside = if color == WHITE: "WKR" else: "BKR"
    queenside = if color == WHITE: "WQR" else: "BQR"

  var
    # End_states will be a sequence of castling strings
    end_states: seq[string] = @[]

    # Slice representing the two spaces between the king and the kingside rook.
    between = board.current_state[rank, 5..6]

  # You're not allowed to castle out of check so if you're in check
  # don't generate it as a legal move.
  if board.current_state.is_in_check(color):
    return

  if board.castle_rights[kingside] and sum(abs(between)) == 0:
    # Before we go ahead and append the move is legal we need to verify
    # that we don't castle through check. Since we remove moves
    # that end in check, and the king moves two during castling,
    # it is sufficient therefore to simply check that moving the king
    # one space in the kingside direction doesn't put us in check.
    var s = clone(board.current_state)
    s[rank, 4] = 0
    s[rank, 5] = king_num

    if not s.is_in_check(color):
      end_states.add("O-O")

  # Slice representing the two spaces between the king and the queenside rook.
  between = board.current_state[rank, 1..3]
  if board.castle_rights[queenside] and sum(abs(between)) == 0:
    # See reasoning above in kingside.
    var s = clone(board.current_state)
    s[rank, 4] = 0
    s[rank, 3] = king_num

    if not s.is_in_check(color):
      end_states.add("O-O-O")

  # Build a sequence of new_states that will get pruned by remove_moves_in_check
  var new_states: seq[ShortAndLongMove] = @[]
  for i, move in end_states:
    var s = board.castle_algebraic_to_boardstate(move, board.to_move)
    new_states.add((move, move, s))

  # Removes the illegal moves that leave you in check.
  result = board.remove_moves_in_check(new_states, color)


proc generate_moves*(board: Board, color: Color): seq[DisambigMove] =
  let
    pawns = board.generate_pawn_moves(color)
    knights = board.generate_knight_moves(color)
    rooks = board.generate_rook_moves(color)
    bishops = board.generate_bishop_moves(color)
    queens = board.generate_queen_moves(color)
    kings = board.generate_king_moves(color)
    castling = board.generate_castle_moves(color)

  result = concat(castling, queens, rooks, bishops, knights, pawns, kings)


proc is_checkmate*(state: Tensor[int], color: Color): bool =
  let check = state.is_in_check(color)

  # Result is auto instantiated to false.
  if not check:
    return

  # Check if there are any possible moves tat could get color out of check.
  let
    response_board = new_board(state)
    responses = response_board.generate_moves(color)

  if len(responses) == 0:
    result = true


proc update_ep_square(board: Board, move: DisambigMove) =
  let
    loc = move.algebraic[^2..^1]
    state = board.current_state.reshape(64)
    #ranks = findAll(move.algebraic, rank_finder)

  var square = if board.to_move == WHITE: flat_alg_table.find(loc) + 8
               else: flat_alg_table.find(loc) - 8

  if square > -1 and square  < 64 and state[square] == 0:
    board.ep_square[board.to_move] = flat_alg_table[square]


template check_for_moves(moves: seq[DisambigMove]): void=
  if len(moves) > 0:
    noresponses = false
    break movechecking


# Make move does not do any legality checking, but simply updates castling
# rights and sets the board state to the new one. Engine boolean is if this
# is called from the engine, in which case we skip status updating for now.
proc make_move*(board: Board, move: DisambigMove, engine: bool = false) =
  let
    to_move = if board.to_move == WHITE: BLACK else: WHITE
    castle_move = "O-O" in move.algebraic or "0-0" in move.algebraic

  var piece = 'P'

  for i, c in move.algebraic:
    # If we have an = then this is the piece the pawn promotes to.
    # Pawns can promote to rooks which would fubar the dict.
    if c.isUpperAscii() and not ('=' in move.algebraic):
      piece = c

  if piece == 'P':
    board.update_ep_square(move)
  # Updates the castle table for castling rights.
  if piece == 'K' or castle_move:
    if board.to_move == WHITE:
      board.castle_rights["WKR"] = false
      board.castle_rights["WQR"] = false
    else:
      board.castle_rights["BKR"] = false
      board.castle_rights["BQR"] = false
  elif piece == 'R':
    # This line of code means that this method takes approximately the same
    # length of time as make_move for Rook moves only.
    # All other moves bypass going to long algebraic.
    let long = board.short_algebraic_to_long_algebraic(move.algebraic)
    # We can get the position the rook started from using slicing in
    # the legal move, since legal returns a long algebraic move
    # which fully disambiguates and gives us the starting square.
    # So once the rook moves then we set it to false.
    if long[1..2] == "a8":
      board.castle_rights["BQR"] = false
    elif long[1..2] == "h8":
      board.castle_rights["BKR"] = false
    elif long[1..2] == "a1":
      board.castle_rights["WQR"] = false
    elif long[1..2] == "h1":
      board.castle_rights["WKR"] = false

  # We need to update castling this side if the rook gets taken without
  # ever moving. We can't castle with a rook that doesn't exist.
  if "xa8" in move.algebraic:
    board.castle_rights["BQR"] = false
  elif "xh8" in move.algebraic:
    board.castle_rights["BKR"] = false
  elif "xa1" in move.algebraic:
    board.castle_rights["WQR"] = false
  elif "xh1" in move.algebraic:
    board.castle_rights["WKR"] = false

  # The earliest possible checkmate is after 4 plies. No reason to check earlier
  if len(board.move_list) > 3 and not engine:
    # If there are no moves that get us out of check we need to see if we're in
    # check right now. If we are that's check mate. If we're not that's a stalemate.
    var
      noresponses = true
      color = if board.to_move == WHITE: BLACK else: WHITE

    # Progressively checking the moves allows us to break as soon as we find a
    # move instead of generating all of them at once just to see if there
    # are no possible moves.
    block movechecking:
      check_for_moves(board.generate_pawn_moves(color))
      check_for_moves(board.generate_knight_moves(color))
      check_for_moves(board.generate_rook_moves(color))
      check_for_moves(board.generate_bishop_moves(color))
      check_for_moves(board.generate_queen_moves(color))
      check_for_moves(board.generate_king_moves(color))
      check_for_moves(board.generate_castle_moves(color))

    if noresponses:
      var check = board.current_state.is_in_check(to_move)
      if check:
        if board.to_move == WHITE:
          board.status = WHITE_VICTORY
        else:
          board.status = BLACK_VICTORY
      else:
        board.status = DRAW

  # Does all the updates.
  # Updates the half move clock.
  if piece == 'P' or 'x' in move.algebraic:
    board.half_move_clock = 0
  else:
    board.half_move_clock += 1

  board.game_states.add(clone(board.current_state))
  board.current_state = clone(move.state)
  board.to_move = to_move
  # Clear the ep square from the opposite color as just moved
  board.ep_square[to_move] = ""
  board.move_list.add(move.algebraic)


proc make_move*(board: Board, move: string) =
  let legality = board.check_move_legality(move)

  if not legality.legal:
    raise newException(ValueError, "You tried to make an illegal move!")

  # Since queenside is the same as kingside with an extra -O on the end
  # we can just check that the kingside move is in the move.
  var
    castle_move = "O-O" in legality.alg or "0-0" in legality.alg
    new_state: Tensor[int]

  if castle_move:
    new_state = board.castle_algebraic_to_boardstate(legality.alg,
                                                     board.to_move)
  else:
    new_state = board.long_algebraic_to_boardstate(legality.alg)

  let big_move: DisambigMove = (legality.alg, new_state)
  make_move(board, big_move)


proc unmake_move(board: Board) =
  board.current_state = clone(board.game_states.pop())
  discard board.move_list.pop() # Take the last move off the move list as well.
  board.to_move = if board.to_move == BLACK: WHITE else: BLACK


proc to_fen*(board: Board): string =
  var fen: seq[string] = @[]

  # Loops over the board and gets the item at each location.
  for y in 0..7:
    for x in 0..7:
      # Adds pieces to the FEN. Lower case for black, and upper
      # for white. Since the dict is in uppercase we don't have
      # do to anything for that.
      var piece = board.current_state[y, x]
      if piece < 0:
        fen.add($piece_names[-piece].toLowerAscii())
      elif piece > 0:
        fen.add($piece_names[piece])
      # Empty spaces are represented by the number of blank spaces
      # between pieces. If the previous item is a piece or the list
      # is empty we add a 1, if the previous space is a number we
      # increment it by one for this empty space.
      else:
        if len(fen) == 0 or not fen[^1].isDigit():
          fen.add("1")
        else:
          fen[^1] = $(parseInt(fen[^1]) + 1)
    # At the end of each row we need to add a "/" to indicate that the row has
    # ended and we are moving to the next. Don't want an ending / though.
    if y < 7:
      fen.add("/")

  # The next field is the next person to move.
  fen.add(" ")
  if board.to_move == WHITE:
    fen.add("w")
  else:
    fen.add("b")

  # The next field is castling rights.
  fen.add(" ")
  var
    castle_names = {"WKR": "K", "WQR": "Q", "BKR": "k", "BQR": "q"}.toTable
    at_least_one = false
  for key, val in board.castle_rights:
    if val:
      at_least_one = true
      fen.add(castle_names[key])

  # Adds a dash if there are no castling rights.
  if not at_least_one:
    fen.add("-")

  # En passant target square next. From wikipedia: If a pawn has just
  # made a two-square move, this is the position "behind" the pawn.
  fen.add(" ")
  var opp_color = if board.to_move == WHITE: BLACK else: WHITE
  if board.ep_square[opp_color] == "":
    fen.add("-")
  else:
    fen.add(board.ep_square[opp_color])

  # Then the half move clock for the 50 move rule.
  fen.add(" ")
  fen.add($board.half_move_clock)

  # And finally the move number. We need to add 1 because the starting position
  # Starts at 1 and not at 0.
  fen.add(" ")
  fen.add($(len(board.move_list) div 2 + 1))

  result = fen.join("")


proc load_fen*(fen: string): Board =
  let
    fields = fen.splitWhitespace()
    rows = fields[0].split('/')

  var board_state: seq[seq[int]] = @[]
  # Loops over each row.
  for r in rows:
    var rank: seq[int] = @[]
    # Loops over each character in the row.
    for c in r:
      if c.isDigit():
        for i in 0 ..< parseInt($c):
          rank.add(0)
      else:
        # Adds a black piece if the character is lower, otherwise add a white
        if c.isLowerASCII():
          rank.add(-piece_numbers[c.toUpperASCII()])
        else:
          rank.add(piece_numbers[c])
    # At the end of the row add it to the board_state
    board_state.add(rank)

  # Who's moving this turn.
  var
    side_to_move = if fields[1] == "w": WHITE else: BLACK
    # Castling rights
    castle_dict = {"WQR": false, "WKR": false, "BQR": false,
                   "BKR": false}.toTable

  let
    castle_names = {'K': "WKR", 'Q': "WQR", 'k': "BKR", 'q': "BQR"}.toTable
    castling_field = fields[2]

  # For each character in the castling field
  for c in castling_field:
    if c == '-':
      break
    var key = castle_names[c]
    castle_dict[key] = true

  # Gets the half move clock if its in the fen.
  var half_move = 0
  if len(fields) > 4:
    half_move = parseInt(fields[4])

  var temp_move_list: seq[string] = @[]
  if len(fields) > 5:
    var num_plies = parseInt(fields[5]) * 2

    # This ensures that the move list is the right length and that move clock
    # is only incremented after black moves.
    if side_to_move == WHITE:
      num_plies = num_plies - 1

    # Just adds temporary digits to the move list so it's the right length
    # for saving a fen.
    if num_plies > 1:
      for i in 1..num_plies:
        temp_move_list.add($i & "Q")

  var ep_square = {WHITE: "", BLACK: ""}.toTable

  result = Board(half_move_clock: half_move, game_states: @[],
                current_state: board_state.toTensor,
                castle_rights: castle_dict, to_move: side_to_move,
                status: IN_PROGRESS, move_list: temp_move_list,
                headers: initTable[string, string](), ep_square: ep_square,
                long: false)


proc load_pgn*(name: string, folder: string = "games"): Board =
  # File location of the pgn.
  var loc = os.joinPath(folder, name)

  # In case you pass the name without .pgn at the end.
  if not loc.endsWith(".pgn"):
    loc = loc & ".pgn"

  if not fileExists(loc):
    raise newException(IOError, "PGN not found!")

  let data = open(loc)

  # We're going to extract the text into a single string so we need to append
  # lines here into this array.
  var
    game_line: seq[string] = @[]
    tags = initTable[string, string]()

  for line in data.lines:
    if not line.startsWith("["):
      game_line.add(line & " ")
    else:
      var
        trimmed = line.strip(chars = {'[', ']'})
        pair = trimmed.split("\"")

      tags[pair[0].strip()] = pair[1]

  var moves_line: string

  # Loops as long as there's an opening comment character.
  var in_comment = false

  for i, c in game_line.join(""):
    if c == '{':
      in_comment = true
      continue
    elif c == '}':
      in_comment = false
      continue

    if not in_comment:
      moves_line.add(c)

  # \d+ looks for 1 or more digits
  # \. escapes the period
  # \s* looks for 0 or more white space
  # Entire: looks for 1 or more digits followed by a period followed by
  # whitespace or no whitespace
  # Splits by move number.
  var
    moves = moves_line.split(re"\d+\.\s*")
    plies: seq[string] = @[]

  for m in moves:
    # Splits the move by the space to get the two plies that make it up.
    var spl = m.splitWhitespace()
    for s in spl:
      plies.add(s.strip())

  # Cuts out the game result
  discard plies.pop()

  # Makes all the moves and then returns the board state at the end.
  result = new_board()
  result.headers = tags

  for ply in plies:
    result.make_move(ply)


proc save_pgn*(board: Board) =
  let full: bool = len(board.headers) > 0
  # First gets the name to save to.
  var name: string
  if full:
    name = board.headers["White"] & "vs" & board.headers[
        "Black"] & board.headers["Date"] & ".pgn"
  else:
    name = "???vs???" & $(now()) & ".pgn"

  let loc = os.joinPath("results", name)

  let f = open(loc, fmWrite)

  if full:
    for key, val in board.headers:
      var line = "[" & key & " " & "\"" & val & "\"" & "]\n"
      f.write(line)

    # Inserts a blank line between the headers and the move line.
    f.write("\n")

    if len(board.move_list) > 0:
      for i, m in board.move_list:
        var line = $m & " "

        # Adds the move number every 2 plies.
        if i mod 2 == 0:
          var move_num = int(i / 2 + 1)
          line = $move_num & ". " & line

        f.write(line)

  # Writes the result at the end of the PGN or * for ongoing game.
  if full and "Result" in board.headers:
    f.write(board.headers["Result"])
  else:
    f.write("*")


proc `$`*(board: Board): string=
  for y in 0..7:
    for x in 0..7:
      var loc = board.current_state[y, x]
      # Black is supposed to be lower case hence this
      # if block differentiating between the two.
      if loc < 0:
        result = result & piece_names[abs(loc)].toLowerAscii()
      elif loc > 0:
        result = result & piece_names[loc]
      else:
        result = result & "."
      # This space makes it look nice
      result = result & " "
    # End of line new line.
    result = result & "\n"


# Creates a new board from scratch.
proc new_board*(): Board =
  # Just loads the starting fen so we can change piece numbering without
  # having to change a hard coded tensor.
  result = load_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")


# Creates a new board with the given state.
proc new_board*(start_board: Tensor[int]): Board =
  let start_castle_rights = {"WQR": true, "WKR": true, "BQR": true,
                             "BKR": true}.toTable
  result = Board(half_move_clock: 0, game_states: @[],
                 current_state: start_board,
                 castle_rights: start_castle_rights, to_move: WHITE,
                 status: Status.IN_PROGRESS, move_list: @[],
                 headers: initTable[string, string]())
