import random
import os
import logging
import copy
import time

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
import torchvision.transforms as transforms

import board
import uci
from board import Color


# Original chess network
# More closely resembles an image classifier than SkipNet
class ChessNet(nn.Module):

    def __init__(self):
        super(ChessNet, self).__init__()
        # 1 input channel, 64 output channels, 5x5 kernel
        # First layer, pools to 4x4
        self.conv1 = nn.Conv2d(1, 64, kernel_size=5, padding=2)
        self.pool1 = nn.MaxPool2d(2, 2)

        # Second layer, pools to 2x2
        self.conv2 = nn.Conv2d(64, 128, kernel_size=3, padding=1)
        self.pool2 = nn.MaxPool2d(2, 2)

        # Third layer, pools to 1x1
        self.conv3 = nn.Conv2d(128, 256, kernel_size=3, padding=1)
        self.pool3 = nn.MaxPool2d(2, 2)

        # Linear operations
        self.fc1 = nn.Linear(256, 128)
        self.fc2 = nn.Linear(128, 64)
        self.fc3 = nn.Linear(64, 1)
        # 3 outputs, 2 = White win, 1 = draw, 0 = black win

    def forward(self, x):

        x = self.pool1(F.relu(self.conv1(x)))
        x = self.pool2(F.relu(self.conv2(x)))
        x = self.pool3(F.relu(self.conv3(x)))

        # view essentially resizes a tensor, -1 means it'll infer that dimension
        x = x.view(-1, 256)
        x = F.relu(self.fc1(x))
        x = F.relu(self.fc2(x))
        x = self.fc3(x)
        return x


class SkipNet(nn.Module):

    def __init__(self):
        super(SkipNet, self).__init__()
        # 1 input channel, 64 output channels, 3x3 kernel, no padding.
        # This leads to a 64x6x6 output
        # Pools to 3x3
        self.conv1 = nn.Conv2d(1, 64, kernel_size=3)
        self.pool1 = nn.MaxPool2d(2, 2)

        # Batch normalization to speed training.
        self.norm = nn.BatchNorm2d(64)

        # Skip layer definitions, first uses 8x8 kernel to reduce the 8x8
        # board to a 1x1 with 128 channels.
        # Second uses a 3x3 kernel to go from 64x3x3 to 128x1x1
        self.skip1 = nn.Conv2d(1, 128, kernel_size=8)
        self.skip2 = nn.Conv2d(64, 128, kernel_size=3)

        # Second layer, convolution with kernel size 2x2 reduce 3x3 to 2x2.
        # Then gets pooled to 1x1.
        self.conv2 = nn.Conv2d(64, 128, kernel_size=2)
        self.pool2 = nn.MaxPool2d(2, 2)

        # Final layer with a 1x1 kernel. This layer will be joined with the
        # two skip layers later.
        self.conv3 = nn.Conv2d(128, 128, kernel_size=1)

        # Linear operations
        self.fc1 = nn.Linear(128*3, 128)
        self.fc2 = nn.Linear(128, 64)
        self.fc3 = nn.Linear(64, 3)

    def forward(self, x):

        # Generate skip layer one, then run through layer 1.
        x1 = self.skip1(x)
        x = self.conv1(x)
        x = self.norm(self.pool1(x))

        # Generate skip layer two then run through layer 2
        x2 = self.skip2(x)
        x = self.pool2(self.conv2(x))

        # Layer 3
        x = self.conv3(x)

        # Initially I concatenated x with x1 and x2, but by accident I later
        # concatted x1 and x2 with the sum. It worked better so I left it.
        xcat = x + x1 + x2
        xcat = torch.cat((xcat, x1, x2), 1)

        # Resize to the right shape for linear.
        xcat = xcat.view(-1, 128*3)

        # Linear layers.
        xcat = F.relu(self.fc1(xcat))
        xcat = F.relu(self.fc2(xcat))
        xcat = self.fc3(xcat)
        return xcat


class Engine():

    def __init__(self, new_board, impl="net"):
        self.board = new_board

        # Time dictionary for time management code.
        self.time_params = {"wtime" : None, "btime" : None, "winc" : None,
                            "binc" : None}

        self.brain = SkipNet()

        net = "SkipNet-89.pt"
        weights = os.path.join(os.path.dirname(__file__), net)
        self.brain.load_state_dict(torch.load(weights, map_location="cpu"))
        logging.debug("Loaded: " + net)

        # Sets the network to evaluation mode.
        # There's a batch normalization layer which runs differently in
        # training and evaluation.
        self.brain.eval()

        # Keeping that random implemenation around for testing.
        self.impl = impl

        self.max_depth = 3
        self.compute = True


    def find_move(self):
        # Shortcuts for weird implementations.
        if self.impl == "random":
            return self.random_move()
        elif self.impl == "greedy":
            return self.greedy_move()

        move, val = self.minimax_search(self.board, depth=self.max_depth)
        return move


    # Returns evaluations of the given board states.
    def evaluate_moves(self, board_states, color):
        run_states = []
        vals = np.zeros(len(board_states))

        # Transformation object, converts to a tensor then normalizes.
        normalize = transforms.Normalize(mean=[0.485], std=[0.229])
        trans = transforms.Compose([transforms.ToTensor()])#, normalize])

        # Goes through each moves, converts it to a long move, and then
        # gets the board state for that long algebraic.
        for i, s in enumerate(board_states):
            # Slight addition of time by checking if each state is a checkmate
            # However if it is we do not need to run it through the network,
            # returning the time lost as time saved there.

            mate = board.is_checkmate(s, color)

            # This will get multiplied by 1 or -1 depending on what color this
            # terminal node is.
            if mate:
                vals[i] = 1
            else:
                # Once we have the state, we run the same conversions on it that
                # were run when the network was trained.
                s = s.reshape((8, 8, 1))
                s = trans(s)
                s.resize_((1, 1, 8, 8))
                run_states.append(s)

        run_states = torch.cat(run_states, 0)

        # Runs the boards through the network, and then gets their label.
        # Remember:
        # 0 = draw, 1 = black win, 2 = white win.
        outputs = self.brain(run_states.float())
        outputs = F.softmax(outputs, dim=1)
        _, label = torch.max(outputs.data, 1)

        # Shifts the outputs to numpy ndarrays.
        outs = outputs.data.numpy()
        labels = label.numpy()

        color = self.board.to_move
        weights = [0, 0, 1] if color == board.Color.WHITE else [0, 1, 0]
        net_vals = np.dot(outs[...,:3], weights)

        # This places the network evaluations into the vals array where the
        # 0s were left for them.
        np.place(vals, vals==0, net_vals)

        return vals


    def minimax_search(self, search_board, alpha=-10, beta=10, depth=1, color=None):
        if color is None:
            color = self.board.to_move

        # If we recieve the stop command don't go any deeper just return our
        # best move.
        cmd = uci.receive_command()
        if cmd == "stop":
            self.compute = False

        # The decision between if we are doing an alpha cutoff or a beta cutoff.
        cutoff = alpha if color == self.board.to_move else beta
        cutoff_type = "alpha" if color == self.board.to_move else "beta"

        # Generate the moves first to reduce code duplication.
        moves = np.asarray(search_board.generate_moves(search_board.to_move))
        # If there are no moves then someone either got checkmated or
        # they got stalemated.
        if len(moves) == 0:
            check = board.is_in_check(search_board.current_state, search_board.to_move)
            # In this situation we were the ones to get checkmated
            # (or stalemated) so set the eval to 0 cuz we really don't
            # want this.
            if search_board.to_move == self.board.to_move:
                return ("", 0)
            # If it's not us to move, but we found a stalemate that means we
            # stalemated the other person and we don't want that either.
            elif not check:
                return ("", 0)
            # Otherwise we found a checkmate and we really want this
            # Negative one because when it gets bumped up to the next depth
            # it gets negated due to negamax.
            # Multiply by depths so that closer checkmates are preferred.
            else:
                return ("", depth)

        # Strips the algebraic moves and states out
        alg = moves[..., 0]
        states = moves[..., 1]
        if depth == 1:
            val = -10 if color == self.board.to_move else 10
            best_move = moves[0][0]

            run_color = Color.WHITE if color == Color.BLACK else Color.BLACK
            mult = 1 if color == self.board.to_move else -1

            for i in range(0, len(states), 5):

                net_vals = self.evaluate_moves(states[i: i+5], run_color)
                net_vals *= mult

                for j, v in enumerate(net_vals):
                    # Updates alpha or beta variable depending on which cutoff
                    # we are using this iteration.
                    if cutoff_type == "alpha":
                        if val < v:
                            best_move = moves[j+i][0]
                            val = v
                        alpha = np.amax([alpha, val])
                    else:
                        if val > v:
                            best_move = moves[j+i][0]
                            val = v
                        beta = np.amin([beta, val])

                    # Once alpha exceeds beta, i.e. once the minimum score that
                    # the engine will receieve on a node (alpha) exceeds the
                    # maximum score that the engine predicts for the opponent
                    # (beta)
                    if alpha >= beta:
                        return (best_move, val)

            return (best_move, val)

        else:
            val = -10 if color == self.board.to_move else 10
            best_move = moves[0][0]
            for m in moves:
                new_board = self.bypass_make_move(search_board, m[0], m[1])

                _, net_val = self.minimax_search(new_board, alpha, beta, depth-1, new_board.to_move)

                # Updates alpha or beta variable depending on which cutoff
                # we are using this iteration.
                if cutoff_type == "alpha":
                    if val < net_val:
                        best_move = m[0]
                        val = net_val
                    alpha = np.amax([alpha, val])
                else:
                    if val > net_val:
                        best_move = m[0]
                        val = net_val
                    beta = np.amin([beta, val])

                if not self.compute:
                    break

                # Once alpha exceeds beta, i.e. once the minimum score that
                # the engine will receieve on a node (alpha) exceeds the
                # maximum score that the engine predicts for the opponent (beta)
                if alpha >= beta:
                    break

            return (best_move, val)


    # Bypasses making a move using board.make_move by updating the castle
    # dict manually and then setting the board state to state.
    def bypass_make_move(self, old_board, move, state):
        to_move = Color.BLACK if old_board.to_move == Color.WHITE else Color.WHITE

        # Copy the old castle dict and update it.
        new_castle = copy.copy(old_board.castle_dict)

        castle_move = "O-O" in move or "0-0" in move

        # The following code is designed to update the castle dict.
        piece = "P"
        for i, c in enumerate(move):
            # If we have an = then this is the piece the pawn promotes to.
            # Pawns can promote to rooks which would fubar the dict.
            if c.isupper() and not "=" in move:
                piece = c

        # Updates the castle dict for castling rights.
        if piece == "K" or castle_move:
            if old_board.to_move == Color.WHITE:
                new_castle["WKR"] = False
                new_castle["WQR"] = False
            else:
                new_castle["BKR"] = False
                new_castle["BQR"] = False
        elif piece == "R":
            # This line of code means that this method takes approximately
            # the same length of time as make_move for Rook moves only.
            # All other moves bypass going to long algebraic.
            legal = old_board.short_algebraic_to_long_algebraic(move)
            # We can get the position the rook started from using slicing in
            # the long move.
            # So once the rook moves then we set it to false.
            if legal[1:3] == "a8":
                new_castle["BQR"] = False
            elif legal[1:3] == "h8":
                new_castle["BKR"] = False
            elif legal[1:3] == "a1":
                new_castle["WQR"] = False
            elif legal[1:3] == "h1":
                new_castle["WKR"] = False

        new_board = board.Board(state, new_castle, to_move)
        return new_board


    def random_move(self):
        moves = np.asarray(self.board.generate_moves(self.board.to_move))
        moves = moves[..., 0]
        return random.choice(moves)

    def greedy_move(self):
        moves = np.asarray(self.board.generate_moves(self.board.to_move))
        moves = moves[..., 0]

        for move in moves:
            self.board.make_move(move)

            checkmate = (not self.board.generate_moves(self.board.to_move) and
                         board.is_in_check(self.board.current_state, self.board.to_move))

            self.board.unmake_move()

            if checkmate:
                return move

        captures = []
        for move in moves:
            if "x" in move:
                captures.append(move)

        if captures:
            return random.choice(captures)
        else:
            return random.choice(moves)
