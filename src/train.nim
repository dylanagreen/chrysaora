import logging
import marshal
import math
import os
import streams
import strformat
import strutils
import tables
import times

import arraymancer

import board
import movegen
import engine
import uci
include net


proc split_game*(name: string, folder: string = "games") =
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
    let test_board = load_pgn(file.extractFilename(), train_loc, train=true)

    var
      # The board state numbers that we take
      num1 = test_board.evals.len div 3 + 3
      num2 = num1 * 2 + 3

      # The boards we'll prep for the network
      board1, board2: Board

    # Unmakes the moves to get the board state at num 1 and 2.
    for j in 1..num2:
      if j == num1:
        board1 = deepCopy(test_board)
      test_board.unmake_move()
    board2 = deepCopy(test_board)

    var
      # V1 and v2 stand for vector 1 and 2 representing the boards as network
      # ready tensors
      v1 = board1.prep_board_for_network()
      v2 = board2.prep_board_for_network()

      v3 = v1.color_swap_board().reshape(1, D_in)
      v4 = v2.color_swap_board().reshape(1, D_in)

      # e1 and e2 are the evaluations of board 1 and 2 respectively.
      e1 = [tanh(board1.handcrafted_eval() / 1000)].toTensor().astype(float32)
      e2 = [tanh(board2.handcrafted_eval() / 1000)].toTensor().astype(float32)

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

  # Adds the final minibatch that is length < 50 to the result.
  result.batches.add(minibatch)
  total_states += minibatch.shape[0]
  # Reshaping for running through the network.
  result.evals.add(evals.reshape(evals.shape[0], 1))

  echo &"Training data loaded. Loaded {total_states / 4} games and {total_states} board states."
  logging.debug(&"Training data loaded. Loaded {total_states / 4} games and {total_states} board states.")
  echo &"Data is in {result.batches.len - 1} batches of 100 states and one batch of {result.batches[^1].shape[0]} states."
  logging.debug(&"Data is in {result.batches.len - 1} batches of 100 states and one batch of {result.batches[^1].shape[0]} states.")


proc bootstrap(fileLog: FileLogger): string=
  let (batches, evals) = generate_bootstrap_data()
  # Adam optimizer needs to be variable as it learns during training
  # Adam works better for the bootstrapping process.
  var optim = optimizerAdam[model, float32](model, learning_rate = 2e-3'f32)

  # Timer to see how long the training takes.
  let t1 = epochtime()

  # For the time being I'm restricting the training to avoid overfitting.
  #  At some point I can make the number of bootstrap epochs variable.
  for t in 1 .. 20:
    var running_loss = 0.0
    for i, minibatch in batches:
      # Generates the prediction finds the loss
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
    flushFile(fileLog.file)

  # Codenaming network version 1 as box. I don't really need to save the
  # Bootstrap since the weights will be saved into the model already.
  result = &"{base_version}-bootstrap.txt"
  var strm = newFileStream(os.joinPath(getAppDir(), result), fmWrite)
  strm.store(model)
  strm.close()
  logging.debug(&"Saved: {base_version}-bootstrap.txt")

  let t2 = epochtime()

  echo &"Bootstrapping completed in {t2-t1} seconds"
  logging.debug(&"Bootstrapping completed in {t2-t1} seconds")

proc generate_training_data(engine: var Engine, file: string, num_plies: int = 4): Tensor[float32] =

  # Location of the training games
  let
    train_loc = parentDir(getAppDir()) / "games" / "train"
    test_board = load_pgn(file.extractFilename(), train_loc, train=true)

  var
    # The board state numbers that we take
    num1 = test_board.evals.len div 3 * 2

    # Copying the board so we can unmake moves
    board1 = deepCopy(test_board)

  # Unmakes the moves to get the board state at num 1 and 2.
  for j in 1..num1:
    board1.unmake_move()

  engine.board = board1
  engine.color = board1.to_move
  let
    parser = UCI(board: board1, previous_cmd: @[], engine: engine)

  var
    # V1 and v2 stand for vector 1 and 2 representing the boards as network
    # ready tensors
    v1 = board1.prep_board_for_network().reshape(1, D_in)

  result = v1

  # Loops over the number of plies.
  for i in 1..num_plies:
    engine.compute = true
    try:
      let
        m = engine.find_move()

      let
        converted = parser.uci_to_algebraic(m)
      board1.make_move(converted)
    except Exception as e:
      echo file.extractFilename()
      echo board1.tofen()
      echo board1.move_list
      raise(e)

    let v2 = board1.prep_board_for_network().reshape(1, D_in)
    result = result.concat(v2, axis=0)

    # Lets the fledgling engine play into a checkmate. In much the same way
    # that a mother bird will sometimes watch as her fledgling jumps out
    # of the nest unprepared, I too watch as my engine plays itself into
    # a loss.
    if board1.status == WHITE_VICTORY or board1.status == BLACK_VICTORY: break

# A template to clear the gradients of a network. Mainly just for readibility.
template zero_grad(store: bool = false)=
  for layer in fields(model):
    for field in fields(layer):
      when field is Variable:
        field.grad = zeros_like(field.grad)
        if store:
          grads.add(zeros_like(field.grad))

proc reinforcement_learning(weights: string = "", fileLog: FileLogger) =
  # I'll be honest, this is super super janky and I'm not even sure that this is
  # actually the correct implementation of TDLeaf(lambda) but it should be close
  # enough. I hope. Weights is a weights file for where to start the training.
  let
    weights_loc = getAppDir() / weights
    train_loc = parentDir(getAppDir()) / "games" / "train"

  # Idiot proofing.
  if not fileExists(weights_loc):
    echo  "Weights file not found, using default weights file."
  else:
    if weights.endsWith("bootstrap.txt"):
      echo "Using bootstrapped weights"
    var strm = newFileStream(weights_loc, fmRead)
    strm.load(model)
    strm.close()

    ctx = model.fc1.weight.context

  var
    # The engine we use to make the moves.
    time_params = {"wtime" : 0, "btime" : 0, "winc" : 0, "binc" : 0}.toTable
    cur_engine = Engine(time_params: time_params, compute: true,
                max_depth: 30, train: true)
    # The number of training steps we've done.
    num_steps = 0

    # The running list of the trace.
    trace: float32

    # The factor to reduce each temporal difference by. 0.7 is pretty standard
    scale = 0.7

    learning_rate = 1e-3'f32

    # The number of plies long the trace should be.
    num_plies = 6

    # Storage of the network gradients
    grads: seq[Tensor[float32]]

    # Storing the previous value for difference calculations.
    prev = 0'f32
    started = false

  # Zeroes the grad while also creating a grad storage.
  #zero_grad(true)
  # Timing variable
  let t1 = epochTime()
  for file in walkFiles(train_loc / "*.pgn"):
    var
      # Storage for all the grads and traces.
      all_traces: seq[float32]
      all_grads: seq[seq[Tensor[float32]]]

    # Clears the transposition table.
    engine.tt = newSeq[Transposition](engine.tt.len)
    #echo file.extractFilename()
    let
      data = generate_training_data(cur_engine, file, num_plies)
      x = ctx.variable(data)
      y_pred = model.forward(x)

    logging.debug(&"Pre-forward pass:")
    logging.debug(y_pred.value)
    for i in countdown(data.shape[0] - 1, 0):
      # This should be equal to y_pred[i, 0] but running it through alone
      # allows us to calculate the grdient.
      var
        single_run = model.forward(ctx.variable(data[i, 0..<D_in], requires_grad = true))

      if not started:
        prev = single_run.value[0, 0]
        started = true
        continue

      let diff = prev - single_run.value[0, 0]

      # echo ""
      # echo single_run.value
      # echo prev
      # echo diff

      prev = single_run.value[0, 0]

      # Reduce the old trace by scale then add the new diff (which is scaled by 1
      # here). This is equivalent to Sum(0.7 ^ lifetime of diff * diff)
      trace *= scale
      trace += diff

      all_traces.add(trace)
      grads = @[]
      zero_grad(true)

      # Backprop the output gradient
      single_run.backprop()

      var j = 0
      for layer in fields(model):
        for field in fields(layer):
          when field is Variable:
            grads[j] = field.grad
            j += 1

      all_grads.add(grads)
      # Writes the log.
      flushFile(fileLog.file)

    # Uses the optimzer to backpropagate the weight updates.
    #optim.update()
    for i in 0..<data.shape[0]:
      var j = 0
      for layer in fields(model):
        for field in fields(layer):
          when field is Variable:
            field.value += learning_rate * trace * grads[j]
            j += 1

    num_steps += 1
    echo &"Completed {num_steps} games."

    # Log the results of the gradient descent.
    logging.debug(&"Post-forward pass:")
    logging.debug(model.forward(x).value)
    logging.debug(&"Completed {num_steps} games.")


  # Codenaming network version 1 as box
  var out_strm = newFileStream(os.joinPath(getAppDir(), &"{base_version}-{num_plies}-{num_steps}.txt"), fmWrite)
  out_strm.store(model)
  out_strm.close()

  let t2 = epochtime()

  echo &"Reinforcement learning completed in {t2-t1} seconds"
  echo &"Average time per game: {(t2-t1)/float(num_steps)} seconds"


if isMainModule:
  # Set up a log to track anything that happens during the training.
  let log_folder = os.joinPath(getAppDir(), "logs")
  if not existsDir(log_folder):
      createDir(log_folder)
  let
    log_name = log_folder / &"training-{base_version}-{$now()}.log"
    fileLog = newFileLogger(log_name, levelThreshold = lvlDebug)
  # Mustn't forget to add a handler for the logging file.
  addHandler(fileLog)

  # The actual training. Bootstraps then trains.
  let name = bootstrap(fileLog)
  reinforcement_learning(name, fileLog)

  # Flush anything left in the log.
  flushFile(fileLog.file)