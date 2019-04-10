import sys
import re
import logging
from string import ascii_lowercase

import numpy as np

import board
import engine

class UCI():
    def __init__(self):
        self.id = {"name" : "Chrysaora 0.002", "author" : "Dylan Green"}
        self.options = {}

        # An internal representation of the board that will get passed to the
        # engine after it's setup.
        self.board = board.Board(None, None, None, None)

        # The engine instance. Defaults to start of the game and playing as
        # white. As the board is updated the engine will be as well.
        self.engine = engine.Engine(self.board)

    def uci_to_algebraic(self, move):
        # Promotions are in the form say a7a8q so length 5
        if len(move) == 5:
            promo = move[-1]
            return move[:-1] + "=" + promo.upper()
        # We here prepend the piece to the move, making it a move that can
        # easily be read by make_move and by extension check_move_legality.
        else:
            # This regex extracts all the locations in the move.
            locs = re.findall("[a-h]\d+", move)

            dest = locs[0]
            startfile = ascii_lowercase.index(dest[0]) # File = x
            startrank = 8 - int(dest[1]) # Rank = y
            start = [startrank, startfile]

            piece = self.board.current_state[start[0], start[1]]
            piece_name = self.board.piece_names[np.abs(piece)]

            # If the piece is a king check if this is a castling move.
            if piece_name == "K" and dest[0] == "e":
                # Only need this for checking for castling.
                dest = locs[-1]

                # Kingside castling
                if dest[0] == "g":
                    return "O-O"
                # Queenside castling
                elif dest[0] == "c":
                    return "O-O-O"

            return piece_name + move


    def algebraic_to_uci(self, move):
        long_algebraic = self.board.short_algebraic_to_long_algebraic(move)

        # No capture x in uci format.
        if "x" in long_algebraic:
            long_algebraic = long_algebraic.replace("x", "")

        # Removes the = in pawn promotions and makes the promo piece lower
        # case.
        if "=" in long_algebraic:
            long_algebraic = long_algebraic.replace("=", "")
            return long_algebraic.lower()

        if len(long_algebraic) == 4:
            return long_algebraic
        # Slicing off the piece character at the start of the move.
        else:
            return long_algebraic[1:]


    def send_command(self, cmd):
        # Logs the output
        logging.debug("Output: " + cmd)

        sys.stdout.write(cmd + "\n")
        sys.stdout.flush()


    def decrypt_uci(self, cmd):
        cmd = cmd.split(" ")

        if cmd[0].lower() == "position":
            self.set_up_position(cmd)
        elif cmd[0].lower() == "isready":
            self.send_command("readyok")
        elif cmd[0].lower() == "quit":
            sys.exit()
        elif cmd[0].lower() == "go":
            # This is when the engine will actaully compute.
            self.compute(cmd)


    # The method that tells the engine to analyze and then returns the best
    # found position.
    def compute(self, cmd):

        parameters = {"wtime" : None, "btime" : None, "winc" : None,
                      "binc" : None}

        # Extracts the computation commands from the go command.
        # Things like wtime, btime, winc, binc.
        if len(cmd) > 1:
            def get_parameter(param):
                try:
                    index = cmd.index(param)
                    return cmd[index + 1]
                # The parameter wasn't passed if this except block runs
                # so return None instead.
                except(ValueError):
                    return None

            for key in parameters.keys():
                parameters[key] = get_parameter(key)

        # Sets the engine's internal board to the current board state.
        self.engine.board = self.board
        self.engine.time_params = parameters

        logging.debug("Finding move.")
        move = self.engine.find_move()
        logging.debug("Found move: " + move)
        uci_move = self.algebraic_to_uci(move)

        # Sends the move to the gui.
        self.send_command("bestmove " + uci_move)


    def set_up_position(self, cmd):
        # Starts with a clean board.
        self.board = board.Board(None, None, None, None)

        # If we load from a fen just load the board from the fen.
        if "fen" in cmd:
            self.board = board.load_fen(" ".join(cmd[2:]))
        # We only run this if we start from start pos and then get
        # given moves.
        elif "moves" in cmd:
            # Strips out the moves, then converts them to algebraic and then
            # Makes them.
            for move in cmd[3:]:
                algebraic = self.uci_to_algebraic(move)
                self.board.make_move(algebraic)


    def identify(self):
        # Sends all the identification commands.
        for key, value in self.id.items():
            self.send_command(" ".join(["id", key, value]))

        # Writes the ok command at the end.
        self.send_command("uciok")