#!/usr/bin/env python3

import sys
from datetime import date
import time
import logging
import os

import board
import engine
import uci


# Containing the UCI code to its own method for readability.
def run_uci():
    # A parser for the Universal Chess Interface.
    interpreter = uci.UCI()

    interpreter.identify()

    # Technically the engine is supposed to keep running after the game ends
    # for analysis. I think.
    while True:
        # Waits for an input command and then parses it through the uci
        # interpreter.
        cmd = input()
        try:
            # Logs the command.
            logging.debug("Input: " + cmd)

            interpreter.decrypt_uci(cmd)
        except Exception as e:
            logging.error(e)
            raise e


# Runs the command line interface instead.
def run_cli():
    name = input("What's your name?")

    headers = {}

    headers["White"] = name
    headers["Black"] = "Chrysaora 0.002"
    headers["Date"] = str(date.today())

    current_board = board.Board(None, None, None, headers=headers)
    ai = engine.Engine(current_board)
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

if __name__ == "__main__":
    # Gets the input command for how the engine should play.
    # If we recieve "uci" as a command then we need to engage in uci mode.
    cmd = input()

    # Initiliazes the log.
    log_folder = os.path.join(os.path.dirname(__file__), "logs")
    if not os.path.exists(log_folder):
        os.makedirs(log_folder)

    log_name = os.path.join(log_folder, str(time.time()) + ".log")

    logging.basicConfig(filename=log_name, level=logging.DEBUG)
    logging.debug(cmd)

    if cmd == "uci":
        run_uci()
    else:
        print("Defaulting to Command Line Interface")
        run_cli()

