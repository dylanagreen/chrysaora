# import strformat
import sequtils
import tables

import arraymancer

import board

# D_in is input dimension
# D_out is output dimension.
let
  (D_in*, H1, D_out) = (10, 16, 1)

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
    fc2: Linear(H1, D_out)
  forward x:
    x.fc1.relu.fc2.tanh

# Initialize the model, in general we'll load a weights file for this.
# I really hope you're not running it with random weights....
var model* = ctx.init(ChessNet)

proc prep_board_for_network*(board: Board): Tensor[float32] =
  result = zeros[float32](D_in)

  for piece in board.piece_list[WHITE]:
    # We always have a king on both sides so we're not counting them
    if piece.name == 'K' : continue
    result[piece_index[piece.name]] += 1

  for piece in board.piece_list[BLACK]:
    if piece.name == 'K' : continue
    result[piece_index[piece.name] + 5] += 1
