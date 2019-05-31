import bitops
import math
import os
import re
import sequtils
import strutils
import system
import tables
import times

import arraymancer

import bitboard

type
  Color* = enum
    WHITE, BLACK

  Status = enum
    IN_PROGRESS, DRAW, WHITE_VICTORY, BLACK_VICTORY

  Piece* = ref object
    name*: char
    pos*: Position
    square*: string

    # The square that's pinning this piece.
    pinned: string

  Move* = ref object
    start*: Position
    fin*: Position
    algebraic*: string

  Board* = ref object
    to_move*: Color
    half_move_clock*: int
    game_states*: seq[Tensor[int]]
    current_state*: Tensor[int]
    castle_rights*: uint32
    castle_history*: array[8, int]
    move_list*: seq[Move]
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

    piece_list*: Table[Color, seq[Piece]]

    # Bitmaps of all the pieces for a color
    WHITE_PIECES*: uint64
    BLACK_PIECES*: uint64

    # Bitmaps for all the attacks by a certain color.
    WHITE_ATTACKS*: uint64
    BLACK_ATTACKS*: uint64

  # Custom move list types
  DisambigMove* = tuple[algebraic: string, state: Tensor[int]]
  ShortAndLongMove* = tuple[short: string, long: string, state: Tensor[int]]


# The piece number -> piece name table.
const
  # These values are centipawn versions of values taken from "Beginner's Guide
  # to Winning Chess" the book that basically taught me all  my chess skills.
  piece_names* = {100: 'P', 500: 'R', 310: 'N',
                  300: 'B', 900: 'Q', 1000: 'K'}.toOrderedTable

var temp: seq[tuple[key: char, val: int]] = @[]
for key, value in piece_names:
  temp.add((value, key))

let
  # The reverse piece name -> piece number table.
  piece_numbers* = temp.toTable

  # The lowercase ascii alphabet.
  ascii_lowercase* = toSeq 'a'..'z'

  # Table of algebraic squares.
  alg_table* = @[["a8", "b8", "c8", "d8", "e8", "f8", "g8", "h8"],
                ["a7", "b7", "c7", "d7", "e7", "f7", "g7", "h7"],
                ["a6", "b6", "c6", "d6", "e6", "f6", "g6", "h6"],
                ["a5", "b5", "c5", "d5", "e5", "f5", "g5", "h5"],
                ["a4", "b4", "c4", "d4", "e4", "f4", "g4", "h4"],
                ["a3", "b3", "c3", "d3", "e3", "f3", "g3", "h3"],
                ["a2", "b2", "c2", "d2", "e2", "f2", "g2", "h2"],
                ["a1", "b1", "c1", "d1", "e1", "f1", "g1", "h1"]].toTensor

  flat_alg_table* = alg_table.reshape(64)

  # Regular expressions for finding strings in algebraic moves.
  loc_finder* = re"[a-h]\d+"
  rank_finder = re"\d+"
  file_finder = re"[a-h]"
  piece_finder = re"[PRNQKB]"
  illegal_piece_finder = re"[A-Z]"


# Forward declarations for use of this later. These are mostly declared so
# that I can use them in movegen.nim.
proc new_board*(): Board
proc make_move*(board: Board, move: Move, skip: bool= false)
proc unmake_move*(board: Board)
proc is_in_check*(board: Board, color: Color): bool

proc update_piece_list*(board: Board, move: Move)
proc revert_piece_list*(board: Board, move: Move)
proc update_piece_bitmaps*(board: Board, move: Move)

# Finds the piece in the board using the piece list.
proc find_piece*(board: Board, color: Color, name: char): seq[Position] =
  # Loop through and find the required piece Positions.
  for piece in board.piece_list[color]:
    if piece.name == name:
      result.add(piece.pos)

# Put these first in case I need to print the board or a piece_list for
# debug purposes.
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


proc `$`*(piece: Piece): string=
  result = result & "Name: " & piece.name & " "
  result = result & "Position: (" & $piece.pos.y & ", " & $piece.pos.x & ") "
  result = result & "Square: " & piece.square & " "


# Convert the row and column Positions to an algebraic chess move.
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


# This import needs to be after the type and constant declaration since those
# are both used in move gen.
import movegen


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

  else:
    let moves = board.generate_attack_mask(piece, start)
    return moves.testBit((7 - fin.y) * 8 + fin.x)


proc is_in_check*(board: Board, color: Color): bool =
  let
    # The direction a pawn must travel to take this color's king.
    # I.e. Black pawns must travel in the positive y (downward) direction
    # To take a white king.
    d = if color == WHITE: 1 else: -1
    opp_color = if color == WHITE: BLACK else: WHITE

  var
    # For this I'll assume there's only one king.
    king = board.find_piece(color, 'K')[0]

  for piece in board.piece_list[opp_color]:
    if piece.name == 'P':
      if piece.pos == (king.y - d, king.x - 1) or
         piece.pos == (king.y - d, king.x + 1):
          return true
    else:
      let attacks = board.generate_attack_mask(piece.name, piece.pos)

      if attacks.testBit((7 - king.y) * 8 + king.x):
        return true


proc short_algebraic_to_long_algebraic*(board: Board, move: string): string =
  var new_move = move
  # A move is minimum two characters (a rank and a file for pawns)
  # so if it's shorter it's not a good move.
  if len(move) < 2:
    return

  # You're not allowed to castle out of check.
  if ("O-O" in move or "0-0" in move) and board.is_in_check(board.to_move):
    return

  # Slices off the checkmate character for parsing. This is largely so that
  # castling into putting the opponent in check parses correctly.
  if move.endsWith('+') or move.endsWith('#'):
    new_move = new_move[0 ..< ^1]

  # Castling is the easiest to check for legality.
  let
    # The rank the king is on.
    king_rank = if board.to_move == WHITE: 7 else: 0

  # Kingside castling
  if new_move == "O-O" or new_move == "0-0":
    var
      check_side = if board.to_move == WHITE: (board.castle_rights and 0x8) == 0x8
                   else: (board.castle_rights and 0x2) == 0x2
      # The two spaces between the king and rook.
      between = board.current_state[king_rank, 5..6]

    if check_side and sum(abs(between)) == 0:
      # Need to check that we don't castle through check here.
      var
        alg = if board.to_move == WHITE: "Kf1" else: "Kf8"
        test_move = Move(start: (king_rank, 4), fin: (king_rank, 5), algebraic: alg)

      let check = board.check_move_for_check(test_move, board.to_move)

      if not check:
        return new_move
      else:
        return
    else:
      return
  # Queenside castling
  elif new_move == "O-O-O" or new_move == "0-0-0":
    var
      check_side = if board.to_move == WHITE: (board.castle_rights and 0x4) == 0x4
                   else: (board.castle_rights and 0x1) == 0x1
      # The three spaces between the king and rook.
      between = board.current_state[king_rank, 1..3]

    if check_side and sum(abs(between)) == 0:
      # Need to check that we don't castle through check here.
      var
        alg = if board.to_move == WHITE: "Kd1" else: "Kd8"
        test_move = Move(start: (king_rank, 4), fin: (king_rank, 3), algebraic: alg)

      let check =  board.check_move_for_check(test_move, board.to_move)

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

  var found_pieces = board.find_piece(board.to_move, piece_char)

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
                 alg: string): bool =
    var test_move = Move(start: start, fin: fin, algebraic: alg)
    result = not board.check_move_for_check(test_move, board.to_move)
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

    let can_make = can_make_move(board, pos, fin, piece_char)

    if can_make:
      if promotion:
        result = board.row_column_to_algebraic(pos, fin, piece_num,
                                                promotion_piece)[1]
      else:
        result = board.row_column_to_algebraic(pos, fin, piece_num)[1]
      if ep:
        result = result & "e.p."

      let no_check = good_move(pos, fin, piece_num, result)

      if not no_check:
        result = ""

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
    #var end_state = board.castle_algebraic_to_boardstate(long_move,
     #                                                    board.to_move)
    let rank = if board.to_move == WHITE: 7 else: 0
    var test_move: Move
    if long_move == "O-O":
      test_move = Move(start: (rank, 4), fin: (rank, 6), algebraic: long_move)
    else:
      test_move = Move(start: (rank, 4), fin: (rank, 2), algebraic: long_move)

    check = board.check_move_for_check(test_move, board.to_move)

  if check:
    return

  result = (true, long_move)


proc is_checkmate*(board: Board, color: Color): bool =
  let check = board.is_in_check(color)

  # Result is auto instantiated to false.
  if not check:
    return

  # Check if there are any possible moves that could get color out of check.
  # In hindsight a very hacky way to do this.
  let responses = board.generate_all_moves(color)

  if len(responses) == 0:
    result = true

proc update_ep_square(board: Board, move: Move) =
  let
    loc = move.algebraic[^2..^1]

  var square = if board.to_move == WHITE: flat_alg_table.find(loc) + 8
               else: flat_alg_table.find(loc) - 8

  if square > -1 and square < 64 and
     board.current_state[square div 8, square mod 8] == 0:
    board.ep_square[board.to_move] = flat_alg_table[square]


proc update_piece_list*(board: Board, move: Move) =
  var
    opp_color = if board.to_move == WHITE: BLACK else: WHITE
    end_alg = alg_table[move.fin.y, move.fin.x]

  # Castling is totally different so avoid doing everything else first.
  # This is a bit of a disaster.
  if "O-O" in move.algebraic:
    var
      rook_start: Position
      rook_end: Position

    if move.algebraic == "O-O":
      rook_start = (move.fin.y, 7)
      rook_end = (move.fin.y, 5)
    else:
      rook_start = (move.fin.y, 0)
      rook_end = (move.fin.y, 3)

    let king_end = alg_table[move.fin.y, move.fin.x]
    let rook_end_square = alg_table[rook_end.y, rook_end.x]
    for p in board.piece_list[board.to_move]:
      if p.name == 'K':
        p.pos = move.fin
        p.square = king_end
      elif p.name == 'R' and p.pos == rook_start:
        p.pos = rook_end
        p.square = rook_end_square
    return

  let
    end_square = move.fin.y * 8 + move.fin.x
    squares = board.piece_list[opp_color].map(proc(x: Piece): string = x.square)
  # Removes the piece that gets taken from the opposite list.
  if 'x' in move.algebraic:
    let index = squares.find(end_alg)
    board.piece_list[opp_color].delete(index)
  # Need to handle en passant on its own since it's weird.
  elif "e.p." in move.algebraic:
    var ep_square = if opp_color == BLACK: end_square + 8 else: end_square - 8
    let index = squares.find(flat_alg_table[ep_square])
    board.piece_list[opp_color].delete(index)

  for p in board.piece_list[board.to_move]:
    if p.pos == move.start:
      p.pos = move.fin
      p.square = alg_table[move.fin.y, move.fin.x]

      # Update name on promotion
      if '=' in move.algebraic:
        p.name = move.algebraic[^1]

      # No need to continue searching.
      break


proc revert_piece_list*(board: Board, move: Move) =
  var
    opp_color = if board.to_move == WHITE: BLACK else: WHITE

  # Castling is totally different so avoid doing everything else first.
  if "O-O" in move.algebraic:
    var
      rook_start: Position
      rook_end: Position

    if move.algebraic == "O-O":
      rook_start = (move.fin.y, 5)
      rook_end = (move.fin.y, 7)
    else:
      rook_start = (move.fin.y, 3)
      rook_end = (move.fin.y, 0)

    let king_end = alg_table[move.start.y, move.start.x]
    let rook_end_square = alg_table[rook_end.y, rook_end.x]
    for p in board.piece_list[board.to_move]:
      if p.name == 'K':
        p.pos = move.start
        p.square = king_end
      elif p.name == 'R' and p.pos == rook_start:
        p.pos = rook_end
        p.square = rook_end_square
    return

  # Adds back a piece that was taken using the mailbox board state to see
  # what used to be there.
  if 'x' in move.algebraic:
    var piece_name = piece_names[abs(board.current_state[move.fin.y, move.fin.x])]
    board.piece_list[opp_color].add(Piece(name: piece_name,
                                          square: alg_table[move.fin.y, move.fin.x],
                                          pos: (move.fin.y, move.fin.x)))
  # Need to handle en passant on its own since it's weird.
  elif "e.p." in move.algebraic:
    board.piece_list[opp_color].add(Piece(name: 'P',
                                          square: alg_table[move.start.y, move.fin.x],
                                          pos: (move.start.y, move.fin.x)))

  for p in board.piece_list[board.to_move]:
    if p.pos == move.fin:
      p.pos = move.start
      p.square = alg_table[move.start.y, move.start.x]

      # Revert promotion
      if '=' in move.algebraic:
        p.name = 'P'

      # No need to continue searching.
      break


proc update_piece_bitmaps*(board: Board, move: Move) =
  var
    bit_start = ((7 - move.start.y) * 8 + move.start.x)
    bit_end = ((7 - move.fin.y) * 8 + move.fin.x)
    update = 0'u64

  # Set the bits in the update, which with xor will clear the start and set
  # the end or vice versa if we're going in reverse.
  update.setBit(bit_end)
  if "e.p." in move.algebraic:
    var ep_clear: uint64
    if board.to_move == WHITE:
      ep_clear = update shr 8
      board.BLACK_PIECES = board.BLACK_PIECES xor ep_clear
    else:
      ep_clear = update shl 8
      board.WHITE_PIECES = board.WHITE_PIECES xor ep_clear
  elif "x" in move.algebraic:
    if board.to_move == WHITE:
      board.BLACK_PIECES = board.BLACK_PIECES xor update
    else:
      board.WHITE_PIECES = board.WHITE_PIECES xor update

  update.setBit(bit_start)
  if "O-O" in move.algebraic:
    if move.algebraic == "O-O":
      update.setBit((7 - move.start.y) * 8 + 7)
      update.setBit((7 - move.fin.y) * 8 + 5)
    else:
      update.setBit((7 - move.start.y) * 8)
      update.setBit((7 - move.fin.y) * 8 + 3)

  if board.to_move == WHITE:
    board.WHITE_PIECES = board.WHITE_PIECES xor update

  else:
    board.BLACK_PIECES = board.BLACK_PIECES xor update


proc update_attack_bitmaps(board: Board, color: Color) =
  if color == WHITE: board.WHITE_ATTACKS = 0 else: board.BLACK_ATTACKS = 0
  for piece in board.piece_list[color]:
    # Gets the attacks for this piece then adds them to the mask using or.
    let attacks = board.generate_attack_mask(piece.name, piece.pos, color)
    if color == WHITE:
      board.WHITE_ATTACKS = board.WHITE_ATTACKS or attacks
    else:
      board.BLACK_ATTACKS = board.BLACK_ATTACKS or attacks


template check_for_moves(moves: seq[Move]): void=
  if len(moves) > 0:
    noresponses = false
    break movechecking


template move_to_tensor*(move: Move) =
  #result = clone(board.current_state)
  let sign = sgn(board.current_state[move.start.y, move.start.x])
  # This allows us to handle promotions with "grace".
  piece = if piece == 'O': 'K' elif '=' in move.algebraic: move.algebraic[^1] else: piece
  board.current_state[move.fin.y, move.fin.x] = sign * piece_numbers[piece]
  board.current_state[move.start.y, move.start.x] = 0

  # Moves the rook for castling moves.
  if "O-O" in move.algebraic:
    if move.algebraic == "O-O":
      board.current_state[move.fin.y, 5] = board.current_state[move.start.y, 7]
      board.current_state[move.start.y, 7] = 0
    else:
      board.current_state[move.fin.y, 3] = board.current_state[move.start.y, 0]
      board.current_state[move.start.y, 0] = 0
  # Deletes the pawn we take in en passant.
  elif "e.p." in move.algebraic:
    board.current_state[move.start.y, move.fin.x] = 0



proc make_move*(board: Board, move: Move, skip: bool = false) =
  let
    to_move = if board.to_move == WHITE: BLACK else: WHITE
    castle_move = "O-O" in move.algebraic or "0-0" in move.algebraic
    # The index to update in the castling history.
    index = 7 - board.castle_rights.countLeadingZeroBits() div 4

  board.castle_history[index] += 1

  var piece = 'P'

  for i, c in move.algebraic:
    # If we have an = then this is the piece the pawn promotes to.
    # Pawns can promote to rooks which would fubar the dict.
    if c.isUpperAscii() and not ('=' in move.algebraic):
      piece = c

  if piece == 'P':
    board.update_ep_square(move)

  # Updates the castle table for castling rights.
  # This block removes castling from both sides if the king moves.
  if piece == 'K' or castle_move:
    # This line moves the current castling rights to the left and duplicates
    # it into the first four bits. 15 is the value of all four first bits set.
    board.castle_rights = (board.castle_rights and 15'u32) or (board.castle_rights shl 4)
    if board.to_move == WHITE:
      board.castle_rights = board.castle_rights and (BLACK_CASTLING or not 15'u32)
    else:
      board.castle_rights = board.castle_rights and (WHITE_CASTLING or not 15'u32)
  elif piece == 'R':
    board.castle_rights = (board.castle_rights and 15'u32) or (board.castle_rights shl 4)
    # Can use the magic of tuple equality for this now.
    if move.start == (0, 0):
      board.castle_rights = board.castle_rights and (not BLACK_QUEENSIDE)
    elif move.start == (0, 7):
      board.castle_rights = board.castle_rights and (not BLACK_KINGSIDE)
    elif move.start == (7, 0):
      board.castle_rights = board.castle_rights and (not WHITE_QUEENSIDE)
    elif move.start == (7, 7):
      board.castle_rights = board.castle_rights and (not WHITE_KINGSIDE)

  # We need to update castling this side if the rook gets taken without
  # ever moving. We can't castle with a rook that doesn't exist.
  if board.to_move == WHITE:
    if "xa8" in move.algebraic:
      board.castle_rights = (board.castle_rights and 15'u32) or (board.castle_rights shl 4)
      board.castle_rights = board.castle_rights and (not BLACK_QUEENSIDE)
    elif "xh8" in move.algebraic:
      board.castle_rights = (board.castle_rights and 15'u32) or (board.castle_rights shl 4)
      board.castle_rights = board.castle_rights and (not BLACK_KINGSIDE)
  else:
    if "xa1" in move.algebraic:
      board.castle_rights = (board.castle_rights and 15'u32) or (board.castle_rights shl 4)
      board.castle_rights = board.castle_rights and (not WHITE_QUEENSIDE)
    elif "xh1" in move.algebraic:
      board.castle_rights = (board.castle_rights and 15'u32) or (board.castle_rights shl 4)
      board.castle_rights = board.castle_rights and (not WHITE_KINGSIDE)


  # Need to update the piece positions in the bit maps before we check for
  # checkmate.
  board.update_piece_list(move)
  board.update_piece_bitmaps(move)

  # Does all the updates.
  # Updates the half move clock.
  if piece == 'P' or 'x' in move.algebraic:
    board.half_move_clock = 0
  else:
    board.half_move_clock += 1

  board.game_states.add(clone(board.current_state))

  move_to_tensor(move)

  board.to_move = to_move
  # Clear the ep square from the opposite color as its no longer in play
  board.ep_square[to_move] = ""
  board.move_list.add(move)

  # For now update both attack bitmaps.
  board.update_attack_bitmaps(WHITE)
  board.update_attack_bitmaps(BLACK)

  # The earliest possible checkmate is after 4 plies. No reason to check earlier
  if len(board.move_list) > 3 and not skip:
    # If there are no moves that get us out of check we need to see if we're in
    # check right now. If we are that's check mate. If we're not that's a stalemate.
    var
      noresponses = true

    # Progressively checking the moves allows us to break as soon as we find a
    # move instead of generating all of them at once just to see if there
    # are no possible moves.
    block movechecking:
      check_for_moves(board.generate_pawn_moves(to_move))
      check_for_moves(board.generate_pawn_captures(to_move))
      check_for_moves(board.generate_knight_moves(to_move))
      check_for_moves(board.generate_rook_moves(to_move))
      check_for_moves(board.generate_bishop_moves(to_move))
      check_for_moves(board.generate_queen_moves(to_move))
      check_for_moves(board.generate_king_moves(to_move))
      check_for_moves(board.generate_castle_moves(to_move))

    if noresponses:
      var check = board.is_in_check(to_move)
      if check:
        if board.to_move == WHITE:
          board.status = WHITE_VICTORY
        else:
          board.status = BLACK_VICTORY
      else:
        board.status = DRAW


proc make_move*(board: Board, move: string) =
  let legality = board.check_move_legality(move)

  if not legality.legal:
    raise newException(ValueError, "You tried to make an illegal move!")

  # Since queenside is the same as kingside with an extra -O on the end
  # we can just check that the kingside move is in the move.
  var
    castle_move = "O-O" in legality.alg or "0-0" in legality.alg
    big_move = Move(start: (0, 0), fin: (0,0), algebraic: "")

  big_move.algebraic = legality.alg

  if castle_move:
    # The rank that castling takes place on.
    let rank = if board.to_move == WHITE: 7 else: 0
    if legality.alg == "O-O" or legality.alg == "0-0":
      big_move.start = (rank, 4)
      big_move.fin = (rank, 6)
    else:
      big_move.start = (rank, 4)
      big_move.fin = (rank, 2)

  else:
    # Uses regex to find the rank/file combinations.
    let locs = findAll(legality.alg, loc_finder)

    # Gets the starting Position and puts into a constant
    var
      dest = locs[0]
      file = ascii_lowercase.find(dest[0]) # File = x
      rank = 8 - parseInt($dest[1]) # Rank = y

    big_move.start = (rank, file)

    # Gets the ending Position.
    dest = locs[1]
    file = ascii_lowercase.find(dest[0]) # File = x
    rank = 8 - parseInt($dest[1]) # Rank = y

    big_move.fin = (rank, file)

  make_move(board, big_move)


proc unmake_move*(board: Board) =
  board.current_state = board.game_states.pop() # Reverts the mailbox board.
  var move = board.move_list.pop() # Take the last move off the move list.
  # We can extract the ep square from the previous move. We have to do this
  # before we change the to_move, since we need the to_move of the move two
  # turns ago (which is the same as the to_move as right now)
  if len(board.move_list) > 0:
    board.update_ep_square(board.move_list[^1])
  board.to_move = if board.to_move == WHITE: BLACK else: WHITE # Invert color
  board.ep_square[board.to_move] = ""
  board.revert_piece_list(move) # Move that piece list back.
  board.update_piece_bitmaps(move) # Reverts the piece bitmaps to the old state.
  board.status = IN_PROGRESS # Whatever it was now, before it was in progress.

  # Reverts the castling state or reduces the castle history depending.
  # Need this if block here because if it's 0 the compiler likes to do its own thing.
  let index = if board.castle_rights == 0'u32: 0
              else: 7 - (board.castle_rights.countLeadingZeroBits() div 4)

  if board.castle_history[index] == 0:
    board.castle_rights = board.castle_rights shr 4
    if index > 0:
      board.castle_history[index - 1] -= 1
  else:
    board.castle_history[index] -= 1

  # For now update both attack bitmaps.
  board.update_attack_bitmaps(WHITE)
  board.update_attack_bitmaps(BLACK)


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
    castle_names = {WHITE_KINGSIDE: "K", WHITE_QUEENSIDE: "Q",
                    BLACK_KINGSIDE: "k", BLACK_QUEENSIDE: "q"}.toTable
    at_least_one = false
  for key, val in castle_names:
    if (key and board.castle_rights) == key:
      at_least_one = true
      fen.add(val)

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

  var
    board_state: seq[seq[int]] = @[]
    piece_list = initTable[Color, seq[Piece]]()
    i = 0

    # Initialize piece bit tables for move generation.
    black_pieces: uint64 = 0
    white_pieces: uint64 = 0

  # Initialize the blank piece lists.
  piece_list[BLACK] = @[]
  piece_list[WHITE] = @[]

  # Loops over each row.
  for r in rows:
    var rank: seq[int] = @[]
    # Loops over each character in the row.
    for c in r:
      if c.isDigit():
        for j in 0 ..< parseInt($c):
          i += 1
          rank.add(0)
      else:
        # Adds a black piece if the character is lower, otherwise add a white
        if c.isLowerASCII():
          rank.add(-piece_numbers[c.toUpperASCII()])
          piece_list[BLACK].add(Piece(name: c.toUpperASCII(),
                                      square: flat_alg_table[i],
                                      pos: (i div 8, i mod 8), pinned: ""))
          # Fen starts at a8 but we want the bits to start at a1 so we
          # vertically flip the bit position.
          var j = (7 - i div 8) * 8 + i mod 8
          black_pieces = black_pieces or uint64(0x1 shl j)
        else:
          rank.add(piece_numbers[c])
          piece_list[WHITE].add(Piece(name: c, square: flat_alg_table[i],
                                      pos: (i div 8, i mod 8), pinned: ""))

          var j = (7 - i div 8) * 8 + i mod 8
          white_pieces = white_pieces or uint64(0x1 shl j)
        i += 1
    # At the end of the row add it to the board_state
    board_state.add(rank)

  # Who's moving this turn.
  var
    side_to_move = if fields[1] == "w": WHITE else: BLACK
    # Castling rights
    castle_dict: uint32 = 0

  let
    castle_names = {'K': WHITE_KINGSIDE, 'Q': WHITE_QUEENSIDE,
                    'k': BLACK_KINGSIDE, 'q': BLACK_QUEENSIDE}.toTable
    castling_field = fields[2]

  # For each character in the castling field
  for c in castling_field:
    if c == '-':
      break
    var key = castle_names[c]
    castle_dict = castle_dict or key # Bitwise magic

  var
    ep_square = {WHITE: "", BLACK: ""}.toTable
    opp_color = if side_to_move == WHITE: BLACK else: WHITE

  if len(fields) > 3:
    ep_square[opp_color] = fields[3]

  # Gets the half move clock if its in the fen.
  var half_move = 0
  if len(fields) > 4:
    half_move = parseInt(fields[4])

  var temp_move_list: seq[Move] = @[]
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
        temp_move_list.add(Move(start: (0, 0), fin: (0, 0), algebraic: $i & "Q"))

  var castle_history: array[8, int] = [0, 0, 0, 0, 0, 0, 0, 0]
  result = Board(half_move_clock: half_move, game_states: @[],
                current_state: board_state.toTensor,
                castle_rights: castle_dict, to_move: side_to_move,
                status: IN_PROGRESS, move_list: temp_move_list,
                headers: initTable[string, string](), ep_square: ep_square,
                long: false, piece_list: piece_list,
                castle_history: castle_history, BLACK_PIECES: black_pieces,
                WHITE_PIECES: white_pieces, BLACK_ATTACKS: 0'u64,
                WHITE_ATTACKS: 0'u64)

  result.update_attack_bitmaps(WHITE)
  result.update_attack_bitmaps(BLACK)


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
        var line = $m.algebraic & " "

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


# Creates a new board from scratch.
proc new_board*(): Board =
  # Just loads the starting fen so we can change piece numbering easily
  result = load_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
