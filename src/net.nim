import strformat
import sequtils
import tables

import arraymancer

import board
# D_in is input dimension (74)
# Two layer network, H1, H2 are hidden dimensions.
# D_out is output dimension.
let
  (D_in*, H1, H2, D_out) = (75, 64, 512, 1)

  # Code name and test status for whever I need it.
  # Test status changes with each change to the internal variations on the
  # network (hidden layer sizes for example)
  # Input vector changes and large scale changes to internal network structure
  # like number of hidden layers whill get their own code name.
  base_version* = "box-t5"

  # Create the autograd context that will hold the computational graph
var ctx* = newContext Tensor[float32]

# This is where the network itself is actually defined.
network ctx, ChessNet:
  layers:
    fc1: Linear(D_in, H1)
    fc2: Linear(H1, D_out)
    #fc3: Linear(H2, D_out)
  # For continuous outputs its typical to sometimes use sigmoids here.
  # Giraffe used RELUs, I currently achieve better results with sigmoids.
  # I'll have to investigate that more.
  forward x:
    x.fc1.sigmoid.fc2.tanh

# Initialize the model, in general we'll load a weights file for this.
# I really hope you're not running it with random weights....
var model* = ctx.init(ChessNet)

# Turns a piece into a position in the network ready tensor.
template piece_to_position(piece: Piece, color: Color) =
  # The start of the number of each piece count for each color
  let num_start = if color == WHITE: 0 else: 5
  start = if color == WHITE: 1 else: 33

  case piece.name
  of 'P':
    val = 1
    # Pawn numbers are stored in 0 (WHITE) and 5 (BLACK)
    result[num_start + 0] += 1
    # Pawn pieces are stored in 11-26 (WHITE) and 43-58 (BLACK)
    start = 8 + int(result[num_start + 0]) * 2 + start
  of 'N':
    val = 2
    # Knight numbers are stored in 1 (WHITE) and 6 (BLACK)
    result[num_start + 1] += 1
    # Knight pieces are stored in 27-30 (WHITE) and 59-62 (BLACK)
    if result[num_start + 1] < 3:
      start = 24 + int(result[num_start + 1]) * 2 + start
    # This handles promotions, in which case we have more than 2 knights.
    # We start by looking from the end of the pawns backwards (in case we
    # haven't filled in all the pawns yet). The loops is necessary in case
    # we have more than one promotion, but in general we don't.
    else:
      start = 26
      while result[start] != -1:
        start -= 2
  of 'B':
    val = 3
    # Bishop numbers are stored in 2 (WHITE) and 7 (BLACK)
    result[num_start + 2] += 1
    # Bishop pieces are stored in 31-34 (WHITE) and 63-66 (BLACK)
    if result[num_start + 2] < 3:
      start = 28 + int(result[num_start + 2]) * 2 + start
    else:
      start = 26
      while result[start] != -1:
        start -= 2
  of 'R':
    val = 4
    # Rook numbers are stored in 3 (WHITE) and 8 (BLACK)
    result[num_start + 3] += 1
    # Rook pieces are stored in 35-38 (WHITE) and 67-70 (BLACK)
    if result[num_start + 3] < 3:
      start = 32 + int(result[num_start + 3]) * 2 + start
    else:
      start = 26
      while result[start] != -1:
        start -= 2
  of 'Q':
    # Queen numbers are stored in 4 (WHITE) and 9 (BLACK)
    val = 5
    result[num_start + 4] += 1
    # Queen piece is stored in 39-40 (WHITE) and 71-72 (BLACK)
    if result[num_start + 4] < 2:
      start = 38 + start
    else:
      start = 26 + start
      while result[start] != -1:
        start -= 2
  else:
    # King piece is stored in 41-42 (WHITE) and 73-74 (BLACK)
    val = 6
    start = 40 + start


proc prep_board_for_network*(board: Board): Tensor[float32] =
  # Structure:
    # 0-4: Num of white pieces (excluding King)
    # 5-9: Num of black pieces (Excluding King)
    # 11-42: White piece slots: Pawn, Knight, Bishop, Rook, Queen, King
    # 43-74: Black piece slots: Pawn, Knight, Bishop, Rook, Queen, King
    # 74: Side to move
  result = concat(zeros[float32](10), ones[float32](65) * -1, axis=0)

  for color in  [WHITE, BLACK]:
    for piece in board.piece_list[color]:
      let sq = float(piece.pos.y * 8 + piece.pos.x)
      var
        start: int
        val: float

      piece_to_position(piece, color)

      result[start] = val
      result[start + 1] = sq
  # Side to move
  result[10] = if board.to_move == WHITE: 1 else: -1


# Color swaps the board network tensor
proc color_swap_board*(board: Tensor[float32]): Tensor[float32] =
  result = concat(zeros[float32](10), ones[float32](65) * -1, axis=0)

  # Swaps the number of the pieces for each color
  result[0..4] = board[5..9]
  result[5..9] = board[0..4]

  # Swaps the pieces themselves
  let
    white_start = 11
    black_start = 43
  result[white_start..<black_start] = board[black_start..74]
  result[black_start..74] = board[white_start..<black_start]

  # Vertically swaps the positions of the pieces.
  for i in countup(white_start + 1, 74, 2):
    result[i] = float(int(result[i]) xor 56)

  # Swaps side to move
  result[10] = if board[10] == 1: -1 else: 1