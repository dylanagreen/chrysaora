import unittest

import arraymancer

import ../src/board
include ../src/net

suite "board state to tensor":

  test "start pos":
    let board = new_board()
    let observed = board.prep_board_for_network()
    let expected = [8, 2, 2, 2, 1, 8, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 48, 1, 49, 1, 50, 1, 51,
                    1, 52, 1, 53, 1, 54, 1, 55, 2, 57, 2, 62, 3, 58, 3, 61, 4,
                    56, 4, 63, 5, 59, 6, 60, 1, 8, 1, 9, 1, 10, 1, 11, 1, 12, 1,
                    13, 1, 14, 1, 15, 2, 1, 2, 6, 3, 2, 3, 5, 4, 0, 4, 7, 5, 3,
                    6, 4].toTensor().astype(float32)

    check(observed == expected)

  test "complicated pos - black to move, in check":
    # From Lichess' daily puzzle 7-23-2019
    let board = load_fen("4R3/4k1p1/4p1Bp/3bN3/8/5PK1/3r2PP/4n3 b - - 7 46")
    let observed = board.prep_board_for_network()

    let expected = [3, 1, 1, 1, 0, 3, 1, 1, 1, 0, -1, 0, 0, 0, 0, 1, 45, 1, 54, 1, 55, -1,
                    -1, -1, -1, -1, -1, -1, -1, -1, -1, 2, 28, -1, -1, 3, 22,
                    -1, -1, 4, 4, -1, -1, -1, -1, 6, 46, 1, 14, 1, 20, 1, 23,
                    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 2, 60, -1, -1, 3,
                    27, -1, -1, 4, 51, -1, -1, -1, -1, 6, 12].toTensor().astype(float32)

    check(observed == expected)

  test "color swap start pos":
    let board = new_board()
    let observed = board.prep_board_for_network().color_swap_board()
    let expected = [8, 2, 2, 2, 1, 8, 2, 2, 2, 1, -1, 1, 1, 1, 1, 1, 48, 1, 49, 1, 50, 1, 51,
                    1, 52, 1, 53, 1, 54, 1, 55, 2, 57, 2, 62, 3, 58, 3, 61, 4,
                    56, 4, 63, 5, 59, 6, 60, 1, 8, 1, 9, 1, 10, 1, 11, 1, 12, 1,
                    13, 1, 14, 1, 15, 2, 1, 2, 6, 3, 2, 3, 5, 4, 0, 4, 7, 5, 3,
                    6, 4].toTensor().astype(float32)

    check(observed == expected)


  test "white to move, black 3 rooks":
    # Atest to make sure we not only generate promotions correctly, but that
    # we put them in the correct place, i.e. the black section.
    # A position from AllieStein v0.2 vs Xiphos 0.5.2, March 24, 2019
    let board = load_fen("2qbrr2/p4pk1/1p5p/2p1N3/P2pPP2/1P1P2P1/5R2/Q4KRr w - - 0 34")
    let observed = board.prep_board_for_network()
    let expected = [6, 1, 0, 2, 1, 6, 0, 1, 3, 1, 1, 0, 0, 0, 0, 1, 32, 1, 36, 1, 37,
                    1, 41, 1, 43, 1, 46, -1, -1, -1, -1, 2, 28, -1, -1, -1, -1,
                    -1, -1, 4, 53, 4, 62, 5, 56, 6, 61, 1, 8, 1, 13, 1, 17, 1, 23,
                    1, 26, 1, 35, -1, -1, 4, 63, -1, -1, -1, -1, 3, 3, -1, -1,
                    4, 4, 4, 5, 5, 2, 6, 14].toTensor().astype(float32)

    check(observed == expected)

  test "black to move, white 3 rooks (reversed previous)":
    # Atest to make sure we not only generate promotions correctly, but that
    # we put them in the correct place, i.e. the black section.
    # A position from AllieStein v0.2 vs Xiphos 0.5.2, March 24, 2019
    let board = load_fen("2qbrr2/p4pk1/1p5p/2p1N3/P2pPP2/1P1P2P1/5R2/Q4KRr w - - 0 34")
    let observed = board.prep_board_for_network().color_swap_board()
    let expected = [6, 0, 1, 3, 1, 6, 1, 0, 2, 1, -1, 0, 0, 0, 0, 1, 48, 1, 53, 1, 41, 1, 47,
                    1, 34, 1, 27, -1, -1, 4, 7, -1, -1, -1, -1, 3, 59, -1, -1,
                    4, 60, 4, 61, 5, 58, 6, 54, 1, 24, 1, 28, 1, 29,
                    1, 17, 1, 19, 1, 22, -1, -1, -1, -1, 2, 36, -1, -1, -1, -1,
                    -1, -1, 4, 13, 4, 6, 5, 0, 6, 5].toTensor().astype(float32)

    check(observed == expected)

