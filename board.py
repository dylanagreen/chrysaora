import xml.etree.ElementTree as ET

import numpy as np
from IPython.display import SVG

class Board():
    """The board state.
    
    state = the current board state
    
    """
    
    def __init__(self, state, color):
        
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
        self.color = color
        self.previous_state = None
        
    #def generate_moves(color):
     #   """Generate all possible moves for a given color
      #  """

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