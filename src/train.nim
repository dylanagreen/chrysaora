import logging
import marshal
import math
import os
import streams
import strformat
import strutils
import tables
import times

import board

var
  # Easier to save the evals and the piece lists.
  evals: seq[float] = @[]

  # For this super shitty eval function the gradients are equal to the difference
  # between white and black pieces
  grads: seq[seq[int]] = @[]

  # Loaded weight values
  loaded_values* = {'K': 1000}.toTable

let
  # Learning rate and lambda hyperparameters
  alpha = 0.002

  lamb = 0.7

  piece_index = {'P': 0, 'N': 1, 'R': 2, 'B': 3, 'Q': 4}.toTable


proc update_training_parameters*(board: Board, eval: float, pv: string) =
  evals.add(eval)

  # Get the moves and make them so we can look at the leaf node
  let moves = pv.split(" ")
  for m in moves:
    # I suspect we always end up adding an empty string at the end so in theory
    # I could just ignore the last move but this is safer in case there's one
    # in the middle or in case we don't add one at the end.
    if m == "": continue
    let alg_move = board.uci_to_algebraic(m)
    board.make_move(alg_move)

  # Here we get the piece nums which in our lame eval function end up being the
  # gradients when you take the derivative with respect to the weights. In our
  # case the weights are the piece values.
  var piece_nums: seq[int] = @[0, 0, 0, 0, 0]

  for piece in board.piece_list[WHITE]:
    # We always have a king on both sides so we're not counting them
    if piece.name == 'K' : continue
    piece_nums[piece_index[piece.name]] += 1

  for piece in board.piece_list[BLACK]:
    if piece.name == 'K' : continue
    piece_nums[piece_index[piece.name]] -= 1
  grads.add(piece_nums)

  # Return the board to its original state
  for m in moves:
    if m == "": continue
    board.unmake_move()

proc update_weights*() =
  # Without two states you can't calculate a difference
  # I made min_states a variable in case we want to discount the opening
  # moves since that's typically an open book kind of thing.
  var min_states = 2
  if evals.len < min_states:
    logging.debug("Not enough states to compute temporal difference")
    logging.debug(&"At least {min_states} states required")
    evals = @[]
    grads = @[]
    return

  var running_diff = 0.0
  # Works backwards from the end, stops at 2  because that gives the first two.
  for i in countdown(evals.len, min_states):
    let diff = evals[i-1] - evals[i-2]

    # Computes the eligability trace
    running_diff = running_diff * lamb + diff
    # Weight update caluclated from magical temporal difference formula
    let cur_grads = grads[i-2]

    for key, val in loaded_values:
      # The update to this will always be 0 anyway.
      # Since # of kings always equal.
      # TODO change this in the future.
      if key == 'K': continue
      let weight_update = alpha * float(cur_grads[piece_index[key]]) * running_diff
      loaded_values[key] += int(weight_update)

  evals = @[]
  grads = @[]

proc save_weights*() =
  var out_strm = newFileStream(os.joinPath(getAppDir(), &"{base_version}-t2.txt"), fmWrite)
  out_strm.store(loaded_values)
  out_strm.close()
