import random
from datetime import date

import board
import engine

if __name__ == "__main__":

    name = input("What's your name?\n")

    headers = {}
    headers["White"] = name
    headers["Black"] = "Chrysaora 0.001"
    headers["Date"] = str(date.today())

    current_board = board.Board(None, None, None, headers=headers)

    user = board.Color.WHITE

    ai = engine.Engine(board.Color.BLACK, current_board)

    print(str(current_board))
    print("You play as white.")
    # Basically while not checkmate or stalemate.
    while current_board.status == board.Status.IN_PROGRESS:
        try:
            m = input("Make a move: ")

            if m == "exit" or m == "quit":
                board.save_pgn(current_board)
                break

            current_board.make_move(m)

            print(str(current_board))
            m = ai.find_move()

            print("AI response: " + str(m))

            current_board.make_move(m)

            print(str(current_board))

        except(ValueError):
            print("Illegal move attempted")
            print("Saving board pgn.")
            board.save_pgn(current_board)
            break

