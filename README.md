# Chrysaora
Chrysaora may very well be the first serious attempt to build a world class chess engine in Nim.

Chrysaora started as an attempt to use supervised learning and a small image classification styled network to play chess using Python. The results of this experiment are stored in [chrysaora_py](https://github.com/dylanagreen/chrysaora_py). The project has now shifted to building an experimental "hybrid" chess engine. This hybrid will have an evaluation function that consists of two parts:

- A reinforcement learning trained neural network
- A handcrafted element, used for quiescence searching and depth-1 move ordering.

Or at least, that's the plan...

### Naming
Chrysaora is named after the genus of jellyfish, which in turn is named after Chrysaor, a being from Greek mythology. Chrysaor roughly translates as "he who has a golden armament." Major releases of Chrysaora are codenamed after types of
jellyfish.

## Support
Chrysaora will be supported until I get my PhD (in Physics), it wins a season of the TCEC, or Nim dies, whichever comes first.

## Dependencies
Deep learning is done using [arraymancer](https://github.com/mratsim/Arraymancer), which is the only dependency outside the Nim standard library.

### Building
Chrysaora requires a minimum Nim version of 0.20.0. With Nim (and arraymancer) installed, building Chrysaora is as simple as:

```
nim c -d:danger -o:chrysaora src/main.nim
```

### Training
To train Chrysaora, put a selection of games in PGN format into a folder in the chrysaora directory named
`games/train`. Two positions (at one third and two thirds of the way through the game) will be used for training.
Chrysaora will self play for 4 plies from these two positions, and then apply TDLeaf(lambda) to update its weights.

To train, compile and run `src/train.nim`:

```
nim c -d:danger -o:chrysaora-train --run src/train.nim
```

Chrysaora has the ability to bootstrap its training process using its internal handcrafted evaluation function.
To do this, a different selection of two random positions from the input training games will be used and labeled
according to the handcrafted evaluation. These two positions will also be color flipped, giving a total of four
positions from each game. 20 training epochs of supervised learning (using MSE loss) will train the
network to play like the handcrafted evaluation. This speeds training to a high playing level as it allows the network to
start near a good minimum, however the network can be trained from scratch without this feature.
This feature is enabled by default.

In the future I plan to allow bootstrapping to be selectively enable with a command
line switch:

```
nim c -d:danger -o:chrysaora-train --run src/train.nim --bootstrap
```

In the future I further plan to allow a command line switch to pass in a weights
file to start training from, allowing continual start/stop training. This update
will likely be coupled with the one that will save periodic snapshots of the network.

```
nim c -d:danger -o:chrysaora-train --run src/train.nim --input:weights.txt
```

## Features
- Move Generation
  - Fancy Magic Bitboards
  - Redundant Mailbox representation
- Hand Crafted Evaluation
  - Centipawn piece imbalance
  - Piece-square tables
- Network Evaluation: 75 input features
  - Number of each piece (10 features)
  - Side to move (1 feature)
  - Square position and piece existence (64 features)
  - More in depth network details can be found in the Chrysora Wiki
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
- [Carrasius](https://github.com/dyth/Carassius), because it was the first coding implementation of TDLeaf(lambda) that I actually understood

Additionally I'd like to thank the Chess Programming Wiki for its help in getting the project started.

## Why a hybrid?

Neural Network based chess engines seem to be the "new era" in computer chess, especially so since Lc0 just
won the superfinal in S15 of the TCEC. However, NN based engines come with their own set of problems. The general width
and size of the NN required to play chess at the level that LC0 plays at is massive, explaining a major part of why NN
based engines tend to be so much slower than traditional hand crafted engines. Consider that if Lc0 could achieve the nps
that Stockfish does it would be, in my opinion, unbeatable.

By hybridizing a NN with a handcrafted evaluation function, I hope to achieve similar playing performance to top level engines with a much narrower network structure. The much narrower network should compute faster, and if my coding and optimization prowess is up to the task, achieve a potentially higher nodes per second.

On the other hand it could blow up in my face. So far it's just blown up in my face.

### My Hybridization
My network-handcrafted evaluation hybridization consists mostly in using a handcrafted eval where the robustness of a
full neural network isn't required. In nearly every case except for extremely contrived examples a handcrafted eval will
be faster than a network.

Chrysaora uses a handcrafted evaluation to order the moves at depth 1 in the iterative deepening framework. Quiesence
searching is also done with the handcrafted evaluation. Quiesence searching is essential to ensure our search tree
doesn't end in a "noisy" move. By using a handcrafted evaluation for this, I hope to speed the high depth probes of
Chrysaora to be fast enough that in the same amount of time a neural network quiesence search is completed I can search
to an additional depth with a handcrafted quiesence.

Additionally, unlike most (if not all?) highly competitive NN engines, Chrysaora uses an alpha-beta pruned minimax
search rather than a Monte Carlo Tree Search. In this way I've hybridized a NN and a classical engine.

## License
You can find the details of Chrysaora's license in the LICENSE.txt file. Chrysaora is licensed under GPL-3.

