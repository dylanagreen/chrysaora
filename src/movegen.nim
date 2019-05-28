import algorithm
import bitops
import tables
import strutils
import sequtils

import arraymancer

import bitboard
import board

# Initializes the lookup tables.
bitboard.init_simple_tables()
bitboard.init_magic_tables()

proc remove_moves_in_check(board: Board, moves: seq[Move], color: Color): seq[Move] =
  let orig_color = board.to_move
  board.to_move = color
  for m in moves:

    # Need skip to be true so we don't end up in an "is in check" loop.
    board.update_piece_list(m)
    board.update_piece_bitmaps(m)

    if not board.is_in_check(color):
      result.add(m)

    board.revert_piece_list(m)
    board.update_piece_bitmaps(m)
  board.to_move = orig_color


proc disambiguate_moves(moves: seq[tuple[short, long: Move]]): seq[Move] =
  # Shortcut for if there's no possible moves being disambiguated.
  if len(moves) == 0:
    return

  # Strips out the short algebraic moves from the sequence.
  let all_short = moves.map(proc (x: tuple[short, long: Move]): string = x.short.algebraic)

  # Loop through the move/board state sequence.
  for i, m in moves:
      # If the number of times that the short moves appears is more than 1 we
      # want to append the long move instead.
      if all_short.count(m.short.algebraic) > 1:
        result.add(m.long)
      else:
        result.add(m.short)


proc generate_attack_mask*(board: Board, piece: char, pos: Position): uint64 =
  case piece
  of 'N':
    return KNIGHT_TABLE[((7 - pos.y)*8 + pos.x)]
  of 'K':
    return KING_TABLE[((7 - pos.y)*8 + pos.x)]
  of 'R':
    let
      magic = ROOK_INDEX[((7 - pos.y)*8 + pos.x)]
      occupied = board.BLACK_PIECES or board.WHITE_PIECES
      index = sliding_index(occupied, magic)
    return ROOK_TABLE[magic.start + index]
  of 'B':
    let
      magic = BISHOP_INDEX[((7 - pos.y)*8 + pos.x)]
      occupied = board.BLACK_PIECES or board.WHITE_PIECES
      index = sliding_index(occupied, magic)
    return BISHOP_TABLE[magic.start + index]
  of 'Q':
    let
      magic1 = ROOK_INDEX[((7 - pos.y)*8 + pos.x)]
      magic2 = BISHOP_INDEX[((7 - pos.y)*8 + pos.x)]
      occupied = board.BLACK_PIECES or board.WHITE_PIECES
      index1 = sliding_index(occupied, magic1)
      index2 = sliding_index(occupied, magic2)
    return ROOK_TABLE[magic1.start + index1] or BISHOP_TABLE[magic2.start + index2]
  else:
    return 0


proc bits_to_algebraic(possible_moves: uint64, start_pos: Position,
                       piece: char, board: Board):
                       seq[tuple[short, long: Move]] =
  var possible_moves = possible_moves
  # Loops through, gets the LSB, and then pops it off.
  var fin = possible_moves.firstSetBit()
  while possible_moves > 0'u64:
    # Resets the LSB with xor.
    possible_moves = possible_moves and (possible_moves - 1)
    # We have to add one because bits are 1 indexed but the tables are 0 indexed.
    let
      end_pos: Position = (7 - ((fin - 1) div 8), (fin - 1) mod 8)
      move_tuple = board.row_column_to_algebraic(start_pos, end_pos, piece_numbers[piece])
    result.add((Move(start: start_pos, fin: end_pos, algebraic: move_tuple.short),
                Move(start: start_pos, fin: end_pos, algebraic: move_tuple.long)))

    # Sets fin to the next LSB, which will be 0 if there are no bits set.
    fin = possible_moves.firstSetBit()


proc pawn_bits_to_algebraic(possible_moves: uint64, color: Color, board: Board,
                            dir: string = "straight", two: bool = false):
                            seq[tuple[short, long: Move]] =
  var possible_moves = possible_moves
  # Loops through, gets the LSB, and then pops it off.
  # TODO: Abstract this
  var fin = possible_moves.firstSetBit()
  while possible_moves > 0'u64:
    # Resets the LSB with xor.
    possible_moves = possible_moves and (possible_moves - 1)
    # We have to add one because bits are 1 indexed but the tables are 0 indexed.
    let end_pos: Position = (7 - ((fin - 1) div 8), (fin - 1) mod 8)
    var
      pos: Position
      ep: bool = false


    pos = if color == WHITE: (end_pos.y + 1, end_pos.x)
          else: (end_pos.y - 1, end_pos.x)

    if dir == "right":
      pos.x = if color == WHITE: end_pos.x - 1
              else: end_pos.x + 1
      if board.current_state[end_pos.y, end_pos.x] == 0: ep = true
    elif dir == "left":
      pos.x = if color == WHITE: end_pos.x + 1
            else: end_pos.x - 1
      if board.current_state[end_pos.y, end_pos.x] == 0: ep = true
    else:
      if two:
        pos.y = if color == WHITE: pos.y + 1
              else: pos.y - 1

    # Promotions on the end rank.
    if (end_pos.y == 0 and color == WHITE) or (end_pos.y == 7 and color == BLACK):
      for key, val in piece_numbers:
        if not (key == 'P') and not (key == 'K'):
          let move_tuple = board.row_column_to_algebraic(pos, end_pos,
                                                         piece_numbers['P'], val)
          result.add((Move(start: pos, fin: end_pos, algebraic: move_tuple.short),
                      Move(start: pos, fin: end_pos, algebraic: move_tuple.long)))
    else:
      var move_tuple = board.row_column_to_algebraic(pos, end_pos, piece_numbers['P'])
      if ep: move_tuple = (move_tuple.short & "e.p.", move_tuple.long & "e.p.")
      result.add((Move(start: pos, fin: end_pos, algebraic: move_tuple.short),
                  Move(start: pos, fin: end_pos, algebraic: move_tuple.long)))

    # Sets fin to the next LSB, which will be 0 if there are no bits set.
    fin = possible_moves.firstSetBit()


proc generate_jump_moves(board: Board, color: Color, table: openArray[uint64], piece: char): seq[Move] =
  let starts = board.find_piece(color, piece)
  var long: seq[tuple[short, long: Move]]

  for pos in starts:
    var possible_moves = table[((7 - pos.y)*8 + pos.x)]

    # We can only move to places not occupied by our own pieces.
    possible_moves = if color == BLACK: possible_moves and (not board.BLACK_PIECES)
                     else: possible_moves and (not board.WHITE_PIECES)

    long = long.concat(bits_to_algebraic(possible_moves, pos, piece, board))

  result = board.remove_moves_in_check(long.disambiguate_moves(), color)


proc generate_knight_moves*(board: Board, color: Color): seq[Move] =
  result = generate_jump_moves(board, color, KNIGHT_TABLE, 'N')


proc generate_king_moves*(board: Board, color: Color): seq[Move] =
  result = generate_jump_moves(board, color, KING_TABLE, 'K')


proc generate_slide_moves(board: Board, color: Color, indices: openArray[Magic], table: openArray[uint64], piece: char): seq[tuple[short, long: Move]]=
  let starts = board.find_piece(color, piece)

  for pos in starts:
    let
      # Due to some weird nonsense with indexing (tensor coordinates go from top
      # to bottom rather than reverse) we need to subtract from 63 to get the
      # indexing to be 0 = a1.
      magic = indices[((7 - pos.y)*8 + pos.x)]
      occupied = board.BLACK_PIECES or board.WHITE_PIECES
      index = sliding_index(occupied, magic)

    var possible_moves = table[magic.start + index]

    # We can only move to places not occupied by our own pieces.
    possible_moves = if color == BLACK: possible_moves and (not board.BLACK_PIECES)
                     else: possible_moves and (not board.WHITE_PIECES)

    result = result.concat(bits_to_algebraic(possible_moves, pos, piece, board))


proc generate_bishop_moves*(board: Board, color: Color): seq[Move] =
  result = generate_slide_moves(board, color, BISHOP_INDEX, BISHOP_TABLE, 'B').disambiguate_moves()
  result = board.remove_moves_in_check(result, color)


proc generate_rook_moves*(board: Board, color: Color): seq[Move] =
  result = generate_slide_moves(board, color, ROOK_INDEX, ROOK_TABLE, 'R').disambiguate_moves()
  result = board.remove_moves_in_check(result, color)


proc generate_queen_moves*(board: Board, color: Color): seq[Move] =
  let
    rook_moves = generate_slide_moves(board, color, ROOK_INDEX, ROOK_TABLE, 'Q')
    bishop_moves = generate_slide_moves(board, color, BISHOP_INDEX, BISHOP_TABLE, 'Q')
  result = concat(rook_moves, bishop_moves).disambiguate_moves()
  result = board.remove_moves_in_check(result, color)


proc generate_pawn_moves*(board: Board, color: Color): seq[Move] =
  let pawns = board.find_piece(color, 'P')
  var pawn_bits = 0'u64

  for pos in pawns:
    pawn_bits.setBit(((7 - pos.y)*8 + pos.x))

  # Generates all the one forward moves.
  var possible_moves = if color == WHITE: pawn_bits shl 8 else: pawn_bits shr 8

  # Can only move straight forwards onto empty squares.
  possible_moves = possible_moves and not (board.BLACK_PIECES or board.WHITE_PIECES)
  result = result.concat(pawn_bits_to_algebraic(possible_moves, color, board).disambiguate_moves())

  # Generates all the one forward moves. By shifting the previous possible moves
  # We thus also doubly check that we move through an empty square.
  possible_moves = if color == WHITE: possible_moves shl 8 else: possible_moves shr 8

  # Can only move straight forwards onto empty squares.
  possible_moves = possible_moves and not (board.BLACK_PIECES or board.WHITE_PIECES)

  # Ensures the two moves ends on the right rank.
  possible_moves = if color == WHITE: possible_moves and RANK_4
                   else: possible_moves and RANK_5

  result = result.concat(pawn_bits_to_algebraic(possible_moves, color, board, two=true).disambiguate_moves())
  result = board.remove_moves_in_check(result, color)


proc generate_pawn_captures*(board: Board, color: Color): seq[Move] =
  let pawns = board.find_piece(color, 'P')
  var pawn_bits = 0'u64
  var ep_bit = 0'u64

  if color  == WHITE:
    var index = flat_alg_table.find(board.ep_square[BLACK])
    if index > -1:
      # Need to flip the y coordinate.
      index = (7 - index div 8) * 8 + index mod 8
      ep_bit.setBit(index)
  else:
    var index = flat_alg_table.find(board.ep_square[WHITE])
    if index > -1:
      # Need to flip the y coordinate.
      index = (7 - index div 8) * 8 + index mod 8
      ep_bit.setBit(index)

  # Ensures that the ep-bit is in the right rank.
  ep_bit = if color == WHITE: ep_bit and RANK_6 else: ep_bit and RANK_3

  for pos in pawns:
    pawn_bits.setBit(((7 - pos.y)*8 + pos.x))

  # Generates all the takes to the right first.
  # Makes sure we don't wrap to the other side, and that we actually take an
  # enemy piece.
  var possible_moves = pawn_bits
  if color == WHITE:
    possible_moves = possible_moves shl 7 and not H_FILE
    possible_moves = (possible_moves and board.BLACK_PIECES) or (possible_moves and ep_bit)
  else:
    possible_moves = possible_moves shr 7 and not A_FILE
    possible_moves = (possible_moves and board.WHITE_PIECES) or (possible_moves and ep_bit)

  result = result.concat(pawn_bits_to_algebraic(possible_moves, color, board, dir = "left").disambiguate_moves())

  # Generates all the takes to the right first.
  # Makes sure we don't wrap to the other side, and that we actually take an
  # enemy piece.
  possible_moves = pawn_bits
  if color == WHITE:
    possible_moves = possible_moves shl 9 and not A_FILE
    possible_moves = (possible_moves and board.BLACK_PIECES) or (possible_moves and ep_bit)
  else:
    possible_moves = possible_moves shr 9 and not H_FILE
    possible_moves = (possible_moves and board.WHITE_PIECES) or (possible_moves and ep_bit)
  result = result.concat(pawn_bits_to_algebraic(possible_moves, color, board, dir = "right").disambiguate_moves())
  result = board.remove_moves_in_check(result, color)

proc generate_castle_moves*(board: Board, color: Color): seq[Move] =
  # Hardcoded because you can only castle from starting Positions.
  # Basically just need to check that the files between the king and
  # the rook are clear, then return the castling algebraic (O-O or O-O-O)
  let
    # The rank that castling takes place on.
    rank = if color == WHITE: 7 else: 0

    # Key values to check in the castling table for castling rights.
    kingside = if color == WHITE: board.castle_rights.testBit(3)
               else: board.castle_rights.testBit(1)
    queenside = if color == WHITE: board.castle_rights.testBit(2)
                else: board.castle_rights.testBit(0)
    orig_color = board.to_move
  var
    # Slice representing the two spaces between the king and the kingside rook.
    between = board.current_state[rank, 5..6]

  # You're not allowed to castle out of check so if you're in check
  # don't generate it as a legal move.
  if board.is_in_check(color):
    return

  board.to_move = color

  if kingside and sum(abs(between)) == 0:
    # Before we go ahead and append the move is legal we need to verify
    # that we don't castle through check. Since we remove moves
    # that end in check, and the king moves two during castling,
    # it is sufficient therefore to simply check that moving the king
    # one space in the kingside direction doesn't put us in check.
    var
      alg = if color == WHITE: "Kf1" else: "Kf8"
      move = Move(start: (rank, 4), fin: (rank, 5), algebraic: alg)

    board.update_piece_list(move)
    board.update_piece_bitmaps(move)

    if not board.is_in_check(color):
      result.add(Move(start: (rank, 4), fin: (rank, 6), algebraic: "O-O"))

    board.revert_piece_list(move)
    board.update_piece_bitmaps(move)

  # Slice representing the two spaces between the king and the queenside rook.
  between = board.current_state[rank, 1..3]
  if queenside and sum(abs(between)) == 0:
    # See reasoning above in kingside.
    var
      alg = if color == WHITE: "Kd1" else: "Kd8"
      move = Move(start: (rank, 4), fin: (rank, 3), algebraic: alg)

    board.update_piece_list(move)
    board.update_piece_bitmaps(move)

    if not board.is_in_check(color):
      result.add(Move(start: (rank, 4), fin: (rank, 2), algebraic: "O-O-O"))

    board.revert_piece_list(move)
    board.update_piece_bitmaps(move)

  board.to_move = orig_color
  result = board.remove_moves_in_check(result, color)


proc generate_all_moves*(board: Board, color: Color): seq[Move] =
  result = result.concat(board.generate_pawn_moves(color))
  result = result.concat(board.generate_pawn_captures(color))
  result = result.concat(board.generate_knight_moves(color))
  result = result.concat(board.generate_bishop_moves(color))
  result = result.concat(board.generate_rook_moves(color))
  result = result.concat(board.generate_queen_moves(color))
  result = result.concat(board.generate_king_moves(color))
  result = result.concat(board.generate_castle_moves(color))