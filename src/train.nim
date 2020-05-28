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
include net

var
  # Easier to save the evals and the piece lists.
  evals: seq[float] = @[]

  # For this super shitty eval function the gradients are equal to the difference
  # between white and black pieces
  all_grads: seq[seq[Tensor[float32]]]
  grads: seq[Tensor[float32]]

  # Loaded weight values
  loaded_values* = {'K': 1000}.toTable

let
  # Learning rate and lambda hyperparameters
  alpha = 0.001'f32

  lamb = 0.7'f32


proc update_training_parameters*(board: Board, eval: float, pv: string) =
  # It should be noted that these evals are calculated as
  # arctanh(network output) * 100 to convert to centipawns
  # This is why my learnning rate is ~0.01 since that way it's approx 1
  # after multiplicatoin which is what giraffe used
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

  # Gonna zero out those gradients just in case.
  for layer in fields(model):
    for field in fields(layer):
      when field is Variable:
        field.grad = field.grad.zeros_like

  let
    x = ctx.variable(board.prep_board_for_network().reshape(1, D_in), requires_grad = true)
    # I don't actually need this, but I need to run x through in order to compute gradients
    y = model.forward(x)

  grads = @[]

  # Store the gradients for each of the layers in order, from beginning to
  # end, so that we can update them later.
  for layer in fields(model):
    for field in fields(layer):
      when field is Variable:
        grads.add(field.grad)
  all_grads.add(grads)

  # Return the board to its original state
  for m in moves:
    if m == "": continue
    board.unmake_move()

proc update_weights*() =
  # Without two states you can't calculate a difference
  # I made min_states a variable in case we want to discount the opening
  # moves since that's typically an open book kind of thing.
  var min_states = 6
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
    let cur_grads = all_grads[i-2]

    var j = 0
    for layer in fields(model):
      for field in fields(layer):
        when field is Variable:
          field.value += alpha * cur_grads[j] * running_diff
          j += 1

  evals = @[]
  grads = @[]

proc save_weights*() =
  # TODO Clear the Nodes somewhere in here????
  # Clearing the ndoes will reduce the size of the network weights we need to save
  var out_strm = newFileStream(os.joinPath(getAppDir(), &"{base_version}-t2.txt"), fmWrite)
  out_strm.store(model)
  out_strm.close()
