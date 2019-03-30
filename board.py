import xml.etree.ElementTree as ET
from enum import Enum
from string import ascii_lowercase
from datetime import date
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

        # Reverse piece -> number dictionary
        self.piece_number = {v: k for k, v in self.piece_names.items()}

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
        pawns = self.generate_pawn_moves(color)
        knights = self.generate_knight_moves(color)
        rooks = self.generate_rook_moves(color)
        bishops = self.generate_bishop_moves(color)
        queens = self.generate_queen_moves(color)
        kings = self.generate_king_moves(color)
        castling = self.generate_castle_moves(color)

        total_moves = pawns+knights+rooks+bishops+queens+kings+castling

        return total_moves


    def remove_moves_in_check(self, moves, color):
        # Shortcut for if there's no possible moves being disambiguated.
        if len(moves) == 0:
            return []

        new_moves = []

        # This is for disambiguating
        moves2 = np.asarray(moves)
        unique, counts = np.unique(moves2[...,0], return_counts=True)

        # By using advanced indexing we receive a list of items that appear
        # more than once in the ambiguous case list (the first item of the
        # moves tuples)
        duplicates = unique[counts > 1]

        # M for move, s for state
        # This removes moves where the ending state is in check.
        # Becuase you're not allowed to move into check.
        # This has the double bonus of removing moves that don't get you
        # out of check as well. Neat.
        for m in moves:
            if "O-O" in m or "0-0" in m:
                s = self.castle_algebraic_to_boardstate(m, color)
            else:
                s = self.long_algebraic_to_boardstate(m[1])
            check = is_in_check(s, color)

            # I could remove it from the old list, but doing so while iterating
            # is dangerous. Plus, remove() requires a search, which increases
            # the run time much more than an append.
            if not check:
                if m == "O-O" or m == "O-O-O":
                    new_moves.append(m)
                elif m[0] in duplicates:
                    new_moves.append(m[1])
                else:
                    new_moves.append(m[0])

        return new_moves


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

        pawns = find_piece(state, self.piece_number["P"])

        end_states = []

        # The ending rank for pawn promotions
        endrank = 7 if d == 1 else 0
        for pos in pawns:
            # En Passant first since we can take En Passant if there
            # is a piece directly in front of our pawn.
            # However, requires the pawn on row 5 (from bottom)
            if pos[0] == 4 + d:
                # Don't check en passant on the left if we're on the first file
                # Similarly don't check to the right if we're on the last file
                left_allowed = pos[1] > 0
                right_allowed = pos[1] < 7
                if left_allowed:
                    pawn_on_left = state[pos[0], pos[1] - 1] == -1
                    pawn_moved_two = previous_state[pos[0] + 2*d, pos[1] - 1] == -1
                    if pawn_on_left and pawn_moved_two:
                        end = [pos[0] + d, pos[1] - 1]
                        end_states.append(self.row_column_to_algebraic(pos, end, 1))

                if right_allowed:
                    pawn_on_right = state[pos[0], pos[1] + 1] == -1
                    pawn_moved_two = previous_state[pos[0] + 2*d, pos[1] + 1] == -1
                    if pawn_on_right and pawn_moved_two:
                        end = [pos[0] + d, pos[1] + 1]
                        end_states.append(self.row_column_to_algebraic(pos, end, 1))

            # Makes sure the space in front of us is clear
            if state[pos[0] + d, pos[1]] == 0:
                # Pawn promotion
                # We do this first because pawns have to promote so we can't
                # just "move one forward" in this position
                # (7 - d)%7 = 6 if going down (dir = 1) or 1 (dir = -1)
                if pos[0] + d == endrank:
                    for i in range(2, 6):
                        end = [pos[0] + d, pos[1]]
                        end_states.append(self.row_column_to_algebraic(pos, end, 1, i))
                else:
                    # Add one move forward
                    end = [pos[0] + d,pos[1]]
                    end_states.append(self.row_column_to_algebraic(pos, end, 1))
                # We do the two forward next as an elif
                # (7 + d)%7 = 1 if going down (dir = 1) or 6 (dir = -1)
                if pos[0] == (7 + d) % 7 and state[pos[0] + 2*d, pos[1]] == 0:
                    end = [pos[0] + 2*d,pos[1]]
                    end_states.append(self.row_column_to_algebraic(pos, end, 1))

            # Takes to the left
            if pos[1] - 1 > -1 and state[pos[0] + d, pos[1] - 1] < 0:
                end = [pos[0] + d,pos[1] - 1]

                # Promotion upon taking
                if pos[0] + d == endrank:
                    for i in range(2, 6):
                        end_states.append(self.row_column_to_algebraic(pos, end, 1, i))
                else:
                    end_states.append(self.row_column_to_algebraic(pos, end, 1))

            # Takes to the right
            if pos[1] + 1 < 8 and state[pos[0] + d, pos[1] + 1] < 0:
                end = [pos[0] + d,pos[1] + 1]

                # Promotion upon taking
                if pos[0] + d == endrank:
                    for i in range(2, 6):
                        end_states.append(self.row_column_to_algebraic(pos, end, 1, i))
                else:
                    end_states.append(self.row_column_to_algebraic(pos, end, 1))

        end_states = self.remove_moves_in_check(end_states, color)
        #end_states = self.disambiguate_moves(end_states)
        return end_states


    def generate_knight_moves(self, color):
        # This code was written from white point of view but flipping piece sign
        # allows it to work for black as well.
        mult = 1 if color.value else -1
        state = np.copy(self.current_state * mult)

        knights = find_piece(state, self.piece_number["N"])

        moves = np.asarray([[2, 1], [2, -1], [-2, 1], [-2, -1]])

        end_states = []

        for pos in knights:
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
                    end_states.append(self.row_column_to_algebraic(pos, end1, 3))

                # Second possible knight position
                if cond2:
                    end_states.append(self.row_column_to_algebraic(pos, end2, 3))

        end_states = self.remove_moves_in_check(end_states, color)
        #end_states = self.disambiguate_moves(end_states)
        return end_states


    def generate_rook_moves(self, color):
        # This code was written from white point of view but flipping piece sign
        # allows it to work for black as well.
        mult = 1 if color.value else -1
        state = np.copy(self.current_state * mult)
        rooks = find_piece(state, self.piece_number["R"])

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
                    end_states.append(self.row_column_to_algebraic(pos, end, piece_val))

        end_states = self.remove_moves_in_check(end_states, color)
        #end_states = self.disambiguate_moves(end_states)
        return end_states


    def generate_bishop_moves(self, color):
        mult = 1 if color.value else -1
        state = np.copy(self.current_state * mult)
        bishops = find_piece(state, self.piece_number["B"])

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
                    end_states.append(self.row_column_to_algebraic(pos, end, piece_val))

                    i = i + 1

        end_states = self.remove_moves_in_check(end_states, color)
        #end_states = self.disambiguate_moves(end_states)
        return end_states

    def generate_queen_moves(self, color):
        mult = 1 if color.value else -1
        state = np.copy(self.current_state * mult)
        queens = find_piece(state, self.piece_number["Q"])

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

        # You shouldn't need a loop, because why would you have more than 1
        # king? Just reshape instead
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
                end_states.append(self.row_column_to_algebraic(king, end, 6))

        end_states = self.remove_moves_in_check(end_states, color)
        #end_states = self.disambiguate_moves(end_states)
        return end_states

    def generate_castle_moves(self, color):
        # Hardcoded because you can only castle from starting positions.
        # Basically just need to check that the files between the king and
        # the rook are clear, then return the castling algebraic (O-O or O-O-O)
        end_states = []

        rank = 7 if color.value else 0 # 0 for Black, 7 for White
        kingside = "WKR" if color.value else "BKR"
        if self.castle_dict[kingside] and np.sum(self.current_state[rank, 5:7])== 0:
            end_states.append("O-O")

        queenside = "WQR" if color.value else "BQR"
        if self.castle_dict[queenside] and np.sum(self.current_state[rank, 1:4])== 0:
            end_states.append("O-O-O")

        end_states = self.remove_moves_in_check(end_states, color)
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
        legal = self.check_move_legality(move)
        if not legal[0]:
            raise ValueError("You tried to make an illegal move!")
            return

        # Since queenside is the same as kingside with an extra -O on the end
        # we can just check that the kingside move is in the move.
        castle_move = "O-O" in legal[1] or "0-0" in legal[1]

        if castle_move:
            new_state = self.castle_algebraic_to_boardstate(legal[1])
        else:
            new_state = self.long_algebraic_to_boardstate(legal[1])
        self.game_states.append(np.copy(self.current_state))

        self.current_state = np.copy(new_state)

        piece = ""
        for i, c in enumerate(move):
            # If we have an = then this is the piece the pawn promotes to.
            # Pawns can promote to rooks which would fubar the dict.
            if c.isupper() and not "=" in move:
                piece = c

        # Updates the castle dict for castling rights.
        if piece == "K" or castle_move:
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

        # The earliest possible checkmate is after 4 plies. No reason
        # to check if it's check earlier than that.
        if len(self.move_list) > 3:
            # If there are no moves that get us out of check we need to see if
            # we're in check right now.
            # If we are that's check mate. If we're not... that's a stalemate.
            color = Color.BLACK if self.to_move.value else Color.WHITE
            responses = self.generate_moves(color)
            if len(responses) == 0:
                check = is_in_check(self.current_state, color)
                if check:
                    if self.to_move == Color.WHITE:
                        self.status = Status.WHITE_VICTORY
                    else:
                        self.status = Status.BLACK_VICTORY
                else:
                    self.status = Status.DRAW

        self.to_move = Color.BLACK if self.to_move.value else Color.WHITE
        self.move_list.append(move)


    def unmake_move(self):
        self.current_state = np.copy(self.game_states.pop(-1))
        self.move_list.pop(-1) # Take the last move off the move list as well.


    def check_move_legality(self, move):
        long_move = self.short_algebraic_to_long_algebraic(move)
        if long_move is None:
            return (False, move)

        if "O-O" in long_move or "0-0" in long_move:
            end_state = self.castle_algebraic_to_boardstate(long_move)
        else:
            end_state = self.long_algebraic_to_boardstate(long_move)

        check  = is_in_check(end_state, self.to_move)
        if check:
            return (False, move)
        return (True, long_move)


    def short_algebraic_to_long_algebraic(self, move):
        # A move is minimum two characters (a rank and a file for pawns)
        # So if it's shorter it's not a good move.
        if len(move) < 2:
            return None
        # Castling is the easiest to check for legality.
        # Kingside castling
        if move == "O-O" or move == "0-0":
            check = "WKR" if self.to_move.value else "BKR"
            rank = 7 if self.to_move.value else 0
            if self.castle_dict[check] and np.sum(self.current_state[rank, 5:7])== 0:
                return move
            else:
                return None
        # Queenside castling
        elif move == "O-O-O" or move == "0-0-0":
            check = "WQR" if self.to_move.value else "BQR"
            rank = 7 if self.to_move.value else 0
            # Need to make sure this is allowed
            if self.castle_dict[check] and np.sum(self.current_state[rank, 1:4])== 0:
                return move
            else:
                return None

        ranks = []
        files = []
        piece = "P"
        promotion_piece = "P"
        # This block exists to ensure that more than two locations haven't
        # been passed in.
        # If more than one was passed we use it for disambiguation
        try:
            for i, c in enumerate(move):
                # Appends a found [rank] character
                if c.islower():
                    # We use a lower case x for taking so I have to exclude it.
                    if not c == "x":
                        files.append(c)
                # A [file] character
                if c.isdigit():
                    ranks.append(c)
                # A [piece] character
                # If we have an = then this is the piece the pawn promotes to
                # So we want to ignore that.
                if c.isupper() and not "=" in move:
                    piece = c
                if c.isupper() and "=" in move:
                    promotion_piece = c
        except(IndexError):
            return None

        # Easy way to check if you input a capital letter that's not a piece.
        if not piece in "PRNQKB":
            return None

        # This regex extracts all the locations in the move.
        locs = re.findall("[a-h]\d+", move)

        # Ensures your move stays within the 8 ranks of the board.
        for pos in locs:
            if int(pos[1:]) > 8:
                return None

        dest = locs[-1]
        endfile = ascii_lowercase.index(dest[0]) # End File = x
        endrank = 8 - int(dest[1]) # End Rank = y
        end = [endrank, endfile]

        if len(locs) == 0 or len(locs) >= 3:
            return None

        mult = 1 if self.to_move.value else -1
        piece_num = self.piece_number[piece] * mult
        promotion_piece = self.piece_number[promotion_piece] * mult
        pieces = find_piece(self.current_state, piece_num)

        # If we have any sort of disambiguation use that as our starting point.
        # This allows us to trim the pieces we search through and find the
        # correct correct one rather than the "first one allowed to make this
        # move."
        start = [None, None]
        if len(locs) == 2:
            dest = locs[0]
            startfile = ascii_lowercase.index(dest[0]) # File = x
            startrank = 8 - int(dest[1]) # Rank = y
            start = [startrank, startfile]
        elif len(files) == 2:
            startfile = ascii_lowercase.index(files[0])
            start[1] = startfile
        elif len(ranks) == 2:
            startrank = 8 - int(ranks[0])
            start[0] = startrank

        good = []
        if not np.array_equal(start, [None, None]):
            for p in pieces:
                if start[0] is None and p[1] == start[1]:
                    good.append(p)
                elif start[1] is None and p[0] == start[0]:
                    good.append(p)
                elif np.array_equal(p, start):
                    good.append(p)

            pieces = good

        # Direction opposite that which the color's pawns move.
        # So 1 is downwards, opposite White's pawns going upwards.
        d = -1 if self.to_move.value else 1

        # The starting file for the pawn row, for double move checking
        pawn_start = 6 if self.to_move.value else 1

        # The ending rank for pawn promotion
        pawn_end = 0 if self.to_move.value else 7
        # Tried to put these in some sort of likelihood order.

        mult = 1 if self.to_move.value else -1
        state = np.copy(self.current_state * mult)

        # This handy line of code prevents you from taking your own pieces.
        if state[end[0], end[1]] > 0:
            return None
        if piece == "P":
            if end[0] == pawn_end and not "=" in move:
                return None
            for pawn in pieces:
                # First check where the ending position is empty
                # Second condition is that the pawn is on the same rank
                if state[end[0], end[1]] == 0 and pawn[1] == end[1]:
                    promotion = end[0] == pawn_end
                    if pawn[0] + d == end[0]:
                        if promotion:
                            return self.row_column_to_algebraic(pawn, end, piece_num, promotion_piece)[1]
                        return self.row_column_to_algebraic(pawn, end, piece_num)[1]

                    # Need to check the space between one move and two is empty.
                    empty = self.current_state[pawn[0] + d, end[1]] == 0
                    if pawn[0] + 2*d == end[0] and pawn[0] == pawn_start and empty:
                        return self.row_column_to_algebraic(pawn, end, piece_num)[1]
                if state[end[0], end[1]] < 0:
                    take_left = pawn[0] + d == end[0] and pawn[1] - 1 == end[1]
                    take_right = pawn[0] + d == end[0] and pawn[1] + 1 == end[1]
                    promotion = end[0] == pawn_end
                    if take_left or take_right:
                        if promotion:
                            return self.row_column_to_algebraic(pawn, end, piece_num, promotion_piece)[1]
                        return self.row_column_to_algebraic(pawn, end, piece_num)[1]

        elif piece == "N":
            for knight in pieces:
                slope = np.abs(knight - end)

                # Avoids a divide by 0 error. If it's on the same rank or file
                # it's illegal anyway.
                if slope[1] == 0 or slope[0] == 0:
                    continue
                if np.array_equal(slope, [1, 2]) or np.array_equal(slope, [2, 1]):
                    return self.row_column_to_algebraic(knight, end, piece_num)[1]
            # Return None if we make it through all the knights without
            # a legal move.
            return None
        elif piece == "R" or  piece == "Q":
            for rook in pieces:
                # Rooks on the same rank
                if rook[0] == end[0]:
                    # Checks that the range between the rook and the ending
                    # is empty so the rook can actually slide there.
                    if rook[1] > end[1]:
                        f = state[end[0], end[1] + 1:rook[1]]
                    if rook[1] < end[1]:
                        f = state[end[0], rook[1] + 1:end[1]]
                    # This avoids same pieces of opposite color canceling
                    f = f != 0
                    if np.sum(f) == 0:
                        return self.row_column_to_algebraic(rook, end, piece_num)[1]
                # Rooks on the same file
                elif rook[1] == end[1]:
                    if rook[0] > end[0]:
                        f = state[end[0] + 1:rook[0], end[1]]
                    if rook[0] < end[0]:
                        f = state[rook[0] + 1:end[0], end[1]]
                    f = f != 0
                    if np.sum(f) == 0:
                        return self.row_column_to_algebraic(rook, end, piece_num)[1]
            # If we make it through all the rooks and didn't find one that has
            # a straight shot to the end then there isn't a good move.
            # However we only do this if we entered this block as a Rook
            # Since queens can still go diagonal.
            if piece == "R":
                return None
        if piece == "B" or piece == "Q":
            for bishop in pieces:
                # First we check that the piece is even on a diagonal
                slope = end-bishop
                slope = slope / np.max(np.abs(slope))
                if np.array_equal(np.abs(slope), [1, 1]):
                    # Now we have to check that the space is empty
                    for i in range(1, 8):
                        cur_pos = bishop + i * slope
                        cur_pos = cur_pos.astype(int)

                        if np.array_equal(cur_pos, end):
                            break
                        elif self.current_state[cur_pos[0], cur_pos[1]] == 0:
                            continue
                        else:
                            break
                    # This will execute if the position that caused the break
                    # is the ending position, otherwise this does not execute.
                    # Or the queen. Same thing.
                    if np.array_equal(cur_pos, end):
                        return self.row_column_to_algebraic(bishop, end, piece_num)[1]
            # Return None if we make it through all the bishops and queens
            # without a legal move.
            return None
        if piece == "K":
            for king in pieces:
                diff = np.abs(king - end)
                # Need to check either diagonal ([1,1]) or straight (sum = 1)
                if np.sum(diff) == 1 or np.array_equal(diff, [1, 1]):
                    return self.row_column_to_algebraic(king, end, piece_num)[1]

        return None


    def castle_algebraic_to_boardstate(self, move, color=None):
        if color is None:
            color = self.to_move
        # This puts in a piece at the given location using np.ndarray.itemset
        # This is marginally faster than new_state[pos[0], pos[1]] = piece.
        # Saves about .5ms on average.
        new_state = np.copy(self.current_state)
        place = new_state.itemset

        # Kingside castling
        if move == "O-O" or move == "0-0":
            rank = 7 if color.value else 0
            place((rank, 7), 0)
            place((rank, 4), 0)
            place((rank, 6), self.piece_number["K"])
            place((rank, 5), self.piece_number["R"])
            return new_state
        # Queenside castling
        elif move == "O-O-O" or move == "0-0-0":
            rank = 7 if color.value else 0
            place((rank, 0), 0)
            place((rank, 4), 0)
            place((rank, 2), self.piece_number["K"])
            place((rank, 3), self.piece_number["R"])
            return new_state


    def long_algebraic_to_boardstate(self, move):

        # This puts in a piece at the given location using np.ndarray.itemset
        # This is marginally faster than new_state[pos[0], pos[1]] = piece.
        # Saves about .5ms on average.
        new_state = np.copy(self.current_state)
        place = new_state.itemset

        piece = "P" # Default to pawn, this generally is changed.
        for i, c in enumerate(move):
            # A [piece] character
            # If we have an = then this is the piece the pawn promotes to.
            if c.isupper():
                piece = c

        locs = re.findall("[a-h]\d+", move)

        # Always true, no matter how long locs is at this point (1 or 2)
        # If it's one then that's just the destination
        # If it's two then the first is the start, and the second is the end.
        dest = locs[-1]
        endfile = ascii_lowercase.index(dest[0]) # End File = x
        endrank = 8 - int(dest[1]) # End Rank = y
        end = [endrank, endfile]

        # We know that this is long_algebraic so we can find the start
        # as well from the move.
        dest = locs[0]
        startfile = ascii_lowercase.index(dest[0]) # End File = x
        startrank = 8 - int(dest[1]) # End Rank = y
        start = [startrank, startfile]

        # Gets the value of the piece
        end_piece = self.current_state[start[0], start[1]]

        # In case of promotions we want the pice to change upon moving.
        if "=" in move:
            end_piece = self.piece_number[piece] * np.sign(end_piece)

        place((start[0], start[1]), 0)
        place((end[0], end[1]), end_piece)
        return new_state

        state = np.copy(self.current_state * mult)

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


    def row_column_to_algebraic(self, start, end, piece, promotion=None):
        # Alg2 fully disambiguates
        alg1 = []
        alg2 = []

        # Don't need to append pawn name
        if np.abs(piece) > 1:
            alg1.append(self.piece_names[np.abs(piece)]) # Piece Name
            alg2.append(self.piece_names[np.abs(piece)])

        # Since alg 2 fully disambiguates we append file and rank to it to start.
        alg2.append(ascii_lowercase[start[1]]) # File = x
        alg2.append(str(8 - start[0])) # Rank = y

        if not self.current_state[end[0], end[1]] == 0:
            # On pawn capures alg notation requires including the starting file.
            if piece == 1:
                alg1.append(ascii_lowercase[start[1]])
            alg1.append("x")
            alg2.append("x")

        # We here append the ending position to the move.
        alg1.append(ascii_lowercase[end[1]]) # End File = x
        alg1.append(str(8 - end[0])) # End Rank = y

        alg2.append(ascii_lowercase[end[1]]) # End File = x
        alg2.append(str(8 - end[0])) # End Rank = y

        if promotion:
            alg1.append("=")
            alg1.append(self.piece_names[np.abs(promotion)])

            alg2.append("=")
            alg2.append(self.piece_names[np.abs(promotion)])

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


def load_pgn(name, loc="games"):
    # In case you pass the name without .pgn at the end.
    if not name.endswith(".pgn"):
        name = name + ".pgn"

    loc = os.path.join(loc, name)
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
    headers = board.headers

    # This checks if the headers is empty since we initialize to empty dicts.
    empty = not headers
    no_moves = moves is None

    if not empty:
        name = headers["White"] + "vs" + headers["Black"] + headers["Date"] + ".pgn"
    else:
        name = "???vs???" + str(date.today()) + ".pgn"
    loc = "results/"

    if not os.path.exists(loc):
        os.makedirs(loc)

    # This actually writes everything to the file.
    with open(os.path.join(loc, name), "w") as f:
        if not empty:
            for k, v in headers.items():
                line = "[" + k + " " + "\"" + v + "\"" + "]\n"
                f.write(line)

        # Inserts a blank line between the headers and the move line.
        f.write("\n")
        if not no_moves:
            for i, m in enumerate(moves):
                line = str(m) + " "
                if i % 2 == 0:
                    move_num = int(i / 2 + 1)
                    line = str(move_num) + ". " + line

                f.write(line)

        # Writes the result at the end of the PGN or * for ongoing game.
        if not empty and "Result" in headers:
            f.write(headers["Result"])
        else:
            f.write("*")

    return name


def is_in_check(state, color):
    # The direction a pawn must travel to take this color's king.
    # I.e. Black pawns must travel in the positive y (downward) direction
    # To take a white king.
    d = 1 if color.value else -1

    mult = 1 if color.value else -1

    # You shouldn't need a loop, because why would you have more than 1 king?
    # Just reshape instead
    king = find_piece(state*mult, 6).reshape(2)

    # Check pawns first because they're the easiest.
    pawn = -1 if color.value else 1

    # Need to ensure that the king is on any rank but the last one.
    # No pawns can put you in check in the last rank anyway.
    if 0 <= king[0] - d < 8:
        if king[1] - 1 >= 0 and state[king[0] - d, king[1] - 1] == pawn:
            return True
        elif king[1] + 1 < 8 and state[king[0] - d, king[1] + 1] == pawn:
            return True

    # Checks if you'd be in check from the opposite king.
    # This should only trigger on you moving your king into that position.
    opposite_king = -6 if color.value else 6
    opposite_loc = find_piece(state, opposite_king).reshape(2)
    diff = np.abs(opposite_loc - king)
    # If the other king is vertical or horizontal the sum will be 1
    # Since it is [0,1] or [1,0]
    # If it is diagonal diff will be  [1, 1]
    if np.sum(diff) == 1 or np.array_equal(diff, [1, 1]):
        return True

    mult = -1 * mult
    rooks = find_piece(state*mult, 2)
    queens = find_piece(state*mult, 5)
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
            # This avoids pieces of the same type but opposite color canceling
            f = f != 0
            if np.sum(f) == 0:
                return True
        elif pos[1] == king[1]:
            if pos[0] < king[0]:
                f = state[pos[0] + 1:king[0], king[1]]
            else:
                f = state[king[0] + 1:pos[0], king[1]]
            f = f != 0
            if np.sum(f) == 0:
                return True

    # Knights can hop which is why I'm doing them before bishops
    knights = find_piece(state*mult, 3)

    for pos in knights:
        slope = np.abs(pos-king)

        # Avoids a divide by 0 error. If it's on the same rank or file
        # the knight can't get the king anyway.
        if slope[1] == 0 or slope[0] == 0:
            continue
        if np.array_equal(slope, [1, 2]) or np.array_equal(slope, [2, 1]):
            return True

    # Now bishops and diagonal queens, I guess
    bishops = find_piece(state*mult, 4)

    for pos in np.append(bishops, queens, axis=0):
        # First we check that the piece is even on a diagonal from the king.
        slope = pos-king
        slope = slope / np.max(np.abs(slope))
        if np.array_equal(np.abs(slope), [1, 1]):
            # Now we have to check that the space between the two is empty.
            for i in range(1, 8):
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


# Quickly finds all the locations of given piece in state.
def find_piece(state, piece):
    x, y = np.where(state==piece)
    x = x.reshape(len(x), 1)
    y = y.reshape(len(y), 1)
    return np.append(x, y, axis=1)


if __name__ == "__main__":
    b = load_pgn("anderssen_kieseritzky_1851.pgn")
    save_pgn(b)