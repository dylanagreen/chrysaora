import strutils
import sequtils
import tables
import times

import arraymancer

import board

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

    # Concats the resulting moves to the result.
    result += lower_moves

when isMainModule:
  # Does all the actual timing. Sets up the board and depth before we time
  # for more accurate timekeeping.
  var
    search_board = new_board()#load_fen("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1")
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