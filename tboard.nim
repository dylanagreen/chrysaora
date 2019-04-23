import unittest
import tables
import sets
import arraymancer

import board

suite "start of game move generation":
  setup:
    var test_board: Board = new_board()

  test "knight moves":
    var moves = test_board.generate_knight_moves(Color.WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m[0])
    var expected = ["Na3", "Nc3", "Nf3", "Nh3"].toHashSet

    check(alg == expected)

  test "rook moves":
    var moves = test_board.generate_rook_moves(Color.WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m[0])
    var expected = initHashSet[string]()

    check(alg == expected)

  test "bishop moves":
    var moves = test_board.generate_bishop_moves(Color.WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m[0])
    var expected = initHashSet[string]()

    check(alg == expected)

  test "queen moves":
    var moves = test_board.generate_queen_moves(Color.WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m[0])
    var expected = initHashSet[string]()

  test "king moves":
    var moves = test_board.generate_king_moves(Color.WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m[0])
    var expected = initHashSet[string]()

    check(alg == expected)

  test "castle moves":
    var moves = test_board.generate_castle_moves(Color.WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m[0])
    var expected = initHashSet[string]()

    check(alg == expected)

  test "pawn moves":
    var moves = test_board.generate_pawn_moves(Color.WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m[0])
    var expected = ["a3", "a4", "b3", "b4", "c3", "c4", "d3", "d4", "e3", "e4",
                    "f3", "f4", "g3", "g4", "h3", "h4"].toHashSet

    check(alg == expected)

suite "complicated move generation":
  setup:
    # Loads a complicated fen to test from.
    var test_board: Board = load_fen("1nb1kb2/7p/r1p2np1/P2r4/RP5q/2N3P1/1B1PP2P/3QK2R w KQkq -")

  test "loading board state from fen":
    var expected = @[[0, -3, -4, 0, -6, -4, 0, 0],
                      [0, 0, 0, 0, 0, 0, 0, -1],
                      [-2, 0, -1, 0, 0, -3, -1, 0],
                      [1, 0, 0, -2, 0, 0, 0, 0],
                      [2, 1, 0, 0, 0, 0, 0, -5],
                      [0, 0, 3, 0, 0, 0, 1, 0],
                      [0, 4, 0, 1, 1, 0, 0, 1],
                      [0, 0, 0, 5, 6, 0, 0, 2]].toTensor

    check(test_board.current_state == expected)

  test "knight moves":
    var moves = test_board.generate_knight_moves(Color.BLACK)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m[0])
    #var expected = ["Na2", "Nb5", "Nxd5", "Ne4"].toHashSet
    var expected = ["Nb8d7", "Nf6d7", "Ng4", "Ne4", "Nh5", "Ng8"].toHashSet

    check(alg == expected)

  test "rook moves":
    var moves = test_board.generate_rook_moves(Color.WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m[0])
    var expected = ["Ra3", "Ra2", "Ra1", "Rf1", "Rg1"].toHashSet

    check(alg == expected)

  test "bishop moves":
    var moves = test_board.generate_bishop_moves(Color.BLACK)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m[0])
    var expected = ["Bb7", "Bd7", "Be6", "Bf5", "Bg4", "Bh3", "Be7", "Bd6",
                    "Bc5", "Bxb4", "Bg7", "Bh6"].toHashSet

    check(alg == expected)

  test "queen moves":
    var moves = test_board.generate_queen_moves(Color.WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m[0])
    var expected = ["Qa1", "Qb1", "Qc1", "Qc2", "Qb3"].toHashSet

    check(alg == expected)

  test "king moves":
    var moves = test_board.generate_king_moves(Color.WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m[0])
    var expected = ["Kf1", "Kf2"].toHashSet

    check(alg == expected)

  test "pawn moves":
    var moves = test_board.generate_pawn_moves(Color.WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m[0])
    var expected = ["b5", "d4", "d3", "e4", "e3", "h3", "gxh4"].toHashSet

    check(alg == expected)

  test "castle moves":
    var moves = test_board.generate_castle_moves(Color.WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m[0])
    var expected = ["O-O"].toHashSet

    check(alg == expected)