import logging
import math
import os
import streams
import strformat
import strutils
import tables
import times

import arraymancer

import board
import engine
import train

# This is a helper proc. TCEC parses entire divisions into single pgn files
# so this proc is designed to split those into single game pgns.
proc split_game(name: string, folder: string = "games") =
  # File location of the pgn.
  var
    start_loc = parentDir(getAppDir()) / folder / name
    temp_loc = parentDir(getAppDir()) / folder / "train" / "temp.pgn"

  # In case you pass the name without .pgn at the end.
  if not start_loc.endsWith(".pgn"):
    start_loc = start_loc & ".pgn"

  if not fileExists(start_loc):
    raise newException(IOError, "PGN not found!")

  # Creates the folder for the split games.
  if not existsDir(folder / "train"):
    createDir(folder / "train")

  let data = open(start_loc)

  # We only use the tags for naming the file.
  var
    f = open(temp_loc, fmWrite)
    tags = initTable[string, string]()
    in_game = false

  for line in data.lines:
    if not line.startsWith("["):
      in_game = true
    else:
      if in_game:
        # If we encounter a tag opening [ but still think we are in the game
        # then we reached the end. We close temp, move it to the new name,
        # and open a new temp to write to.
        in_game = false
        f.close()
        var new_name = tags["White"] & "vs" & tags["Black"] & " " & tags["Date"]

        # Adds the round for multiple games played by the same players on the
        # same date
        if tags.hasKey("Round"):
          new_name = new_name & " " & tags["Round"]

        new_name = new_name & ".pgn"
        temp_loc.moveFile(parentDir(getAppDir()) / folder / "train" / new_name)
        f = open(temp_loc, fmWrite)
        tags = initTable[string, string]()

      var
        trimmed = line.strip(chars = {'[', ']'})
        pair = trimmed.split("\"")

      tags[pair[0].strip()] = pair[1]

    f.write(line & "\n")

  # Moves the final game as well once we jump out of the loop.
  f.close()
  var new_name = tags["White"] & "vs" & tags["Black"] & " " & tags["Date"]
  if tags.hasKey("Round"):
    new_name = new_name & " " & tags["Round"] & ".pgn"
  else:
    new_name = new_name & ".pgn"

  temp_loc.moveFile(parentDir(getAppDir()) / folder / "train" / new_name)


proc split_all_games() =
  let start_loc = parentDir(getAppDir()) / "games"

  for file in walkFiles(start_loc / "*.pgn"):
    split_game(file.extractFilename())
    echo &"Split {file.extractFilename()}"


proc generate_bootstrap_data(): tuple[batches, evals: seq[Tensor[float32]]] =
  echo "Generating bootstrap data..."
  # Location of the training games
  let train_loc = parentDir(getAppDir()) / "games" / "train"

  # We record the number of batches for reporting purposes.
  var
    num_batches = 0
    minibatch = zeros[float32](1, 74)
    evals = zeros[float32](1)
    total_states = 0

  # Walking through the pgn files only (so it doesn't matter if you accidentally
  # put a png in there once like I did :))
  for file in walkFiles(train_loc / "*.pgn"):

    # The test board we'll be unmaking moves on.
    let test_board = load_pgn(file.extractFilename(), train_loc)

    var
      # The board state numbers that we take, 1/3 and 2/3 of the way through
      num1 = test_board.move_list.len div 3
      num2 = num1 * 2

      # The boards we'll prep for the network
      board1, board2: Board

    # Just bumping us off the exact 1/3 2/3 positions.
    if num2 < test_board.move_list.len - 3:
      num2 = num2 + 3
    num1 = num1 + 3

    # Unmakes the moves to get the board state at num 1 and 2.
    for j in 1..num2:
      if j == num1:
        board1 = deepCopy(test_board)
      test_board.unmake_move()
    board2 = deepCopy(test_board)

    var
      # v1 and v2 stand for vector 1 and 2 representing the boards as network
      # ready tensors
      v1 = board1.prep_board_for_network()
      v2 = board2.prep_board_for_network()

      # v3 and v4 are color swapped versions of v1 and v2
      # TODO: make color swap work with shape 1, D_in.
      v3 = v1.color_swap_board().reshape(1, D_in)
      v4 = v2.color_swap_board().reshape(1, D_in)

      # e1 and e2 are the evaluations of board 1 and 2 respectively.
      # tanh and divided to get them between the -1 and 1 of the network.
      e1 = [tanh(board1.handcrafted_eval() / 100)].toTensor().astype(float32)
      e2 = [tanh(board2.handcrafted_eval() / 100)].toTensor().astype(float32)

    v1 = v1.reshape(1, D_in)
    v2 = v2.reshape(1, D_in)
    # If this is the first one loaded then we create the state/eval in the
    # final tensor. Otherwise we can straight concat it.
    if minibatch.shape[0] == 1:
      num_batches += 1
      minibatch = v1
      evals = e1
    else:
      minibatch = minibatch.concat(v1, axis=0)
      evals = evals.concat(e1, axis=0)

    # Second board from every game is always able to be concated.
    minibatch = minibatch.concat(v2, axis=0)
    evals = evals.concat(e2, axis=0)

    # Adds the color swapped boards, and the negative versions of their evals
    minibatch = minibatch.concat(v3, axis=0)
    evals = evals.concat(-e1, axis=0)

    minibatch = minibatch.concat(v4, axis=0)
    evals = evals.concat(-e2, axis=0)

    if minibatch.shape[0] == 100:
      result.batches.add(minibatch)
      total_states += 100
      # Reshaping for running through the network.
      result.evals.add(evals.reshape(evals.shape[0], 1))

      minibatch = zeros[float32](1, 74)
      evals = zeros[float32](1)

  # Adds the final minibatch that is length < 100 to the result.
  result.batches.add(minibatch)
  total_states += minibatch.shape[0]
  # Reshaping for running through the network.
  result.evals.add(evals.reshape(evals.shape[0], 1))

  echo &"Training data loaded. Loaded {total_states / 4} games and {total_states} board states."
  logging.debug(&"Training data loaded. Loaded {total_states / 4} games and {total_states} board states.")

  echo &"Data is in {result.batches.len - 1} batches of 100 states and one batch of {result.batches[^1].shape[0]} states."
  logging.debug(&"Data is in {result.batches.len - 1} batches of 100 states and one batch of {result.batches[^1].shape[0]} states.")


proc bootstrap*() =
  let (batches, evals) = generate_bootstrap_data()
  # Adam optimizer needs to be variable as it learns during training
  # Adam works better for the bootstrapping process. Allegedly.
  var optim = optimizerAdam[model, float32](model, learning_rate = 1e-4'f32)

  # Timer to see how long the training takes.
  let t1 = epochtime()

  # For the time being I'm restricting the training to avoid overfitting.
  # At some point I can make the number of bootstrap epochs variable.
  for t in 1 .. 100:
    var running_loss = 0.0
    for i, minibatch in batches:
      # Generates the prediction, finds the loss
      let
        x = ctx.variable(minibatch)
        y_pred = model.forward(x)
        loss = mse_loss(y_pred, evals[i])

      # Keeping a running loss for averaging
      running_loss += loss.value[0]

      # Back propagation
      loss.backprop()
      optim.update()

    echo &"Epoch {t}: avg loss {running_loss / float(batches.len)}"
    logging.debug(&"Epoch {t}: avg loss {running_loss / float(batches.len)}")

  let t2 = epochtime()

  echo &"Bootstrapping completed in {t2-t1:3.3f} seconds"
  logging.debug(&"Bootstrapping completed in {t2-t1:3.3f} seconds")

  save_weights(true)
