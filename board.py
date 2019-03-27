import xml.etree.ElementTree as ET
from enum import Enum
from string import ascii_lowercase
import os.path
import re

import numpy as np
from IPython.display import SVG


# Enum for white or black.
class Color(Enum):
    WHITE = True
    BLACK = False


# Enum for game status
class Status(Enum):
    IN_PROGRESS = 0
    DRAW = 1
    WHITE_VICTORY = 2
    BLACK_VICTORY = 3


class Board():
    """The board state.

    current_state = the current board state
    previous_state = the previous state

    """

    def __init__(self, state, castle_dict, to_move, headers=None):

        if state is not None:
            self.current_state = state
        else:
            # This is the board state at the state of the game.
            self.current_state = np.asarray([[-2, -3, -4, -5, -6, -4, -3, -2],
                                            [-1, -1, -1, -1, -1, -1, -1, -1],
                                            [0, 0, 0, 0, 0, 0, 0, 0],
                                            [0, 0, 0, 0, 0, 0, 0, 0],
                                            [0, 0, 0, 0, 0, 0, 0, 0],
                                            [0, 0, 0, 0, 0, 0, 0, 0],
                                            [1, 1, 1, 1, 1, 1, 1, 1],
                                            [2, 3, 4, 5, 6, 4, 3, 2]])
        self.game_states = []
        self.game_states.append(np.copy(self.current_state))

        # Dict containing a conversion between the piece num and the piece name.
        self.piece_names = {1:"P", 2:"R", 3:"N", 4:"B", 5:"Q", 6:"K"}

        if castle_dict is not None:
            self.castle_dict = castle_dict
        else:
            # White Queenside Rook, White Kingside Rook etc.
            # No point storing king motion, if it moves both get set to False.
            self.castle_dict = {"WQR" : True, "WKR" : True,
                                "BQR" : True, "BKR" : True}

        if to_move is not None:
            self.to_move = to_move
        else:
            self.to_move = Color.WHITE

        self.status = Status.IN_PROGRESS
        self.move_list = []

        if headers is not None:
            self.headers = headers
        else:
            self.headers = {}

    def generate_moves(self, color):
        """Generate all possible moves for a given color
        """

        pawns = self.generate_pawn_moves(color)
        knights = self.generate_knight_moves(color)
        rooks = self.generate_rook_moves(color)
        bishops = self.generate_bishop_moves(color)
        queens = self.generate_queen_moves(color)
        kings = self.generate_king_moves(color)
        castling = self.generate_castle_moves(color)

        total_moves = pawns+knights+rooks+bishops+queens+kings+castling

        new_moves = []
        # M for move, s for state
        # This removes moves where the ending state is in check.
        # Becuase you're not allowed to move into check.
        # This has the double bonus of removing moves that don't get you
        # out of check as well. Neat.
        for m in total_moves:
            s = self.algebraic_to_boardstate(m)
            check = is_in_check(s, color)

            # I could remove it from the old list, but doing so while iterating
            # is dangerous. Plus, remove() requires a search, which increases
            # the run time much more than an append.
            if not check:
                new_moves.append(m)

        # If there are no moves that get us out of check we need to see if
        # we're in check right now.
        # If we are that's check mate. If we're not... that's a stalemate.
        if len(new_moves) == 0:
            check = is_in_check(self.current_state, color)
            if check:
                if self.to_move == Color.WHITE:
                    self.status = Status.BLACK_VICTORY
                else:
                    self.status = Status.WHITE_VICTORY
                return []
            else:
                self.status = Status.DRAW
                return []
        return new_moves


    def disambiguate_moves(self, moves):
        # Shortcut for if there's no possible moves being disambiguated.
        if len(moves) == 0:
            return []
        moves = np.asarray(moves)
        unique, counts = np.unique(moves[...,0], return_counts=True)

        duplicates = unique[counts > 1]

        moves2 = []
        for i, m in enumerate(moves):
            if m[0] in duplicates:
                moves2.append(m[1])
            else:
                moves2.append(m[0])

        return moves2


    def generate_pawn_moves(self, color):
        # Mult required to simplify finding algorithm.
        # Could use piece here instead, but in the end there are the
        # same amount of multiplications done.
        mult = 1 if color.value else -1
        # Direction of travel, reverse for black and white.
        # Positive is going downwards, negative is going upwards.
        d = -1 * mult
        state = np.copy(self.current_state * mult)
        previous_state = np.copy(self.game_states[-1] * mult)

        x, y = np.where(state==1)
        x = x.reshape(len(x), 1)
        y = y.reshape(len(y), 1)

        pawns = np.append(x,y,axis=1)

        end_states = []

        # The ending rank for pawn promotions
        endrank = 7 if d == 1 else 0
        for pos in pawns:
            # En Passant first since we can take En Passant if there
            # is a piece directly in front of our pawn.
            # However, requires the pawn on row 5 (from bottom)
            if pos[0] == 4 + d:
                if state[pos[0], pos[1] - 1] == -1 and previous_state[pos[0] + 2*d, pos[1] - 1] == -1:
                    end = [pos[0] + d, pos[1] - 1]
                    end_states.append(rowcolumn_to_algebraic(pos, end, 1))

                elif state[pos[0], pos[1] + 1] == -1 and previous_state[pos[0] + 2*d, pos[1] + 1] == -1:
                    end = [pos[0] + d, pos[1] + 1]
                    end_states.append(rowcolumn_to_algebraic(pos, end, 1))

            # Makes sure the space in front of us is clear
            elif state[pos[0] + d, pos[1]] == 0:
                # Pawn promotion
                # We do this first because pawns have to promote so we can't
                # just "move one forward" in this position
                # (7 - d)%7 = 6 if going down (dir = 1) or 1 (dir = -1)
                if pos[0] + d == endrank:
                    for i in range(2, 6):
                        end = [pos[0] + d, pos[1]]
                        end_states.append(rowcolumn_to_algebraic(pos, end, 1, i))
                else:
                    # Add one move forward
                    end = [pos[0] + d,pos[1]]
                    end_states.append(rowcolumn_to_algebraic(pos, end, 1))
                # We do the two forward next as an elif
                # (7 + d)%7 = 1 if going down (dir = 1) or 6 (dir = -1)
                if pos[0] == (7 + d) % 7 and state[pos[0] + 2*d, pos[1]] == 0:
                    end = [pos[0] + 2*d,pos[1]]
                    end_states.append(rowcolumn_to_algebraic(pos, end, 1))

            # Takes to the left
            if pos[1] - 1 > -1 and state[pos[0] + d, pos[1] - 1] < 0:
                end = [pos[0] + d,pos[1] - 1]

                # Promotion upon taking
                if pos[0] + d == endrank:
                    for i in range(2, 6):
                        end_states.append(rowcolumn_to_algebraic(pos, end, 1, i))
                else:
                    end_states.append(rowcolumn_to_algebraic(pos, end, 1))

            # Takes to the right
            if pos[1] + 1 < 8 and state[pos[0] + d, pos[1] + 1] < 0:
                end = [pos[0] + d,pos[1] + 1]

                # Promotion upon taking
                if pos[0] + d == endrank:
                    for i in range(2, 6):
                        end_states.append(rowcolumn_to_algebraic(pos, end, 1, i))
                else:
                    end_states.append(rowcolumn_to_algebraic(pos, end, 1))

        end_states = self.disambiguate_moves(end_states)
        return end_states


    def generate_knight_moves(self, color):
        # This code was written from white point of view but flipping piece sign
        # allows it to work for black as well.
        mult = 1 if color.value else -1
        state = np.copy(self.current_state * mult)

        # This is quick code for finding the position of all knights.
        x, y = np.where(state == 3)
        x = x.reshape(len(x), 1)
        y = y.reshape(len(y), 1)

        knight_locs = np.append(x, y, axis=1)
        moves = np.asarray([[2, 1], [2, -1], [-2, 1], [-2, -1]])

        end_states = []

        for pos in knight_locs:
            for m in moves:
                s1 = np.copy(state)
                end1 = pos + m
                end2 = pos + np.flip(m)

                # If at least one coordinate goes above 7 or below 0 this will be False
                cond1 = np.sum(end1 > 7) == 0 and np.sum(end1 < 0) == 0
                cond2 = np.sum(end2 > 7) == 0 and np.sum(end2 < 0) == 0

                # This adds to the condition that the end square must not be
                # occupied by a piece of the same color. Since white is
                # always >0 we require the end square to be empty (==0) or
                # occupied by black (<0)
                cond1 = cond1 and s1[end1[0], end1[1]] <= 0
                cond2 = cond2 and s1[end2[0], end2[1]] <= 0

                # The following code blocks only run if the ending positions
                # are actually on the board.
                # The first knight position
                if cond1:
                    end_states.append(rowcolumn_to_algebraic(pos, end1, 3))

                # Second possible knight position
                if cond2:
                    end_states.append(rowcolumn_to_algebraic(pos, end2, 3))

        end_states = self.disambiguate_moves(end_states)
        return end_states


    def generate_rook_moves(self, color):
        # This code was written from white point of view but flipping piece sign
        # allows it to work for black as well.
        mult = 1 if color.value else -1
        state = np.copy(self.current_state * mult)

        x, y = np.where(state == 2)
        x = x.reshape(len(x), 1)
        y = y.reshape(len(y), 1)

        rooks = np.append(x, y, axis=1)

        return self.generate_straight_moves(color, rooks)


    def generate_straight_moves(self, color, starts, queen=False):
        # This code was written from white point of view but flipping piece sign
        # allows it to work for black as well.
        mult = 1 if color.value else -1
        state = np.copy(self.current_state * mult)

        piece_val = 5 if queen else 2
        end_states = []
        for pos in starts:
            # This slicesthe array from the rook towards the edge of the board.
            # Need to reverse leftward and upward directions so they go "out"
            # from the rook, i.e. the left array should be the board locations
            # going right to left and not vice versa.
            # This is so that we can minimize code changes per direction.
            direction_dict = {}
            direction_dict['r'] = state[pos[0], pos[1] + 1:]
            direction_dict['l'] = state[pos[0], :pos[1]][::-1]
            direction_dict['u'] = state[:pos[0],pos[1]][::-1]
            direction_dict['d'] = state[pos[0] + 1:,pos[1]]

            for key, val in direction_dict.items():
                # Reverses the direction of adding to the position since we
                # reversed the up and leftward arrays.
                sign = -1 if key == 'u' or key == 'l' else 1

                once = True
                blocked = False

                i = 0
                while (once or not blocked) and i < len(val) and len(val) > 0:
                    once = False

                    # Sets to true once we hit a piece.
                    # We don't break because we still want to add this position.
                    # Although we do break if it's a piece of our color.
                    if val[i] < 0:
                        blocked = True
                    elif val[i] > 0:
                        break
                    i = i+1

                    # This was an embarrasing bug to correct.
                    if key == 'r' or key == 'l':
                        end = [pos[0], pos[1] + (i * sign)]
                    else:
                        end = [pos[0] + (i * sign), pos[1]]
                    end_states.append(rowcolumn_to_algebraic(pos, end, piece_val))

        end_states = self.disambiguate_moves(end_states)
        return end_states


    def generate_bishop_moves(self, color):
        mult = 1 if color.value else -1
        state = np.copy(self.current_state * mult)

        x, y = np.where(state==4)
        x = x.reshape(len(x), 1)
        y = y.reshape(len(y), 1)

        bishops = np.append(x, y, axis=1)

        return self.generate_diagonal_moves(color, bishops)


    def generate_diagonal_moves(self, color, starts, queen=False):
        mult = 1 if color.value else -1
        state = np.copy(self.current_state * mult)

        piece_val = 5 if queen else 4

        end_states = []
        for pos in starts:

            # This dict contains the direction that the loop will travel in
            addition_dict = {'ul' : np.array([-1, -1]),
                            'ur' : np.array([-1, 1]),
                            'lr' : np.array([1, 1]),
                            'll' : np.array([1, -1])}
            # This dict contains the maximum the loop will travel in each diagonal direction
            # Subtracting from 7 is necessary for the edges that are the maximum
            max_dict = {'ul' : np.min(pos),
                       'ur' : np.min(np.abs([0, 7] - pos)),
                       'lr' : np.min(7 - pos),
                       'll' : np.min(np.abs([7, 0] - pos))}

            # Traverses each direction
            for key, val in addition_dict.items():
                i = 1
                blocked = False
                while i <= max_dict[key] and not blocked:

                    end = pos + i * val

                    # We get blocked if we hit a piece of the opposite color
                    # And by one of this color, but we break if we do that
                    # since we can't take our own color.
                    if state[end[0], end[1]] < 0:
                        blocked = True
                    elif state[end[0], end[1]] > 0:
                        break

                    # This puts the piece in its new place
                    end_states.append(rowcolumn_to_algebraic(pos, end, piece_val))

                    i = i + 1

        end_states = self.disambiguate_moves(end_states)
        return end_states

    def generate_queen_moves(self, color):
        mult = 1 if color.value else -1
        state = np.copy(self.current_state * mult)

        x, y = np.where(state==5)
        x = x.reshape(len(x), 1)
        y = y.reshape(len(y), 1)

        queens = np.append(x, y, axis=1)

        diags = self.generate_diagonal_moves(color, queens, True)
        straights = self.generate_straight_moves(color, queens, True)

        end_states = diags + straights

        return end_states


    def generate_king_moves(self, color):
        mult = 1 if color.value else -1
        state = np.copy(self.current_state * mult)

        x, y = np.where(state==6)
        x = x.reshape(len(x), 1)
        y = y.reshape(len(y), 1)

        # You shouldn't need a loop, because why would you have more than 1 king?
        # Just reshape instead
        king = np.append(x,y,axis=1).reshape(2)

        shifts = [[-1, -1], [-1, 0], [-1, 1], [0, -1], [0, 1],
                 [1, -1], [1, 0], [1, 1]]

        end_states = []
        for pos in shifts:
            end = pos + king

            if 0 <= end[0] < 8 and 0 <= end[1] < 8:

                # Can't take our own pieces, so don't add it as a board pos
                if state[end[0], end[1]] > 0:
                    continue
                end_states.append(rowcolumn_to_algebraic(king, end, 6))

        end_states = self.disambiguate_moves(end_states)
        return end_states

    def generate_castle_moves(self, color):
        # Hardcoded because you can only castle from starting positions.
        # Basically just need to check that the files between the king and
        # the rook are clear, then return the castling algebraic (O-O or O-O-O)
        rank = 0 - int(color.value) # 0 for Black, -1 for White
        kingside = "WKR" if color.value else "BKR"

        end_states = []
        if self.castle_dict[kingside] and np.sum(self.current_state[rank, 5:7])== 0:
            end_states.append("O-O")

        queenside = "WQR" if color.value else "BQR"
        if self.castle_dict[queenside] and np.sum(self.current_state[rank, 1:4])== 0:
            end_states.append("O-O-O")

        return end_states


    def get_board_svg(self):
        # Parses the board in first as a background.
        tree = ET.ElementTree()
        tree.parse("pieces/board.svg")
        composite = tree.getroot()

        # Numpy iterator that gives us the position as well as the piece number
        it = np.nditer(self.current_state, flags=['multi_index'])

        while not it.finished:
            pos = it.multi_index
            piece = it[0]

            # 0 is empty space so we increment the iterator and skip the rest.
            if piece == 0:
                it.iternext()
                continue

            # Parses the raw piece svg file into XML
            name = self.piece_names[np.abs(piece)].lower()
            if piece < 0:
                name = 'b' + name
            else:
                name = 'w' + name

            tree.parse("pieces/" + name + ".svg")
            piece = tree.getroot()

            # The positioning of the piece. Each square is 50x50 pixels.
            x_pos = pos[1] * 50.5
            y_pos = pos[0] * 50.5
            piece.set("x", str(x_pos))
            piece.set("y", str(y_pos))

            # Adds the piece as a subelement of the board XML.
            composite.append(piece)

            it.iternext()

        # Returns the SVG representing the board
        return SVG(ET.tostring(composite))


    def make_move(self, move):
        new_state = self.algebraic_to_boardstate(move)
        self.game_states.append(np.copy(self.current_state))

        self.current_state = np.copy(new_state)

        piece = ""
        for i, c in enumerate(move):
            # If we have an = then this is the piece the pawn promotes to.
            if c.isupper():
                piece = c

        # Updates the castle dict for castling rights.
        if piece == "K":
            if self.to_move.value:
                self.castle_dict["WKR"] = False
                self.castle_dict["WQR"] = False
            else:
                self.castle_dict["BKR"] = False
                self.castle_dict["BQR"] = False
        elif piece == "R":
            diff = self.game_states[-1] - self.current_state
            # If the rook position is nonzero in the difference we know that
            # the rook moved off that position. And hence castling that side
            # Is no longer allowed.
            if diff[0, 0] == -2:
                self.castle_dict["BQR"] = False
            elif diff[0, 7] == -2:
                self.castle_dict["BKR"] = False
            elif diff[7, 0] == -2:
                self.castle_dict["WQR"] = False
            elif diff[7, 7] == -2:
                self.castle_dict["WKR"] = False

        if move.endswith("#"):
            if self.to_move == Color.WHITE:
                self.status = Status.WHITE_VICTORY
            else:
                self.status = Status.BLACK_VICTORY
        self.to_move = Color.BLACK if self.to_move.value else Color.WHITE
        self.move_list.append(move)


    def unmake_move(self):
        self.current_state = np.copy(self.game_states.pop(-1))
        self.move_list.pop(-1) # Take the last move off the move list as well.


    def algebraic_to_boardstate(self, move):
        # Reverse piece -> number dictionary
        piece_number = {v: k for k, v in self.piece_names.items()}

        # This puts in a piece at the given location using np.ndarray.itemset
        # This is marginally faster than new_state[pos[0], pos[1]] = piece.
        # Saves about .5ms on average.
        new_state = np.copy(self.current_state)
        place = new_state.itemset

        # Kingside castling
        if move == "O-O" or move == "0-0":
            # Need to make sure this is allowed
            check = "WKR" if self.to_move.value else "BKR"
            rank = 7 if self.to_move.value else 0
            if self.castle_dict[check]:
                place((rank, 7), 0)
                place((rank, 4), 0)
                place((rank, 6), piece_number["K"])
                place((rank, 5), piece_number["R"])
                return new_state
        # Queenside castling
        elif move == "O-O-O" or move == "0-0-0":
            check = "WQR" if self.to_move.value else "BQR"
            rank = 7 if self.to_move.value else 0
            # Need to make sure this is allowed
            if self.castle_dict[check]:
                place((rank, 0), 0)
                place((rank, 4), 0)
                place((rank, 2), piece_number["K"])
                place((rank, 3), piece_number["R"])
                return new_state

        locs = []
        ranks = []
        files = []
        piece = "P" # Default to pawn, this generally be changed.
        try:
            for i, c in enumerate(move):
                # Appends a found [rank] character
                if c.islower():
                    # We use a lower case x for taking so I have to exclude it.
                    if not c == "x":
                        files.append(c)
                        # This is a full move, [rank][file]
                    if move[i+1].isdigit():
                        locs.append(move[i:i+2])
                # A [file] character
                if c.isdigit():
                    ranks.append(c)
                # A [piece] character
                # If we have an = then this is the piece the pawn promotes to.
                if c.isupper():
                    piece = c

        except(IndexError):
            raise ValueError("You tried to make an illegal move.")
            return self.current_state

        if len(locs) == 0 or len(locs) >= 3:
            raise ValueError("You tried to make an illegal move.")
            return self.current_state

        # Always true, no matter how long locs is at this point (1 or 2)
        # If it's one then that's just the destination
        # If it's two then the first is the start, and the second is the end.
        dest = locs[-1]
        endfile = ascii_lowercase.index(dest[0]) # End File = x
        endrank = 8 - int(dest[1]) # End Rank = y
        end = [endrank, endfile]

        # Gets the value of the piece
        piece = piece_number[piece]
        mult = 1 if self.to_move.value else -1

        # Internal function that moves a piece, to reduce code duplication.
        # Additionally updates the self.to_move value.
        def move_piece(start, end, piece):
            place((start[0], start[1]), 0)
            place((end[0], end[1]), piece)
            #self.to_move = Color.BLACK if self.to_move.value else Color.WHITE
            return new_state

        # Disambiguation case, don't need to find the pieces in this case
        # since we know where to start at.
        if len(locs) > 1:
            piece = piece * mult
            dest = locs[0]
            startfile = ascii_lowercase.index(dest[0]) # End File = x
            startrank = 8 - int(dest[1]) # End Rank = y
            start = [startrank, startfile]
            return move_piece(start, end, piece)

        state = np.copy(self.current_state * mult)

        search = 1 if "=" in move else piece
        x, y = np.where(state==search)
        x = x.reshape(len(x), 1)
        y = y.reshape(len(y), 1)
        starts = np.append(x, y, axis=1)

        # Need this to be separate or the if blocks don't trigger.
        end_piece = piece * mult
        for s in starts:
            # Partial disambiguation cases first
            if len(files) > 1:
                startfile = ascii_lowercase.index(files[0]) # End File = x
                if s[1] == startfile:
                    return move_piece(s, end, end_piece)
                continue
            elif len(ranks) > 1:
                startrank = 8 - int(ranks[0]) # End Rank = y
                if s[0] == startrank:
                    return move_piece(s, end, end_piece)
                continue

            # Pawns
            if piece == 1:
                # Direction the pawn would move.
                d = -1 if self.to_move.value else 1

                # The only time we ever need to check for taking since the
                # piece moves differently. Also if we got here only one
                # pawn should be able to take, since we dealt with
                # disambiguation already.
                if "x" in move:
                    # Takes going to the right diagonally
                    if np.array_equal(s[0] + d, end[0]) and s[1] + 1 == end[1]:
                        return move_piece(s, end, end_piece)
                    # Takes going to the left diagonally
                    elif s[0] + d == end[0] and s[1] - 1 == end[1]:
                        return move_piece(s, end, end_piece)
                elif  s[0] + d == end[0] and s[1] == end[1]:
                    return move_piece(s, end, end_piece)
                elif  s[0] + (2 * d) == end[0] and s[1] == end[1]:
                    return move_piece(s, end, end_piece)
            # Rooks (and straight Queens)
            if piece == 2 or piece == 5:
                # If this rook is on the rank or file then it's the correct one
                if s[0] == end[0] or s[1] == end[1]:
                    return move_piece(s, end, end_piece)

            # Bishops (and diagonal Queens)
            if piece == 4 or piece == 5:
                # Finds the slope of the line between start and end
                # If it's 1,1 we know it's a good diagonal.
                diag = np.abs(s - end)
                diag = diag / np.max(diag)

                if np.array_equal(diag, [1, 1]):
                    return move_piece(s, end, end_piece)
            # Knights
            if piece == 3:
                # Finds the slope of the line between start and end
                # If it's 1,2 or 2,1 it's a good knight move
                slope = np.abs(end-s)
                if np.array_equal(slope, [1, 2]) or np.array_equal(slope, [2, 1]):
                    return move_piece(s, end, end_piece)
            if piece == 6:
                #If the distance between s and end is 1 then the king can
                # get here. You should only have one king so I don't know why
                # I check this but if you pass a move where a king tries to
                # move two spaces then I guess this will catch it.
                # Used to check the sum of the dist, but diagonals sum to 2
                # so oops.
                dist = np.abs(s - end)
                if dist[0] == 1 or dist[1] == 1:
                    return move_piece(s, end, end_piece)

        raise ValueError("You tried to make an illegal move.")
        return self.current_state


    def __str__(self):
        s = ""
        for y in range(0, 8):
            for x in range(0, 8):
                loc = self.current_state[y, x]
                # Black is supposed to be lower case hence this
                # if block differentiating between the two.
                if loc < 0:
                    s = s + self.piece_names[np.abs(loc)].lower()
                elif loc > 0:
                    s = s + self.piece_names[loc]
                else:
                    s = s + "."
                # This space makes it look nice
                s = s + " "
            # End of line new line.
            s = s + "\n"
        return s


def rowcolumn_to_algebraic(start, end, piece, promotion=None):
    piece_names = {1:"P", 2:"R", 3:"N", 4:"B", 5:"Q", 6:"K"}

    # Alg2 fully disambiguates
    alg1 = []
    alg2 = []

    # Don't need to append pawn name
    if piece > 1:
        alg1.append(piece_names[np.abs(piece)]) # Piece Name
        alg2.append(piece_names[np.abs(piece)])

    alg2.append(ascii_lowercase[start[1]]) # File = x
    alg2.append(str(8 - start[0])) # Rank = y

    alg1.append(ascii_lowercase[end[1]]) # End File = x
    alg1.append(str(8 - end[0])) # End Rank = y

    alg2.append(ascii_lowercase[end[1]]) # End File = x
    alg2.append(str(8 - end[0])) # End Rank = y

    if promotion:
        alg1.append("=")
        alg1.append(piece_names[np.abs(promotion)])

        alg2.append("=")
        alg2.append(piece_names[np.abs(promotion)])

    return ("".join(alg1), "".join(alg2))


def load_fen(fen):
    piece_values = {"P":1, "R":2, "N":3, "B":4, "Q":5, "K":6,
                "p":-1, "r":-2, "n":-3, "b":-4, "q":-5, "k":-6}

    fields = fen.split(' ')
    rows = fields[0].split('/')
    board = []
    # Iterates over each row
    for r in rows:
        rank = []
        for c in r:
            # Puts in the requisite number of 0s
            if c.isdigit():
                for i in range(0, int(c)):
                    rank.append(0)
            else:
                rank.append(piece_values[c])
        board.append(rank)

    board = np.asarray(board)

    # Sets castling rights.
    castle_dict = {"WQR" : False, "WKR" : False, "BQR" : False, "BKR" : False}
    castle_names = {"K" : "WKR", "Q" : "WQR", "k" : "BKR", "q" : "BQR"}
    castling = fields[2]
    for c in castling:
        if  c == "-":
            break
        castle_dict[castle_names[c]] = True

    to_move = Color.WHITE if fields[1] == "w" else Color.BLACK

    return Board(board, castle_dict, to_move)


def load_pgn(name):
    loc = os.path.join("games", name)
    if not os.path.isfile(loc):
        print("PGN not found!")
        return

    # We're going to extract the text into a single string so we need to append
    # lines here into this array.
    game_line = []
    tags = {}
    with open(loc, 'r') as f:
        for line in f:
            line = line.rstrip()
            if not line.startswith("["):
                game_line.append(line + " ")
            # This parses the tags by stripping the [] and then splitting on
            # the quotes surrounding the value.
            else:
                line = line.strip("[]")
                pair = line.split("\"")
                tags[pair[0].rstrip()] = pair[1]
    game_line = "".join(game_line)

    # Removes the comments in the PGN, one at a time.
    while "{" in game_line:
        before = game_line[:game_line.index("{")]
        after = game_line[game_line.index("}") + 1:]
        game_line = before + after

    # \d+ looks for 1 or more digits
    # \. escapes the period
    # \s* looks for 0 or more white space
    # Entire: looks for 1 or more digits followed by a period followed by
    # whitespace or no whitespace
    moves = re.split("\d+\.\s*", game_line)

    plies = []
    for m in moves:
        spl = m.split(" ")
        for s in spl:
            if s:
                plies.append(s)

    # Pop off the last ply (the game result)
    plies.pop(-1)

    # Makes all the moves and then returns the board state at the end.
    b = Board(None, None, None, headers=tags)
    for ply in plies:
        b.make_move(ply)

    return b


def save_pgn(board):
    moves = board.move_list


def is_in_check(state, color):
    # The direction a pawn must travel to take this color's king.
    # I.e. Black pawns must travel in the positive y (downward) direction
    # To take a white king.
    d = 1 if color.value else -1

    mult = 1 if color.value else -1

    x, y = np.where(state*mult==6)
    x = x.reshape(len(x), 1)
    y = y.reshape(len(y), 1)

    # You shouldn't need a loop, because why would you have more than 1 king?
    # Just reshape instead
    king = np.append(x,y,axis=1).reshape(2)

    # Check pawns first because they're the easiest.
    pawn = -1 if color.value else 1
    if king[1] - 1 >= 0 and state[king[0] - d, king[1] - 1] == pawn:
        return True
    elif king[1] + 1 < 8 and state[king[0] - d, king[1] + 1] == pawn:
        return True

    mult = -1 * mult
    x, y = np.where(state*mult==2)
    x = x.reshape(len(x), 1)
    y = y.reshape(len(y), 1)
    rooks = np.append(x,y,axis=1)

    x, y = np.where(state*mult==5)
    x = x.reshape(len(x), 1)
    y = y.reshape(len(y), 1)
    queens = np.append(x,y,axis=1)

    # Check rooks next because I seem to do that a lot.
    for pos in np.append(rooks, queens, axis=0):
        # Rook needs to be on the same file or rank to be able to put the king
        # in check
        # Check the sum between the two pieces, if it's 0 then no pieces are
        # between and it's a valid check.
        if pos[0] == king[0]:
            if pos[1] < king[1]:
                f = state[king[0], pos[1] + 1:king[1]]
            else:
                f = state[king[0], king[1] + 1:pos[1]]
            if np.sum(f) == 0:
                return True
        elif pos[1] == king[1]:
            if pos[0] < king[0]:
                f = state[pos[0] + 1:king[0], king[1]]
            else:
                f = state[king[0] + 1:pos[0], king[1]]
            if np.sum(f) == 0:
                return True

    # Knights can hop which is why I'm doing them before bishops
    x, y = np.where(state*mult==3)
    x = x.reshape(len(x), 1)
    y = y.reshape(len(y), 1)
    knights = np.append(x,y,axis=1)

    for pos in knights:
        slope = np.abs(pos-king)

        # Avoids a divide by 0 error. If it's on the same rank or file
        # the knight can't get the king anyway.
        if slope[1] == 0 or slope[0] == 0:
            continue
        if np.array_equal(slope, [1, 2]) or np.array_equal(slope, [2, 1]):
            return True

    # Now bishops and diagonal queens, I guess
    # Knights can hop which is why I'm doing them before bishops
    x, y = np.where(state*mult==4)
    x = x.reshape(len(x), 1)
    y = y.reshape(len(y), 1)
    bishops = np.append(x,y,axis=1)

    for pos in np.append(bishops, queens, axis=0):
        # First we check that the piece is even on a diagonal from the king.
        slope = pos-king
        slope = slope / np.max(slope)
        if np.array_equal(np.abs(slope), [1, 1]):
            # Now we have to check that the space between the two is empty.
            for i in range(1, 7):
                cur_pos = king + i * slope
                cur_pos = cur_pos.astype(int)

                if state[cur_pos[0], cur_pos[1]] == 0:
                    continue
                else:
                    break
            # This will execute if the position that caused the for loop to
            # break is the bishop itself, otherwise this does not execute.
            # Or the queen. Same thing.
            if np.array_equal(cur_pos, pos):
                return True

    return False

if __name__ == "__main__":
    board = Board(None, None, None)
    print(str(board))