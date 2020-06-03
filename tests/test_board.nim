import unittest
import tables
import arraymancer
import sequtils
import system
import tables
import times

import ../src/board
import ../src/perft

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

  test "disambiguating pieces: 1 illegal, 1 legal":
    # In this test two rooks can make the same move and are not disambiguated.
    # One however leaves the king in check and should be ignored leading to the
    # other being correctly found and thus ideentifying the move as legal.
    test_fen = "4r1k1/5r1p/P1p3b1/2P5/1p1Bp2P/1B2Q3/6P1/1qN3K1 b - - 4 41"
    test_board = load_fen(test_fen)

    var legal = test_board.check_move_legality("Re7")
    check(legal[0] == true)

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
    var test_board = load_pgn("anderssen_kieseritzky_1851", "tests")
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
    var test_board = load_pgn(test_pgn, "tests")
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
      test_board = load_pgn(test_pgn, "tests")
      generated = test_board.to_fen()
    check(generated == test_fen)

suite "make/unmake tests":
  # Just tests that changing positions and changing back works good
  test "startpos e2e4":
    var
      board = new_board()
      white_pieces = deepCopy(board.piece_list[WHITE])
      black_pieces = deepCopy(board.piece_list[BLACK])
      zobrist = board.zobrist
    board.make_move("e2e4")
    board.unmake_move()
    check(board.piece_list[WHITE] == white_pieces)
    check(board.piece_list[BLACK] == black_pieces)
    check(board.zobrist == zobrist)

  # Checks that if a piece is taken and then put back it gets put back into
  # the correct place in the list.
  test "position 6 capture":
    var
      board = load_fen("r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10")
      white_pieces = deepCopy(board.piece_list[WHITE])
      black_pieces = deepCopy(board.piece_list[BLACK])
      zobrist = board.zobrist
    board.make_move("Bc4xf7")
    board.unmake_move()
    check(board.piece_list[WHITE] == white_pieces)
    check(board.piece_list[BLACK] == black_pieces)
    check(board.zobrist == zobrist)

  test "loading game and unmaking moves":
    # 2/3 of the way through this game, Stockfish was in check but not mate.
    # This loads the entire pgn, then unmakes 1/3 of the moves to check that
    # the check status is correct through unmaking moves.
    var
      test_pgn = "LCZero v0.21.1-nT40.T8.610vsStockfish 19050918 2019.05.11 4.1"
      board = load_pgn(test_pgn, "tests")
      num = board.movelist.len div 3 * 2

    for j in 1..num:
      board.unmake_move()

    check(board.check[WHITE] == false)
    check(board.check[BLACK] == true)

suite "perft tests":
  test "position 1 depth 4":
    var
      search_board = new_board()
      depth = 4
      z1 = search_board.zobrist
      t1 = cpuTime()
      num_nodes = perft_search(search_board, depth, search_board.to_move)
      t2 = cpuTime()
      z2 = search_board.zobrist
      time = t2 - t1

    check(num_nodes == 197281)
    check(z1 == z2)
    echo "NPS: ", float(num_nodes) / time

  test "position 2 depth 3":
    var
      search_board = load_fen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - ")
      depth = 3
      z1 = search_board.zobrist
      t1 = cpuTime()
      num_nodes = perft_search(search_board, depth, search_board.to_move)
      t2 = cpuTime()
      z2 = search_board.zobrist
      time = t2 - t1

    check(num_nodes == 97862)
    check(z1 == z2)
    echo "NPS: ", float(num_nodes) / time

  test "position 3 depth 4":
    var
      search_board = load_fen("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - -")
      depth = 4
      z1 = search_board.zobrist
      t1 = cpuTime()
      num_nodes = perft_search(search_board, depth, search_board.to_move)
      t2 = cpuTime()
      z2 = search_board.zobrist
      time = t2 - t1

    check(num_nodes == 43238)
    check(z1 == z2)
    echo "NPS: ", float(num_nodes) / time

  test "position 4 depth 4":
    var
      search_board = load_fen("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1")
      depth = 4
      z1 = search_board.zobrist
      t1 = cpuTime()
      num_nodes = perft_search(search_board, depth, search_board.to_move)
      t2 = cpuTime()
      z2 = search_board.zobrist
      time = t2 - t1

    check(num_nodes == 422333)
    check(z1 == z2)
    echo "NPS: ", float(num_nodes) / time

  test "position 5 depth 3":
    var
      search_board = load_fen("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8")
      depth = 3
      z1 = search_board.zobrist
      t1 = cpuTime()
      num_nodes = perft_search(search_board, depth, search_board.to_move)
      t2 = cpuTime()
      z2 = search_board.zobrist
      time = t2 - t1

    check(num_nodes == 62379)
    check(z1 == z2)
    echo "NPS: ", float(num_nodes) / time

  test "position 6 depth 3":
    var
      search_board = load_fen("r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10")
      depth = 3
      z1 = search_board.zobrist
      t1 = cpuTime()
      num_nodes = perft_search(search_board, depth, search_board.to_move)
      t2 = cpuTime()
      z2 = search_board.zobrist
      time = t2 - t1

    check(num_nodes == 89890)
    check(z1 == z2)
    echo "NPS: ", float(num_nodes) / time
