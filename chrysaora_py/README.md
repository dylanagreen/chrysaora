# Chrysaora

Chrysaora is an attempt to teach an image classification convolutional neural network (CCN) to play chess. Chrysaora uses an alpha-beta pruning algorithm to prune a minimax search that searched through the outputs of this network. 

The theory is that every board "state" comes from a match won by either black or white or from a draw. This means that each board state can be considered an image, which will be categorized into one of three different categories. Then, once the network is trained, you pass it every possible move it could make, and then pick the move that the network classifies as win for its side. If there are more than one, then pick the board with the highest confidence.

This folder represents the original python version of Chrysaora. By the time the network was fully integrated and developed, I found that Python was a little too slow for my purposes. Move generation alone was taking half of the search time, with little room for improvement since I was a little locked into the syntax I was using in Python. 

# Dependencies
Deep learning is done using PyTorch, with backend math and move generation done by NumPy and SciPy.  

### Naming

Chrysaora is named after the genus of jellyfish, which in turn is named after Chrysaor, a being from Greek mythology. Chrysaor roughly translates as "he who has a golden armament."

## Something to Keep in Mind

Would I like Chrysaora to one day be a high level chess engine? **Yes**. Is it going to be incredibly difficult if not impossible for that to be a reality? **Double yes**. Why?

Well for one, keep in mind that this is, by and large, an experiment. I have absolutely no idea how replacing a traditional evaluation function with an FCN will work in practice. I have no idea if it'll even be able to reasonably approximate an evaluation function. It's entirely possible that it can't and the project dies there.

However, if by some miracle the FCN plays decently well, it's important to note something further: *Python is slow.* And on top of that, *neural networks are slow.* The most powerful of engines can search millions of nodes per second, but LeelaChess0 tops out at a couple hundred kilonodes per second. There are a few ways around this, if we actually get this far. Much of the move generation and tree searching code can be reimplemented with few changes in Cython, which should provide substantial speedup. But the network is still slow. If we can even come within a factor of 10 of the nodes per second Lc0 reaches that would be impressive.

# Why a CNN?
The instigating force behind Chrysaora is that of image classification. Humans, or at the very least high level grandmasters, can look at a chess board position and tell rather quickly which of the two sides has the advantage. My personal theory, which is being put to the test here, is that this is analagous to an image classification problem. In much the same way a person can look at a picture of a dog, discern the features, and go "that's a dog", a CNN can do the same. I hope to transfer this thinking to chess. A grandmaster looks at a board, looks at the features, and goes "white's winning." Why should a CNN not be able to do the same?

Lc0 (and my personal underdog in TCEC, AllieStein) are both also based on Neural Networks. Chrysaora differs in that it's not trained using reinforcement learning, but rather using a loss function and a much more rigid rule structure. My initial experiments are... promising in some aspects, and less in others. Chrysaora has been coded in such a way that the internal network can be easily swapped for a different one, and it may be prudent in the future to swap to a RL trained network instead. 

## Licenses
The SVGs used for each piece are licensed under [CC BY-SA 3.0.](https://creativecommons.org/licenses/by-sa/3.0/) and were created by Colin M.L. Burnett. 

