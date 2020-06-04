# import strformat
import sequtils
import tables

import arraymancer

import board

# D_in is input dimension
# D_out is output dimension.
let
  (D_in*, H1, H2, D_out) = (110, 256, 128, 1)

  # Code name and test status for whever I need it.
  # Test status changes with each change to the internal variations on the
  # network (hidden layer sizes for example)
  # Input vector changes and large scale changes to internal network structure
  # like number of hidden layers whill get their own code name.
  base_version* = "noctiluca" # A bioluminescent jellyfish

  piece_index = {'P': 0, 'N': 1, 'R': 2, 'B': 3, 'Q': 4}.toTable

  # Create the autograd context that will hold the computational graph
var ctx* = newContext Tensor[float32]

# This is where the network itself is actually defined.
network ctx, ChessNet:
  layers:
    fc1: Linear(D_in, H1)
    fc2: Linear(H1, H2)
    fc3: Linear(H2, D_out)
  forward x:
    x.fc1.relu.fc2.relu.fc3.tanh

# Initialize the model, in general we'll load a weights file for this.
# I really hope you're not running it with random weights....
var model* = ctx.init(ChessNet)

# proc prep_board_for_network*(board: Board): Tensor[float32] =
#   result = zeros[float32](D_in)

#   for piece in board.piece_list[WHITE]:
#     # We always have a king on both sides so we're not counting them
#     if piece.name == 'K' : continue
#     result[piece_index[piece.name]] += 1

#   for piece in board.piece_list[BLACK]:
#     if piece.name == 'K' : continue
#     result[piece_index[piece.name] + 5] += 1

# Turns a piece into a position in the network ready tensor.
template piece_to_position(piece: Piece, color: Color) =
  # This whole template is mildly magic numbery nonsense. Trust that it works
  # and if you don't believe me run test_net.
  # The start of the number of each piece count for each color
  let num_start = if color == WHITE: 0 else: 5

  # In essence the number of things after the numbers before the pieces
  start = if color == WHITE: 4 else: 52

  val = 1

  case piece.name
  of 'P':
    # val = 1
    # Pawn numbers are stored in 0 (WHITE) and 5 (BLACK)
    result[num_start + 0] += 1
    # Pawn pieces are stored in 15-38 (WHITE) and 63-86 (BLACK)
    start = int(result[num_start + 0]) * 3 + start + 7
  of 'N':
    # val = 2
    # Knight numbers are stored in 1 (WHITE) and 6 (BLACK)
    result[num_start + 1] += 1
    # Knight pieces are stored in 39-44 (WHITE) and 87-92 (BLACK)
    if result[num_start + 1] < 3:
      start = int(result[num_start + 1]) * 3 + start + 31
    # This handles promotions, in which case we have more than 2 knights.
    # We start by looking from the end of the pawns backwards (in case we
    # haven't filled in all the pawns yet). The loops is necessary in case
    # we have more than one promotion, but in general we don't.
    else:
      start = start + 31
      while result[start] != 0:
        start -= 3
  of 'B':
    # val = 3
    # Bishop numbers are stored in 2 (WHITE) and 7 (BLACK)
    result[num_start + 2] += 1
    # Bishop pieces are stored in 45-50 (WHITE) and 93-98 (BLACK)
    if result[num_start + 2] < 3:
      start = int(result[num_start + 2]) * 3 + start + 37
    else:
      start = start + 31
      while result[start] != 0:
        start -= 3
  of 'R':
    # val = 4
    # Rook numbers are stored in 3 (WHITE) and 8 (BLACK)
    result[num_start + 3] += 1
    # Rook pieces are stored in 51-56 (WHITE) and 99-104 (BLACK)
    if result[num_start + 3] < 3:
      start = int(result[num_start + 3]) * 3 + start + 43
    else:
      start = start + 31
      while result[start] != 0:
        start -= 3
  of 'Q':
    # Queen numbers are stored in 4 (WHITE) and 9 (BLACK)
    # val = 5
    result[num_start + 4] += 1
    # Queen piece is stored in 57-59 (WHITE) and 105-107 (BLACK)
    if result[num_start + 4] < 2:
      start = 52 + start
    else:
      start = start + 31
      while result[start] != 0:
        start -= 3
  else:
    # King piece is stored in 60-62 (WHITE) and 108-110 (BLACK)
    # val = 6
    start = 55 + start


proc prep_board_for_network*(board: Board): Tensor[float32] =
  # Structure:
    # 0-4: Num of white pieces (excluding King)
    # 5-9: Num of black pieces (Excluding King)
    # 10: Side to move
    # 11-12: White castling rights (King, Queen)
    # 13-14: Black castling rights (King, Queen)
    # 15-62: White piece slots: Pawn, Knight, Bishop, Rook, Queen, King
    # 63-110: Black piece slots: Pawn, Knight, Bishop, Rook, Queen, King
  result = zeros[float32](110)

  for color in  [WHITE, BLACK]:
    for piece in board.piece_list[color]:
      #let sq = float(piece.pos.y * 8 + piece.pos.x)
      var
        start: int
        val: float

      piece_to_position(piece, color)

      # Converts the 0-8 coordinates into -4-4 coordinates. I'm pretty sure but
      # not convinced that this will be better for the engine to learn center is good
      # might even invert these bad boys at some point.
      result[start] = val
      result[start + 1] = if piece.pos.y > 3: float(piece.pos.y - 3)
                          else: float(piece.pos.y - 4)
      result[start + 2] = if piece.pos.x > 3: float(piece.pos.x - 3)
                          else: float(piece.pos.x - 4)

  # Side to move
  # result[10] = 0#if board.to_move == WHITE: 1 else: -1

  # Castling rights
  var rights = board.castle_rights
  for i in 10..13:
    # Pretty much just pops off the first bit and then shifts it right.
    result[i] = float32(rights and 1'u8)
    rights = rights shr 1

  result = result / 8 # Reduce network inputs to be between 0 and 1.


# Color swaps the board network tensor
proc color_swap_board*(board: Tensor[float32]): Tensor[float32] =
  result = zeros[float32](110)

  # Swaps the number of the pieces for each color
  result[0..4] = board[5..9]
  result[5..9] = board[0..4]

  # Swap the castling rights
  result[10..11] = board[12..13]
  result[12..13] = board[10..11]

  # Swaps the pieces themselves
  let
    white_start = 14
    black_start = 62
  result[white_start..<black_start] = board[black_start..<board.shape[0]]
  result[black_start..<board.shape[0]] = board[white_start..<black_start]

  # Vertically swaps the positions of the pieces.
  for i in countup(white_start + 1, board.shape[0], 3):
    if result[i] != 0:
      result[i] = -result[i]

  # Swaps side to move
  # result[10] = -board[10]