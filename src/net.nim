import strformat
import sequtils
import tables

import arraymancer

import board
# D_in is input dimension (74)
# Two layer network, H1, H2 are hidden dimensions.
# D_out is output dimension.
let
  (D_in*, H1, H2, D_out) = (75, 1024, 512, 1)

  # Create the autograd context that will hold the computational graph
var ctx* = newContext Tensor[float32]

# This is where the network itself is actually defined.
network ctx, ChessNet:
  layers:
    fc1: Linear(D_in, H1)
    fc2: Linear(H1, H2)
    fc3: Linear(H2, D_out)
  # For continuous outputs its typical to sometimes use sigmoids here.
  # Giraffe used RELUs, and RELUs are also much quicker to converge for
  # my purposes.
  forward x:
    x.fc1.sigmoid.fc2.sigmoid.fc3.tanh

# Initialize the model, in general we'll load a weights file for this.
# I really hope you're not running it with random weights....
var model* = ctx.init(ChessNet)

# Turns a piece into a position in the network ready tensor.
template piece_to_position(piece: Piece, color: Color) =
  # The start of the number of each piece count for each color
  let num_start = if color == WHITE: 0 else: 5
  start = if color == WHITE: 0 else: 32

  case piece.name
  of 'P':
    val = 1
    # Pawn numbers are stored in 0 (WHITE) and 5 (BLACK)
    result[num_start + 0] += 1
    # Pawn pieces are stored in 10-25 (WHITE) and 42-57 (BLACK)
    start = 8 + int(result[num_start + 0]) * 2 + start
  of 'N':
    val = 2
    # Knight numbers are stored in 1 (WHITE) and 6 (BLACK)
    result[num_start + 1] += 1
    # Knight pieces are stored in 26-29 (WHITE) and 58-61 (BLACK)
    if result[num_start + 1] < 3:
      start = 24 + int(result[num_start + 1]) * 2 + start
    # This handles promotions, in which case we have more than 2 knights.
    # We start by looking from the end of the pawns backwards (in case we
    # haven't filled in all the pawns yet). The loops is necessary in case
    # we have more than one promotion, but in general we don't.
    else:
      start = 25
      while result[start] != -1:
        start -= 2
  of 'B':
    val = 3
    # Bishop numbers are stored in 2 (WHITE) and 7 (BLACK)
    result[num_start + 2] += 1
    # Bishop pieces are stored in 30-33 (WHITE) and 62-65 (BLACK)
    if result[num_start + 2] < 3:
      start = 28 + int(result[num_start + 2]) * 2 + start
    else:
      start = 25
      while result[start] != -1:
        start -= 2
  of 'R':
    val = 4
    # Rook numbers are stored in 3 (WHITE) and 8 (BLACK)
    result[num_start + 3] += 1
    # Rook pieces are stored in 34-37 (WHITE) and 66-69 (BLACK)
    if result[num_start + 3] < 3:
      start = 32 + int(result[num_start + 3]) * 2 + start
    else:
      start = 25
      while result[start] != -1:
        start -= 2
  of 'Q':
    # Queen numbers are stored in 4 (WHITE) and 9 (BLACK)
    val = 5
    result[num_start + 4] += 1
    # Queen piece is stored in 38-39 (WHITE) and 70-71 (BLACK)
    if result[num_start + 4] < 2:
      start = 38 + start
    else:
      start = 25 + start
      while result[start] != -1:
        start -= 2
  else:
    # King piece is stored in 40-41 (WHITE) and 72-73 (BLACK)
    val = 6
    start = 40 + start


proc prep_board_for_network*(board: Board): Tensor[float32] =
  # Structure:
    # 0-4: Num of white pieces (excluding King)
    # 5-9: Num of black pieces (Excluding King)
    # 10-41: White piece slots: Pawn, Knight, Bishop, Rook, Queen, King
    # 42-73: Black piece slots: Pawn, Knight, Bishop, Rook, Queen, King
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
  result[74] = if board.to_move == WHITE: 1 else: -1


# Color swaps the board network tensor
proc color_swap_board*(board: Tensor[float32]): Tensor[float32] =
  result = concat(zeros[float32](10), ones[float32](65) * -1, axis=0)

  # Swaps the number of the pieces for each color
  result[0..4] = board[5..9]
  result[5..9] = board[0..4]

  # Swaps the pieces themselves
  result[10..41] = board[42..73]
  result[42..73] = board[10..41]

  # Vertically swaps the positions of the pieces.
  for i in countup(11, 73, 2):
    result[i] = float(int(result[i]) xor 56)

  result[74] = if board[74] == 1: -1 else: 1