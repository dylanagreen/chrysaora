import unittest

import arraymancer

import ../src/board
include ../src/net

# Everything about this file was tedious as hell to write.
suite "board state to tensor":

  test "start pos":
    let board = new_board()
    let observed = board.prep_board_for_network()
    let expected = [0, 0, 0, 0, 0 # Piece difference
                    # 1, # Side to move (WHITE)
                    # 1, 1, 1, 1 # Castling rights
                    ].toTensor().astype(float32) # Black King

    check(observed == expected)

  test "complicated pos - black to move, in check":
    # From Lichess' daily puzzle 7-23-2019
    let board = load_fen("4R3/4k1p1/4p1Bp/3bN3/8/5PK1/3r2PP/4n3 b - - 7 46")
    let observed = board.prep_board_for_network()

    let expected = [0, 0, 0, 0, 0 # Piece difference
                    # -1, # Side to move (BLACK)
                    # 0, 0, 0, 0 # Castling rights
                    ].toTensor().astype(float32) # Black king

    check(observed == expected)

  test "color swap start pos":
    let board = new_board()
    let observed = board.prep_board_for_network().color_swap_board()
    let expected = [0, 0, 0, 0, 0 # Piece difference
                    # -1, # Side to move (BLACK)
                    # 1, 1, 1, 1 # Castling rights
                    ].toTensor().astype(float32) # Black King

    check(observed == expected)

  test "white to move, black 3 rooks":
    # A test to make sure we not only generate promotions correctly, but that
    # we put them in the correct place, i.e. the black section.
    # A position from AllieStein v0.2 vs Xiphos 0.5.2, March 24, 2019
    let board = load_fen("2qbrr2/p4pk1/1p5p/2p1N3/P2pPP2/1P1P2P1/5R2/Q4KRr w - - 0 34")
    let observed = board.prep_board_for_network()
    let expected = [0.0, 0.5, -0.5, -0.5, 0.0 # Piece difference
                    # 1, # Side to move (WHITE)
                    # 0, 0, 0, 0 # Castling rights
                    ].toTensor().astype(float32) # Black king

    check(observed == expected)

  test "black to move, white 3 rooks (reversed previous)":
    # Atest to make sure we not only generate promotions correctly, but that
    # we put them in the correct place, i.e. the white section.
    # A position from AllieStein v0.2 vs Xiphos 0.5.2, March 24, 2019
    let board = load_fen("2qbrr2/p4pk1/1p5p/2p1N3/P2pPP2/1P1P2P1/5R2/Q4KRr w - - 0 34")
    let observed = board.prep_board_for_network().color_swap_board()
    let expected = [0.0, -0.5, 0.5, 0.5, 0.0 # Piece difference
                    # -1, # Side to move (BLACK)
                    # 0, 0, 0, 0 # Castling rights
                    ].toTensor().astype(float32) # Black king

    check(observed == expected)

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
