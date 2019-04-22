import unittest
import sets

import board

suite "start of game move generation":
  setup:
    var test_board: board.Board = board.new_board()

  test "knight moves":
    var moves = test_board.generate_knight_moves(Color.WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m[0])
    var expected = ["Na3", "Nc3", "Nf3", "Nh3"].toHashSet

    check(alg == expected)

  #[#test "rook moves":
    #moves = #generate the moves
    var expected: array[0, string] = []
    check(moves == expected)

  test "bishop moves":
    #moves = #generate the moves
    var expected: array[0, string] = []
    check(moves == expected)

  test "queen moves":
    #moves = #generate the moves
    var expected: array[0, string] = []
    check(moves == expected)]#

  test "king moves":
    var moves = test_board.generate_king_moves(Color.WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m[0])
    var expected = initHashSet[string]()

    check(alg == expected)

  #[#test "pawn moves":
    #moves = #generate the moves
    var expected: array[16, string] = ["a3", "a4", "b3", "b4", "c3", "c4", "d3",
                                       "d4", "e3", "e4", "f3", "f4", "g3", "g4",
                                       "h3", "h4"]
    check(moves == expected)

suite "complicated move generation":
  setup:
    var temp: int = 4
    # make the board object

  test "knight moves":
    #moves = #generate the moves
    var expected: array[4, string] = ["Na3", "Nc3", "Nf3", "Nh3"]
    check(moves == expected)

  test "rook moves":
    #moves = #generate the moves
    var expected: array[0, string] = []
    check(moves == expected)

  test "bishop moves":
    #moves = #generate the moves
    var expected: array[0, string] = []
    check(moves == expected)

  test "queen moves":
    #moves = #generate the moves
    var expected: array[0, string] = []
    check(moves == expected)

  test "king moves":
    #moves = #generate the moves
    var expected: array[0, string] = []

  test "pawn moves":
    #moves = #generate the moves
    var expected: array[16, string] = ["a3", "a4", "b3", "b4", "c3", "c4", "d3",
                                        "d4", "e3", "e4", "f3", "f4", "g3", "g4",
                                        "h3", "h4"]
    check(moves == expected)]#