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

    def __init__(self, new_board, impl="net", max_depth=3):
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
    def evaluate_moves(self, board_states):
        states = []

        # Transformation object, converts to a tensor then normalizes.
        normalize = transforms.Normalize(mean=[0.485], std=[0.229])
        trans = transforms.Compose([transforms.ToTensor()])#, normalize])

        # Goes through each moves, converts it to a long move, and then
        # gets the board state for that long algebraic.
        for s in board_states:
            # Once we have the state, we run the same conversions on it that
            # were run when the network was trained.
            #s = s.astype("uint8")
            #s = np.where(s == 0, 128, s)
            s = s.reshape((8, 8, 1))
            s = trans(s)
            s.resize_((1, 1, 8, 8))
            states.append(s)

        states = torch.cat(states, 0)

        # Runs the boards through the network, and then gets their label.
        # Remember:
        # 0 = draw, 1 = black win, 2 = white win.
        outputs = self.brain(states.float())
        outputs = F.softmax(outputs, dim=1)
        _, label = torch.max(outputs.data, 1)

        # Shifts the outputs to numpy ndarrays.
        outs = outputs.data.numpy()
        labels = label.numpy()

        color = self.board.to_move
        weights = [0, 0, 1] if color == board.Color.WHITE else [0, 1, 0]
        vals = np.dot(outs[...,:3], weights)

        return vals


    def minimax_search(self, search_board, depth=1, color=None):
        if color is None:
            color = self.board.to_move

        # If we recieve the stop command don't go any deeper just return our
        # best move.
        cmd = uci.receive_command()
        if cmd == "stop":
            self.compute = False

        if depth == 1:
            mult = 1 if color == self.board.to_move else -1
            moves = search_board.generate_moves(search_board.to_move)

            states = []
            for m in moves:
                # Turns the short algebraic move into a long algebraic'
                # So that it can be turned into a search_board state.
                long_move = search_board.short_algebraic_to_long_algebraic(m)

                # Turns the move into a search_board state
                if "O-O" in long_move:
                    s = search_board.castle_algebraic_to_boardstate(long_move)
                else:
                    s = search_board.long_algebraic_to_boardstate(long_move)

                states.append(s)

            vals = self.evaluate_moves(states)
            vals *= mult
            i = np.argmax(vals)

            # Returns the best move and its evaluation.
            return (moves[i], vals[i])

        else:
            moves = search_board.generate_moves(search_board.to_move)

            vals = []
            for m in moves:
                new_board = copy.deepcopy(search_board)
                new_board.make_move(m)

                # Check to see if making this move checkmates one of the sides.
                if not new_board.status == board.Status.IN_PROGRESS:
                    # In this situation we were the ones to get checkmated
                    # (or stalemated)
                    if new_board.to_move == self.board.to_move:
                        vals.append(-1)
                    else:
                        vals.append(1)
                else:
                    best_move, val = self.minimax_search(new_board, depth-1, new_board.to_move)
                    vals.append(val)

                if not self.compute:
                    break

            # Inverts the evaluations from the next lower depth.
            vals = np.asarray(vals)
            vals *= -1
            i = np.argmax(vals)
            return (moves[i], vals[i])


    def random_move(self):
        moves = self.board.generate_moves(self.board.to_move)
        return random.choice(moves)

    def greedy_move(self):
        moves = self.board.generate_moves(self.board.to_move)

        captures = []
        for move in moves:
            if "x" in move:
                captures.append(move)

        if captures:
            return random.choice(captures)
        else:
            return random.choice(moves)
