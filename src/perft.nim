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
    #[if m.algebraic == "e4" and depth == 2:
      print = true
    #[elif m.algebraic == "Rg5" and depth == 3 and to_print:
      print = true
    elif m.algebraic == "g3" and depth == 2 and to_print:
      print = true]#
    else:
      print = false#]#
    search_board.make_move(m, skip=true)
   # echo "made ", m.algebraic
    let lower_moves = search_board.perft_search(depth-1, search_board.to_move, print)

    search_board.unmake_move()
    #echo "unmade ", m.algebraic
    #if depth == 2 and to_print:
      #interpreter.board = search_board
      #echo interpreter.algebraic_to_uci(m.algebraic), ": ", lower_moves
      #echo m.algebraic, ": ", lower_moves
    # Concats the resulting moves to the result.
    result += lower_moves

when isMainModule:
  # Does all the actual timing. Sets up the board and depth before we time
  # for more accurate timekeeping.
  var
    search_board = new_board()#load_fen("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - -")

  # long is a hack field I added that causes more shortcuts when using
  # algebraic notation for marginally more speed.
  search_board.long = true
  var
    depth = 4
    t1 = cpuTime()
    num_nodes = perft_search(search_board, depth, search_board.to_move, true)
    t2 = cpuTime()

    time = t2 - t1

  echo "Perft Position 1 depth ", depth
  echo "Number of nodes: ", num_nodes
  echo "NPS: ", float(num_nodes) / time
  echo "Time: ", time