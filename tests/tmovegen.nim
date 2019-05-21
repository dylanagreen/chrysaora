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
    var expected = ["Na3", "Nc3", "Nf3", "Nh3"].toHashSet

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
    var expected = ["a3", "a4", "b3", "b4", "c3", "c4", "d3", "d4", "e3",
                    "e4", "f3", "f4", "g3", "g4", "h3", "h4"].toHashSet

    check(alg == expected)

  test "all moves":
    var moves = test_board.generate_all_moves(WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)

    var expected = ["a3", "a4", "b3", "b4", "c3", "c4", "d3", "d4", "e3",
                    "e4", "f3", "f4", "g3", "g4", "h3", "h4", "Na3", "Nc3",
                    "Nf3", "Nh3"].toHashSet

    check(alg == expected)

suite "complicated move generation":
  setup:
    let
      test_fen = "1nb1kb2/7p/r1p2np1/P2r4/RP5q/2N3P1/1B1PP2P/3QK2R w KQkq -"
      # Loads a complicated fen to test from.
      test_board = load_fen(test_fen)

  test "knight moves":
    var moves = test_board.generate_knight_moves(BLACK)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)

    #var expected = ["Na2", "Nb5", "Nxd5", "Ne4"].toHashSet
    var expected = ["Nb8d7", "Nf6d7", "Ng4", "Ne4", "Nh5", "Ng8"].toHashSet

    check(alg == expected)

  test "rook moves":
    var moves = test_board.generate_rook_moves(WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)
    var expected = ["Ra3", "Ra2", "Ra1", "Rf1", "Rg1"].toHashSet

    check(alg == expected)

  test "bishop moves":
    var moves = test_board.generate_bishop_moves(BLACK)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)
    var expected = ["Bb7", "Bd7", "Be6", "Bf5", "Bg4", "Bh3", "Be7", "Bd6",
                    "Bc5", "Bxb4", "Bg7", "Bh6"].toHashSet

    check(alg == expected)

  test "queen moves":
    var moves = test_board.generate_queen_moves(WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)
    var expected = ["Qa1", "Qb1", "Qc1", "Qc2", "Qb3"].toHashSet

    check(alg == expected)

  test "king moves":
    var moves = test_board.generate_king_moves(WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m.algebraic)
    var expected = ["Kf1", "Kf2"].toHashSet

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
    var expected = ["b5", "d4", "d3", "e4", "e3", "h3", "gxh4"].toHashSet

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
    var expected = ["O-O", "b5", "d4", "d3", "e4", "e3", "h3", "gxh4", "Kf1",
                    "Kf2", "Qa1", "Qb1", "Qc1", "Qc2", "Qb3", "Ra3", "Ra2",
                    "Ra1", "Rf1", "Rg1", "Na2", "Nb5", "Nxd5", "Ne4", "Ba1",
                    "Ba3", "Bc1", "Nb1"].toHashSet

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

