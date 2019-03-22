import xml.etree.ElementTree as ET

import numpy as np
from IPython.display import SVG
from enum import Enum


# Enum for white or black.
class Color(Enum):
    WHITE = True
    BLACK = False
    

class Board():
    """The board state.
    
    state = the current board state
    
    """
    
    def __init__(self, state):
        
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
        self.previous_state = None
        
    #def generate_moves(color):
     #   """Generate all possible moves for a given color
      #  """

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

                # This adds to the condition that the end square must not be occupied by a piece of the same
                # color. Since white is always >0 we require the end square to be empty (==0) or occupied
                # by black (<0)
                cond1 = cond1 and s1[end1[0], end1[1]] <= 0
                cond2 = cond2 and s1[end2[0], end2[1]] <= 0

                # The following code blocks only run if the ending positions are actually on the board.
                # The first knight position, sets the old one to empty (0) then sets the new space.
                if cond1:
                    s1 = np.copy(state)
                    s1[pos[0], pos[1]] = 0
                    s1[end1[0], end1[1]] = 3
                    end_states.append(np.copy(s1 * mult))

                # Second possible knight position
                if cond2:
                    s1 = np.copy(state)
                    s1[pos[0], pos[1]] = 0
                    s1[end2[0], end2[1]] = 3
                    end_states.append(np.copy(s1 * mult))

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
            # This slices out the array from the rook towards the edge of the board.
            # Need to reverse the leftward and upward directions so they go "out"
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

                    s1 = np.copy(state)
                    s1[pos[0], pos[1]] = 0

                    # This was an embarrasing bug to correct.
                    if key == 'r' or key == 'l':
                        s1[pos[0], pos[1] + (i * sign)] = piece_val
                    else:
                        s1[pos[0] + (i * sign), pos[1]] = piece_val
                    end_states.append(np.copy(s1 * mult))

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

                    end = pos + i*val

                    # We get blocked if we hit a piece of the opposite color
                    # And by one of this color, but we break if we do that since we can't 
                    # take our own color.
                    if state[end[0], end[1]] < 0:
                        blocked = True
                    elif state[end[0], end[1]] > 0:
                        break

                    # This puts the piece in its new place
                    s1 = np.copy(state)
                    s1[pos[0], pos[1]] = 0
                    s1[end[0], end[1]] = piece_val

                    end_states.append(np.copy(s1 * mult))

                    i = i + 1

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

    
    def generate_king_moves(color):
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
                s1 = np.copy(state)

                # Can't take our own pieces, so don't add it as a board pos
                if s1[end[0], end[1]] > 0:
                    continue

                s1[king[0], king[1]] = 0
                s1[end[0], end[1]] = 6
                end_states.append(np.copy(s1 * mult))

        return end_states


    def get_board_svg(self):
        # Parses the board in first as a background.
        tree = ET.ElementTree()
        tree.parse("pieces/board.svg")
        composite = tree.getroot()

        # Dict containing a conversion between the piece number and the piece name.
        piece_names = {1:"wp", 2:"wr", 3:"wkn", 4:"wb", 5:"wq", 6:"wk",
                       -1:"bp", -2:"br", -3:"bkn", -4:"bb", -5:"bq", -6:"bk"}

        # Numpy iterator that gives us the position as well as the piece number
        it = np.nditer(self.current_state, flags=['multi_index'])

        while not it.finished:
            pos = it.multi_index
            piece = it[0]

            # 0 is an empty space so we increment the iterator and skip the rest.
            if piece == 0:
                it.iternext()
                continue

            # Parses the raw piece svg file into XML
            tree.parse("pieces/" + piece_names[int(piece)] + ".svg")
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