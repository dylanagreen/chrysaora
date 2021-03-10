import marshal
import os
import streams
import strformat
import tables

import arraymancer

import board

# A definition of the tanh activation function. On Arraymancer > 0.5.2 compilation
# will fail as the compiler is not sure if you're referring to nnp_activation.tanh
# or ufunc.tanh. Annoying but I haven't found a great fix for it yet besides this.
# See https://github.com/mratsim/Arraymancer/issues/459
proc tanh*[T: SomeFloat](t: Tensor[T]): Tensor[T] {.noInit.} =
  t.map_inline tanh(x)

# D_in is input dimension
# D_out is output dimension.
let
  (D_in*, H1, H2, D_out) = (10, 256, 128, 1)

  # Code name and test status for whever I need it.
  # Test status changes with each change to the internal variations on the
  # network (hidden layer sizes for example)
  # Input vector changes and large scale changes to internal network structure
  # like number of hidden layers will get their own code name.
  base_version* = "noctiluca" # A bioluminescent jellyfish

# Create the autograd context that will hold the computational graph
var
  ctx* = newContext Tensor[float32]
  beta = 1

# This is where the network itself is actually defined.
network ctx, ChessNet:
  layers:
    x:   Input([D_in])
    fc1: Linear(D_in, D_out)
    # fc2: Linear(H1, H2)
    # fc3: Linear(H2, D_out)
  forward x:
    x.fc1.tanh

# "Crappy hack" - Jjp137
export forward

# Initialize the model, in general we'll load a weights file for this.
# I really hope you're not running it with random weights....
var model* = ctx.init(ChessNet)
const piece_indices: array[5, char] = ['P', 'N', 'B', 'R', 'Q']

proc prep_board_for_network*(board: Board): Tensor[float32] =
  # Structure:
  # 0-4: Num difference of pieces excluding King (White - Black)
  # 5: Side to move
  # 6-7: White castling rights (King, Queen)
  # 8-9: Black castling rights (King, Queen)
  result = zeros[float32](D_in)

  for color in  [WHITE, BLACK]:
    for piece in board.piece_list[color]:
      if piece.name == 'K': continue

      let
        diff = if color == WHITE: 1.0 else: -1.0
        ind = piece_indices.find(piece.name)

      result[ind] += diff

  # Side to move
  result[5] = if board.to_move == WHITE: 1 else: -1

  # Castling rights
  var rights = board.castle_rights
  for i in 6..9:
    # Pretty much just pops off the first bit and then shifts it right.
    result[i] = float32(rights and 1'u8)
    rights = rights shr 1

  result = result / 8 # Reduce network inputs to be between 0 and 1.


# Color swaps the board network tensor
proc color_swap_board*(board: Tensor[float32]): Tensor[float32] =
  result = zeros[float32](D_in)

  # Swaps the number of the pieces for each color
  result[0..4] = -board[0..4]
  # result[5..9] = board[0..4]

  # Swaps side to move
  result[5] = -board[5]

  # Swap the castling rights
  result[6..7] = board[8..9]
  result[8..9] = board[6..7]


# Functionality for generating a completely random (ish) weights file.
proc random_weights*() =
  var weights_loc = os.joinPath(getAppDir(), &"{base_version}-t0.txt")
  var out_strm = newFileStream(weights_loc, fmWrite)
  out_strm.store(model)
  out_strm.close()

if isMainModule:
  random_weights()