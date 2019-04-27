# Chrysaora

Chrysaora may very well be the first serious attempt to build a world class chess engine in Nim.

Chrysaora started as an attempt to use supervised learning and a small image classification styled network to play chess using Python. The results of this experiment are stored in chrysaora_py. The project has now shifted to building an experimental "hybrid" chess engine. This hybrid will have an evaluation function that consists of two parts:

- A reinforcement learning trained neural network
- A handcraft evaluation function top layer.

At present I see a few ways to integrate the two, none of which I have settled on yet. Chrysaora also features an alpha-beta pruned minimax search. 

# Dependencies
Deep learning is done using arraymancer, which is the only dependency outside the Nim standard library.

### Support
Chrysaora will be supported until I get my PhD, it wins a season of the TCEC or Nim dies, whichever comes first.

### Naming

Chrysaora is named after the genus of jellyfish, which in turn is named after Chrysaor, a being from Greek mythology. Chrysaor roughly translates as "he who has a golden armament."

## Why a hybrid?

Neural Network based chess engines seem to be the "new era" so to speak in computer chess, although Stockfish has, as of the writing of this README, remained the champion of the TCEC. NN based engines come with their own set of problems, however. The general width and size of the NN required to play chess at the level that LC0 plays at is massive, explaining a major part of why NN based engines tend to be so much slower than traditional hand crafted engines. Consider that if Lc0 could achieve the nps that Stockfish does it would be, in my opinion, unbeatable.

By hybridizing a NN with a handcrafted evaluation function, I hope to achieve similar playing performance to top level engines with a much narrower network structure. The much narrower network should compute faster, and if my coding and optimization prowess is up to the task, achieve a potentially higher nodes per second. 

On the other hand it could blow up in my face.

## Licenses
The SVGs used for each piece are licensed under [CC BY-SA 3.0.](https://creativecommons.org/licenses/by-sa/3.0/) and were created by Colin M.L. Burnett. 

You can find the details of Chrysaora's license in the LICENSE.txt file. Chrysaora is licensed under GPL-3.

