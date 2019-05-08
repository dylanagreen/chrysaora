
# Note that this is backwards to basically every chess engine I've ever
# seen. Most of them do black in the 4/8 bits and white in 1/2. Oops.
const
  BLACK_QUEENSIDE*:uint8 = 0x1
  BLACK_KINGSIDE*:uint8 = 0x2
  WHITE_QUEENSIDE*:uint8 = 0x4
  WHITE_KINGSIDE*:uint8 = 0x8

  BLACK_CASTLING*:uint8 = BLACK_KINGSIDE or BLACK_QUEENSIDE
  WHITE_CASTLING*:uint8 = WHITE_KINGSIDE or WHITE_QUEENSIDE