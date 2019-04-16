import sys
import re
import logging
import select
from string import ascii_lowercase

import numpy as np

import board
import engine

class UCI():
    def __init__(self):
        self.id = {"name" : "Chrysaora 0.003", "author" : "Dylan Green"}
        self.options = {}

        # An internal representation of the board that will get passed to the
        # engine after it's setup.
        self.board = board.Board(None, None, None, None)

        # The engine instance. Defaults to start of the game and playing as
        # white. As the board is updated the engine will be as well.
        self.engine = engine.Engine(self.board)

        # A record of the previous "position" command.
        # I use this to compare to the current one, allowing the engine to
        # only make the two new moves.
        # This avoids a slow down when the list of moves becomes unmanagably
        # long.
        self.previous_pos = []

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
        # Converts the castling move.
        if "O-" in move:
            long_algebraic = ["e"]
            rank = "1" if self.board.to_move == board.Color.WHITE else "8"
            long_algebraic.append(rank)
            if move == "O-O":
                long_algebraic.append("g")

            elif move == "O-O-O":
                long_algebraic.append("c")

            long_algebraic.append(rank)
            return "".join(long_algebraic)

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


    def decrypt_uci(self, cmd):
        cmd = cmd.split(" ")

        if cmd[0].lower() == "position":
            self.set_up_position(cmd)
        elif cmd[0].lower() == "isready":
            send_command("readyok")
        elif cmd[0].lower() == "quit":
            sys.exit()
        elif cmd[0].lower() == "go":
            # This is when the engine will actaully compute.
            self.compute(cmd)
        elif cmd[0].lower() == "ucinewgame":
            self.board = board.Board(None, None, None, None)
            self.previous_pos = []
        elif cmd[0].lower() == "setoption":
            self.set_option(cmd)


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
        self.engine.compute = True

        logging.debug("Finding move.")
        move = self.engine.find_move()
        logging.debug("Found move: " + move)
        uci_move = self.algebraic_to_uci(move)

        # Sends the move to the gui.
        send_command("bestmove " + uci_move)


    def set_up_position(self, cmd):
        # Checks that all the moves except the last two are identical
        # to the previous position command. If they are then we
        # can start the moves from the last two.
        # Need to ensure the lengths of the two even match up to try.
        if len(self.previous_pos) == len(cmd) - 2:
            equal = np.asarray(self.previous_pos)==np.asarray(cmd[:-2])
            same = np.sum(equal) == len(self.previous_pos)
        else:
            same = False

        # If we load from a fen just load the board from the fen.
        # We don't want to load the fen again if we're skipping moves.
        if "fen" in cmd and not same:
            self.board = board.load_fen(" ".join(cmd[2:]))
        # We only run this if we get given moves.
        if "moves" in cmd:
            # Default starting index.
            start = cmd.index("moves")

            # If we only have one move then setting the start to do the "final
            # two moves" make it try pass "moves" as a move.
            # start + 2 < len(command) ensures that there are at least
            # two moves to be made so setting it to -3 works.
            if same and start + 2 < len(cmd):
                start = -3
            # If they're not the same we'll have to start over.
            elif "fen" in cmd:
                self.board = board.load_fen(" ".join(cmd[2:]))
            else:
                self.board = board.Board(None, None, None)

            # Strips out the moves, then converts them to algebraic and then
            # makes them.
            for move in cmd[start+1:]:
                algebraic = self.uci_to_algebraic(move)
                self.board.make_move(algebraic)

        # When the command is just start post we should reset the board to the
        # start pos.
        if "startpos" in cmd and not "moves" in cmd:
            logging.debug("Reset Board")
            self.board = board.Board(None, None, None, None)

        self.previous_pos = cmd


    def set_option(self, cmd):
        name_index = cmd.index("name")
        value_index = cmd.index("value")

        # Use slice instead of a single index in case I set an option to have
        # multiple word names.
        option = " ".join(cmd[name_index + 1 : value_index])

        if option == "max_depth":
            self.engine.max_depth = int(cmd[value_index + 1])
            logging.debug("Engine: Set max depth to " + str(self.engine.max_depth))


    def identify(self):
        # Sends all the identification commands.
        for key, value in self.id.items():
            send_command(" ".join(["id", key, value]))

        send_command("option name max_depth type spin default 3 min 1 max 6")
        # Writes the ok command at the end.
        send_command("uciok")


def send_command(cmd):
    # Logs the output
    logging.debug("Output: " + cmd)

    sys.stdout.write(cmd + "\n")
    sys.stdout.flush()

def receive_command():
    # Returns the empty string if there's nothing in stdin.
    if not select.select([sys.stdin,],[],[],0.0)[0]:
        return ""

    # Returns the command if there's something in stdin.
    line = sys.stdin.readline().rstrip()
    logging.debug("Input: " + line)
    return line