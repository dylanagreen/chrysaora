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

# I am not speed - Lightning McChrysaora
proc `<`(x: Tensor[float32], y: float): Tensor[float32] =
  result = x.map(proc(i:float32): float32 = float32(i < y))

proc `>`(x: Tensor[float32], y: float): Tensor[float32] =
  result = x.map(proc(i:float32): float32 = float32(i > y))

# D_in is input dimension
# D_out is output dimension.
let
  (D_in*, H1, H2, D_out) = (96, 64, 128, 1)

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
  files = {'N': 16, 'B': 32, 'R': 48, 'Q': 64, 'P': 80}.toTable
  ranks = {'N': 8, 'B': 24, 'R': 40, 'Q': 56, 'P': 72}.toTable

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
  # 64-71: Queen Files
  # 72-79: Pawn Ranks
  # 80-87: Pawn Files
  # 88-95: Doubled Pawn by File
  result = zeros[float32](D_in)

  for color in [WHITE, BLACK]:
    for piece in board.piece_list[color]:
      # We don't care about kings for piece diff (or positioning for now)
      if piece.name == 'K': continue

      var
        diff = if color == WHITE: 1.0 else: -1.0
        ind = piece_indices.find(piece.name)

      # Normalizes inputs to be between -1 and 1.
      diff = diff / max_pieces[piece.name]

      result[ind] += diff

      # Notes the piece in the rank and file for that piece
      # if piece.name == 'P': continue

      var
        r = ranks[piece.name] + piece.pos.y
        f = files[piece.name] + piece.pos.x

      # We store white pawn files in the regular place and black in the doubled
      # pawn section briefly.
      if piece.name == 'P' and color == BLACK:
        f += 8

      # To ensure that inputs remain between 0 and 1
      diff = if piece.name == 'Q' or piece.name == 'P': 1.0 else: 0.5
      result[r] = if color == WHITE: result[r] + diff else: result[r] - diff
      result[f] = if color == WHITE: result[f] + diff else: result[f] - diff


  # This block reduces a doubled pawn.
  # Subtract from where white is doubled, where black is doubled
  # then put piece numbers in by subtracting black num from white num
  let
    f = files['P']
    # dub_white = result[f..(f + 8)].map(proc(x:float32): float32 = float32(x > 0.0))
    # dub_black = result[f..(f + 8)].map(proc(x:float32): float32 = float32(x < 0.0))
    doubled = (result[f..(f + 7)] > 1.0) - (result[(f + 8)..(f + 15)] < -1.0)
    # doubled = dub_white - dub_black

  # Subtracting the black from the white plus the doubled to make sure it's
  # between 0 and 1.
  result[f..(f + 7)] = result[f..(f + 7)] + result[(f + 8)..(f + 15)] - doubled
  result[(f + 8)..(f + 15)] = doubled

  # Reducing pawn rank to be maximum of 1 (if all 8 pawns are on the same rank)
  result[(f - 8)..(f - 1)] = result[(f - 8)..(f - 1)] / 8

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
  # Need to negate files to swap piece value though.
  # Hence ranks get swapped (reversed) and the files do not.
  for p, pos in ranks:
    result[pos..(pos + 7)] = -board[(pos + 7)..pos|-1]
    result[(pos + 8)..(pos + 15)] = -board[(pos + 8)..(pos + 15)]

  # Swapping doubled pawns
  result[88..95] = -board[88..95]


# Functionality for generating a completely random (ish) weights file.
proc random_weights*() =
  var weights_loc = os.joinPath(getAppDir(), &"{base_version}-t0.txt")
  var out_strm = newFileStream(weights_loc, fmWrite)
  out_strm.store(model)
  out_strm.close()

if isMainModule:
  random_weights()