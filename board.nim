import system
import tables
import sequtils
import strutils
import re
import math

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


# The piece number -> piece name table.
const
  piece_names = {1:'P', 2:'R', 3:'N', 4:'B', 5:'Q', 6:'K'}.toTable


var temp: seq[tuple[key: char, val: int]] = @[]
for key, value in piece_names:
  temp.add((value, key))


let
  # The lowercase ascii alphabet.
  ascii_lowercase = toSeq 'a'..'z'

  # The reverse piece name -> piece number table.
  piece_numbers = temp.toTable


# Creates a new board from scratch.
proc new_board*(): Board =
  let start_board: Tensor[int] = @[[-2, -3, -4, -5, -6, -4, -3, -2],
                                  [-1, -1, -1, -1, -1, -1, -1, -1],
                                  [0, 0, 0, 0, 0, 0, 0, 0],
                                  [0, 0, 0, 0, 0, 0, 0, 0],
                                  [0, 0, 0, 0, 0, 0, 0, 0],
                                  [0, 0, 0, 0, 0, 0, 0, 0],
                                  [1, 1, 1, 1, 1, 1, 1, 1],
                                  [2, 3, 4, 5, 6, 4, 3, 2]].toTensor

  let start_castle_rights = {"WQR" : true, "WKR" : true, "BQR" : true,
                             "BKR" : true}.toTable
  result = Board(half_move_clock: 0, game_states: @[],
                 current_state: start_board, castle_rights: start_castle_rights,
                 to_move: Color.WHITE, status: Status.IN_PROGRESS,
                 move_list: @[], headers: initTable[string, string]())
  return


# Creates a new board with the given state.
proc new_board*(start_board: Tensor[int]): Board =
  let start_castle_rights = {"WQR" : true, "WKR" : true, "BQR" : true,
                             "BKR" : true}.toTable
  result = Board(half_move_clock: 0, game_states: @[],
                 current_state: start_board, castle_rights: start_castle_rights,
                 to_move: Color.WHITE, status: Status.IN_PROGRESS,
                 move_list: @[], headers: initTable[string, string]())
  return


# Finds the piece in the board state.
proc find_piece(state: Tensor[int], piece: int): seq[tuple[y, x:int]]=
  # Loop through and find the required piece positions.
  for coords, piece_num in state:
    if piece_num == piece:
      result.add((coords[0], coords[1]))

  return result


# Convert the row and column positions to an algebraic chess move.
# Use open arrays here since finish or start may be passed as a fixed length
# array or as a sequence as created by find_piece.
# TODO: Rewrite so that alg1 is generated and simply appended to alg2 instead of building them simultaneously
proc row_column_to_algebraic(self: Board, start:tuple[y, x:int], finish:tuple[y, x:int], piece: int, promotion: int = 0): tuple[short: string, long: string]=
  var
    alg1: string = ""
    alg2: string = ""

  if abs(piece) > 1:
    alg1.add(piece_names[abs(piece)])
    alg2.add(piece_names[abs(piece)])

  # Add the starting position to the fully disambiguated move.
  alg2.add(ascii_lowercase[start.x]) # File = x
  alg2.add($(8 - start.y)) # Rank = y

  # The x for captures
  if self.current_state[finish.y, finish.x] != 0:
    # On pawn captures alg notation requires including the starting file.
    # Since we may not include a piece character
    if piece == 1:
      alg1.add(ascii_lowercase[start.x])
    alg1.add("x")
    alg2.add("x")

  # We here append the ending position to the move.
  alg1.add(ascii_lowercase[finish.x]) # File = x
  alg1.add($(8 - finish.y)) # Rank = y

  alg2.add(ascii_lowercase[finish.x]) # File = x
  alg2.add($(8 - finish.y)) # Rank = y

  if promotion != 0:
    alg1.add("=")
    alg1.add(piece_names[abs(promotion)])

    alg2.add("=")
    alg2.add(piece_names[abs(promotion)])

  return (alg1, alg2)


proc long_algebraic_to_board_state(self: Board, move: string): Tensor[int]=
  var new_state = clone(self.current_state)

  var piece:char = 'P' # Default to pawn, this generally is changed.
  for i, c in move:
      # A [piece] character
      # If we have an = then this is the piece the pawn promotes to.
      if c.isUpperAscii():
          piece = c

  # Uses regex to find the rank/file combinations.
  let locs = findAll(move, re"[a-h]\d+")

  # Gets the starting position and puts into a constant
  var
    dest = locs[0]
    file = ascii_lowercase.find(dest[0]) # File = x
    rank = 8 - parseInt($dest[1]) # Rank = y

  let start = [rank, file]

  # Gets the ending position.
  dest = locs[1]
  file = ascii_lowercase.find(dest[0]) # File = x
  rank = 8 - parseInt($dest[1]) # Rank = y

  let finish = [rank, file]

  # Gets the value of the piece that's moving.
  var end_piece:int = self.current_state[start[0], start[1]]

  # In case of promotions we want the pice to change upon moving.
  if "=" in move:
    end_piece = piece_numbers[piece] * sgn(end_piece)

  new_state[start[0], start[1]] = 0
  new_state[finish[0], finish[1]] = end_piece

  # Turns the pawn that gets taken en passant to 0. This pawn is on the
  # same rank as the pawn moving, and the same file as where the pawn ends.
  if "e.p." in move:
    new_state[start[0], finish[1]] = 0

  return new_state


proc castle_algebraic_to_board_state(self: Board, move: string, color: Color): Tensor[int]=
  result = clone(self.current_state)

  var
    # Piece numbers for placing.
    king_num = piece_numbers['K']
    rook_num = piece_numbers['R']

  # The rank that the king and rook are on.
  let rank = if color == Color.WHITE: 7 else: 0

  # Flips the piece to negative if we're castling for black.
  if not (color == Color.WHITE):
    king_num = king_num * -1
    rook_num = rook_num * -1

  # Kingside castling
  if move == "O-O" or move == "0-0":
    result[rank, 7] = 0 # The rook
    result[rank, 4] = 0 # The king
    result[rank, 6] = king_num
    result[rank, 5] = rook_num
    return

  # Queenside castling
  elif move == "O-O-O" or move == "0-0-0":
    result[rank, 0] = 0 # The rook
    result[rank, 4] = 0 # The king
    result[rank, 2] = king_num
    result[rank, 3] = rook_num
    return

proc is_in_check(state: Tensor[int], color: Color): bool=
  let
    # The direction a pawn must travel to take this color's king.
    # I.e. Black pawns must travel in the positive y (downward) direction
    # To take a white king.
    d = if color == Color.WHITE: 1 else: -1

    # Color flipping for black instead of white.
    mult = if color == Color.WHITE: -1 else: 1

    # The king's number
    king_num = if color == Color.WHITE: piece_numbers['K'] else: -piece_numbers['K']
    # Check pawns first because they're the easiest.
    pawn_num = if color == Color.WHITE: -piece_numbers['P'] else: piece_numbers['P']

    # For this I'll assume there's only one king.
    king = state.find_piece(king_num)[0]

  # Need to ensure that the king is on any rank but the last one.
  # No pawns can put you in check in the last rank anyway.
  if king.y - d in 0..7:
    if king.x - 1 >= 0 and state[king.y - d, king.x - 1] == pawn_num:
        return true
    elif king.x + 1 < 8 and state[king.y - d, king.x + 1] == pawn_num:
        return true

  # Checks if you'd be in check from the opposite king.
  # This should only trigger on you moving your king into that position.
  let opposite_king = -king_num
  var opposite_locs = state.find_piece(opposite_king)

  let opposite_loc = opposite_locs[0]

 # If the other king is vertical or horizontal the sum will be 1 since it's
 # [0,1] or [1,0]. If it is diagonal diff will be  [1, 1]
  let diff = [abs(king.y - opposite_loc.y), abs(king.x - opposite_loc.x)]
  if sum(diff) == 1 or diff == [1, 1]:
    return true

  # Rooks and Queens
  let
    queens = find_piece(state*mult, piece_numbers['Q'])
    rooks = find_piece(state*mult, piece_numbers['R'])

  var
    # The slide a rook would have to take to get to the king.
    slide:Tensor[int] = @[0].toTensor

  for pos in concat(queens, rooks):
    # If moving puts the king next to the rook you're in check guaranteed.
    if pos.y == king.y and abs(pos.x - king.x) == 1:
     return true
    elif pos.x == king.x and abs(pos.y - king.y) == 1:
      return true

    # Rook needs to be on the same file or rank to be able to put the king in
    # check. Check the sum between the two pieces, if it's 0 then no pieces are
    # between and it's a valid check.
    if pos.y == king.y:
      # Slides from the rook to the king, left to right.
      if pos.x < king.x:
        slide = state[king.y, pos.x + 1 ..< king.x]
      # Slides from the king to the rook, left to right.
      else:
        slide = state[king.y, king.x + 1 ..< pos.x]
      slide = abs(slide)
      if sum(slide) == 0:
        return true

    if pos.x == king.x:
      # Slides from the rook to the king, top down.
      if pos.y < king.y:
        slide = state[pos.y + 1 ..< king.y, king.x]
      # Slides from the king to the rook, top down.
      else:
        slide = state[king.y + 1 ..< pos.y, king.x]
      slide = abs(slide)
      if sum(slide) == 0:
        return true

  # Knights can hop which is why I'm doing them before bishops
  var knights = find_piece(state*mult, piece_numbers['N'])

  for pos in knights:
      var slope: tuple[y, x: int] = (abs(pos.y - king.y), abs(pos.x - king.x))

      # Avoids a divide by 0 error. If it's on the same rank or file
      # the knight can't get the king anyway.
      if slope.x == 0 or slope.y == 0:
          continue
      if slope == (1, 2) or slope == (2, 1):
          return true

  # Now bishops and diagonal queens
  var bishops = find_piece(state*mult, piece_numbers['B'])

  for pos in concat(bishops, queens):
    # First we check that the piece is even on a diagonal from the king.
    # The following code finds the absolute value of the slope as well
    # as the slope value from the bishop to the king.
    var slope: tuple[y, x:float] = (float(pos.y - king.y), float(pos.x - king.x))
    var abs_slope: tuple[y, x:float] = (abs(slope.y), abs(slope.x))
    var max = max([abs_slope.y, abs_slope.x])
    slope = (slope[0] / max, slope[1] / max)
    abs_slope = (abs_slope[0] / max, abs_slope[1] / max)

    # If the absolute slope is 1,1 then it's a diagonal.
    if abs_slope.x == 1.0 and abs_slope.y == 1.0:
      var cur_pos: tuple[y, x:int] = pos
      # Now we have to check that the space between the two is empty.
      for i in 1..7:
        cur_pos = (king.y + i * int(slope.y), king.x + i * int(slope.x))

        if not (state[cur_pos.y, cur_pos.x] == 0):
            break
      # This will execute if the position that caused the for loop to
      # break is the bishop itself, otherwise this does not execute.
      # Or the queen. Same thing.
      if cur_pos == pos:
          return true

  return false


# TODO: An incredible amount of the code in here is the same as is_in_check -> refactor
proc short_algebraic_to_long_algebraic*(self: Board, move: string): string=
  var new_move = move
  # A move is minimum two characters (a rank and a file for pawns)
  # so if it's shorter it's not a good move.
  if len(move) < 2:
    return

  # You're not allowed to castle out of check.
  var check = self.current_state.is_in_check(self.to_move)
  if ("O-O" in move or "0-0" in move) and check:
      return

  # Slices off the checkmate character for parsing. This is largely so that
  # castling into putting the opponent in check parses correctly.
  if move.endsWith('+') or move.endsWith('#'):
    new_move = new_move[0 ..< ^1]

  # Castling is the easiest to check for legality.
  var
    # The rank the king is on.
    king_rank = if self.to_move == Color.WHITE: 7 else: 0

    # The king's number representation
    king_num = if self.to_move == Color.WHITE: piece_numbers['K'] else: -piece_numbers['K']

  # Kingside castling
  if new_move == "O-O" or new_move == "0-0":
    var
      check_side = if self.to_move == Color.WHITE: "WKR" else: "BKR"
      # The two spaces between the king and rook.
      between = self.current_state[king_rank, 5..6]

    if self.castle_rights[check_side] and sum(abs(between)) == 0:
        # Need to check that we don't castle through check here.
        var new_state = clone(self.current_state)
        new_state[king_rank, 4] = 0
        new_state[king_rank, 5] = king_num

        check = new_state.is_in_check(self.to_move)
        if not check:
            return new_move
        else:
            return
    else:
        return
  # Queenside castling
  elif new_move == "O-O-O" or new_move == "0-0-0":
    var
      check_side = if self.to_move == Color.WHITE: "WQR" else: "BQR"
      # The three spaces between the king and rook.
      between = self.current_state[king_rank, 1..3]

    if self.castle_rights[check_side] and sum(abs(between)) == 0:
        # Need to check that we don't castle through check here.
        var new_state = clone(self.current_state)
        new_state[king_rank, 4] = 0
        new_state[king_rank, 3] = king_num

        check = new_state.is_in_check(self.to_move)
        if not check:
            return new_move
        else:
            return
    else:
        return

  # Use regex to extract the positions as well as the singular ranks
  # and files and the pieces (for finding the piece and pawn promotion)
  let
    locs = findAll(move, re"[a-h]\d+")
    ranks = findAll(move, re"\d+")
    files = findAll(move, re"[a-h]")
    pieces = findAll(move, re"[PRNQKB]")
    illegal_piece = findAll(move, re"[A-Z]")

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
    if not (parseInt(r) in  1..8):
      return

  # Gets the ending position and puts into a constant
  var
    dest = locs[^1]
    file = ascii_lowercase.find(dest[0]) # File = x
    rank = 8 - parseInt($dest[1]) # Rank = y

  let fin: tuple[y, x: int] = (rank, file)

  # Defults everything to pawn.
  var
    mult = if self.to_move == Color.WHITE: 1 else: -1
    piece_char = 'P'
    piece_num = piece_numbers['P'] * mult
    promotion_piece = piece_numbers['P'] * mult

  # If a piece was passed in we set the piece_char to that piece.
  if len(pieces) > 0:
    piece_char = pieces[0][0]

  # Puts the found piece number into either piece_num or promotion_piece
  # Depending what piece is moving.
  if '=' in new_move:
    promotion_piece = piece_numbers[piece_char] * mult
  else:
    piece_num = piece_numbers[piece_char] * mult

  var found_pieces = self.current_state.find_piece(piece_num)

  # If we have any sort of disambiguation use that as our starting point.
  # This allows us to trim the pieces we search through and find the
  # correct correct one rather than the "first one allowed to make this move."
  var start: tuple[y, x: int] = (-1, -1)

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
    var good: seq[tuple[y, x:int]] = @[]
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
    d = if self.to_move == Color.WHITE: -1 else: 1

    # The starting file for the pawn row, for double move checking
    pawn_start = if self.to_move == Color.WHITE: 6 else: 1

    # The file the pawn needs to be on to take en passant.
    ep_file = if self.to_move == Color.WHITE: 3 else: 4

    # The ending rank for pawn promotion
    pawn_end = if self.to_move == Color.WHITE: 0 else: 7

    state = clone(self.current_state * mult)

  # This handy line of code prevents you from taking your own pieces.
  if state[fin.y, fin.x] > 0:
    return

  # An inner proc to remove code duplication that checks if moving the piece
  # would end with you in check. This exists in case you try to move a piece
  # that's pinned.
  proc good_move(start: tuple[y, x: int], fin: tuple[y, x: int],  piece_num: int, ep: bool=false): bool=
    var s = clone(self.current_state)
    s[start.y, start.x] = 0
    s[fin.y, fin.x] = piece_num

    if ep:
      s[start.y, fin.x] = 0

    result = not s.is_in_check(self.to_move)
    return


  if piece_char == 'P':
    # This requires that the pawn promote upon reaching the end.
    if fin.y == pawn_end and not ('=' in new_move):
      return
    # Loop over the found pawns.
    for pawn in found_pieces:
      var
        found: tuple[y, x: int] = (-1, -1)
        promotion: bool = fin.x == pawn_end
        # Ensures that this pawn would actually have to move forward and not
        # backward to get to the ending square. This is true if the pawn
        # moves backwards.
        direc = if self.to_move == Color.WHITE: pawn.y < fin.y  else: pawn.y > fin.y

      if direc:
        continue

      # First check where the ending position is empty
      # Second condition is that the pawn is on the same rank
      if state[fin.y, fin.x] == 0 and pawn.x == fin.x:
        # If this pawn can move forward 1 and end on the end it's good.
        if pawn.y + d == fin.y:
            found = pawn

        # Need to check the space between one move and two is empty.
        var empty = state[pawn.y + d, fin.x] == 0
        if pawn.y + 2 * d == fin.y and pawn.y == pawn_start and empty:
            found = pawn

      # This is the case for where the ending state isn't empty, which
      # means that the pawn needs to travel diagonally to take this piece.
      if state[fin.y, fin.x] < 0:
        let
          take_left = pawn.y + d == fin.y and pawn.x - 1 == fin.x
          take_right = pawn.y + d == fin.y and pawn.x + 1 == fin.x

        if take_left or take_right:
            found = pawn

      # Interestingly d happens to correspond to "pawn of the opposite color"
      # Bools check that we are adjacent to a pawn of the opposite color which
      # is a requirement of en_passant.
      let
        ep_left = pawn.x == fin.x - 1 and self.current_state[pawn.y, fin.x] == d
        ep_right = pawn.x == fin.x + 1 and self.current_state[pawn.y, fin.x] == d

        # We need to start on the correct file for en passant.
        good_start = pawn.y == ep_file
        # Makes sure the ending far enough from the edge for a good en passant.
        good_end = fin.y in 1..6

      var ep = false

      # Can't en passant on turn 1 (or anything less than turn 3 I think)
      # so if you got this far it's not a legal pawn move.
      if len(self.game_states) > 1:
        let previous_state = clone(self.game_states[^1])
        if state[fin.y, fin.x] == 0 and (ep_left or ep_right) and good_start:
            # Checks that in the previous state the pawn actually
            # moved two spaces. This prevents trying an en passant
            # move three moves after the pawn moved.
            if good_end and previous_state[fin.y + d, fin.x] == d:
                found = pawn
                ep = true

      # Ensures that moving this piece doesn't end in check. In theory it could
      # end in a promotion, but if moving this piece leaves us in check then it
      # won't matter what piece it promotes to so I can just check as a pawn.
      if not (found == (-1, -1)) and good_move(found, fin, piece_num, ep):
        if promotion:
            return self.row_column_to_algebraic(pawn, fin, piece_num, promotion_piece)[1]
        if ep:
            return self.row_column_to_algebraic(found, fin, piece_num)[1] & "e.p."
        return self.row_column_to_algebraic(found, fin, piece_num)[1]

  elif piece_char == 'N':
    for knight in found_pieces:
      var
        found: tuple[y, x: int] = (-1, -1)
        slope: tuple[y, x: int] = (abs(fin.y - knight.y), abs(fin.x - knight.x))

      # Avoids a divide by 0 error. If it's on the same rank or file
      # the knight can't get the king anyway.
      if slope.x == 0 or slope.y == 0:
          continue
      if slope == (1, 2) or slope == (2, 1):
          found = knight

      # Ensures that moving this piece doesn't end in check.
      if not (found == (-1, -1)) and good_move(found, fin, piece_num):
          return self.row_column_to_algebraic(found, fin, piece_num)[1]

  elif piece_char == 'R' or  piece_char == 'Q':
    for rook in found_pieces:
      var found: tuple[y, x: int] = (-1, -1)
      # If we only move one space then we found the piece already.
      if rook.y == fin.y and abs(rook.x - fin.x) == 1:
        found = rook
      elif rook.x == fin.x and abs(rook.y - fin.y) == 1:
        found = rook
      else:
        # The slide a rook would have to take to get to the end.
        var slide:Tensor[int] = @[0].toTensor

        if rook.y == fin.y:
          # Slides from the rook to the fin, left to right.
          if rook.x < fin.x:
            slide = state[fin.y, rook.x + 1 ..< fin.x]
          # Slides from the fin to the rook, left to right.
          else:
            slide = state[fin.y, fin.x + 1 ..< rook.x]
          slide = abs(slide)
          if sum(slide) == 0:
            found = rook

        if rook.x == fin.x:
          # Slides from the rook to the fin, top down.
          if rook.y < fin.y:
            slide = state[rook.y + 1 ..< fin.y, fin.x]
          # Slides from the fin to the rook, top down.
          else:
            slide = state[fin.y + 1 ..< rook.y, fin.x]
          slide = abs(slide)
          if sum(slide) == 0:
            found = rook

      # Ensures that moving this piece doesn't end in check.
      if not (found == (-1, -1)) and good_move(found, fin, piece_num):
          return self.row_column_to_algebraic(found, fin, piece_num)[1]

    # If we make it through all the rooks and didn't find one that has a
    # straight shot to the end then there isn't a good move. However we only do
    # this if we entered this block as a Rook Since queens can still go diagonal
    if piece_char == 'R':
        return

  if piece_char == 'B' or  piece_char == 'Q':
    for bishop in found_pieces:
      # First we check that the piece is even on a diagonal from the fin.
      # The following code finds the absolute value of the slope as well
      # as the slope value from the bishop to the fin.
      var
        found: tuple[y, x: int] = (-1, -1)
        slope: tuple[y, x:float] = (float(bishop.y - fin.y), float(bishop.x - fin.x))
        abs_slope: tuple[y, x:float] = (abs(slope.y), abs(slope.x))
        max = max([abs_slope.y, abs_slope.x])

      slope = (slope[0] / max, slope[1] / max)
      abs_slope = (abs_slope[0] / max, abs_slope[1] / max)

      # If the absolute slope is 1,1 then it's a diagonal.
      if abs_slope.x == 1.0 and abs_slope.y == 1.0:
        var cur_pos: tuple[y, x:int] = bishop
        # Now we have to check that the space between the two is empty.
        for i in 1..7:
          cur_pos = (fin.y + i * int(slope.y), fin.x + i * int(slope.x))

          if not (state[cur_pos.y, cur_pos.x] == 0):
              break
        # This will execute if the position that caused the for loop to
        # break is the bishop itself, otherwise this does not execute.
        # Or the queen. Same thing.
        if cur_pos == bishop:
            found = bishop

      # Ensures that moving this piece doesn't end in check.
      if not (found == (-1, -1)) and good_move(found, fin, piece_num):
        return self.row_column_to_algebraic(found, fin, piece_num)[1]

  if piece_char == 'K':
    for king in found_pieces:
      var found: tuple[y, x: int] = (-1, -1)

      let diff = [abs(king.y - fin.y), abs(king.x - fin.x)]
      if sum(diff) == 1 or diff == [1, 1]:
        found = king

      #Ensures that moving this piece doesn't end in check.
      if not (found == (-1, -1)) and good_move(found, fin, piece_num):
        return self.row_column_to_algebraic(found, fin, piece_num)[1]

  return


proc check_move_legality*(self: Board, move: string): tuple[legal: bool, alg: string]=
  result = (false, move)

  # Tries to get the long version of the move. If there is not piece that could
  # make thismove the long_move is going to be the empty string.
  let long_move = self.short_algebraic_to_long_algebraic(move)
  if long_move == "":
    return

  var check: bool

  # Only need to check if you castle into check since short_algebraic_to_long
  # already checks to see if the move ends in check and if it does it returns
  # "".  Doesn't check castling ending in check, however, hence why this
  # is here. Castling shortcuts in short_algebraic.
  if "O-O" in long_move or "0-0" in long_move:
    var end_state = self.castle_algebraic_to_boardstate(long_move, self.to_move)
    check = end_state.is_in_check(self.to_move)

  if check:
    return
  return (true, long_move)


proc remove_moves_in_check(self: Board, moves: openArray[tuple[short: string, long: string, state: Tensor[int]]], color: Color): seq[tuple[alg: string, state: Tensor[int]]]=
  # Shortcut for if there's no possible moves being disambiguated.
  if len(moves) == 0:
    return

  # Convert to a tensor of strings so we can slice out only the first column.
  var new_moves: seq[seq[string]] = @[]
  for move_state in moves:
    new_moves.add(@[move_state[0], move_state[1]])
  let moves_tensor = new_moves.toTensor

  # Loop through the move/board state sequence.
  for i, m in moves:
    var check = m[2].is_in_check(color)

    if not check:
      # If the number of times that the short moves appears is more than 1 we
      # want to append the long move.
      # moves_tensor[1..^1,0] slices out only the short algebraic moves.
      if moves_tensor[_,0].toSeq.count(m[0]) > 1:
        result.add((m[1], m[2]))
      else:
        result.add((m[0], m[2]))

  return result


# I hate pawns.
proc generate_pawn_moves*(self: Board, color: Color): seq[tuple[alg: string, state: Tensor[int]]]=
  var
    # Color flipping for black instead of white.
    mult:int = if color == Color.WHITE: 1 else: -1

    # Direction of travel, reverse for black and white. Positive is going
    # downwards, negative is going upwards.
    d = -1 * mult
    state = self.current_state * mult

    # Find the pawns
    pawn_num = piece_numbers['P']
    pawns = state.find_piece(pawn_num)

    # End_states will be a sequence of tuples returned by row_column_to_algebraic
    end_states:seq[tuple[short: string, long: string]] = @[]

    # The ending position, this will change throughout the method.
    fin:tuple[y, x: int] = (0, 0)

  let
     # The ending rank for pawn promotions
     endrank = if color == Color.WHITE: 7 else: 0
     # The starting rank for moving two spaces
     startrank = if color == Color.WHITE: 6 else: 1

  # Find all the pawn moves here lol.
  for pos in pawns:
    # En Passant first since we can take En Passant if there is a piece
    # directly in front of our pawn. However, requires the pawn on row 5 (from
    # bottom) Can't en passant if there's no other game states to check either.
    if len(self.game_states) > 1 and pos.y == 4 + d:
      let previous_state = self.game_states[^1] * mult
      # Don't check en passant on the left if we're on the first file
      # Similarly don't check to the right if we're on the last file
      var
        left_allowed = pos.x > 0
        right_allowed = pos.x < 7

        # Booleans for checking if en passant is legal or not.
        pawn_on_left = false
        pawn_on_right = false
        pawn_moved_two = false
        different_pawn = false

      if left_allowed:
        pawn_on_left = state[pos.y, pos.x - 1] == -1
        pawn_moved_two = previous_state[pos.y + 2 * d, pos.x - 1] == -1

        # Need to ensure this doesn't trigger if a different pawn is hanging
        # out there. Thanks Lc0 for playing a move that necessitated this against
        # KomodoMCTS
        different_pawn = not (state[pos.y + 2 * d, pos.x - 1] == -1)
        if pawn_on_left and pawn_moved_two and different_pawn:
            fin = (pos.y + d, pos.x - 1)
            end_states.add(self.row_column_to_algebraic(pos, fin, pawn_num))

      if right_allowed:
        pawn_on_right = state[pos.y, pos.x + 1] == -1
        pawn_moved_two = previous_state[pos.y + 2 * d, pos.x + 1] == -1
        different_pawn = not (state[pos.y + 2 * d, pos.x + 1] == -1)
        if pawn_on_right and pawn_moved_two and different_pawn:
          fin = (pos.y + d, pos.x + 1)
          end_states.add(self.row_column_to_algebraic(pos, fin, pawn_num))

    # Makes sure the space in front of us is clear
    if state[pos.y + d, pos.x] == 0:
      # Pawn promotion
      # We do this first because pawns have to promote so we can't
      # just "move one forward" in this position
      if pos.y + d == endrank:
        for key, val in piece_numbers:
          if not (key == 'P') and not (key == 'K'):
            fin = (pos.y + d, pos.x)
            end_states.add(self.row_column_to_algebraic(pos, fin, pawn_num, val))
      else:
          # Add one move forward
          fin = (pos.y + d, pos.x)
          end_states.add(self.row_column_to_algebraic(pos, fin, pawn_num))
      # This is for moving two forward. Ensures that the space 2 ahead is clear
      if pos.y == startrank and state[pos.y + 2 * d, pos.x] == 0:
          fin = (pos.y + 2 * d, pos.x)
          end_states.add(self.row_column_to_algebraic(pos, fin, pawn_num))

    # Takes to the left
    # First condition ensures that we remain within the bounds of the board.
    if pos.x - 1 > -1 and state[pos.y + d, pos.x - 1] < 0:
      fin = (pos.y + d, pos.x - 1)

      # Promotion upon taking
      if pos.y + d == endrank:
        for key, val in piece_numbers:
          if not (key == 'P') or not (key == 'K'):
            end_states.add(self.row_column_to_algebraic(pos, fin, pawn_num, val))
      else:
        end_states.add(self.row_column_to_algebraic(pos, fin, pawn_num))

    # Takes to the right
    # First condition ensures that we remain within the bounds of the board.
    if pos.x + 1 < 8 and state[pos.y + d, pos.x + 1] < 0:
      fin = (pos.y + d, pos.x + 1)

      # Promotion upon taking
      if pos.y + d == endrank:
        for key, val in piece_numbers:
          if not (key == 'P') or not (key == 'K'):
            end_states.add(self.row_column_to_algebraic(pos, fin, pawn_num, val))
      else:
        end_states.add(self.row_column_to_algebraic(pos, fin, pawn_num))

  # Build a sequence of new_states that will get pruned by remove_moves_in_check
  var new_states: seq[tuple[short: string, long: string, state: Tensor[int]]] = @[]
  for i, move in end_states:
      var s = self.long_algebraic_to_boardstate(move[1])
      new_states.add((move[0], move[1], s))

  # Removes the illegal moves that leave you in check.
  result = self.remove_moves_in_check(new_states, color)

  return


proc generate_knight_moves*(self: Board, color: Color): seq[tuple[alg: string, state: Tensor[int]]]=
  var
    # Color flipping for black instead of white.
    mult:int = if color == Color.WHITE: 1 else: -1
    state = self.current_state * mult

    # All possible knight moves, ignore flips.
    moves:array[4, tuple[y, x: int]] = [(2, 1), (2, -1), (-2, 1), (-2, -1)]
    # Find the knights
    knight_num = piece_numbers['N']
    knights = state.find_piece(knight_num)

    # End_states will be a sequence of tuples returned by row_column_to_algebraic
    end_states:seq[tuple[short: string, long: string]] = @[]

  for pos in knights:
    for m in moves:
    # copy the tensor state
      var
        end1: tuple[y, x: int] = (pos.y + m.y, pos.x + m.x)
        end2: tuple[y, x: int] = (pos.y + m.x, pos.x + m.y) # Flip m

        # Boolean conditions to ensure the ending is within the bounds of the board.
        legal1: bool = end1.x in 0..7 and end1.y in 0..7
        legal2: bool = end2.x in 0..7 and end2.y in 0..7

      # This adds to the condition that the end square must not be occupied by
      # a piece of the same color. Since white is always >0 we require the end
      # square to be empty (==0) or occupied by black (<0)
      legal1 = legal1 and state[end1.y, end1.x] <= 0
      legal2 = legal2 and state[end2.y, end2.x] <= 0

      # The following code blocks only run if the ending positions are actually
      # on the board.
      if legal1:
        end_states.add(self.row_column_to_algebraic(pos, end1, knight_num))

      if legal2:
        end_states.add(self.row_column_to_algebraic(pos, end2, knight_num))

  # Build a sequence of new_states that will get pruned by remove_moves_in_check
  var new_states: seq[tuple[short: string, long: string, state: Tensor[int]]] = @[]
  for i, move in end_states:
      var s = self.long_algebraic_to_boardstate(move[1])
      new_states.add((move[0], move[1], s))

  # Removes the illegal moves that leave you in check.
  result = self.remove_moves_in_check(new_states, color)

  return result


proc generate_straight_moves(self: Board, color: Color, starts: seq[tuple[y, x:int]], queen: bool = false): seq[tuple[alg: string, state: Tensor[int]]]=
  var
    # Color flipping for black instead of white.
    mult:int = if color == Color.WHITE: 1 else: -1
    state = self.current_state * mult

    # Get the piece num for the algebraic move.
    piece_num = if queen: piece_numbers['Q'] else: piece_numbers['R']

    # End_states will be a sequence of tuples returned by row_column_to_algebraic
    end_states:seq[tuple[short: string, long: string]] = @[]

    # The ending position, this will change throughout the method.
    fin:tuple[y, x: int] = (0, 0)

  # We here loop through each rook starting position.
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
            end_states.add(self.row_column_to_algebraic(pos, fin, piece_num))
            break
          else:
            end_states.add(self.row_column_to_algebraic(pos, fin, piece_num))

  # Build a sequence of new_states that will get pruned by remove_moves_in_check
  var new_states: seq[tuple[short: string, long: string, state: Tensor[int]]] = @[]
  for i, move in end_states:
      var s = self.long_algebraic_to_boardstate(move[1])
      new_states.add((move[0], move[1], s))

  # Removes the illegal moves that leave you in check.
  result = self.remove_moves_in_check(new_states, color)

  return result


proc generate_rook_moves*(self: Board, color: Color): seq[tuple[alg: string, state: Tensor[int]]]=
  var
    # Color flipping for black instead of white.
    mult:int = if color == Color.WHITE : 1 else: -1
    state = self.current_state * mult

    # Find the rooks
    rook_num = piece_numbers['R']
    rooks = state.find_piece(rook_num)

  return generate_straight_moves(self, color, rooks, queen=false)


proc generate_diagonal_moves(self: Board, color: Color, starts: seq[tuple[y, x:int]], queen: bool = false): seq[tuple[alg: string, state: Tensor[int]]]=
  var
    # Color flipping for black instead of white.
    mult:int = if color == Color.WHITE: 1 else: -1
    state = self.current_state * mult

    # Get the piece num for the algebraic move.
    piece_num = if queen: piece_numbers['Q'] else: piece_numbers['B']

    # End_states will be a sequence of tuples returned by row_column_to_algebraic
    end_states:seq[tuple[short: string, long: string]] = @[]

    # The ending position, this will change throughout the method.
    fin:tuple[y, x: int] = (0, 0)

  for pos in starts:
    # We loop through the x and y dirs here since bishops move diagonally
    # so we need directions like [1, 1] and [-1, -1] etc.
    for xdir in [-1, 1]:
      for ydir in [-1, 1]:
        # Start at 1 since 0 represents the position the bishop is at.
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
            end_states.add(self.row_column_to_algebraic(pos, fin, piece_num))
            break
          else:
            end_states.add(self.row_column_to_algebraic(pos, fin, piece_num))

  # Build a sequence of new_states that will get pruned by remove_moves_in_check
  var new_states: seq[tuple[short: string, long: string, state: Tensor[int]]] = @[]
  for i, move in end_states:
      var s = self.long_algebraic_to_boardstate(move[1])
      new_states.add((move[0], move[1], s))

  # Removes the illegal moves that leave you in check.
  result = self.remove_moves_in_check(new_states, color)

  return result


proc generate_bishop_moves*(self: Board, color: Color): seq[tuple[alg: string, state: Tensor[int]]]=
  var
    # Color flipping for black instead of white.
    mult:int = if color == Color.WHITE : 1 else: -1
    state = self.current_state * mult

    # Find the rooks
    bishop_num = piece_numbers['B']
    bishops = state.find_piece(bishop_num)

  return generate_diagonal_moves(self, color, bishops, queen=false)


proc generate_queen_moves*(self: Board, color: Color): seq[tuple[alg: string, state: Tensor[int]]]=
  var
    # Color flipping for black instead of white.
    mult:int = if color == Color.WHITE : 1 else: -1
    state = self.current_state * mult

    # Find the rooks
    queen_num = piece_numbers['Q']
    queens = state.find_piece(queen_num)

  let
    diags = generate_diagonal_moves(self, color, queens, queen=true)
    straights = generate_straight_moves(self, color, queens, queen=true)

  result = concat(diags, straights)

  return result


proc generate_king_moves*(self: Board, color: Color): seq[tuple[alg: string, state: Tensor[int]]]=
  var
    # Color flipping for black instead of white.
    mult:int = if color == Color.WHITE: 1 else: -1
    state = self.current_state * mult

    # Find the kings
    king_num = piece_numbers['K']
    kings = state.find_piece(king_num)

    # All possible king moves
    moves:array[8, tuple[y, x: int]] = [(-1, -1), (-1, 0), (-1, 1), (0, -1),
                                        (0, 1), (1, -1), (1, 0), (1, 1)]

    # End_states will be a sequence of tuples returned by row_column_to_algebraic
    end_states:seq[tuple[short: string, long: string]] = @[]

  for pos in kings:
    for m in moves:
      var fin: tuple[y, x: int] = (pos.y + m.y, pos.x + m.x)

      # Ensures that the ending position is inside the board and that we
      # don't try to take our own piece.
      if fin.x in 0..7 and fin.y in 0..7 and state[fin.y, fin.x] <= 0:
        end_states.add(self.row_column_to_algebraic(pos, fin, king_num))

  # Build a sequence of new_states that will get pruned by remove_moves_in_check
  var new_states: seq[tuple[short: string, long: string, state: Tensor[int]]] = @[]
  for i, move in end_states:
      var s = self.long_algebraic_to_boardstate(move[1])
      new_states.add((move[0], move[1], s))

  # Removes the illegal moves that leave you in check.
  result = self.remove_moves_in_check(new_states, color)

  return result


proc generate_castle_moves*(self: Board, color: Color): seq[tuple[alg: string, state: Tensor[int]]]=
  # Hardcoded because you can only castle from starting positions.
  # Basically just need to check that the files between the king and
  # the rook are clear, then return the castling algebraic (O-O or O-O-O)
  let
    # The rank that castling takes place on.
    rank = if color == Color.WHITE: 7 else: 0

    # The king's number on the board.
    king_num = if color == Color.WHITE: piece_numbers['K'] else: -1 * piece_numbers['K']

    # Key values to check in the castling table for castling rights.
    kingside = if color == Color.WHITE: "WKR" else: "BKR"
    queenside = if color == Color.WHITE: "WQR" else: "BQR"

  var
    # End_states will be a sequence of castling strings
    end_states:seq[string] = @[]

    # Slice representing the two spaces between the king and the kingside rook.
    between = self.current_state[rank, 5..6]

  # You're not allowed to castle out of check so if you're in check
  # don't generate it as a legal move.
  if self.current_state.is_in_check(color):
      return

  if self.castle_rights[kingside] and sum(abs(between)) == 0:
    # Before we go ahead and append the move is legal we need to verify
    # that we don't castle through check. Since we remove moves
    # that end in check, and the king moves two during castling,
    # it is sufficient therefore to simply check that moving the king
    # one space in the kingside direction doesn't put us in check.
    var s = clone(self.current_state)
    s[rank, 4] = 0
    s[rank, 5] = king_num

    if not s.is_in_check(color):
      end_states.add("O-O")

  # Slice representing the two spaces between the king and the queenside rook.
  between = self.current_state[rank, 1..3]
  if self.castle_rights[queenside] and sum(abs(between)) == 0:
    # See reasoning above in kingside.
    var s = clone(self.current_state)
    s[rank, 4] = 0
    s[rank, 3] = king_num

    if not s.is_in_check(color):
      end_states.add("O-O-O")

  # Build a sequence of new_states that will get pruned by remove_moves_in_check
  var new_states: seq[tuple[short: string, long: string, state: Tensor[int]]] = @[]
  for i, move in end_states:
      var s = self.castle_algebraic_to_boardstate(move, self.to_move)
      new_states.add((move, move, s))

  # Removes the illegal moves that leave you in check.
  result = self.remove_moves_in_check(new_states, color)

  return result


proc generate_moves*(self: Board, color: Color): seq[tuple[alg: string, state: Tensor[int]]]=
  let
    pawns = self.generate_pawn_moves(color)
    knights = self.generate_knight_moves(color)
    rooks = self.generate_rook_moves(color)
    bishops = self.generate_bishop_moves(color)
    queens = self.generate_queen_moves(color)
    kings = self.generate_king_moves(color)
    castling = self.generate_castle_moves(color)

  result = concat(castling, queens, rooks, bishops, knights, pawns, kings)
  return


proc is_checkmate*(state: Tensor[int], color: Color): bool=
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

  return


proc make_move*(self: Board, move: string)=
  let legality = self.check_move_legality(move)

  if not legality.legal:
    raise newException(ValueError, "You tried to make an illegal move!")

  # Since queenside is the same as kingside with an extra -O on the end
  # we can just check that the kingside move is in the move.
  var
    castle_move = "O-O" in legality.alg or "0-0" in legality.alg
    new_state: Tensor[int]

  if castle_move:
      new_state = self.castle_algebraic_to_boardstate(legality.alg, self.to_move)
  else:
      new_state = self.long_algebraic_to_boardstate(legality.alg)

  # Add the current state to the list of game states and then change the state.
  self.game_states.add(clone(self.current_state))
  self.current_state = clone(new_state)

  var piece = 'P'
  for i, c in move:
    # If we have an = then this is the piece the pawn promotes to.
    # Pawns can promote to rooks which would fubar the dict.
    if c.isUpperAscii() and not ('=' in move):
        piece = c

  # Updates the castle table for castling rights.
  if piece == 'K' or castle_move:
    if self.to_move == Color.WHITE:
        self.castle_rights["WKR"] = false
        self.castle_rights["WQR"] = false
    else:
        self.castle_rights["BKR"] = false
        self.castle_rights["BQR"] = false
  elif piece == 'R':
    # We can get the position the rook started from using slicing in
    # the legal move, since legal returns a long algebraic move
    # which fully disambiguates and gives us the starting square.
    # So once the rook moves then we set it to false.
    if legality.alg[1..2] == "a8":
        self.castle_rights["BQR"] = false
    elif legality.alg[1..2] == "h8":
        self.castle_rights["BKR"] = false
    elif legality.alg[1..2] == "a1":
        self.castle_rights["WQR"] = false
    elif legality.alg[1..2] == "h1":
        self.castle_rights["WKR"] = false

  # Updates the half move clock.
  if piece == 'P' or 'x' in legality.alg:
    self.half_move_clock = 0
  else:
    self.half_move_clock += 1

  # We need to update castling this side if the rook gets taken without
  # ever moving. We can't castle with a rook that doesn't exist.
  if "xa8" in legality.alg:
    self.castle_rights["BQR"] = false
  elif "xh8" in legality.alg:
    self.castle_rights["BKR"] = false
  elif "xa1" in legality.alg:
    self.castle_rights["WQR"] = false
  elif "xh1" in legality.alg:
    self.castle_rights["WKR"] = false

  # The earliest possible checkmate is after 4 plies. No reason to check earlier
  if len(self.move_list) > 3:
    # If there are no moves that get us out of check we need to see if we're in
    # check right now. If we are that's check mate. If we're not that's a stalemate.
    var
      color = if self.to_move == Color.WHITE: Color.BLACK else: Color.WHITE
      responses = self.generate_moves(color)
    if len(responses) == 0:
        var check = self.current_state.is_in_check(color)
        if check:
            if self.to_move == Color.WHITE:
                self.status = Status.WHITE_VICTORY
            else:
                self.status = Status.BLACK_VICTORY
        else:
            self.status = Status.DRAW

  self.to_move = if self.to_move == Color.WHITE: Color.BLACK else: Color.WHITE
  self.move_list.add(legality.alg)


proc unmake_move(self: Board)=
  self.current_state = clone(self.game_states.pop())
  discard self.move_list.pop() # Take the last move off the move list as well.
  self.to_move = if self.to_move == Color.BLACK: Color.WHITE else: Color.BLACK


proc to_fen*(self: Board): string=
  var fen: seq[string] = @[]

  # Loops over the board and gets the item at each location.
  for y in 0..7:
    for x in 0..7:
      # Adds pieces to the FEN. Lower case for black, and upper
      # for white. Since the dict is in uppercase we don't have
      # do to anything for that.
      var piece = self.current_state[y, x]
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
  if self.to_move == Color.WHITE:
      fen.add("w")
  else:
      fen.add("b")

  # The next field is castling rights.
  fen.add(" ")
  var castle_names = {"WKR" : "K", "WQR" : "Q", "BKR" : "k", "BQR" : "q"}.toTable
  var at_least_one = false
  for key, val in self.castle_rights:
    if val:
      at_least_one = true
      fen.add(castle_names[key])

  # Adds a dash if there are no castling rights.
  if not at_least_one:
    fen.add("-")

  var last_move: string
  const pieces = "RNQBK"
  # En passant target square next. From wikipedia: If a pawn has just
  # made a two-square move, this is the position "behind" the pawn.
  var found: bool
  fen.add(" ")
  if len(self.move_list) == 0:
    fen.add("-")
    found = true
  else:
    last_move = self.move_list[^1]
    # If any piece is in the move, it obviously wasn't a pawn, so we
    # have no en passant square. Even if it's a pawn promotion. You
    # can't move two into a promotion.
    for p in pieces:
      if p in last_move:
        fen.add("-")
        found = true

  if not found:
    # Moves in move list are always in long algebraic, so if we get
    # here we know that the first two characters are the start,
    # and the second two are the end. If the difference is 2 then
    # we can add the place in between to the fen.
    var
      endfile = ascii_lowercase.find(last_move[^2]) # File = x
      endrank = 8 - parseInt($last_move[^1]) # Rank = y
    let fin: tuple[y, x: int] = (endrank, endfile)

    var
      startfile = ascii_lowercase.find(last_move[0]) # File = x
      startrank = 8 - parseInt($last_move[1]) # Rank = y
    let start: tuple[y, x: int] = (startrank, startfile)

    var diff = (abs(fin.y - start.y), abs(fin.x - start.x))
    if diff == (2, 0):
      fen.add($ascii_lowercase[fin.x])
      fen.add($(8 - (start.y + fin.y) / 2))

  # Then the half move clock for the 50 move rule.
  fen.add(" ")
  fen.add($self.half_move_clock)

  # And finally the move number.
  fen.add(" ")
  fen.add($(len(self.move_list) div 2))

  return fen.join("")


proc load_fen*(fen: string): Board=
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
    side_to_move = if fields[1] == "w": Color.WHITE else: Color.BLACK
    # Castling rights
    castle_dict = {"WQR" : false, "WKR" : false, "BQR" : false, "BKR" : false}.toTable

  let castle_names = {'K' : "WKR", 'Q' : "WQR", 'k' : "BKR", 'q' : "BQR"}.toTable
  var castling_field = fields[2]

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
    let num_plies = parseInt(fields[5]) * 2
    # Just adds temporary digits to the move list so it's the right length
    # for saving a fen.
    for i in 1..num_plies:
      temp_move_list.add($i & "Q")

  result = Board(half_move_clock: half_move, game_states: @[],
      current_state: board_state.toTensor, castle_rights: castle_dict,
      to_move: side_to_move, status: Status.IN_PROGRESS, move_list: temp_move_list)


proc load_pgn*(name: string, folder: string="games"): Board=
  # File location of the pgn.
  var loc = folder & "/" & name

  # In case you pass the name without .pgn at the end.
  if not loc.endsWith(".pgn"):
    loc = loc & ".pgn"

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

  var moves_line = game_line.join("")

  # Loops as long as there's an opening comment character.
  while '{' in moves_line:
    var
      before = moves_line[0..<moves_line.find('{')]
      after = moves_line[moves_line.find('}') + 1..^1]
    moves_line = before & after

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

  return

#proc save_pgn(b: Board)=

