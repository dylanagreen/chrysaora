import bitops
import random
import strutils

type
  # Custom Position type.
  Position* = tuple[y, x: int]

  Magic* = tuple[magic, mask, shift, start: uint64]

const
  # Note that this is backwards to basically every chess engine I've ever
  # seen. Most of them do black in the 4/8 bits and white in 1/2. Oops.
  BLACK_QUEENSIDE*:uint32 = 0x1
  BLACK_KINGSIDE*:uint32 = 0x2
  WHITE_QUEENSIDE*:uint32 = 0x4
  WHITE_KINGSIDE*:uint32 = 0x8

  BLACK_CASTLING*:uint32 = BLACK_KINGSIDE or BLACK_QUEENSIDE
  WHITE_CASTLING*:uint32 = WHITE_KINGSIDE or WHITE_QUEENSIDE

  A_FILE*: uint64 = 0x0101010101010101'u64
  B_FILE*: uint64 = A_FILE shl 1
  C_FILE*: uint64 = B_FILE shl 1
  D_FILE*: uint64 = C_FILE shl 1
  E_FILE*: uint64 = D_FILE shl 1
  F_FILE*: uint64 = E_FILE shl 1
  G_FILE*: uint64 = F_FILE shl 1
  H_FILE*: uint64 = G_FILE shl 1

  RANK_1*: uint64 = 0xFF
  RANK_2*: uint64 = RANK_1 shl 8
  RANK_3*: uint64 = RANK_2 shl 8
  RANK_4*: uint64 = RANK_3 shl 8
  RANK_5*: uint64 = RANK_4 shl 8
  RANK_6*: uint64 = RANK_5 shl 8
  RANK_7*: uint64 = RANK_6 shl 8
  RANK_8*: uint64 = RANK_7 shl 8

var
  KNIGHT_TABLE*: array[64, uint64]
  KING_TABLE*: array[64, uint64]

# Initiates the simple tables, for knights and kings. This, as opposed to the
# "magic" tables that Bishops and Rooks use.
proc init_simple_tables*() =
  # All possible knight moves, ignore flips.
  var
    knight_rays: array[4, Position] = [(2, 1), (2, -1), (-2, 1), (-2, -1)]
    king_rays: array[8, Position] = [(-1, -1), (-1, 0), (-1, 1), (0, -1),
                                     (0, 1), (1, -1), (1, 0), (1, 1)]

  # Loops over each of the 63 squares. Inside this loop we generate the mask
  # of knight moves for that square.
  for y in 0..7:
    for x in 0..7:
      var knight_move: uint64 = 0
      for shift in knight_rays:
        let
          end1: Position = (y + shift.y, x + shift.x)
          end2: Position = (y + shift.x, x + shift.y)

        # The following code blocks only run if the ending Positions are actually
        # on the board. Moved these into the blocks for short circuiting
        if end1.x in 0..7 and end1.y in 0..7:
          knight_move.setBit(end1.y * 8 + end1.x)

        if end2.x in 0..7 and end2.y in 0..7:
          knight_move.setBit(end2.y * 8 + end2.x)

      KNIGHT_TABLE[y*8 + x] = knight_move

      var king_move: uint64 = 0
      for shift in king_rays:
        let
          fin: Position = (y + shift.y, x + shift.x)

          # Boolean conditions to ensure ending is within the bounds of the board.
          legal: bool = fin.x in 0..7 and fin.y in 0..7

        # The following code blocks only run if the ending Positions are actually
        # on the board.
        if legal:
          king_move.setBit(fin.y * 8 + fin.x)

      KING_TABLE[y*8 + x] = king_move


const
  # These magics are Ethereal's magics. For now.
  BISHOP_MAGICS*: array[64, uint64] =
     [0xFFEDF9FD7CFCFFFF'u64, 0xFC0962854A77F576'u64, 0x5822022042000000'u64, 0x2CA804A100200020'u64,
     0x0204042200000900'u64, 0x2002121024000002'u64, 0xFC0A66C64A7EF576'u64, 0x7FFDFDFCBD79FFFF'u64,
     0xFC0846A64A34FFF6'u64, 0xFC087A874A3CF7F6'u64, 0x1001080204002100'u64, 0x1810080489021800'u64,
     0x0062040420010A00'u64, 0x5028043004300020'u64, 0xFC0864AE59B4FF76'u64, 0x3C0860AF4B35FF76'u64,
     0x73C01AF56CF4CFFB'u64, 0x41A01CFAD64AAFFC'u64, 0x040C0422080A0598'u64, 0x4228020082004050'u64,
     0x0200800400E00100'u64, 0x020B001230021040'u64, 0x7C0C028F5B34FF76'u64, 0xFC0A028E5AB4DF76'u64,
     0x0020208050A42180'u64, 0x001004804B280200'u64, 0x2048020024040010'u64, 0x0102C04004010200'u64,
     0x020408204C002010'u64, 0x02411100020080C1'u64, 0x102A008084042100'u64, 0x0941030000A09846'u64,
     0x0244100800400200'u64, 0x4000901010080696'u64, 0x0000280404180020'u64, 0x0800042008240100'u64,
     0x0220008400088020'u64, 0x04020182000904C9'u64, 0x0023010400020600'u64, 0x0041040020110302'u64,
     0xDCEFD9B54BFCC09F'u64, 0xF95FFA765AFD602B'u64, 0x1401210240484800'u64, 0x0022244208010080'u64,
     0x1105040104000210'u64, 0x2040088800C40081'u64, 0x43FF9A5CF4CA0C01'u64, 0x4BFFCD8E7C587601'u64,
     0xFC0FF2865334F576'u64, 0xFC0BF6CE5924F576'u64, 0x80000B0401040402'u64, 0x0020004821880A00'u64,
     0x8200002022440100'u64, 0x0009431801010068'u64, 0xC3FFB7DC36CA8C89'u64, 0xC3FF8A54F4CA2C89'u64,
     0xFFFFFCFCFD79EDFF'u64, 0xFC0863FCCB147576'u64, 0x040C000022013020'u64, 0x2000104000420600'u64,
     0x0400000260142410'u64, 0x0800633408100500'u64, 0xFC087E8E4BB2F736'u64, 0x43FF9E4EF4CA2C89'u64]

  ROOK_MAGICS: array[64, uint64] =
     [0xA180022080400230'u64, 0x0040100040022000'u64, 0x0080088020001002'u64, 0x0080080280841000'u64,
     0x4200042010460008'u64, 0x04800A0003040080'u64, 0x0400110082041008'u64, 0x008000A041000880'u64,
     0x10138001A080C010'u64, 0x0000804008200480'u64, 0x00010011012000C0'u64, 0x0022004128102200'u64,
     0x000200081201200C'u64, 0x202A001048460004'u64, 0x0081000100420004'u64, 0x4000800380004500'u64,
     0x0000208002904001'u64, 0x0090004040026008'u64, 0x0208808010002001'u64, 0x2002020020704940'u64,
     0x8048010008110005'u64, 0x6820808004002200'u64, 0x0A80040008023011'u64, 0x00B1460000811044'u64,
     0x4204400080008EA0'u64, 0xB002400180200184'u64, 0x2020200080100380'u64, 0x0010080080100080'u64,
     0x2204080080800400'u64, 0x0000A40080360080'u64, 0x02040604002810B1'u64, 0x008C218600004104'u64,
     0x8180004000402000'u64, 0x488C402000401001'u64, 0x4018A00080801004'u64, 0x1230002105001008'u64,
     0x8904800800800400'u64, 0x0042000C42003810'u64, 0x008408110400B012'u64, 0x0018086182000401'u64,
     0x2240088020C28000'u64, 0x001001201040C004'u64, 0x0A02008010420020'u64, 0x0010003009010060'u64,
     0x0004008008008014'u64, 0x0080020004008080'u64, 0x0282020001008080'u64, 0x50000181204A0004'u64,
     0x48FFFE99FECFAA00'u64, 0x48FFFE99FECFAA00'u64, 0x497FFFADFF9C2E00'u64, 0x613FFFDDFFCE9200'u64,
     0xFFFFFFE9FFE7CE00'u64, 0xFFFFFFF5FFF3E600'u64, 0x0010301802830400'u64, 0x510FFFF5F63C96A0'u64,
     0xEBFFFFB9FF9FC526'u64, 0x61FFFEDDFEEDAEAE'u64, 0x53BFFFEDFFDEB1A2'u64, 0x127FFFB9FFDFB5F6'u64,
     0x411FFFDDFFDBF4D6'u64, 0x0801000804000603'u64, 0x0003FFEF27EEBE74'u64, 0x7645FFFECBFEA79E'u64]


var
  ROOK_TABLE*: array[102400, uint64]
  BISHOP_TABLE*: array[5248, uint64]
  ROOK_INDEX*: array[64, Magic]
  BISHOP_INDEX*: array[64, Magic]

  ZOBRIST_TABLE*: array[64*12 + 2, uint64]


proc generate_straight_moves(occupied: uint64, start: Position): uint64 =
  var
    # The ending position, this will change throughout the method.
    fin_pos: Position = (0, 0)
    fin: int = -1
  # Loop through the two possible axes
  for axis in ['x', 'y']:
    # Loop through the two possible directions along each axis
    for dir in [-1, 1]:
      # This loops outward until the loop hits another piece that isn't the
      # piece we started with.
      for i in 1..7:
        # The two x directions.
        if axis == 'x':
          fin_pos = (start.y, start.x + dir * i)
        # The two y directions.
        else:
          fin_pos = (start.y + i * dir, start.x)

        fin = fin_pos.y * 8 + fin_pos.x
        # If this happens we went outside the bounds of the board.
        if not (fin_pos.y in 0..7) or not (fin_pos.x in 0..7):
          break

        # Sets the bit as a possible ending.
        result.setBit(fin)
        # If this bit is occupied we can't move beyond it, so we need to break
        # this loop and do another direction.
        if occupied.testBit(fin):
          break


proc generate_diagonal_moves(occupied: uint64, start: Position): uint64 =
  var
    # The ending Position, this will change throughout the method.
    fin_pos: Position = (0, 0)
    fin: int = -1
  # We loop through the x and y dirs here since bishops move diagonally
  # so we need directions like [1, 1] and [-1, -1] etc.
  for xdir in [-1, 1]:
    for ydir in [-1, 1]:
      # Start at 1 since 0 represents the position the bishop is at.
      for i in 1..7:
        fin_pos = (start.y + ydir * i, start.x + xdir * i)
        fin = fin_pos.y * 8 + fin_pos.x

        # If this happens we went outside the bounds of the board.
        if not (fin_pos.y in 0..7) or not (fin_pos.x in 0..7):
          break

        # Sets the bit as a possible ending.
        result.setBit(fin)
        # If this bit is occupied we can't move beyond it, so we need to break
        # this loop and do another direction.
        if occupied.testBit(fin):
          break


proc sliding_index(occupied: uint64, mask: uint64, shift: uint64,
                   magic: uint64): uint64 =
  result = ((occupied and mask) * magic) shr (64'u64 - shift)


proc sliding_index*(occupied: uint64, magic_table: Magic): uint64 =
  result = sliding_index(occupied, magic_table.mask, magic_table.shift,
                         magic_table.magic)


proc pretty_print*(num: uint64) =
  var temp = int(num).toBin(64)
  temp = temp.insertSep('\n', 8)
  echo temp


proc init_magic_tables*() =
  # Loops over each square of the board.
  for i in 0..63:
    # Need to build up the edge bitboard here. We first add the two ranks,
    # and then we take out the rank we're on (since if we are on the edge
    # we don't want to remove all the moves on that rank.)
    var tops = RANK_1 or RANK_8
    var sides = A_FILE or H_FILE
    if i div 8 == 0: tops = tops and not RANK_1
    elif i div 8 == 7: tops = tops and not RANK_8
    # Then we add the two files, and remove the file we're on.
    if i mod 8 == 0: sides = sides and not A_FILE
    elif i mod 8 == 7: sides = sides and not H_FILE

    let edges = tops or sides
    # We do the rook table for this square first. I'm not sure why I decided to
    # do this this way.
    var
      start_pos = (i div 8, i mod 8)
      occupied = uint64(0)
      mask = generate_straight_moves(occupied, start_pos) and not edges
      # The shift that is required when using the magic number.
      shift = uint64(popcount(mask))
      # The starting index in the table for the moves keyed to this square.
      start = if i == 0: 0'u64
              else: ROOK_INDEX[i-1].start + uint64(1 shl ROOK_INDEX[i-1].shift)
      # Variable to run the while loop once.
      once = true
    ROOK_INDEX[i] = (ROOK_MAGICS[i], mask, shift, start)

    while occupied > 0'u64 or once:
      once = false
      let index = sliding_index(occupied, ROOK_INDEX[i])
      ROOK_TABLE[start + index] = generate_straight_moves(occupied, start_pos)

      # Carry-Rippler trick to traverse all subsets.
      occupied = (occupied - mask) and mask

    occupied = 0'u64
    mask = generate_diagonal_moves(occupied, start_pos) and not edges
    shift = uint64(popcount(mask))
    start = if i == 0: 0'u64
            else: BISHOP_INDEX[i-1].start + uint64(1 shl BISHOP_INDEX[i-1].shift)
    once = true
    BISHOP_INDEX[i] = (BISHOP_MAGICS[i], mask, shift, start)

    while occupied > 0'u64 or once:
      once = false
      let index = sliding_index(occupied, BISHOP_INDEX[i])
      BISHOP_TABLE[start + index] = generate_diagonal_moves(occupied, start_pos)

      # Carry-Rippler trick to traverse all subsets.
      occupied = (occupied - mask) and mask


# Initializes the bitstrings for the zobrist hashing.
proc init_zobrist*() =
  # Initialize random number generator with a seed for reproducibility
  var r = initRand(1106)
  # Loops over each square
  for s in 0..63:
    # Loops over the 12 possible pieces.
    for p in 0..11:
      var num = r.next()
      while num in ZOBRIST_TABLE:
        num = r.next()
      ZOBRIST_TABLE[s + p * 64] = num

  # The two side to move entries.
  for i in 0..1:
    var num = r.next()
    while num in ZOBRIST_TABLE:
      num = r.next()
    ZOBRIST_TABLE[ZOBRIST_TABLE.len() + i - 2] = num
