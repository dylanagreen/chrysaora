import xml.etree.ElementTree as ET

import numpy as np
from IPython.display import SVG

class Board():
    """The board state.
    
    state = the current board state
    
    """
    
    def __init__(self, state, is_white):
        
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
        self.is_white = is_white
        self.previous_state = None
        
    #def generate_moves(color):
     #   """Generate all possible moves for a given color
      #  """

    def generate_knight_moves(is_white):
        # This code was written from white point of view but flipping piece sign
        # allows it to work for black as well.
        mult = 1 if is_white else -1
        state = np.copy(self.current_state * mult) 

        # This is quick code for finding the position of all knights.
        x, y = np.where(state==3)
        x = x.reshape(len(x), 1)
        y = y.reshape(len(y), 1)

        knight_locs = np.append(x,y,axis=1)
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


    def display_board():
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
        return SVG(ET.tostring(board))