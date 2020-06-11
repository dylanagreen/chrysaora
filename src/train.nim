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
  # To save the evals for generating temporal differences
  evals: seq[float] = @[]

  # Save the grads into grads then shove that grads into all_grades
  all_grads: seq[seq[Tensor[float32]]]
  grads: seq[Tensor[float32]]

  num_increments = 0

let
  # Learning rate and lambda hyperparameters
  alpha = 0.1'f32

  lamb = 0.7'f32

  save_after = 5

# Today in hellish function definitions that took way too long to figure
var optim = optimizerSGDMomentum[model, float32](model, learning_rate = alpha, momentum=0.9'f32)

proc save_weights*() =
  # TODO Clear the Nodes somewhere in here????
  # Clearing the ndoes will reduce the size of the network weights we need to save
  var out_strm = newFileStream(os.joinPath(getAppDir(), &"{base_version}-v1-{num_increments}.txt"), fmWrite)
  out_strm.store(model)
  out_strm.close()

proc update_training_parameters*(board: Board, eval: float, pv: string, swap: bool = false) =
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
    x = ctx.variable(board.prep_board_for_network().reshape(1, D_in), requires_grad=true)
    y = model.forward(x)

  y.backprop()
  # Why add the network eval and not the one we pass out to uci? You ask
  # Because the checkmate detection code sets evals to be in the thousands.
  # lol. I'm not super sure if I need to negate these, but I negate them in
  # minimax search so I should?
  # if swap:
  #   evals.add(-y.value[0, 0])
  # else:
  evals.add(y.value[0, 0])

  # Store the gradients for each of the layers in order, from beginning to
  # end, so that we can update them later.
  grads = @[]
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
  logging.debug(&"EVALS? {$evals}")
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

  # Zero the gradients because I'm going to add all the temporal difference
  # wieght updates into the gradient variable so that I can use the optimizer
  # to step forward. This allows me to easily switch from the original weight
  # updates (which was essentially SGD) to things like Adam (which Giraffe used)
  for layer in fields(model):
    for field in fields(layer):
      when field is Variable:
        field.grad = field.grad.zeros_like

  var running_diff = 0.0
  # Works backwards from the end, stops at 2  because that gives the first two.
  for i in countdown(evals.len, min_states):
    let diff = evals[i-1] - evals[i-2]
    logging.debug(&"Equality?{all_grads[i-1] == all_grads[i-2]}")

    # Computes the eligability trace
    running_diff = running_diff * lamb + diff
    # Weight update calculated from magical temporal difference formula
    let cur_grads = all_grads[i-2]
    logging.debug(&"DIFF: {running_diff}")
    var j = 0
    for layer in fields(model):
      for field in fields(layer):
        when field is Variable:
          field.grad += cur_grads[j] * running_diff
          j += 1

  optim.update()
  evals = @[]
  grads = @[]

  if num_increments mod save_after == 0:
    save_weights()

  num_increments += 1

