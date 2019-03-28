import random

import numpy as np

import board


class Engine():

    def __init__(self, color, new_board):
        self.color = color
        self.board = new_board

    # In the future this will handle everyting, evaluating, then searching
    # and so on and so forth until it finds a good move.
    # For now I'm just going to return a random move lol.
    def find_move(self):
        moves = self.board.generate_moves(self.color)

        move = random.choice(moves)
        return move
