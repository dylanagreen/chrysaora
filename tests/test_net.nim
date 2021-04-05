import unittest

import arraymancer

import ../src/board
include ../src/net

# Everything about this file was tedious as hell to write.
suite "board state to tensor":

# Empty tensor for testing:
#  let expected = [0.0, 0.0, 0.0, 0.0, 0.0, # Piece difference
#               1.0, # Side to move (WHITE)
#               0.0, 0.0, # Castling rights
#               0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Knight Ranks
#               0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Knight Files
#               0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Bishop Ranks
#               0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Bishop Files
#               0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Rook Ranks
#               0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Rook Files
#               0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Queen Ranks
#               0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Queen Files
#               0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Pawn Ranks
#               0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Pawn Files
#               0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 # Doubled Pawns by file

  test "start pos":
    let board = new_board()
    let observed = board.prep_board_for_network()
    let expected = [0.0, 0.0, 0.0, 0.0, 0.0, # Piece difference
                    1.0, # Side to move (WHITE)
                    0.0, 0.0, # Castling rights
                    -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, # Knight Ranks
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Knight Files
                    -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, # Bishop Ranks
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Bishop Files
                    -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, # Rook Ranks
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Rook Files
                    -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, # Queen Ranks
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Queen Files
                    0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, # Pawn Ranks
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Pawn Files
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 # Doubled Pawns by file
                    ].toTensor().astype(float32)

    check(observed == expected)

  test "complicated pos - black to move, in check":
    # From Lichess' daily puzzle 7-23-2019
    let board = load_fen("4R3/4k1p1/4p1Bp/3bN3/8/5PK1/3r2PP/4n3 b - - 7 46")
    let observed = board.prep_board_for_network()

    let expected = [0.0, 0.0, 0.0, 0.0, 0.0, # Piece difference
                    -1.0, # Side to move (BLACK)
                    0.0, 0.0, # Castling rights
                    0.0, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, -0.5, # Knight Ranks
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Knight Files
                    0.0, 0.0, 0.5, -0.5, 0.0, 0.0, 0.0, 0.0, # Bishop Ranks
                    0.0, 0.0, 0.0, -0.5, 0.0, 0.0, 0.5, 0.0, # Bishop Files
                    0.5, 0.0, 0.0, 0.0, 0.0, 0.0, -0.5, 0.0, # Rook Ranks
                    0.0, 0.0, 0.0, -0.5, 0.5, 0.0, 0.0, 0.0, # Rook Files
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Queen Ranks
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Queen Files
                    0.0, -0.125, -0.25, 0.0, 0.0, 0.125, 0.25, 0.0, # Pawn Ranks
                    0.0, 0.0, 0.0, 0.0, -1.0, 1.0, 0.0, 0.0, # Pawn Files
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 # Doubled Pawns by file
                    ].toTensor().astype(float32)

    check(observed == expected)

  test "color swap start pos":
    let board = new_board()
    let observed = board.prep_board_for_network().color_swap_board()
    let expected = [0.0, 0.0, 0.0, 0.0, 0.0, # Piece difference
                    -1.0, # Side to move (BLACK)
                    0.0, 0.0, # Castling rights
                    -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, # Knight Ranks
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Knight Files
                    -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, # Bishop Ranks
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Bishop Files
                    -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, # Rook Ranks
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Rook Files
                    -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, # Queen Ranks
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Queen Files
                    0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, # Pawn Ranks
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Pawn Files
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 # Doubled Pawns by file
                    ].toTensor().astype(float32)

    check(observed == expected)

  test "white to move, black 3 rooks":
    # A test to make sure we not only generate promotions correctly, but that
    # we put them in the correct place, i.e. the black section.
    # A position from AllieStein v0.2 vs Xiphos 0.5.2, March 24, 2019
    let board = load_fen("2qbrr2/p4pk1/1p5p/2p1N3/P2pPP2/1P1P2P1/5R2/Q4KRr w - - 0 34")
    let observed = board.prep_board_for_network()

    let expected = [0.0, 0.5, -0.5, -0.5, 0.0, # Piece difference
                    1.0, # Side to move (WHITE)
                    0.0, 0.0, # Castling rights
                    0.0, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 0.0, # Knight Ranks
                    0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, # Knight Files
                    -0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Bishop Ranks
                    0.0, 0.0, 0.0, -0.5, 0.0, 0.0, 0.0, 0.0, # Bishop Files
                    -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.0, # Rook Ranks
                    0.0, 0.0, 0.0, 0.0, -0.5, 0.0, 0.5, -0.5, # Rook Files
                    -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, # Queen Ranks
                    1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Queen Files
                    0.0, -0.25, -0.25, -0.125, 0.25, 0.375, 0.0, 0.0, # Pawn Ranks
                    0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, -1.0, # Pawn Files
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 # Doubled Pawns by file
                    ].toTensor().astype(float32)

    check(observed == expected)

  test "black to move, white 3 rooks (reversed previous)":
    # A test to make sure we not only generate promotions correctly, but that
    # we put them in the correct place, i.e. the white section.
    # A position from AllieStein v0.2 vs Xiphos 0.5.2, March 24, 2019
    let board = load_fen("2qbrr2/p4pk1/1p5p/2p1N3/P2pPP2/1P1P2P1/5R2/Q4KRr w - - 0 34")
    let observed = board.prep_board_for_network().color_swap_board()
    let expected = [0.0, -0.5, 0.5, 0.5, 0.0, # Piece difference
                    -1.0, # Side to move (BLACK)
                    0.0, 0.0, # Castling rights
                    0.0, 0.0, 0.0, 0.0, -0.5, 0.0, 0.0, 0.0, # Knight Ranks
                    0.0, 0.0, 0.0, 0.0, -0.5, 0.0, 0.0, 0.0, # Knight Files
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, # Bishop Ranks
                    0.0, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 0.0, # Bishop Files
                    0.0, -0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, # Rook Ranks
                    0.0, 0.0, 0.0, 0.0, 0.5, 0.0, -0.5, 0.5, # Rook Files
                    -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, # Queen Ranks
                    -1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Queen Files
                    0.0, 0.0, -0.375, -0.25, 0.125, 0.25, 0.25, 0.0, # Pawn Ranks
                    0.0, 0.0, 1.0, 0.0, -1.0, 0.0, -1.0, 1.0, # Pawn Files
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 # Doubled Pawns by file
                    ].toTensor().astype(float32)

    check(observed == expected)

  test "white to move, unequal castling rights, doubled d-file":
    # Testing to make sure that we're putting the castling rights into the right place
    # in the network tensor.
    # Position from lichess puzzle, March 17, 2021
    let board = load_fen("1r3Bk1/3P2pp/p3pq2/8/3PKp2/2PQ1P2/P6P/R6R w Kq - 0 1")
    let observed = board.prep_board_for_network()
    let expected = [0.125, 0.0, 0.5, 0.5, 0.0, # Piece difference
                    1.0, # Side to move (WHITE)
                    1.0, -1.0, # Castling rights
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Knight Ranks
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Knight Files
                    0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Bishop Ranks
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, # Bishop Files
                    -0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, # Rook Ranks
                    0.5, -0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, # Rook Files
                    0.0, 0.0, -1.0, 0.0, 0.0, 1.0, 0.0, 0.0, # Queen Ranks
                    0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0, 0.0, # Queen Files
                    0.0, -0.125, -0.25, 0.0, 0.0, 0.25, 0.25, 0.0, # Pawn Ranks
                    0.0, 0.0, 1.0, 1.0, -1.0, 0.0, -1.0, 0.0, # Pawn Files
                    0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0 # Doubled Pawns by file
                    ].toTensor().astype(float32)

    check(observed == expected)

  test "black to move, doubled c-file":
    # Testing to make sure that doubled black pawns work as expected
    # Position from lichess puzzle, April 4, 2021
    let board = load_fen("r1bQRrk1/ppp3pp/2p5/5q2/5PP1/2N5/PP5P/5RK1 b - - 0 19")
    let observed = board.prep_board_for_network()
    let expected = [-0.125, 0.5, -0.5, 0.0, 0.0, # Piece difference
                    -1.0, # Side to move (WHITE)
                    0.0, 0.0, # Castling rights
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, # Knight Ranks
                    0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, # Knight Files
                    -0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, # Bishop Ranks
                    0.0, 0.0, -0.5, 0.0, 0.0, 0.0, 0.0, 0.0, # Bishop Files
                    -0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, # Rook Ranks
                    -0.5, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, # Rook Files
                    1.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, # Queen Ranks
                    0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0, 0.0, # Queen Files
                    0.0, -0.625, -0.125, 0.0, 0.25, 0.0, 0.375, 0.0, # Pawn Ranks
                    0.0, 0.0, -1.0, 0.0, 0.0, 1.0, 0.0, 0.0, # Pawn Files
                    0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0 # Doubled Pawns by file
                    ].toTensor().astype(float32)

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
