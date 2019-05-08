import strutils
import sequtils
import tables
import times

import arraymancer

import board
import engine
import uci

var
  time_params = {"wtime" : -1, "btime" : -1, "winc" : -1, "binc" : -1}.toTable
  cur_engine = Engine(board: new_board(), time_params: time_params, compute: true,
                  max_depth: 3)
  interpreter = UCI(board: new_board(), previous_pos: @[], engine: cur_engine)

proc perft_search*(search_board: Board, depth: int = 1, color: Color): int =
  # Generates the moves for this node.
  let moves = search_board.generate_moves(search_board.to_move)

  if depth == 1:
    return len(moves)

  for i, m in moves:
    # Generate a new board state for move generation. We use bypass make move
    # here because it gets a more accurate nps that the engine will be seeing
    # since that is how the engine makes moves.
    let new_board = deepCopy(search_board)
    new_board.make_move((m.algebraic, m.state), engine=true)
    let lower_moves = new_board.perft_search(depth-1, new_board.to_move)

    #if depth == 3:
      #interpreter.board = search_board
      #echo interpreter.algebraic_to_uci(m.algebraic), ": ", lower_moves
      #echo m.algebraic
    # Concats the resulting moves to the result.
    result += lower_moves

when isMainModule:
  # Does all the actual timing. Sets up the board and depth before we time
  # for more accurate timekeeping.
  var
    search_board = new_board()#load_fen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq -")
  # long is a hack field I added that causes more shortcuts when using
  # algebraic notation for marginally more speed.
  search_board.long = true
  var
    depth = 4
    t1 = cpuTime()
    num_nodes = perft_search(search_board, depth, search_board.to_move)
    t2 = cpuTime()

    time = t2 - t1

  echo "Perft Position 1 depth ", depth
  echo "Number of nodes: ", num_nodes
  echo "NPS: ", float(num_nodes) / time
  echo "Time: ", time