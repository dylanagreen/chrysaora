import random
import os
import logging

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
import torchvision.transforms as transforms

import board


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

        weights = os.path.join(os.path.dirname(__file__),"SkipNet-89.pt")
        self.brain.load_state_dict(torch.load(weights, map_location="cpu"))

        # Sets the network to evaluation mode.
        # There's a batch normalization layer which runs differently in
        # training and evaluation.
        self.brain.eval()

        # Keeping that random implemenation around for testing.
        if impl == "random":
            self.eval = self.random_move
        elif impl == "greedy":
            self.eval = self.greedy_move
        else:
            self.eval = self.evaluate_moves


    def find_move(self):
        moves = self.board.generate_moves(self.board.to_move)

        evals = self.eval(moves)

        best = np.argmax(eval)
        return moves[best]


    # Evaluates and returns the best move for now.
    # TODO refactor to return move evaluations, use search move to run search and find move to pick one.
    def evaluate_moves(self, moves):
        states = []

        # Transformation object, converts to a tensor then normalizes.
        normalize = transforms.Normalize(mean=[0.485], std=[0.229])
        trans = transforms.Compose([transforms.ToTensor()])#, normalize])

        # Goes through each moves, converts it to a long move, and then
        # gets the board state for that long algebraic.
        for m in moves:
            long_move = self.board.short_algebraic_to_long_algebraic(m)

            if "O-O" in long_move or "0-0" in long_move:
                s = self.board.castle_algebraic_to_boardstate(long_move)

            else:
                s = self.board.long_algebraic_to_boardstate(long_move)

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

        weights = [0, 0, 1] if self.board.to_move == board.Color.WHITE else [0, 1, 0]
        vals = np.dot(outs[...,:3], weights)

        logging.debug(str(vals))
        logging.debug(str(moves))
        return vals


    def search_moves(self, moves, depth=2):



    def random_move(self, moves):
        return random.choice(moves)

    def greedy_move(self, moves):
        moves = self.board.generate_moves(self.board.to_move)

        captures = []
        for move in moves:
            if "x" in move:
                captures.append(move)

        if captures:
            return random.choice(captures)
        else:
            return random.choice(moves)
