import unittest

import arraymancer

import ../src/board
include ../src/net

suite "board state to tensor":

  test "start pos":
    let board = new_board()
    let observed = board.prep_board_for_network()
    let expected = [8, 2, 2, 2, 1, 8, 2, 2, 2, 1, 1, 48, 1, 49, 1, 50, 1, 51, 1,
                    52, 1, 53, 1, 54, 1, 55, 2, 57, 2, 62, 3, 58, 3, 61, 4, 56,
                    4, 63, 5, 59, 6, 60, 1, 8, 1, 9, 1, 10, 1, 11, 1, 12, 1, 13,
                    1, 14, 1, 15, 2, 1, 2, 6, 3, 2, 3, 5, 4, 0, 4, 7, 5, 3, 6,
                    4, 1].toTensor().astype(float32)

    check(observed == expected)

  test "complicated pos - black to move, in check":
    # From Lichess' daily puzzle 7-23-2019
    let board = load_fen("4R3/4k1p1/4p1Bp/3bN3/8/5PK1/3r2PP/4n3 b - - 7 46")
    let observed = board.prep_board_for_network()

    let expected = [3, 1, 1, 1, 0, 3, 1, 1, 1, 0, 1, 45, 1, 54, 1, 55, -1, -1,
                    -1, -1, -1, -1, -1, -1, -1, -1, 2, 28, -1, -1, 3, 22, -1,
                    -1, 4, 4, -1, -1, -1, -1, 6, 46, 1, 14, 1, 20, 1, 23, -1,
                    -1, -1, -1, -1, -1, -1, -1, -1, -1, 2, 60, -1, -1, 3, 27,
                    -1, -1, 4, 51, -1, -1, -1, -1, 6, 12, -1].toTensor().astype(float32)

    check(observed == expected)

