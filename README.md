# Chrysaora
Chrysaora may very well be the first serious attempt to build a world class chess engine in Nim.

Chrysaora started as an attempt to use supervised learning and a small image classification styled network to play chess using Python. The results of this experiment are stored in [chrysaora_py](https://github.com/dylanagreen/chrysaora_py). The project has now shifted to building an experimental "hybrid" chess engine. This hybrid will have an evaluation function that consists of two parts:

- A reinforcement learning trained neural network
- A handcrafted element, used for quiescence searching and depth-1 move ordering.

At present I see a few ways to integrate the two, none of which I have settled on yet. 

## Support
Chrysaora will be supported until I get my PhD (in Physics), it wins a season of the TCEC, or Nim dies, whichever comes first.

## Naming
Chrysaora is named after the genus of jellyfish, which in turn is named after Chrysaor, a being from Greek mythology. Chrysaor roughly translates as "he who has a golden armament."

## Dependencies
Deep learning is done using [arraymancer](https://github.com/mratsim/Arraymancer), which is the only dependency outside the Nim standard library.

### Building
Chrysaora requires a minimum Nim version of 0.20.0. With Nim (and arraymancer) installed, building Chrysaora is as simple as:

```
nim c -d:danger src/main.nim
```

## Features
- Move Generation
  - Fancy Magic Bitboards
  - Redundant Mailbox representation
- Hand Crafted Evaluation
  - Centipawn piece imbalance
  - Piece-square tables
- Search
  - Fail-hard alpha-beta pruning minimax
  - Zobrist hashing indexed transposition tables
  - Iterative Deepening

### Acknowledgements
I'd like to say a very special thank you to the following engines, which I consulted during the coding of Chrysaora:
- [Ethereal](https://github.com/AndyGrant/Ethereal), for help with understanding bitboards
- [Laser](https://github.com/jeffreyan11/laser-chess-engine), for the idea of recording the ep target square between moves
- [Stockfish](https://github.com/official-stockfish/Stockfish), for help understanding magic number generation
- [Lc0](https://github.com/LeelaChessZero/lc0), for paving the way for NN engines
- [Giraffe](https://github.com/ianfab/Giraffe), for providing the network structure for Chrysaora

Additionally I'd like to thank the Chess Programming Wiki for its help in getting the project started.

## Why a hybrid?

Neural Network based chess engines seem to be the "new era" so to speak in computer chess, especially so since Lc0 just won the superfinal in S15 of the TCEC. NN based engines come with their own set of problems, however. The general width and size of the NN required to play chess at the level that LC0 plays at is massive, explaining a major part of why NN based engines tend to be so much slower than traditional hand crafted engines. Consider that if Lc0 could achieve the nps that Stockfish does it would be, in my opinion, unbeatable.

By hybridizing a NN with a handcrafted evaluation function, I hope to achieve similar playing performance to top level engines with a much narrower network structure. The much narrower network should compute faster, and if my coding and optimization prowess is up to the task, achieve a potentially higher nodes per second.

On the other hand it could blow up in my face.

## Licenses
You can find the details of Chrysaora's license in the LICENSE.txt file. Chrysaora is licensed under GPL-3.

