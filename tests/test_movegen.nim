import unittest
import tables
import sets
import arraymancer
import sequtils
import tables
import times

import ../src/board
import ../src/movegen

suite "start of game move generation":
  setup:
    let test_board = new_board()

  test "knight moves":
    var moves = test_board.generate_knight_moves(WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)
    var expected = ["Nb1a3", "Nb1c3", "Ng1f3", "Ng1h3"].toHashSet

    check(alg == expected)

  test "rook moves":
    var moves = test_board.generate_rook_moves(WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)
    var expected = initHashSet[string]()

    check(alg == expected)

  test "bishop moves":
    var moves = test_board.generate_bishop_moves(WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)
    var expected = initHashSet[string]()

    check(alg == expected)

  test "queen moves":
    var moves = test_board.generate_queen_moves(WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)
    var expected = initHashSet[string]()

    check(alg == expected)

  test "king moves":
    var moves = test_board.generate_king_moves(WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)
    var expected = initHashSet[string]()

    check(alg == expected)

  test "castle moves":
    var moves = test_board.generate_castle_moves(WHITE)

    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)
    var expected = initHashSet[string]()

    check(alg == expected)

  test "pawn moves":
    var
      moves1 = test_board.generate_pawn_moves(WHITE)
      moves2 = test_Board.generate_pawn_captures(WHITE)

    let moves = concat(moves1, moves2)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)
    var expected = ["a2a3", "a2a4", "b2b3", "b2b4", "c2c3", "c2c4", "d2d3",
                    "d2d4", "e2e3", "e2e4", "f2f3", "f2f4", "g2g3", "g2g4",
                    "h2h3", "h2h4"].toHashSet

    check(alg == expected)

  test "all moves":
    var moves = test_board.generate_all_moves(WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)

    var expected = ["a2a3", "a2a4", "b2b3", "b2b4", "c2c3", "c2c4", "d2d3",
                    "d2d4", "e2e3", "e2e4", "f2f3", "f2f4", "g2g3", "g2g4",
                    "h2h3", "h2h4", "Nb1a3", "Nb1c3", "Ng1f3", "Ng1h3"].toHashSet

    check(alg == expected)

suite "complicated move generation":
  setup:
    let
      test_fen = "1nb1kb2/7p/r1p2np1/P2r4/RP5q/2N3P1/1B1PP2P/3QK2R w K -"
      # Loads a complicated fen to test from.
      test_board = load_fen(test_fen)

  test "knight moves":
    var moves = test_board.generate_knight_moves(BLACK)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)

    #var expected = ["Na2", "Nb5", "Nxd5", "Ne4"].toHashSet
    var expected = ["Nb8d7", "Nf6d7", "Nf6g4", "Nf6e4", "Nf6h5", "Nf6g8"].toHashSet

    check(alg == expected)

  test "rook moves":
    var moves = test_board.generate_rook_moves(WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)
    var expected = ["Ra4a3", "Ra4a2", "Ra4a1", "Rh1f1", "Rh1g1"].toHashSet

    check(alg == expected)

  test "bishop moves":
    var moves = test_board.generate_bishop_moves(BLACK)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)
    var expected = ["Bc8b7", "Bc8d7", "Bc8e6", "Bc8f5", "Bc8g4", "Bc8h3",
                    "Bf8e7", "Bf8d6", "Bf8c5", "Bf8xb4", "Bf8g7",
                    "Bf8h6"].toHashSet

    check(alg == expected)

  test "queen moves":
    var moves = test_board.generate_queen_moves(WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)
    var expected = ["Qd1a1", "Qd1b1", "Qd1c1", "Qd1c2", "Qd1b3"].toHashSet

    check(alg == expected)

  test "king moves":
    var moves = test_board.generate_king_moves(WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)
    var expected = ["Ke1f1", "Ke1f2"].toHashSet

    check(alg == expected)

  test "pawn moves":
    var
      moves1 = test_board.generate_pawn_moves(WHITE)
      moves2 = test_Board.generate_pawn_captures(WHITE)

    let moves = concat(moves1, moves2)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)
    var expected = ["b4b5", "d2d3", "d2d4", "e2e3", "e2e4", "h2h3", "g3xh4"].toHashSet

    check(alg == expected)

  test "castle moves":
    var moves = test_board.generate_castle_moves(WHITE)

    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)
    var expected = ["O-O"].toHashSet

    check(alg == expected)

  test "all moves":
    var moves = test_board.generate_all_moves(WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)
    var expected = ["Nc3xd5", "Nc3b5", "Nc3a2", "Nc3b1", "Nc3e4", "Ra4a3",
                    "Ra4a2", "Ra4a1", "Rh1f1", "Rh1g1", "Bb2a1", "Bb2c1",
                    "Bb2a3", "Qd1a1", "Qd1b1", "Qd1c1", "Qd1c2", "Qd1b3",
                    "Ke1f1", "Ke1f2", "b4b5", "d2d3", "d2d4", "e2e3", "e2e4",
                    "h2h3", "g3xh4", "O-O"].toHashSet

    check(alg == expected)

suite "checkmate verification":
  test "white":
    # Puzzle from Lichess, already solved as a checkmate
    let test_board = load_fen("5rk1/8/7p/3R2p1/3P4/8/6PP/4q1K1 w - - 0 37")
    var moves = test_board.generate_all_moves(WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)
    var expected = initHashSet[string]()

    check(alg == expected)

    var checkmate = test_board.is_checkmate(test_board.to_move)
    check(checkmate == true)

  test "black":
    # Puzzle from Lichess, already solved as a checkmate
    let
      test_fen = "r6k/1bp2Bp1/p5p1/1p6/3qn2Q/7P/P4PP1/2R3K1 b - - 1 25"
      test_board = load_fen(test_fen)

    var moves = test_board.generate_all_moves(BLACK)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)
    var expected = initHashSet[string]()

    check(alg == expected)

    var checkmate = test_board.is_checkmate(test_board.to_move)
    check(checkmate == true)

