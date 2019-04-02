import unittest

import numpy as np

from .. import board

class MoveGenerationTestCase(unittest.TestCase):
    def test_knight_moves(self):
        # Base state board checking
        self.board = board.Board(None, None, None)
        moves = set(self.board.generate_knight_moves(board.Color.WHITE))
        expected = set(["Na3", "Nc3", "Nf3", "Nh3"])
        self.assertSetEqual(moves, expected)

        # A more complicated set, with piece blockage and taking.
        complicated = np.asarray([[-2, -3, -4, -5, -6, -4, -3, -2],
                                [-1, -1, -1, -1, -1, -1, -1, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 3, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 3, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [1, 1, 1, 1, 1, 1, 1, 1],
                                [2, 0, 4, 5, 6, 4, 0, 2]])
        self.board = board.Board(complicated, None, None)
        moves = set(self.board.generate_knight_moves(board.Color.WHITE))
        expected = set(["Nb6", "Nxc7", "Nxe7", "Nf6", "Ne3", "Nc3", "Nb4",
                        "Ne6", "Ng6", "Nh5", "Nh3", "Nd3"])
        self.assertSetEqual(moves, expected)

    def test_rook_moves(self):
        # Base state board checking
        self.board = board.Board(None, None, None)
        moves = set(self.board.generate_rook_moves(board.Color.WHITE))
        expected = set()
        self.assertSetEqual(moves, expected)

        # A more complicated set, with piece blockage and taking.
        complicated = np.asarray([[-2, -3, 2, -5, -6, 0, -3, -2],
                                [-1, -1, -1, -1, -1, -1, -1, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 2, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [1, 1, 1, 1, 1, 1, 1, 1],
                                [2, 3, 4, 5, 6, 4, 3, 2]])
        self.board = board.Board(complicated, None, None)
        moves = set(self.board.generate_rook_moves(board.Color.WHITE))
        expected = set(["Rb3", "Rb5", "Rb6", "Rxb7", "Ra4", "Rc4", "Rd4",
                        "Re4", "Rf4", "Rg4", "Rh4", "Rd4", "Rxc7", "Rxd8",
                        "Rxb8"])
        self.assertSetEqual(moves, expected)

    def test_bishop_moves(self):
        # Base state board checking
        self.board = board.Board(None, None, None)
        moves = set(self.board.generate_bishop_moves(board.Color.WHITE))
        expected = set()
        self.assertSetEqual(moves, expected)

        # A more complicated set, with piece blockage and taking.
        complicated = np.asarray([[-2, -3, -4, -5, -6, 4, -3, -2],
                                [-1, -1, -1, -1, -1, -1, -1, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 4, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [1, 1, 1, 1, 1, 1, 1, 1],
                                [2, 3, 4, 5, 6, 4, 3, 2]])
        self.board = board.Board(complicated, None, None)
        moves = set(self.board.generate_bishop_moves(board.Color.WHITE))
        expected = set(["Ba3", "Ba5", "Bc3", "Bc5", "Bd6", "Bb4xe7", "Bf8xe7",
                        "Bxg7"])
        self.assertSetEqual(moves, expected)

    def test_queen_moves(self):
        # Base state board checking
        self.board = board.Board(None, None, None)
        moves = set(self.board.generate_queen_moves(board.Color.WHITE))
        expected = set()
        self.assertSetEqual(moves, expected)

        # A more complicated set, with piece blockage and taking.
        complicated = np.asarray([[-2, -3, 5, -5, -6, 0, -3, -2],
                                [-1, -1, -1, -1, -1, -1, -1, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 5, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [1, 1, 1, 1, 1, 1, 1, 1],
                                [2, 3, 4, 5, 6, 4, 3, 2]])
        self.board = board.Board(complicated, None, None)
        moves = set(self.board.generate_queen_moves(board.Color.WHITE))
        expected = set(["Qa3", "Qa5", "Qc3", "Qc5", "Qd6", "Qxe7", "Qxc7",
                        "Qxd8", "Qb3", "Qb5", "Qb6", "Qxb7", "Qa4", "Qc4", "Qd4",
                        "Qe4", "Qf4", "Qg4", "Qh4", "Qd4", "Qxb8", "Qxd8", "Qxd7"])
        self.assertSetEqual(moves, expected)

    def test_king_moves(self):
        # Base state board checking
        self.board = board.Board(None, None, None)
        moves = set(self.board.generate_king_moves(board.Color.WHITE))
        expected = set()
        self.assertSetEqual(moves, expected)

        # A more complicated set, with piece blockage and taking.
        complicated = np.asarray([[-2, -3, -4, -5, -6, -4, -3, -2],
                                [-1, -1, -1, -1, -1, -1, -1, -1],
                                [0, 0, 0, 0, 6, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [1, 1, 1, 1, 1, 1, 1, 1],
                                [2, 3, 4, 5, 0, 4, 3, 2]])
        self.board = board.Board(complicated, None, None)
        moves = set(self.board.generate_king_moves(board.Color.WHITE))
        expected = set(["Kf5", "Ke5", "Kd5"])
        self.assertSetEqual(moves, expected)

    def test_pawn_moves(self):
        # Base state board checking
        self.board = board.Board(None, None, None)
        moves = set(self.board.generate_pawn_moves(board.Color.WHITE))
        expected = set(["a3", "a4", "b3", "b4", "c3", "c4", "d3", "d4", "e3",
                        "e4", "f3", "f4", "g3", "g4", "h3", "h4"])
        self.assertSetEqual(moves, expected)

        # A more complicated set, with piece blockage and taking.
        # As well as pawn promotion
        complicated = np.asarray([[0, -3, -4, -5, -6, -4, -3, -2],
                                [1, -1, -1, -1, -1, -1, -1, -1],
                                [0, 0, 0, 0, 5, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [-1, 0, 0, -1, 0, 0, 0, 0],
                                [1, 1, 1, 1, 1, 1, 1, 1],
                                [2, 3, 4, 5, 6, 4, 3, 2]])
        self.board = board.Board(complicated, None, None)
        moves = set(self.board.generate_pawn_moves(board.Color.WHITE))
        expected = set(["bxa3", "b3", "b4", "c3", "c4", "cxd3", "exd3", "e3",
                        "e4", "f3", "f4", "g3", "g4", "h3", "h4", "a8=Q",
                        "a8=R", "a8=B", "a8=N", "axb8=Q", "axb8=R", "axb8=B", "axb8=N"])
        self.assertSetEqual(moves, expected)

        # This set ensures that the en passant code doesn't break pawns moving.
        crash = np.asarray([[5, 0, 0, 0, 0, 0, 0, 0],
                           [0, 0, 0, 0, 0, 0, 0, 0],
                           [0, 0, 0, 0, 0, 0, 0, 0],
                           [0, 0, 0, 0, 0, 0, 0, 0],
                           [0, 0, 0, 0, 0, -1, 0, 0],
                           [6, -1, 0, 0, -1, -1, 0, -1],
                           [0, 0, 0, 0, 0, 0, -6, 0],
                           [2, 3, 0, 0, 0, 0, 3, 0]])
        self.board = board.Board(crash, None, None)
        moves = set(self.board.generate_pawn_moves(board.Color.BLACK))
        expected = set(['b2', 'e2', 'h2'])
        self.assertSetEqual(moves, expected)

    def test_algebraic_conversion(self):
        self.board = board.Board(None, None, None)
        # Move a pawn
        move = self.board.short_algebraic_to_long_algebraic("a3")
        state = self.board.long_algebraic_to_boardstate(move)
        expected = np.asarray([[-2, -3, -4, -5, -6, -4, -3, -2],
                                [-1, -1, -1, -1, -1, -1, -1, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [1, 0, 0, 0, 0, 0, 0, 0],
                                [0, 1, 1, 1, 1, 1, 1, 1],
                                [2, 3, 4, 5, 6, 4, 3, 2]])
        np.testing.assert_array_equal(state, expected)

        # Move a pawn 2
        move = self.board.short_algebraic_to_long_algebraic("a4")
        state = self.board.long_algebraic_to_boardstate(move)
        expected = np.asarray([[-2, -3, -4, -5, -6, -4, -3, -2],
                                [-1, -1, -1, -1, -1, -1, -1, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [1, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 1, 1, 1, 1, 1, 1, 1],
                                [2, 3, 4, 5, 6, 4, 3, 2]])
        np.testing.assert_array_equal(state, expected)

        # Move a knight
        move = self.board.short_algebraic_to_long_algebraic("Nc3")
        state = self.board.long_algebraic_to_boardstate(move)
        expected = np.asarray([[-2, -3, -4, -5, -6, -4, -3, -2],
                                [-1, -1, -1, -1, -1, -1, -1, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 3, 0, 0, 0, 0, 0],
                                [1, 1, 1, 1, 1, 1, 1, 1],
                                [2, 0, 4, 5, 6, 4, 3, 2]])
        np.testing.assert_array_equal(state, expected)

        # Rook with partial file disambiguation
        complicated = np.asarray([[-2, -3, -4, -5, -6, -4, -3, -2],
                                [-1, -1, -1, -1, -1, -1, -1, -1],
                                [0, 0, 2, 0, 0, 0, 0, 2],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [1, 1, 1, 1, 1, 1, 1, 1],
                                [2, 3, 4, 5, 6, 4, 3, 2]])
        self.board = board.Board(complicated, None, None)
        move = self.board.short_algebraic_to_long_algebraic("Rcf6")
        state = self.board.long_algebraic_to_boardstate(move)
        expected = np.asarray([[-2, -3, -4, -5, -6, -4, -3, -2],
                                [-1, -1, -1, -1, -1, -1, -1, -1],
                                [0, 0, 0, 0, 0, 2, 0, 2],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [1, 1, 1, 1, 1, 1, 1, 1],
                                [2, 3, 4, 5, 6, 4, 3, 2]])
        np.testing.assert_array_equal(state, expected)

        # Queen with partial rank disambiguation and black to move
        complicated = np.asarray([[-2, -3, -4, 0, -6, -4, -3, -2],
                                [-1, -5, -1, -1, -1, -1, -1, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, -5, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [1, 1, 1, 1, 1, 1, 1, 1],
                                [2, 3, 4, 5, 6, 4, 3, 2]])
        self.board = board.Board(complicated, None, to_move = board.Color.BLACK)
        move = self.board.short_algebraic_to_long_algebraic("Q4f4")
        state = self.board.long_algebraic_to_boardstate(move)
        expected = np.asarray([[-2, -3, -4, 0, -6, -4, -3, -2],
                                [-1, -5, -1, -1, -1, -1, -1, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, -5, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [1, 1, 1, 1, 1, 1, 1, 1],
                                [2, 3, 4, 5, 6, 4, 3, 2]])
        np.testing.assert_array_equal(state, expected)

        # Three bishops with full disambiguation and black to move
        complicated = np.asarray([[-2, -3, -4, 0, -6, -4, -3, -2],
                                [-1, -4, -1, -1, -1, -1, -4, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, -4, 0, 0, 0, 0, 0],
                                [1, 1, 1, 1, 1, 1, 1, 1],
                                [2, 3, 4, 5, 6, 4, 3, 2]])
        self.board = board.Board(complicated, None, to_move = board.Color.BLACK)
        move = self.board.short_algebraic_to_long_algebraic("Bg7d4")
        state = self.board.long_algebraic_to_boardstate(move)
        expected = np.asarray([[-2, -3, -4, 0, -6, -4, -3, -2],
                                [-1, -4, -1, -1, -1, -1, 0, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, -4, 0, 0, 0, 0],
                                [0, 0, -4, 0, 0, 0, 0, 0],
                                [1, 1, 1, 1, 1, 1, 1, 1],
                                [2, 3, 4, 5, 6, 4, 3, 2]])
        np.testing.assert_array_equal(state, expected)

        # Move a king
        complicated = np.asarray([[-2, -3, -4, 0, -6, -4, -3, -2],
                                [-1, -4, -1, -1, -1, -1, -4, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 6, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, -4, 0, 0, 0, 0, 0],
                                [1, 1, 1, 1, 1, 1, 1, 1],
                                [2, 3, 4, 5, 0, 4, 3, 2]])
        self.board = board.Board(complicated, None, None)
        move = self.board.short_algebraic_to_long_algebraic("Kc5")
        state = self.board.long_algebraic_to_boardstate(move)
        expected = np.asarray([[-2, -3, -4, 0, -6, -4, -3, -2],
                                [-1, -4, -1, -1, -1, -1, -4, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 6, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, -4, 0, 0, 0, 0, 0],
                                [1, 1, 1, 1, 1, 1, 1, 1],
                                [2, 3, 4, 5, 0, 4, 3, 2]])
        np.testing.assert_array_equal(state, expected)

        # Kingside castling
        complicated = np.asarray([[-2, -3, -4, 0, -6, -4, -3, -2],
                                [-1, -4, -1, -1, -1, -1, -4, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, -4, 0, 0, 0, 0, 0],
                                [1, 1, 1, 1, 1, 1, 1, 1],
                                [2, 3, 4, 5, 6, 0, 0, 2]])
        self.board = board.Board(complicated, None, None)
        move = self.board.short_algebraic_to_long_algebraic("O-O")
        state = self.board.castle_algebraic_to_boardstate(move)
        expected = np.asarray([[-2, -3, -4, 0, -6, -4, -3, -2],
                                [-1, -4, -1, -1, -1, -1, -4, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, -4, 0, 0, 0, 0, 0],
                                [1, 1, 1, 1, 1, 1, 1, 1],
                                [2, 3, 4, 5, 0, 2, 6, 0]])
        np.testing.assert_array_equal(state, expected)

        # Queenside castling
        complicated = np.asarray([[-2, -3, -4, 0, -6, -4, -3, -2],
                                [-1, -4, -1, -1, -1, -1, -4, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, -4, 0, 0, 0, 0, 0],
                                [1, 1, 1, 1, 1, 1, 1, 1],
                                [2, 0, 0, 0, 6, 0, 0, 2]])
        self.board = board.Board(complicated, None, None)
        move = self.board.short_algebraic_to_long_algebraic("O-O-O")
        state = self.board.castle_algebraic_to_boardstate(move)
        expected = np.asarray([[-2, -3, -4, 0, -6, -4, -3, -2],
                                [-1, -4, -1, -1, -1, -1, -4, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, -4, 0, 0, 0, 0, 0],
                                [1, 1, 1, 1, 1, 1, 1, 1],
                                [0, 0, 6, 2, 0, 0, 0, 2]])
        np.testing.assert_array_equal(state, expected)

        # Rook takes a piece
        complicated = np.asarray([[-2, -3, -4, 0, -6, -4, -3, -2],
                                [-1, -4, -1, -1, -1, -1, -4, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, -4, 0, 0, 0, 0, 0],
                                [2, 1, 1, 1, 1, 1, 1, 1],
                                [2, 0, 0, 0, 6, 0, 0, 2]])
        self.board = board.Board(complicated, None, None)
        move = self.board.short_algebraic_to_long_algebraic("Rxa7")
        state = self.board.long_algebraic_to_boardstate(move)
        expected = np.asarray([[-2, -3, -4, 0, -6, -4, -3, -2],
                                [2, -4, -1, -1, -1, -1, -4, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, -4, 0, 0, 0, 0, 0],
                                [0, 1, 1, 1, 1, 1, 1, 1],
                                [2, 0, 0, 0, 6, 0, 0, 2]])
        np.testing.assert_array_equal(state, expected)

        # Pawn takes a piece
        complicated = np.asarray([[-2, -3, -4, 0, -6, -4, -3, -2],
                                [-1, -4, -1, -1, -1, -1, -4, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, -4, 0, 0, 0, 0, 0],
                                [1, 1, 1, 1, 1, 1, 1, 1],
                                [2, 3, 4, 5, 6, 4, 3, 2]])
        self.board = board.Board(complicated, None, None)
        move = self.board.short_algebraic_to_long_algebraic("dxc3")
        state = self.board.long_algebraic_to_boardstate(move)
        expected = np.asarray([[-2, -3, -4, 0, -6, -4, -3, -2],
                                [-1, -4, -1, -1, -1, -1, -4, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 1, 0, 0, 0, 0, 0],
                                [1, 1, 1, 0, 1, 1, 1, 1],
                                [2, 3, 4, 5, 6, 4, 3, 2]])
        np.testing.assert_array_equal(state, expected)

        # Pawn promotes to Queen
        complicated = np.asarray([[-2, -3, -4, 0, -6, -4, -3, -2],
                                [-1, -4, -1, 1, -1, -1, -4, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, -4, 0, 0, 0, 0, 0],
                                [1, 1, 1, 1, 1, 1, 1, 1],
                                [2, 3, 4, 5, 6, 4, 3, 2]])
        self.board = board.Board(complicated, None, None)
        move = self.board.short_algebraic_to_long_algebraic("d8=Q")
        state = self.board.long_algebraic_to_boardstate(move)
        expected = np.asarray([[-2, -3, -4, 5, -6, -4, -3, -2],
                                [-1, -4, -1, 0, -1, -1, -4, -1],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, -4, 0, 0, 0, 0, 0],
                                [1, 1, 1, 1, 1, 1, 1, 1],
                                [2, 3, 4, 5, 6, 4, 3, 2]])
        np.testing.assert_array_equal(state, expected)

        # Total nonsense
        #self.board = board.Board(None, None, None)
        #self.assertRaises(ValueError, self.board.algebraic_to_boardstate, "I love you")

    def test_is_in_check(self):
        # Bishop in check, from both white and black
        state = np.asarray([[-2, -3, -4, 2, -6, -4, -3, -2],
                            [-1, -4, -1, 0, -1, -1, -4, -1],
                            [0, 0, 0, 0, 0, 0, 0, 0],
                            [0, 0, 0, 0, 0, 0, 0, 0],
                            [0, 0, 0, 6, 0, 0, 0, 0],
                            [0, 0, -4, 0, 0, 0, 0, 0],
                            [1, 1, 1, 1, 1, 1, 1, 1],
                            [2, 3, 4, 5, 0, 4, 3, 2]])
        self.assertTrue(board.is_in_check(state, board.Color.WHITE))

        state = np.asarray([[-2, -3, -4, 2, -6, -4, -3, -2],
                            [-1, -4, -1, 0, -1, -1, -4, -1],
                            [0, 0, 0, 0, 0, 0, 0, 0],
                            [0, 0, 0, 0, 6, 0, 0, 0],
                            [0, 0, 0, 0, 0, 0, 0, 0],
                            [0, 0, -4, 0, 0, 0, 0, 0],
                            [1, 1, 1, 1, 1, 1, 1, 1],
                            [2, 3, 4, 5, 0, 4, 3, 2]]) * -1

        self.assertTrue(board.is_in_check(state, board.Color.BLACK))

        # Rook
        state = np.asarray([[-2, -3, -4, 2, -6, -4, -3, -2],
                            [-1, 0, -1, 0, -1, -1, -4, -1],
                            [0, 0, 0, -2, 0, 0, 0, 0],
                            [0, 0, 0, 0, 0, 0, 0, 0],
                            [0, -2, 4, 6, 0, 0, 0, 0],
                            [0, 0, 0, 0, 0, 0, 0, 0],
                            [1, 1, 1, 1, 1, 1, 1, 1],
                            [2, 3, 4, 5, 0, 4, 3, 2]])
        self.assertTrue(board.is_in_check(state, board.Color.WHITE))

        # Knight
        state = np.asarray([[-2, -3, -4, 2, -6, -4, -3, -2],
                            [-1, 0, -1, 0, -1, -1, -4, -1],
                            [0, 0, 0, 0, -3, 0, 0, 0],
                            [0, 0, 0, 0, 0, 0, 0, 0],
                            [0, -2, 4, 6, 0, 0, 0, 0],
                            [0, 0, 0, 0, 0, 0, 0, 0],
                            [1, 1, 1, 1, 1, 1, 1, 1],
                            [2, 3, 4, 5, 0, 4, 3, 2]]) * -1
        self.assertTrue(board.is_in_check(state, board.Color.BLACK))

        # Knight different direction
        state = np.asarray([[-2, -3, -4, 2, -6, -4, -3, -2],
                            [-1, 0, -1, 0, -1, -1, -4, -1],
                            [0, 0, 0, 0, 0, 0, 0, 0],
                            [0, 0, 0, 0, 0, -3, 0, 0],
                            [0, -2, 4, 6, 0, 0, 0, 0],
                            [0, 0, 0, 0, 0, 0, 0, 0],
                            [1, 1, 1, 1, 1, 1, 1, 1],
                            [2, 3, 4, 5, 0, 4, 3, 2]]) * -1
        self.assertTrue(board.is_in_check(state, board.Color.BLACK))

        # Pawn
        state = np.asarray([[-2, -3, -4, 2, -6, -4, -3, -2],
                            [-1, 0, -1, 0, -1, -1, -4, -1],
                            [0, 6, 0, 0, 0, 0, 0, 0],
                            [0, 0, 0, 0, 0, -3, 0, 0],
                            [0, 0, 4, 0, 0, 0, 0, 0],
                            [0, 0, 0, 0, 0, 0, 0, 0],
                            [1, 1, 1, 1, 1, 1, 1, 1],
                            [2, 3, 4, 5, 0, 4, 3, 2]])
        self.assertTrue(board.is_in_check(state, board.Color.WHITE))

        # Pawn
        state = np.asarray([[-2, -3, -4, 2, -6, -4, -3, -2],
                            [0, 0, -1, 0, -1, -1, -4, -1],
                            [0, 6, 0, 0, 0, 0, 0, 0],
                            [0, 0, 0, 0, 0, -3, 0, 0],
                            [0, 0, 4, 0, 0, 0, 0, 0],
                            [0, 0, 0, 0, 0, 0, 0, 0],
                            [1, 1, 1, 1, 1, 1, 1, 1],
                            [2, 3, 4, 5, 0, 4, 3, 2]])
        self.assertTrue(board.is_in_check(state, board.Color.WHITE))

        # Pawn Black
        state = np.asarray([[-2, -3, -4, 2, 6, -4, -3, -2],
                            [-1, 0, -1, 0, -1, -1, -4, -1],
                            [0, 0, 0, 0, 0, 0, 0, 0],
                            [0, 0, 0, 0, 0, -3, 0, 0],
                            [0, 0, 4, 0, 0, 0, 0, 0],
                            [0, 0, 0, 0, -6, 0, 0, 0],
                            [1, 1, 1, 1, 1, 1, 1, 1],
                            [2, 3, 4, 5, 0, 4, 3, 2]])
        self.assertTrue(board.is_in_check(state, board.Color.BLACK))

        # Bar something really really busted that should be sufficient.
        # It wasn't.


    def test_all_moves(self):
        self.board = board.Board(None, None, None)
        moves = set(self.board.generate_moves(board.Color.WHITE))
        expected = set(["Na3", "Nc3", "Nf3", "Nh3", "a3", "a4", "b3", "b4",
                        "c3", "c4", "d3", "d4", "e3", "e4", "f3", "f4", "g3",
                        "g4", "h3", "h4"])
        self.assertSetEqual(moves, expected)

        self.board = board.Board(None, None, to_move=board.Color.BLACK)
        moves = set(self.board.generate_moves(board.Color.BLACK))
        expected = set(["Na6", "Nc6", "Nf6", "Nh6", "a5", "a6", "b5", "b6",
                        "c5", "c6", "d5", "d6", "e5", "e6", "f5", "f6", "g5",
                        "g6", "h5", "h6"])
        self.assertSetEqual(moves, expected)

        # A puzzle from lichess. Note that the pawn on g7 shouldn't be able to
        # move! It puts you in check!
        # The checkmate sequence is 34 ... Qh4 35 Kg1 Ne2#
        self.board = board.load_fen("5r1k/6pp/p1Q5/2p1B3/5n2/6q1/PPP3P1/5R1K b - - 0 34")
        moves = set(self.board.generate_moves(board.Color.BLACK))
        expected = set(["h5", "h6", "a5", "c4", "Ra8", "Rb8", "Rc8",
                        "Rd8", "Re8", "Rg8", "Rf7", "Rf6", "Rf5", "Qa3", "Qb3",
                        "Qc3", "Qd3", "Qe3", "Qf3", "Qh3", "Qxg2", "Qg4", "Qg5",
                        "Qg6", "Qh4", "Qh2", "Qe1", "Qf2", "Kg8", "Nd5", "Nh5",
                        "Ne6", "Ng6", "Ne2", "Nxg2", "Nh3", "Nd3"])
        self.assertSetEqual(moves, expected)


    def test_checkmate(self):
        # Another puzzle from Lichess, this one already solved.
        self.board = board.load_fen("r6k/1bp2Bp1/p5p1/1p6/3qn2Q/7P/P4PP1/2R3K1 b - - 1 25")
        moves = set(self.board.generate_moves(board.Color.BLACK))
        expected = set([])
        self.assertSetEqual(moves, expected)
        #self.assertTrue(self.board.status == board.Status.WHITE_VICTORY)

        # Another puzzle, checking Checkmate for white
        self.board = board.load_fen("5rk1/8/7p/3R2p1/3P4/8/6PP/4q1K1 w - - 0 37")
        moves = set(self.board.generate_moves(board.Color.WHITE))
        expected = set([])
        self.assertSetEqual(moves, expected)
        #self.assertTrue(self.board.status == board.Status.BLACK_VICTORY)


    def test_loading_pgn(self):
        # Tests on the immortal game, because why not?
        self.board = board.load_pgn("anderssen_kieseritzky_1851.pgn", "tests/pgns")
        expected = np.asarray([[-2, 0, -4, -6, 0, 0, 0, -2],
                                [-1, 0, 0, -1, 4, -1, 3, -1],
                                [-3, 0, 0, 0, 0, -3, 0, 0],
                                [0, -1, 0, 3, 1, 0, 0, 1],
                                [0, 0, 0, 0, 0, 0, 1, 0],
                                [0, 0, 0, 1, 0, 0, 0, 0],
                                [1, 0, 1, 0, 6, 0, 0, 0],
                                [-5, 0, 0, 0, 0, 0, -4, 0]])
        np.testing.assert_array_equal(self.board.current_state, expected)
        self.assertTrue(self.board.status == board.Status.WHITE_VICTORY)

        expected_tags = {'Event': 'London', 'Site': 'London ENG',
                        'Date': '1851.06.21', 'EventDate': '?', 'Round': '?',
                        'Result': '1-0', 'White': 'Adolf Anderssen',
                        'Black': 'Lionel Adalbert Bagration Felix Kieseritzky',
                        'ECO': 'C33', 'WhiteElo': '?', 'BlackElo': '?',
                        'PlyCount': '45'}

        self.assertDictEqual(self.board.headers, expected_tags)


    def test_saving_pgn(self):
        self.board = board.load_pgn("anderssen_kieseritzky_1851.pgn", "tests/pgns")

        name = board.save_pgn(self.board)
        self.board2 = board.load_pgn(name, "results")

        np.testing.assert_array_equal(self.board.current_state, self.board2.current_state)
        self.assertDictEqual(self.board.headers, self.board2.headers)

        self.board = board.Board(None, None, None)
        name = board.save_pgn(self.board)

        self.board2 = board.load_pgn(name, "results")
        np.testing.assert_array_equal(self.board.current_state, self.board2.current_state)
        self.assertDictEqual(self.board.headers, self.board2.headers)


    def test_move_disambiguation(self):
        # This should remove the knight moves from the h file as they
        # put the king in check.
        # Found in a random move vs random move game.
        crash = np.asarray([[0, -6, 0, 0, 0, -4, 0, 0],
                            [-2, 0, 0, 0, 0, -1, 0, -2],
                            [0, -3, 0, 1, 0, -3, 0, 0],
                            [0, 0, 0, 1, 0, 1, 5, 3],
                            [-1, -1, 0, 0, 0, 0, 0, 0],
                            [0, 0, 1, 0, 1, 0, 0, 0],
                            [1, 0, 0, 0, 3, 0, 1, 0],
                            [2, 0, 4, 0, 0, 0, 0, 6]])

        castle_dict = {"WQR" : False, "WKR" : False, "BQR" : False, "BKR" : False}
        self.board = board.Board(crash, castle_dict, None)
        moves = set(self.board.generate_moves(board.Color.WHITE))
        expected = set(['d7', 'c4', 'cxb4', 'e4', 'a3', 'g3', 'g4', 'Ng1',
                        'Ne2g3', 'Ne2f4', 'Nd4', 'Rb1', 'Bb2', 'Ba3', 'Bd2',
                        'Qxf6', 'Qh6', 'Qh4', 'Qf4', 'Qg6', 'Qg7', 'Qg8',
                        'Qg4', 'Qg3', 'Kh2', 'Kg1'])

        self.assertSetEqual(moves, expected)


    #def test_castles_upon_rook_removal(self):
        #self.board = board.load_pgn("test5vsChrysaora 0.0012019-03-30.pgn")
        #expected = {'WQR': False, 'WKR': False, 'BQR': False, 'BKR': False}
        #self.assertDictEqual(self.board.castle_dict, expected)


    def test_en_passant(self):
        self.board = board.load_pgn("test5000vsChrysaora 0.0012019-03-29.pgn", "tests/pgns")
        # En passant move.
        self.board.make_move("d6")

        expected = np.asarray([[0, -3, -4, -6, 0, 0, 0, 0],
                             [0, -1, 0, 0, 0, 1, 0, 1],
                             [-2, 1, -1, 1, 0, 1, 0, 0],
                             [0, 0, 0, 0, 0, 1, 0, 2],
                             [-1, 0, 1, 0, 0, 4, -1, 0],
                             [0, 0, 0, 0, 0, 0, 0, 0],
                             [0, 0, 0, 0, 0, 0, 0, 0],
                             [2, 3, 0, 5, 6, 4, 3, 0]])

        np.testing.assert_array_equal(expected, self.board.current_state)


    def test_castling_through_check(self):
        # Kingside
        complicated = np.asarray([[0, -3, -4, -6, 0, 0, 0, 0],
                             [0, -1, 0, 0, 0, 1, 0, 1],
                             [-2, 1, -1, 1, 0, 1, 0, 0],
                             [0, 0, 0, 0, 0, 1, 0, 2],
                             [-1, 0, 1, 0, 0, -2, -1, 0],
                             [0, 0, 0, 0, 0, 0, 0, 0],
                             [0, 0, 0, 0, 0, 0, 0, 0],
                             [2, 3, 0, 5, 6, 0, 0, 2]])

        self.board = board.Board(complicated, None, None, None)

        self.assertFalse("O-O" in self.board.generate_moves(board.Color.WHITE))

        # Queenside
        complicated = np.asarray([[0, -3, -4, -6, 0, 0, 0, 0],
                             [0, -1, 0, 0, 0, 1, 0, 1],
                             [-2, 1, -1, 1, 0, 1, 0, 0],
                             [0, 0, 0, 0, 0, 1, 0, 2],
                             [-1, 0, 1, -2, 0, 0, -1, 0],
                             [0, 0, 0, 0, 0, 0, 0, 0],
                             [0, 0, 0, 0, 0, 0, 0, 0],
                             [2, 0, 0, 0, 6, 5, 0, 2]])

        self.board = board.Board(complicated, None, None, None)
        self.assertFalse("O-O-O" in self.board.generate_moves(board.Color.WHITE))


    def test_castling_out_of_check(self):
        # Tests check by a rook straight
        straight = np.asarray([[0, -3, -4, -6, 0, 0, 0, 0],
                             [0, -1, 0, 0, 0, 1, 0, 1],
                             [-2, 1, -1, 1, 0, 1, 0, 0],
                             [0, 0, 0, 0, 0, 1, 0, 2],
                             [-1, 0, 1, 0, -2, 0, -1, 0],
                             [0, 0, 0, 0, 0, 0, 0, 0],
                             [0, 0, 0, 0, 0, 0, 0, 0],
                             [2, 0, 0, 0, 6, 0, 0, 2]])

        self.board = board.Board(straight, None, None, None)
        moves = self.board.generate_moves(board.Color.WHITE)
        self.assertFalse("O-O-O" in moves)
        self.assertFalse("O-O" in moves)

        with self.assertRaises(ValueError):
            self.board.make_move("O-O")
            self.board.make_move("O-O-O")

        # Tests check diagonally.
        diag = np.asarray([[0, -3, -4, -6, 0, 0, 0, 0],
                             [0, -1, 0, 0, 0, 1, 0, 1],
                             [-2, 1, -1, 1, 0, 1, 0, 0],
                             [0, 0, 0, 0, 0, 1, 0, 2],
                             [-1, 0, 1, 0, 0, 0, -1, 0],
                             [0, 0, 0, 0, 0, 0, -4, 0],
                             [0, 0, 0, 0, 0, 0, 0, 0],
                             [2, 0, 0, 0, 6, 0, 0, 2]])

        self.board = board.Board(diag, None, None, None)
        moves = self.board.generate_moves(board.Color.WHITE)
        self.assertFalse("O-O-O" in moves)
        self.assertFalse("O-O" in moves)

        with self.assertRaises(ValueError):
            self.board.make_move("O-O")
            self.board.make_move("O-O-O")


    def test_en_passant_black(self):
        self.board = board.load_pgn("Komodo 2227.00vsAndscacs 095 2019-01-09.pgn", "tests/pgns")

        expected = np.asarray([[0, 0, 0, 0, 0, 0, 0, 0],
                                [-1, 0, 0, 0, 0, 0, -4, 0],
                                [1, -1, 0, -6, 0, 0, 1, 0],
                                [0, 6, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 4, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0]])

        np.testing.assert_array_equal(expected, self.board.current_state)


    def test_disambiguating_moving_in_check(self):
        # This tests disambiguating moving pieces, when one of them would
        # leave you in check if you moved it, and which piece is not
        # disambiguated for you. It should correctly find the second
        # rook to move instead of the first.
        self.board = board.load_pgn( "Ethereal 11.14vsLCZero v20rc2-32194 2018-12-31.pgn", "tests/pgns")

        expected = np.asarray([[ 0, 0, 0, 0, 0, 0, -2, 0],
                               [ 0, 0, 0, 0, 0, 0, -6, 0],
                               [ 0, 0, 0, 0, 0, 0, -2, 0],
                               [ 1, 0, 0, 0, 1, 0, 0, 0],
                               [ 0, 0, 0, 0, 0, 0, 0, 0],
                               [ 0, 0, 0, 0, 0, 0, 0, 5],
                               [ 1, 0, 0, 0, 0, 0, 0, 0],
                               [ 0, 0, 0, 0, 0, 0, 0, 6]])
        np.testing.assert_array_equal(expected, self.board.current_state)

    def test_promoting_to_pawn(self):
        complicated = np.asarray([[0, 0, 0, 0, 0, 0, 0, 0],
                                [-1, 1, 0, 0, 0, 0, -4, 0],
                                [1, -1, 0, -6, 0, 0, 1, 0],
                                [0, 6, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0],
                                [0, 0, 4, 0, 0, 0, 0, 0],
                                [0, 0, 0, 0, 0, 0, 0, 0]])

        self.board = board.Board(complicated, None, None, None)
        with self.assertRaises(ValueError):
            self.board.make_move("b8=P")

    def test_en_passant_different_pawn(self):
        # Tests en_passant where a different pawn is occupying the space "two
        # back" from the one trying to take. This tests my en passant checking
        # method, need to ensure that it's the same pawn that is in the space
        # two spaces back in the previous state and not a different one.
        self.board = board.load_pgn("KomodoMCTS 2221.00vsLCZero v19.1-11248 2018-12-15.pgn", "tests/pgns")

        expected = np.asarray([[ 0, 0, 0, 0, 0, 0, 0, 0],
                               [ 0, 0, 0, 0, 0, 0, 0, 0],
                               [ 0, 0, 0, 0, 0, 0, 0, 0],
                               [ 0, 0, 0, 0, 0, 0, 0, 0],
                               [ 0, 0, 0, 0, 0, 0, 0, 0],
                               [ 0, 0, -6, 0, 6, 0, 0, 0],
                               [-1, 0, 0, -1, 0, -1, 0, 0],
                               [ 0, 0, 0, 2, 0, 0, 0, 0]])

        np.testing.assert_array_equal(expected, self.board.current_state)


if __name__ == "__main__":
    unittest.main()
    #MoveGenerationTestCase().test_something()
