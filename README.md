# Chrysaora
Chrysaora may very well be the first serious attempt to build a world class chess engine in Nim.

Chrysaora started as an attempt to use supervised learning and a small image classification styled network to play chess using Python. The results of this experiment are stored in [chrysaora_py](https://github.com/dylanagreen/chrysaora_py). The project has now shifted to building an experimental "hybrid" chess engine. This hybrid will have an evaluation function that consists of two parts:

- A reinforcement learning trained neural network
- A handcrafted element, used for quiescence searching and depth-1 move ordering.

Or at least, that's the plan...

The work on chrysaora is hevily inspired and based by the [Giraffe](https://arxiv.org/pdf/1509.01549.pdf) and [KnightCap](https://arxiv.org/pdf/cs/9901001.pdf) papers, both of which I consulted liberally while writing the engine. Most of my training code only came together after really understanding Knightcap.

### Naming
Chrysaora is named after the genus of jellyfish, which in turn is named after Chrysaor, a being from Greek mythology. Chrysaor roughly translates as "he who has a golden armament." Major releases of Chrysaora are codenamed after other genus or species of jellyfish, typically things I find cool.

For some reason I use female pronouns when referrring to Chrysaora in my head, but I can't imagine she particularly cares considering she's a nonsentient chess engine.

- v0.1.0 **Noctiluca** - Named after a bioluminescent jellyfish as a bioluminescent algae bloom occured while I was coding it. Everyone was quarantined so I coded Chrysaora instead of going to see it. Sad.

## Support
Chrysaora will be supported until I get my PhD (in Physics), it wins a season of the TCEC, or Nim dies, whichever comes first.

## Dependencies
Deep learning is done using [arraymancer](https://github.com/mratsim/Arraymancer), which is the only dependency outside the Nim standard library.

### Building
Chrysaora requires a minimum Nim version of 1.20.0. With Nim (and arraymancer) installed, building Chrysaora is as simple as:

```
nim c -d:danger -o:chrysaora src/main.nim
```

### Training
In order to train Chrysaora, you must build a version with the training code implemented. Currently all versions of Chrysaora build with training built in, although in the future this will be an option that must be enabled. Chrysaora learns by playing chess games against an opponent. It is possible to self train Chrysaora by pitting two engine instances against each other, but the weight updates of one engine will overwite the other.

Currently Chrysaora will train by setting the in game uci option to true. This is done by running the following after loading an instance of Chrysaora but before telling her to find a move:
```
setoption name Train value true
```

If you use cutechess-cli to run Chrysaora against another engine to train against, you must add `option.Train=true` to Chrysaora's command in order for training mode to be turned on.

While training, Chrysaora will keep a running record of its internal evaluations as well as the gradients used to calculate these evaluations for each of its own color board states. I.e. if Chrysaora is playing white, then it will store evaluations and gradients for all white moves in the game (as these are the moves that Chrysaora herself makes.)

At the end of the game Chrysaora will use the TDleaf(lambda) update rules to update the internal weights based on the game performance. This is done when either `ucinewgame` or `quit` is passed to Chrysaora. Chrysaora will save the weights only upon exit.

## Features
- Move Generation
  - Fancy Magic Bitboards
  - Redundant Mailbox representation
- Hand Crafted Evaluation
  - Centipawn piece imbalance
  - Piece-square tables
- Network Evaluation: 111 input features
  - Number of each piece (10 features)
  - Side to move (1 feature)
  - Castling rights (4 features)
  - Square position (64 features)
  - Piece existence (32 features)i
- Search
  - Fail-hard alpha-beta pruning minimax
  - Zobrist hashing indexed transposition tables
  - Iterative deepening

## Planned Features
- Ability to build non-training versions of Chrysaora
- Automatic saving of weights after a set number of games
- Self training

### Acknowledgements
I'd like to say a very special thank you to the following engines, which I consulted during the coding of Chrysaora:
- [Ethereal](https://github.com/AndyGrant/Ethereal), for help with understanding bitboards, as well as their magic numbers
- [Laser](https://github.com/jeffreyan11/laser-chess-engine), for the idea of recording the ep target square between moves
- [Stockfish](https://github.com/official-stockfish/Stockfish), for help understanding magic number generation
- [Lc0](https://github.com/LeelaChessZero/lc0), for paving the way for NN engines
- [Giraffe](https://github.com/ianfab/Giraffe), for providing the initial network structures for Chrysaora

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
search rather than a Monte Carlo Tree Search.

## License
You can find the details of Chrysaora's license in the LICENSE.txt file. Chrysaora is licensed under GPL-3.

