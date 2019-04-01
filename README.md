# Chrysaora

Chrysaora is an attempt to teach an image classification fully convolutional network (FCN) to play chess. In addition, I plan to bolster Chrysaora's playing strength with a search function, although at present I am uncertain as to whether it will be MCTS or Alpha-Beta, or possibly a combination of both.

The theory is that every board "state" comes from a match won by either black or white or from a draw. This means that each board state can be considered an image, which will be categorized into one of three different categories. Then, once the network is trained, you pass it every possible move it could make, and then pick the move that the network classifies as win for its side. If there are more than one, then pick the board with the highest confidence.

# Dependencies
FCN work is done using PyTorch, with backend math and move generation done by NumPy and SciPy.  

### Naming

Chrysaora is named after the genus of jellyfish, which in turn is named after Chrysaor, a being from Greek mythology. Chrysaor roughly translates as "he who has a golden armament."

# Something to Keep in Mind

Would I like Chrysaora to one day be a high level chess engine? **Yes**. Is it going to be incredibly difficult if not impossible for that to be a reality? **Double yes**. Why?

Well for one, keep in mind that this is, by and large, an experiment. I have absolutely no idea how replacing a traditional evaluation function with an FCN will work in practice. I have no idea if it'll even be able to reasonably approximate an evaluation function. It's entirely possible that it can't and the project dies there.

However, if by some miracle the FCN plays decently well, it's important to note something further: *Python is slow.* And on top of that, *neural networks are slow.* The most powerful of engines can search millions of nodes per second, but LeelaChess0 tops out at a couple hundred kilonodes per second. There are a few ways around this, if we actually get this far. Much of the move generation and tree searching code can be reimplemented with few changes in Cython, which should provide substantial speedup. But the network is still slow. If we can even come within a factor of 10 of the nodes per second Lc0 reaches that would be impressive.

## Licenses
The SVGs used for each piece are licensed under [CC BY-SA 3.0.](https://creativecommons.org/licenses/by-sa/3.0/) and were created by Colin M.L. Burnett. 
