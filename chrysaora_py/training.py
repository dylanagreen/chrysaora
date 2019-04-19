import os
import random

import numpy as np

import torch
import torch.nn as nn
import torch.optim as optim
import torchvision.transforms as transforms
from torch.utils.data import Dataset, DataLoader, ConcatDataset
import torchvision.transforms.functional as TF

from sklearn.metrics import confusion_matrix
import seaborn as sns
import matplotlib.pyplot as plt

import board
import engine

class PGNDataset(Dataset):
    def __init__(self, name, loc, transform=None, flip=False):
        self.name = name
        self.transform = transform

        self.board = board.load_pgn(name, loc)

        # This adds the ending game state to the end of the game_states list.
        self.board.game_states.append(np.copy(self.board.current_state))

        # Ply 17 (move 9) is when I'll consider, in general, that the opening
        # book is complete.
        self.start = int(len(self.board.move_list) / 2)

        self.flip = flip

    def __len__(self):
        return len(self.board.move_list[self.start:])

    def __getitem__(self, index):

        b = self.board.game_states[index+self.start]
        c = np.copy(b)

        # Color flips the board by flipping vertically and swapping the colors.
        if self.flip:
            c = np.flipud(c)*-1

        c = c*np.abs(c)
        c = c.reshape(8,8,1)

        r = self.board.headers["Result"]

        # White win
        if r == "1-0":
            if self.flip:
                label = 1
            else:
                label = 2
        # Black win
        elif r == "0-1":
            if self.flip:
                label = 2
            else:
                label = 1
        # Draw
        else:
            label = 0

        # Transforms the board.
        if self.transform:
            c = self.transform(c)

        return (c, label)



def train():
    if torch.cuda.is_available():
      device = torch.device('cuda:0')
    else:
      device = torch.device('cpu')
    print(device)

    normalize = transforms.Normalize(mean=[0.485], std=[0.229])
    # Transformation object, converts to a tensor then normalizes.
    trans = transforms.Compose([transforms.ToTensor()])#, normalize])

    loc = os.path.join(os.path.dirname(__file__), *["network", "train"])
    games = os.listdir(loc)

    # Macs still dumb.
    if ".DS_Store" in games:
        games.remove(".DS_Store")

    d = []

    i = 0
    for g in games:
        if i % 500 == 0 and i > 0:
            print("Loaded " + str(i) + " games.")
        d.append(PGNDataset(g, loc, transform=trans, flip=False))
        d.append(PGNDataset(g, loc, transform=trans, flip=True))
        i += 1
    print("Number of training games: " + str(i))
    data = ConcatDataset(d)
    trainloader = DataLoader(data, batch_size=50, shuffle=True, num_workers=4)
    print("Number of training board states: " + str(len(data)))

    # Where the actual training happens.
    name = 'SkipNetFlip.pt'
    net = engine.SkipNet().to(device)
    crit = nn.CrossEntropyLoss()
    opt = optim.SGD(net.parameters(), lr=.01, momentum=0.85)


    num_epochs = 7
    loss_history = []
    for epoch in range(0, num_epochs):
        net.train()
        running_loss = 0.0

        for i, batch in enumerate(trainloader, 0):

            # Get the input with their true labels
            inputs, labels = batch

            inputs = inputs.float()
            labels = labels #.float()

            # If we have a GPU this shifts labels and inputs onto it.
            inputs = inputs.to(device)
            labels = labels.to(device)

            # Zeros the optimzer
            opt.zero_grad()

            # Get the predicted labels and find the loss by comparing
            outputs = net(inputs)
            #print(outputs.shape)
            outputs = outputs.view(-1, 3)
            loss = crit(outputs, labels)

            # Propagate the loss backwards
            loss.backward()
            opt.step()

            # Prints every div batches (Batch size currently 25)
            running_loss += loss.item()
            div = 200
            if i % div == div - 1:
                #print(running_loss)
                print('[%d, %5d] Avg. loss: %.3f' % (epoch + 1, i + 1, running_loss / div))
                loss_history.append(running_loss / div)
                running_loss = 0.0

    print('Finished Training')

    loc = os.path.join(os.path.dirname(__file__), *["network", "val"])
    games = os.listdir(loc)

    # Macs still dumb.
    if ".DS_Store" in games:
        games.remove(".DS_Store")

    d = []

    i = 0
    for g in games:
        if i % 500 == 0 and i > 0:
            print("Loaded " + str(i) + " games.")
        d.append(PGNDataset(g, loc, transform=trans))
        d.append(PGNDataset(g, loc, transform=trans, flip=True))
        i += 1

    print("Number of validation games: " + str(i))
    data = ConcatDataset(d)
    valloader = DataLoader(data, batch_size=50, shuffle=True, num_workers=4)
    print("Number of validation board states: " + str(len(data)))


    # The array of predictions.
    preds = np.asarray([])
    trues = np.asarray([])

    correct = 0
    total = 0

    net.eval()
    for data in valloader:
        # The true labels and image data
        inputs, labels = data

        # If we have a GPU this shifts labels and inputs onto it.
        inputs = inputs.float().to(device)
        #print(inputs.shape)
        #labels = labels
        labels = labels.to(device)

        # Gets the predicted labels
        outputs = net(inputs)
        _, predicted = torch.max(outputs.data, 1)

        # Adds to the total the number of labels here (should be equal to batch size)
        total = total + labels.size(0)

        # If the predicted label is the same as the true label increment correct by 1
        # This line checks all 50 patches in the batch at once.
        correct += (predicted == labels).sum().item()

        trues = np.concatenate((trues, labels.to('cpu').numpy()))
        preds = np.concatenate((preds, predicted.to('cpu').numpy()))

        if total % 2000 == 0:
            print("Board: " + str(total))

    accuracy = correct / total * 100
    print('Total boards analyzed: ' + str(total))
    print('Accuracy: '  + str(accuracy) + '%')

    # Saves the network.
    torch.save(net.state_dict(), name[:-3] + '-' + str(round(accuracy)) + '.pt')

    # Shows a confusion matrix.
    confusion = confusion_matrix(trues, preds)
    confusion2 = confusion/1e2

    classes = ["Draw", "Black Win", "White Win"]

    sns.heatmap(confusion2.T, annot=True, cmap='GnBu', xticklabels=classes, yticklabels=classes)
    plt.xlabel('True')
    plt.ylabel('Predicted')
    plt.show()


def generate_network_data(seasons, num_train):
    required_locs = ["split/final/white/", "split/final/black/",
                     "split/final/draw/", "network/train/", "network/val/"]

    for l in required_locs:
        if not os.path.exists(l):
            print("Making: " + l)
            os.makedirs(l)

    # Internal method for splitting a multi game pgn into individuals.
    def split(name):
        loc = os.path.join("split", name)

        # We're going to extract the text into a single string so we need to
        # append lines here into this array.
        game_line = []
        tags = {}
        with open(loc, 'r', encoding="ISO-8859-1") as f:
            prev = ""
            for line in f:
                game_line.append(line + " ")

                # Extracts the tags so we can use them for naming.
                if line.startswith("["):
                    line = line.rstrip()
                    line = line.strip("[]")
                    pair = line.split("\"")
                    tags[pair[0].rstrip()] = pair[1]

                # Possible end game states.
                # If the previous line contained an end game marker then the
                # game is over and we need to record that split game into a new
                # file.
                ends = ["1-0", "1/2-1/2", "0-1", "*"]
                over = False
                for e in ends:
                    if prev.endswith(e):
                        over = True

                # Saves it to the correct location.
                if over:
                    name2 = tags["White"] + "vs" + tags["Black"] + " " + tags["Date"].replace(".", "-") + " " + tags["Result"].replace("1/2", "0.5") +  ".pgn"
                    if tags["Result"] == "1-0":
                        loc2 = os.path.join("split/final/white/", name2)
                    elif tags["Result"] == "0-1":
                        loc2 = os.path.join("split/final/black/", name2)
                    else:
                        loc2 = os.path.join("split/final/draw/", name2)

                    with open(loc2, "w") as f2:
                        for l in game_line:
                            f2.write(l.rstrip() + "\n")
                    game_line = []
                    tags = {}

                # Sets the previous line to this one for the next iteration.
                prev = line.rstrip()

    # Loop through the input seasons and then split into individual games.
    for i in seasons:
        name = "TCEC_Season_"+ str(i) + "_full.pgn"
        print("Splitting: " + name)
        split(name)

    results = ["black", "white", "draw"]


    for r in results:
        loc = "split/final/" + r + "/"
        train_end = "network/train"
        val_end = "network/val"
        games = os.listdir(loc)

        # Shuffles the games so we get a random mix in each.
        random.shuffle(games)
        i = 0
        while i < num_train * 1.5:
            # Puts the first num_train into the training set, and the next
            # half of num_train into validation. Validation size is thus
            # 1/2 the training size.
            if i < num_train:
                os.rename(os.path.join(loc, games[i]), os.path.join(train_end, games[i]))
            else:
                os.rename(os.path.join(loc, games[i]), os.path.join(val_end, games[i]))
            i += 1

        print(r + " complete")


if __name__ == "__main__":
    train()
