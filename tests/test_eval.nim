import unittest

# import arraymancer

import ../src/board
import ../src/engine

suite "evaluation function":

  test "start pos":
    let
      board = new_board()
      observed = board.handcrafted_eval()
      expected = 0.0

    check(observed == expected)

  test "start pos reversal":
    let
      b1 = new_board()
      b2 = b1.color_swap()

      white_to_move = b1.handcrafted_eval()
      black_to_move = b2.handcrafted_eval()
      expected = 0.0

    check(white_to_move == expected)
    check(black_to_move == expected)
    check(white_to_move == black_to_move)

  test "up one bishop":
    let
      # Random position from a game on lichess, 3/10/21
      # https://lichess.org/P8m6HLy7/black#39
      board = load_fen("r4rk1/pR2np1p/2nNN1p1/2p1q3/2B1P3/4P2P/P5P1/3Q1RK1 b - - 0 20")
      observed = board.handcrafted_eval()
      # Pawns, Knights, Bishops, Rooks, Queens
      expected = 0.0 + 0 + 300 + 0 + 0

    check(observed == expected)

  test "up one bishop reversed":
    let
      # Random position from a game on lichess, 3/10/21
      # https://lichess.org/P8m6HLy7/black#39
      b1 = load_fen("r4rk1/pR2np1p/2nNN1p1/2p1q3/2B1P3/4P2P/P5P1/3Q1RK1 b - - 0 20")
      b2 = b1.color_swap()

      black_to_move = b1.handcrafted_eval()
      white_to_move = b2.handcrafted_eval()
      # Pawns, Knights, Bishops, Rooks, Queens
      expected = 0.0 + 0 + 300 + 0 + 0

    check(white_to_move == -expected)
    check(black_to_move == expected)
    check(white_to_move == -black_to_move)
