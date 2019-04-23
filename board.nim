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
    #to_move:
    half_move_clock*: int
    game_states*: seq[Tensor[int]]
    current_state*: Tensor[int]


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

  result = Board(half_move_clock: 0, game_states: @[], current_state: start_board)
  return result


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
  # Tensors aren't reference based so this works.
  var new_state = self.current_state

  var piece:char = 'P' # Default to pawn, this generally is changed.
  for i, c in move:
      # A [piece] character
      # If we have an = then this is the piece the pawn promotes to.
      if c.isUpperAscii():
          piece = c

  # Uses regex to find the rank/file combinations.
  var locs = findAll(move, re"[a-h]\d+")

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


proc is_in_check(self: Board, color: Color): bool=
  return false


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
    var check = self.is_in_check(color)

    if not check:
      # If the number of times that the short moves appears is more than 1 we
      # want to append the long move.
      # moves_tensor[1..^1,0] slices out only the short algebraic moves.
      if moves_tensor[1..^1,0].toSeq.count(m[0]) > 1:
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


#proc generate_castle_moves(self: Board, color: Color): tuple[alg: string, state: Tensor[int]]=

#proc make_move(self: Board, move: string)=

#proc unmake_move(self: Board)=

#proc check_move_legality(self: Board, move: string): tuple[legal: bool, alg: string]=

#proc short_algebraic_to_long_algebraic(self: Board, move: string): string=

#proc castle_algebraic_to_board_state(self: Board, move: string): Tensor[int]=

#proc to_fen(self: Board): string=

#proc load_fen(fen: string): Board=

#proc load_pgn(name: string, loc: string) Board=

#proc save_pgn(b: Board)=

#proc is_checkmate(self: Board, color: Color): bool=
