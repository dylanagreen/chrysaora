import sequtils
import times

import arraymancer

import engine
import board

proc perft_search(search_board: Board, depth: int = 1, color: Color): int =

  # Generates the moves for this node.
  let moves = search_board.generate_moves(search_board.to_move)

  for i, m in moves:
    if depth == 1:
      return len(moves)

    else:
      # Generate a new board state for move generation. We use bypass make move
      # here because it gets a more accurate nps that the engine will be seeing
      # since that is how the engine makes moves.
      let
        new_board = bypass_make_move(search_board, m.algebraic, m.state)
        lower_moves = new_board.perft_search(depth-1, new_board.to_move)

      # Concats the resulting moves to the result.
      result += lower_moves

# Does all the actual timing. Sets up the board and depth before we time
# for more accurate timekeeping.
var
  search_board = new_board()
  depth = 4
  t1 = cpuTime()
  num_nodes = perft_search(search_board, depth, search_board.to_move)
  t2 = cpuTime()

  time = t2 - t1

echo "Perft Position 1 depth ", depth
echo "Number of nodes: ", num_nodes
echo "NPS: ", float(num_nodes) / time
echo "Time: ", time

#[search_board = load_fen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - ")
t1 = cpuTime()
nodes = perft_search(search_board, depth, search_board.to_move)
t2 = cpuTime()

num_nodes = len(nodes)
time = t2 - t1

echo "Perft kiwipete depth ", depth
echo "Number of nodes: ", num_nodes
echo "NPS: ", float(num_nodes) / time
echo "Time: ", time]#