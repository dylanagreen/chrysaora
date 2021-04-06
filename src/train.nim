import logging
import marshal
import math
import os
import streams
import strformat
import strutils

import arraymancer

import board
import engine

var
  # To save the evals for generating temporal differences
  evals: seq[float] = @[]

  # Save the grads into grads then shove that grads into all_grades
  all_grads: seq[seq[Tensor[float32]]]
  grads: seq[Tensor[float32]]
  update: seq[Tensor[float32]]

  # For momentum
  prev_grads: seq[Tensor[float32]]

  num_increments = 0

let
  # Learning rate and lambda hyperparameters
  alpha = 0.1'f32
  lamb = 0.70'f32
  beta = arctanh(0.25) # To constrain eval outputs

  # Momentum term
  gamma = 0.9'f32

  save_after = 10

proc init_prev_grads*() =
  prev_grads = @[]
  for layer in fields(model):
    for field in fields(layer):
      when field is Variable:
        prev_grads.add(field.grad.zeros_like)

# Today in hellish function definitions that took way too long to figure out
# var optim = optimizerSGDMomentum[model, float32](model, learning_rate = alpha, momentum=0.9'f32)

proc save_weights*(bootstrap:bool = false) =
  if num_increments == 0 and not bootstrap: return # Do not save on no training games.
  let name = if bootstrap: &"{base_version}-t0.txt"
             else: &"{base_version}-t{num_train + 1}-{num_increments + best_count}.txt"
  var out_strm = newFileStream(os.joinPath(getAppDir(), name), fmWrite)
  out_strm.store(model)
  out_strm.close()

  logging.debug(&"Saved weights after game {num_increments} as {name}")

  if bootstrap:
    echo &"Saved bootstrap weights as {name}."

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
  # TODO: Investigate if this is necessary or not.
  for layer in fields(model):
    for field in fields(layer):
      when field is Variable:
        field.grad = field.grad.zeros_like

  let
    x = ctx.variable(board.prep_board_for_network().reshape(1, D_in))
    y = model.forward(x)

  y.backprop()
  # Why add the network eval and not the one we pass out to uci?
  # Largely because we compute temporal difference with beta*tanh values.
  # I answer. I'm not super sure if I need to negate these, but I negate them in
  # minimax search so I should?
  # if swap:
  #   evals.add(-y.value[0, 0])
  # else:
  let reduced_val = tanh(beta * y.value[0, 0])
  evals.add(reduced_val)

  # Store the gradients for each of the layers in order, from beginning to
  # end, so that we can update them later.
  grads = @[]
  update = @[]
  for layer in fields(model):
    for field in fields(layer):
      when field is Variable:
        # We need the gradient of the reduced_val not just the y value
        grads.add(field.grad * (1 - reduced_val^2) * beta)
        update.add(field.grad.zeros_like)
  all_grads.add(grads)

  # Return the board to its original state
  for m in moves:
    if m == "": continue
    board.unmake_move()

proc update_weights*(status: Status = IN_PROGRESS, color: COLOR = WHITE) =
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

  # Adds the result of the game to the difference, which should help training
  # When trained against stockfish Chrysaora will probably lose every game
  # but its the thought that counts.
  if status == DRAW:
    evals.add(0)
  elif status != IN_PROGRESS:
    # let win = (color == WHITE and status == WHITE_VICTORY) or (color == BLACK and status == BLACK_VICTORY)
    if status == WHITE_VICTORY:
      evals.add(1)
    else:
      evals.add(-1)

  logging.debug(&"EVALS {$evals}")

  var running_diff = 0.0
  # Works backwards from the end, stops at min_states which needs to be greater
  # than 2, since 2 will give the first two states.
  grads = @[]
  for i in countdown(evals.len, min_states):
    # Computes the eligability trace
    let diff = evals[i-1] - evals[i-2]
    running_diff = diff + running_diff * lamb

    # Weight update calculated from magical temporal difference formula
    let cur_grads = all_grads[i-2]
    logging.debug(&"DIFF: {evals[i-1]} - {evals[i-2]}: {running_diff}")

    # Add the delta for this diff/eval into the grads sequence
    # I changed this from the previous method so that we can store the
    # TOTAL accumulated gradient for things like momentum.
    var j = 0
    for layer in fields(model):
      for field in fields(layer):
        when field is Variable:
          update[j] += cur_grads[j] * running_diff
          j += 1

  # Do the actual update with the accumulated gradient.
  var j = 0
  for layer in fields(model):
    for field in fields(layer):
      when field is Variable:
        let delta = alpha * update[j] + gamma * prev_grads[j]
        prev_grads[j] = delta
        field.value += delta
        j += 1

  evals = @[]
  grads = @[]
  num_increments += 1

  if num_increments mod save_after == 0 and num_increments > 0:
    save_weights()

proc set_up_training*(cur_eng: Engine) =
  training = true
  cur_eng.on_move_found = update_training_parameters

  init_prev_grads()

  logging.debug("Training parameters used for this run:")
  logging.debug(&"alpha (lr) = {alpha}")
  logging.debug(&"lambda (decay) = {lamb}")
  logging.debug(&"gamma (momentum) = {gamma}")
