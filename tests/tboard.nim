import unittest
import tables
import sets
import arraymancer
import times

import ../src/board
import ../src/perft

suite "start of game move generation":
  setup:
    let test_board = new_board()

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

    check(alg == expected)

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

    var expected = ["a3", "a4", "b3", "b4", "c3", "c4", "d3", "d4", "e3",
                    "e4", "f3", "f4", "g3", "g4", "h3", "h4"].toHashSet

    check(alg == expected)

  test "all moves":
    var moves = test_board.generate_moves(Color.WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m[0])

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

  test "all moves":
    var moves = test_board.generate_moves(Color.WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m[0])

    var expected = ["O-O", "b5", "d4", "d3", "e4", "e3", "h3", "gxh4", "Kf1",
                    "Kf2", "Qa1", "Qb1", "Qc1", "Qc2", "Qb3", "Ra3", "Ra2",
                    "Ra1", "Rf1", "Rg1", "Na2", "Nb5", "Nxd5", "Ne4", "Ba1",
                    "Ba3", "Bc1", "Nb1"].toHashSet

    check(alg == expected)

suite "checkmate verification":
  test "white":
    # Puzzle from Lichess, already solved as a checkmate
    let test_board = load_fen("5rk1/8/7p/3R2p1/3P4/8/6PP/4q1K1 w - - 0 37")
    var moves = test_board.generate_moves(Color.WHITE)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m[0])
    var expected = initHashSet[string]()

    check(alg == expected)

    var checkmate = test_board.current_state.is_checkmate(test_board.to_move)
    check(checkmate == true)

  test "black":
    # Puzzle from Lichess, already solved as a checkmate
    let
      test_fen = "r6k/1bp2Bp1/p5p1/1p6/3qn2Q/7P/P4PP1/2R3K1 b - - 1 25"
      test_board = load_fen(test_fen)

    var moves = test_board.generate_moves(Color.BLACK)

    # This strips out the algebraic parts of the moves.
    var alg: HashSet[string] = initHashSet[string]()
    for i, m in moves:
      alg.incl(m[0])
    var expected = initHashSet[string]()

    check(alg == expected)

    var checkmate = test_board.current_state.is_checkmate(test_board.to_move)
    check(checkmate == true)

suite "short algebraic conversion":
  setup:
    # Loads a complicated fen to test from.
    # Taken from the game that was the lichess puzzle on 4/23/19
    let
      test_fen = "r4rk1/1p2qpb1/5np1/4p1Bp/p2nP2P/2N5/PPP1Q1P1/N1KR3R w - - 4 18"
      test_board = load_fen(test_fen)

  test "knight moves":
    var long = test_board.short_algebraic_to_long_algebraic("Nb3")
    check(long == "Na1b3")

    long = test_board.short_algebraic_to_long_algebraic("Nb5")
    check(long == "Nc3b5")

    long = test_board.short_algebraic_to_long_algebraic("Nd5")
    check(long == "Nc3d5")

  test "rook moves":
    # Rook sideways
    var long = test_board.short_algebraic_to_long_algebraic("Rd2")
    check(long == "Rd1d2")

    # Rooks partial disambiguation
    long = test_board.short_algebraic_to_long_algebraic("Rdf1")
    check(long == "Rd1f1")

    long = test_board.short_algebraic_to_long_algebraic("Rhf1")
    check(long == "Rh1f1")

    # Rook forward
    long = test_board.short_algebraic_to_long_algebraic("Rh3")
    check(long == "Rh1h3")

  test "bishop moves":
    # Bishop diagonal
    var long = test_board.short_algebraic_to_long_algebraic("Bd2")
    check(long == "Bg5d2")

    long = test_board.short_algebraic_to_long_algebraic("Bh6")
    check(long == "Bg5h6")

    # Piece taking
    long = test_board.short_algebraic_to_long_algebraic("Bxf6")
    check(long == "Bg5xf6")

  test "queen moves":
    # Piece taking
    var long = test_board.short_algebraic_to_long_algebraic("Qxh5")
    check(long == "Qe2xh5")

    # Queen straight move
    long = test_board.short_algebraic_to_long_algebraic("Qe2e3")
    check(long == "Qe2e3")

    # Queen makes an illegal move
    long = test_board.short_algebraic_to_long_algebraic("Qd1")
    check(long == "")

  test "pawn moves":
    # Illegal pawn move
    var long = test_board.short_algebraic_to_long_algebraic("e5")
    check(long == "")

    # Pawn moves 2
    long = test_board.short_algebraic_to_long_algebraic("b4")
    check(long == "b2b4")

    # Pawn moves 1
    long = test_board.short_algebraic_to_long_algebraic("b3")
    check(long == "b2b3")

    # Pawn full disambiguation
    long = test_board.short_algebraic_to_long_algebraic("g2g3")
    check(long == "g2g3")

  test "king moves":
    # Illegal pawn move
    var long = test_board.short_algebraic_to_long_algebraic("Kc2")
    check(long == "")

    # King moves diagonal
    long = test_board.short_algebraic_to_long_algebraic("Kd2")
    check(long == "Kc1d2")

    # King moves straight
    long = test_board.short_algebraic_to_long_algebraic("Kb1")
    check(long == "Kc1b1")

suite "castling algebraic conversion":
  setup:
    # This test suite uses a modified version of the fen from short algebraic
    var
      test_fen = "r4rk1/1p2qpb1/2n2np1/4p1Bp/p3P2P/2N5/PPP1Q1P1/R3K2R w KQ -"
      test_board = load_fen(test_fen)

  test "kingside":
    var long = test_board.short_algebraic_to_long_algebraic("O-O")
    check(long == "O-O")

  test "queenside":
    var long = test_board.short_algebraic_to_long_algebraic("O-O-O")
    check(long == "O-O-O")

  test "queenside illegal":
    test_fen = "r4rk1/1p2qpb1/2n2np1/4p1Bp/p3P2P/8/PPP1Q1P1/R2NK2R b KQ -"
    test_board = load_fen(test_fen)

    var long = test_board.short_algebraic_to_long_algebraic("O-O-O")
    check(long == "")

  test "kingside illegal":
    test_fen = "r4rk1/1p2qpb1/2n2np1/4p1Bp/p3P2P/2N5/PPP3P1/R3KQ1R w KQ -"
    test_board = load_fen(test_fen)

    var long = test_board.short_algebraic_to_long_algebraic("O-O")
    check(long == "")

suite "move legality":
  setup:
    # Loads a complicated fen to test from.
    # Taken from the game that was the lichess puzzle on 4/23/19
    var
      test_fen = "r4rk1/1p2qpb1/5np1/4p1Bp/p2nP2P/2N5/PPP1Q1P1/N1KR3R w - - 4 18"
      test_board = load_fen(test_fen)

  test "knight moves":
    var legal = test_board.check_move_legality("Nb3")
    check(legal[0])

    legal = test_board.check_move_legality("Nb5")
    check(legal[0])

    legal = test_board.check_move_legality("Nd5")
    check(legal[0])

  test "rook moves":
    # Rook sideways
    var legal = test_board.check_move_legality("Rd2")
    check(legal[0])

    # Rooks partial disambiguation
    legal = test_board.check_move_legality("Rdf1")
    check(legal[0])

    legal = test_board.check_move_legality("Rhf1")
    check(legal[0])

    # Rook forward
    legal = test_board.check_move_legality("Rh3")
    check(legal[0])

  test "bishop moves":
    # Bishop diagonal
    var legal = test_board.check_move_legality("Bd2")
    check(legal[0])

    legal = test_board.check_move_legality("Bh6")
    check(legal[0])

    # Piece taking
    legal = test_board.check_move_legality("Bxf6")
    check(legal[0])

  test "queen moves":
    # Piece taking
    var legal = test_board.check_move_legality("Qxh5")
    check(legal[0])

    # Queen straight move
    legal = test_board.check_move_legality("Qe2e3")
    check(legal[0])

    # Queen makes an illegal move
    legal = test_board.check_move_legality("Qd1")
    check(legal[0] == false)

  test "pawn moves":
    # Illegal pawn move
    var legal = test_board.check_move_legality("e5")
    check(legal[0] == false)

    # Pawn moves 2
    legal = test_board.check_move_legality("b4")
    check(legal[0])

    # Pawn moves 1
    legal = test_board.check_move_legality("b3")
    check(legal[0])

    # Pawn full disambiguation
    legal = test_board.check_move_legality("g2g3")
    check(legal[0])

  test "king moves":
    # Illegal pawn move
    var legal = test_board.check_move_legality("Kc2")
    check(legal[0] == false)

    # King moves diagonal
    legal = test_board.check_move_legality("Kd2")
    check(legal[0])

    # King moves straight
    legal = test_board.check_move_legality("Kb1")
    check(legal[0])

  test "kingside castling":
    test_fen = "r4rk1/1p2qpb1/2n2np1/4p1Bp/p3P2P/2N5/PPP1Q1P1/R3K2R w KQ -"
    test_board = load_fen(test_fen)

    var legal = test_board.check_move_legality("O-O")
    check(legal[0])

  test "queenside":
    test_fen = "r4rk1/1p2qpb1/2n2np1/4p1Bp/p3P2P/2N5/PPP1Q1P1/R3K2R w KQ -"
    test_board = load_fen(test_fen)

    var legal = test_board.check_move_legality("O-O-O")
    check(legal[0])

  test "queenside illegal":
    test_fen = "r4rk1/1p2qpb1/2n2np1/4p1Bp/p3P2P/8/PPP1Q1P1/R2NK2R b KQ -"
    test_board = load_fen(test_fen)

    var legal = test_board.check_move_legality("O-O-O")
    check(legal[0] == false)

  test "kingside illegal":
    test_fen = "r4rk1/1p2qpb1/2n2np1/4p1Bp/p3P2P/2N5/PPP3P1/R3KQ1R w KQ -"
    test_board = load_fen(test_fen)

    var legal = test_board.check_move_legality("O-O")
    check(legal[0] == false)

suite "loading/saving":

  test "loading fen":
    var
      test_fen = "1nb1kb2/7p/r1p2np1/P2r4/RP5q/2N3P1/1B1PP2P/3QK2R w KQkq -"
      test_board = load_fen(test_fen)
      expected = @[[0, -310, -300, 0, -1000, -300, 0, 0],
                   [0, 0, 0, 0, 0, 0, 0, -100],
                   [-500, 0, -100, 0, 0, -310, -100, 0],
                   [100, 0, 0, -500, 0, 0, 0, 0],
                   [500, 100, 0, 0, 0, 0, 0, -900],
                   [0, 0, 310, 0, 0, 0, 100, 0],
                   [0, 300, 0, 100, 100, 0, 0, 100],
                   [0, 0, 0, 900, 1000, 0, 0, 500]].toTensor

    check(test_board.current_state == expected)

  test "saving fen":
    var
      test_fen = "r4rk1/1p2qpb1/5np1/4p1Bp/p2nP2P/2N5/PPP1Q1P1/N1KR3R w - - 4 18"
      test_board = load_fen(test_fen)

      generated = test_board.to_fen()

    check(generated == test_fen)

  test "loading pgn - immortal game":
    let t1 = cpuTime()
    var test_board = load_pgn("anderssen_kieseritzky_1851", "games")
    echo "Time taken: ", cpuTime() - t1
    var expected = @[[-500, 0, -300, -1000, 0, 0, 0, -500],
                     [-100, 0, 0, -100, 300, -100, 310, -100],
                     [-310, 0, 0, 0, 0, -310, 0, 0],
                     [0, -100, 0, 310, 100, 0, 0, 100],
                     [0, 0, 0, 0, 0, 0, 100, 0],
                     [0, 0, 0, 100, 0, 0, 0, 0],
                     [100, 0, 100, 0, 1000, 0, 0, 0],
                     [-900, 0, 0, 0, 0, 0, -300, 0]].toTensor

    check(test_board.current_state == expected)

  test "loading pgn - Komodo MCTS vs Lc0":
    let t1 = cpuTime()
    let test_pgn = "KomodoMCTS 2221.00vsLCZero v19.1-11248 2018-12-15"
    var test_board = load_pgn(test_pgn, "games")
    echo "Time taken: ", cpuTime() - t1

    var expected = @[[0, 0, 0, 0, 0, 0, 0, 0],
                     [0, 0, 0, 0, 0, 0, 0, 0],
                     [0, 0, 0, 0, 0, 0, 0, 0],
                     [0, 0, 0, 0, 0, 0, 0, 0],
                     [0, 0, 0, 0, 0, 0, 0, 0],
                     [0, 0, -1000, 0, 1000, 0, 0, 0],
                     [-100, 0, 0, -100, 0, -100, 0, 0],
                     [0, 0, 0, 500, 0, 0, 0, 0]].toTensor

    check(test_board.current_state == expected)

    # For testing saving to make sure it doesn't throw an exception
    #test_board.save_pgn()

  test "pgn -> fen":
    let
      test_pgn = "KomodoMCTS 2221.00vsLCZero v19.1-11248 2018-12-15"
      test_fen = "8/8/8/8/8/2k1K3/p2p1p2/3R4 b - - 0 78"
    var
      test_board = load_pgn(test_pgn, "games")
      generated = test_board.to_fen()
    check(generated == test_fen)

suite "perft tests":
  test "position 1 depth 4":
    var
      search_board = new_board()
      depth = 4
      t1 = cpuTime()
      num_nodes = perft_search(search_board, depth, search_board.to_move)
      t2 = cpuTime()
      time = t2 - t1

    check(num_nodes == 197281)
    echo "NPS: ", float(num_nodes) / time

  test "position 2 depth 3":
    var
      search_board = load_fen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - ")
      depth = 3
      t1 = cpuTime()
      num_nodes = perft_search(search_board, depth, search_board.to_move)
      t2 = cpuTime()
      time = t2 - t1

    check(num_nodes == 97862)
    echo "NPS: ", float(num_nodes) / time

  test "position 3 depth 4":
    var
      search_board = load_fen("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - -")
      depth = 4
      t1 = cpuTime()
      num_nodes = perft_search(search_board, depth, search_board.to_move)
      t2 = cpuTime()
      time = t2 - t1

    check(num_nodes == 43238)
    echo "NPS: ", float(num_nodes) / time

  test "position 4 depth 4":
    var
      search_board = load_fen("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1")
      depth = 4
      t1 = cpuTime()
      num_nodes = perft_search(search_board, depth, search_board.to_move)
      t2 = cpuTime()
      time = t2 - t1

    check(num_nodes == 422333)
    echo "NPS: ", float(num_nodes) / time

  test "position 5 depth 3":
    var
      search_board = load_fen("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8")
      depth = 3
      t1 = cpuTime()
      num_nodes = perft_search(search_board, depth, search_board.to_move)
      t2 = cpuTime()
      time = t2 - t1

    check(num_nodes == 62379)
    echo "NPS: ", float(num_nodes) / time

  test "position 6 depth 3":
    var
      search_board = load_fen("r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10")
      depth = 3
      t1 = cpuTime()
      num_nodes = perft_search(search_board, depth, search_board.to_move)
      t2 = cpuTime()
      time = t2 - t1

    check(num_nodes == 89890)
    echo "NPS: ", float(num_nodes) / time
