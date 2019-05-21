import strutils
import sequtils
import tables
import times

import arraymancer

import board
import movegen
#import engine
#import uci

var
  time_params = {"wtime" : -1, "btime" : -1, "winc" : -1, "binc" : -1}.toTable
  #cur_engine = Engine(board: new_board(), time_params: time_params, compute: true,
                  #max_depth: 3)
  #interpreter = UCI(board: new_board(), previous_pos: @[], engine: cur_engine)

proc perft_search*(search_board: Board, depth: int = 1, color: Color, to_print: bool = false): int =
  # Generates the moves for this node.
  let moves = search_board.generate_all_moves(search_board.to_move)

  var print = false
  if depth == 1:
    for i, m in moves:
      if to_print:
        echo m.algebraic, ": 1"
    return len(moves)

  for i, m in moves:
    # Generate a new board state for move generation. We use bypass make move
    # here because it gets a more accurate nps that the engine will be seeing
    # since that is how the engine makes moves.
    let new_board = deepCopy(search_board)
    new_board.make_move(m, skip=true)
    #[if m.algebraic == "hxg2" and depth == 3:
      print = true
    elif m.algebraic == "e4" and depth == 2:# and to_print:
      print = true
    else:
      print = false]#
    let lower_moves = new_board.perft_search(depth-1, new_board.to_move, print)

    #if depth == 2:# and to_print:
      #interpreter.board = search_board
      #echo interpreter.algebraic_to_uci(m.algebraic), ": ", lower_moves
      #echo m.algebraic, ": ", lower_moves
    # Concats the resulting moves to the result.
    result += lower_moves

when isMainModule:
  # Does all the actual timing. Sets up the board and depth before we time
  # for more accurate timekeeping.
  var
    search_board = load_fen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - ")

  # long is a hack field I added that causes more shortcuts when using
  # algebraic notation for marginally more speed.
  search_board.long = true
  var
    depth = 3
    t1 = cpuTime()
    num_nodes = perft_search(search_board, depth, search_board.to_move, false)
    t2 = cpuTime()

    time = t2 - t1

  echo "Perft Position 3 depth ", depth
  echo "Number of nodes: ", num_nodes
  echo "NPS: ", float(num_nodes) / time
  echo "Time: ", time