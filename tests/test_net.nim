import unittest

import arraymancer

import ../src/board
include ../src/net

# Everything about this file was tedious as hell to write. But:
# Bugs caught with these tests: 4
# Tests are important kids!
suite "board state to tensor":

  test "start pos":
    let board = new_board()
    let observed = board.prep_board_for_network()
    let expected = [8, 2, 2, 2, 1, # White piece count
                    8, 2, 2, 2, 1, # Black piece count
                    1, # Side to move (WHITE)
                    1, 1, 1, 1, # Castling rights
                    1, 3, -4, 1, 3, -3, 1, 3, -2, 1, 3, -1,
                    1, 3, 1, 1, 3, 2, 1, 3, 3, 1, 3, 4, # White pawns
                    1, 4, -3, 1, 4, 3, # White knights (hahahahahaha)
                    1, 4, -2, 1, 4, 2, # White bishops
                    1, 4, -4, 1, 4, 4, # White rooks
                    1, 4, -1, # White queen
                    1, 4, 1, # White king
                    1, -3, -4, 1, -3, -3, 1, -3, -2, 1, -3, -1,
                    1, -3, 1, 1, -3, 2, 1, -3, 3, 1, -3, 4, # Black pawns
                    1, -4, -3, 1, -4, 3, # Black knights
                    1, -4, -2, 1, -4, 2, # Black bishops
                    1, -4, -4, 1, -4, 4, # Black rooks
                    1, -4, -1, # Black queen
                    1, -4, 1].toTensor().astype(float32) # Black King

    check(observed == expected / 8)

  test "complicated pos - black to move, in check":
    # From Lichess' daily puzzle 7-23-2019
    let board = load_fen("4R3/4k1p1/4p1Bp/3bN3/8/5PK1/3r2PP/4n3 b - - 7 46")
    let observed = board.prep_board_for_network()

    let expected = [3, 1, 1, 1, 0, # White piece count
                    3, 1, 1, 1, 0, # Black piece count
                    -1, # Side to move (BLACK)
                    0, 0, 0, 0, # Castling rights
                    1, 2, 2, 1, 3, 3, 1, 3, 4, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, # White pawns
                    1, -1, 1, 0, 0, 0, # White knights
                    1, -2, 3, 0, 0, 0, # White bishops
                    1, -4, 1, 0, 0, 0, # White rooks
                    0, 0, 0, # White queen
                    1, 2, 3, # White king
                    1, -3, 3, 1, -2, 1, 1, -2, 4, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, # Black pawns
                    1, 4, 1, 0, 0, 0, # Black knights
                    1, -1, -1, 0, 0, 0, # Black bishops
                    1, 3, -1, 0, 0, 0, # Black rooks
                    0, 0, 0, # Black queen
                    1, -3, 1].toTensor().astype(float32) # Black king

    check(observed == expected / 8)

  test "color swap start pos":
    let board = new_board()
    let observed = board.prep_board_for_network().color_swap_board()
    let expected = [8, 2, 2, 2, 1, # White piece count
                    8, 2, 2, 2, 1, # Black piece count
                    -1, # Side to move (BLACK)
                    1, 1, 1, 1, # Castling rights
                    1, 3, -4, 1, 3, -3, 1, 3, -2, 1, 3, -1,
                    1, 3, 1, 1, 3, 2, 1, 3, 3, 1, 3, 4, # White pawns
                    1, 4, -3, 1, 4, 3, # White knights
                    1, 4, -2, 1, 4, 2, # White bishops
                    1, 4, -4, 1, 4, 4, # White rooks
                    1, 4, -1, # White queen
                    1, 4, 1, # White king
                    1, -3, -4, 1, -3, -3, 1, -3, -2, 1, -3, -1,
                    1, -3, 1, 1, -3, 2, 1, -3, 3, 1, -3, 4, # Black pawns
                    1, -4, -3, 1, -4, 3, # Black knights
                    1, -4, -2, 1, -4, 2, # Black bishops
                    1, -4, -4, 1, -4, 4, # Black rooks
                    1, -4, -1, # Black queen
                    1, -4, 1].toTensor().astype(float32) # Black King

    check(observed == expected / 8)

  test "white to move, black 3 rooks":
    # A test to make sure we not only generate promotions correctly, but that
    # we put them in the correct place, i.e. the black section.
    # A position from AllieStein v0.2 vs Xiphos 0.5.2, March 24, 2019
    let board = load_fen("2qbrr2/p4pk1/1p5p/2p1N3/P2pPP2/1P1P2P1/5R2/Q4KRr w - - 0 34")
    let observed = board.prep_board_for_network()
    let expected = [6, 1, 0, 2, 1, # White piece count
                    6, 0, 1, 3, 1, # Black piece count
                    1, # Side to move (WHITE)
                    0, 0, 0, 0, # Castling rights
                    1, 1, -4, 1, 1, 1, 1, 1, 2, 1, 2, -3,
                    1, 2, -1, 1, 2, 3, 0, 0, 0, 0, 0, 0, # White pawns
                    1, -1, 1, 0, 0, 0, # White knights
                    0, 0, 0, 0, 0, 0, # White bishops
                    1, 3, 2, 1, 4, 3, # White rooks
                    1, 4, -4, # White queen
                    1, 4, 2, # White king
                    1, -3, -4, 1, -3, 2, 1, -2, -3, 1, -2, 4,
                    1, -1, -2, 1, 1, -1, 0, 0, 0, 1, 4, 4, # Black pawns and promoted rook
                    0, 0, 0, 0, 0, 0, # Black knights
                    1, -4, -1, 0, 0, 0, # Black bishops
                    1, -4, 1, 1, -4, 2, # Black rooks
                    1, -4, -2, # Black queen
                    1, -3, 3].toTensor().astype(float32) # Black king

    check(observed == expected / 8)

  test "black to move, white 3 rooks (reversed previous)":
    # Atest to make sure we not only generate promotions correctly, but that
    # we put them in the correct place, i.e. the white section.
    # A position from AllieStein v0.2 vs Xiphos 0.5.2, March 24, 2019
    let board = load_fen("2qbrr2/p4pk1/1p5p/2p1N3/P2pPP2/1P1P2P1/5R2/Q4KRr w - - 0 34")
    let observed = board.prep_board_for_network().color_swap_board()
    let expected = [6, 0, 1, 3, 1, # White piece count
                    6, 1, 0, 2, 1, # Black piece count
                    -1, # Side to move (BLACK)
                    0, 0, 0, 0, # Castling rights
                    1, 3, -4, 1, 3, 2, 1, 2, -3, 1, 2, 4,
                    1, 1, -2, 1, -1, -1, 0, 0, 0, 1, -4, 4, # White pawns and promoted rook
                    0, 0, 0, 0, 0, 0, # White knights
                    1, 4, -1, 0, 0, 0, # White bishops
                    1, 4, 1, 1, 4, 2, # White rooks
                    1, 4, -2, # White queen
                    1, 3, 3, # White king
                    1, -1, -4, 1, -1, 1, 1, -1, 2, 1, -2, -3,
                    1, -2, -1, 1, -2, 3, 0, 0, 0, 0, 0, 0, # Black pawns
                    1, 1, 1, 0, 0, 0, # Black knights
                    0, 0, 0, 0, 0, 0, # Black bishops
                    1, -3, 2, 1, -4, 3, # Black rooks
                    1, -4, -4, # Black queen
                    1, -4, 2].toTensor().astype(float32) # Black king

    check(observed == expected / 8)

suite "make/unmake before and after equality":
  test "white to move, black 3 rooks":
    # A position from AllieStein v0.2 vs Xiphos 0.5.2, March 24, 2019
    var board = load_fen("2qbrr2/p4pk1/1p5p/2p1N3/P2pPP2/1P1P2P1/5R2/Q4KRr w - - 0 34")
    let expected = board.prep_board_for_network()
    board.make_move("Ne5xf7")
    board.unmake_move()
    check(expected == board.prep_board_for_network())

  test "complicated pos - black to move, in check, 2 moves made":
    # From Lichess' daily puzzle 7-23-2019
    var board = load_fen("4R3/4k1p1/4p1Bp/3bN3/8/5PK1/3r2PP/4n3 b - - 7 46")
    let expected = board.prep_board_for_network()

    board.make_move("Ke7d6")
    board.make_move("Re8h8")
    board.unmake_move()
    board.unmake_move()

    check(expected == board.prep_board_for_network())
