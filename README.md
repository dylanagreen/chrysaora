# Chrysaora

Chrysaora is an attempt to teach an image classification fully convolutional network (FCN) to play chess. In addition, I plan to bolster Chrysaora's playing strength with a rudimentary Monte Carlo tree search, providing two separate deep learning techniques to playing chess. 

The theory is that every board "state" comes from a match won by either black or white or from a draw. This means that each board state can be considered an image, which will be categorized into one of three different categories. Then, once the network is trained, you pass it every possible move it could make, and then pick the move that the network classifies as win for its side. If there are more than one, then pick the board with the highest confidence.

FCN work is done using PyTorch, with backend math and move generation done by NumPy and SciPy.  

Chrysaora is named after the genus of jellyfish, which in turn is named after Chrysaor, a being from Greek mythology. Chrysaor roughly translates as "he who has a golden armament."

## Licenses
The SVGs used for each piece are licensed under [CC BY-SA 3.0.](https://creativecommons.org/licenses/by-sa/3.0/) and were created by Colin M.L. Burnett. 
