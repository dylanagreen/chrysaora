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
  (D_in*, H1, H2, D_out) = (72, 64, 128, 1)

  # Code name and test status for whever I need it.
  # Test status changes with each change to the internal variations on the
  # network (hidden layer sizes for example)
  # Input vector changes and large scale changes to internal network structure
  # like number of hidden layers will get their own code name.
  base_version* = "noctiluca" # A bioluminescent jellyfish

# Create the autograd context that will hold the computational graph
var
  ctx* = newContext Tensor[float32]

# This is where the network itself is actually defined.
network ctx, ChessNet:
  layers:
    x:   Input([D_in])
    fc1: Linear(D_in, H1)
    # fc2: Linear(H1, H2)
    fc2: Linear(H1, D_out)
  forward x:
    x.fc1.relu.fc2

# "Crappy hack" - Jjp137
export forward

# Initialize the model, in general we'll load a weights file for this.
# I really hope you're not running it with random weights....
var model* = ctx.init(ChessNet)
const
  piece_indices: array[5, char] = ['P', 'N', 'B', 'R', 'Q']
  max_pieces* = {'P': 8.0, 'N': 2.0, 'R': 2.0, 'B': 2.0, 'Q': 1.0}.toTable
  files = {'N': 16, 'B': 32, 'R': 48, 'Q': 64}.toTable
  ranks = {'N': 8, 'B': 24, 'R': 40, 'Q': 56}.toTable

proc prep_board_for_network*(board: Board): Tensor[float32] =
  # Structure:
  # 0-4: Num difference of pieces excluding King (White - Black)
  # 5: Side to move
  # 6-7: (White - Black) castling rights (King, Queen)
  # 8-15: Knight Ranks
  # 16-23: Knight Files
  # 24-31: Bishop Ranks
  # 32-39: Bishop Files
  # 40-47: Rook Ranks
  # 48-55: Rook Files
  # 56-63: Queen Ranks
  # 64-72: Queen Files
  result = zeros[float32](D_in)

  for color in [WHITE, BLACK]:
    for piece in board.piece_list[color]:
      if piece.name == 'K': continue

      var
        diff = if color == WHITE: 1.0 else: -1.0
        ind = piece_indices.find(piece.name)

      # Normalizes inputs to be between -1 and 1.
      diff = diff / max_pieces[piece.name]

      result[ind] += diff

      # Notes the piece in the rank and file for that piece
      if piece.name == 'P': continue

      let
        r = ranks[piece.name] + piece.pos.y
        f = files[piece.name] + piece.pos.x

      # To ensure that inputs remain between 0 and 1
      diff = if piece.name == 'Q': 1.0 else: 0.5
      result[r] = if color == WHITE: result[r] + diff else: result[r] - diff
      result[f] = if color == WHITE: result[f] + diff else: result[f] - diff


  # Side to move
  result[5] = if board.to_move == WHITE: 1 else: -1

  # Castling rights
  # Structure of these rights in both the engine and in the network is
  # [WK, WQ, BK, BQ]
  var rights = board.castle_rights

  # White castling rights
  for i in 6..7:
    # Pretty much just pops off the first bit and then shifts it right.
    result[i] += float32(rights and 1'u8)
    rights = rights shr 1

  # Black castling rights
  for i in 6..7:
    # Pretty much just pops off the first bit and then shifts it right.
    result[i] -= float32(rights and 1'u8)
    rights = rights shr 1


# Color swaps the board network tensor
proc color_swap_board*(board: Tensor[float32]): Tensor[float32] =
  result = zeros[float32](D_in)

  # Swaps the number of the pieces for each color
  result[0..4] = -board[0..4]
  # result[5..9] = board[0..4]

  # Swaps side to move
  result[5] = -board[5]

  # Swap the castling rights
  result[6..7] = -board[6..7]

  # We don't need to swap the files since we flip vertically.
  # Hence ranks get swapped (reversed) and the fiels do not.
  for p, pos in ranks:
    result[pos..(pos + 7)] = -board[(pos + 7)..pos|-1]
    result[(pos + 8)..(pos + 15)] = -board[(pos + 8)..(pos + 15)]


# Functionality for generating a completely random (ish) weights file.
proc random_weights*() =
  var weights_loc = os.joinPath(getAppDir(), &"{base_version}-t0.txt")
  var out_strm = newFileStream(weights_loc, fmWrite)
  out_strm.store(model)
  out_strm.close()

if isMainModule:
  random_weights()