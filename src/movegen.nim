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

proc check_move_for_check*(board: Board, move: Move, color: Color): bool =
  board.update_piece_list(move)
  board.update_piece_bitmaps(move)

  result = board.is_in_check(color)

  board.revert_piece_list(move)
  board.update_piece_bitmaps(move)


proc remove_moves_in_check(board: Board, moves: seq[Move], color: Color): seq[Move] =
  let orig_color = board.to_move
  var
    test = false
    # The pieces squares are technically attacked too.
    attacks = if color == WHITE: board.BLACK_ATTACKS or board.BLACK_PIECES
              else: board.WHITE_ATTACKS or board.WHITE_PIECES
  board.to_move = color
  for m in moves:
    # We already removed all the illegal king moves, this is overkill
    # Except in certain cases where the king could move along the attack vector
    # In a direction that hasn't been generated before.
    if m.algebraic[0] == 'K':
      if board.check[color]:
        test = true
      else:
        result.add(m)
        continue
    # Need to check castling moves
    elif m.algebraic[0] == 'O':
      if attacks.testBit((7 - m.fin.y) * 8 + m.fin.x):
        continue
    # There are rare cases where taking a pawn en passant could leave you in
    # check. The easiest way right now to verify this doesn't happen is to
    # just check every ep move. Perft 3 has an example of such a position with
    # first move e2e4.
    elif m.algebraic.endsWith("e.p."):
      test = true

    # This checks if the piece is attacked right now. It can only be pinned if it is.
    test = test or attacks.testBit((7 - m.start.y) * 8 + m.start.x)

    # If we're in check and the ending isn't on the attack vectors then it's
    # not even a good move since it can't possibly get us out.
    if board.check[color] and not test:
      if attacks.testBit((7 - m.fin.y) * 8 + m.fin.x):
        test = true
      else:
        continue

    # This should short circuit if we don't need to test that move and auto add it.
    if not test or not board.check_move_for_check(m, color):
      result.add(m)

  board.to_move = orig_color


proc generate_attack_mask*(board: Board, piece: char, pos: Position, color: Color = WHITE): uint64 =
  let square = (7 - pos.y) * 8 + pos.x
  case piece
  of 'P':
    result.setBit(square)
    if color == WHITE:
      return (result shl 7 and not H_FILE) or (result shl 9 and not A_FILE)
    else:
      return (result shr 7 and not A_FILE) or (result shr 9 and not H_FILE)
  of 'N':
    return KNIGHT_TABLE[square]
  of 'K':
    return KING_TABLE[square]
  of 'R':
    let
      magic = ROOK_INDEX[square]
      occupied = board.BLACK_PIECES or board.WHITE_PIECES
      index = sliding_index(occupied, magic)
    return ROOK_TABLE[magic.start + index]
  of 'B':
    let
      magic = BISHOP_INDEX[square]
      occupied = board.BLACK_PIECES or board.WHITE_PIECES
      index = sliding_index(occupied, magic)
    return BISHOP_TABLE[magic.start + index]
  of 'Q':
    let
      magic1 = ROOK_INDEX[square]
      magic2 = BISHOP_INDEX[square]
      occupied = board.BLACK_PIECES or board.WHITE_PIECES
      index1 = sliding_index(occupied, magic1)
      index2 = sliding_index(occupied, magic2)
    return ROOK_TABLE[magic1.start + index1] or BISHOP_TABLE[magic2.start + index2]
  else:
    return 0


proc bits_to_algebraic(possible_moves: uint64, start_pos: Position,
                       piece: char, board: Board):
                       seq[Move] =
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
    result.add(Move(start: start_pos, fin: end_pos, algebraic: move_tuple.long, uci: move_tuple.uci))

    # Sets fin to the next LSB, which will be 0 if there are no bits set.
    fin = possible_moves.firstSetBit()


proc generate_piece_moves(board: Board, color: Color, piece: char): seq[Move] =
  let starts = board.find_piece(color, piece)
  var long: seq[Move]

  for pos in starts:
    var possible_moves = board.generate_attack_mask(piece, pos)

    # We can only move to places not occupied by our own pieces.
    possible_moves = if color == BLACK: possible_moves and (not board.BLACK_PIECES)
                     else: possible_moves and (not board.WHITE_PIECES)

    # Efficiently removes king moves that leave us in check.
    if piece == 'K':
      # We need to remove the pieces themselves from the attack maps here.
      possible_moves = if color == BLACK: possible_moves and (not board.WHITE_ATTACKS)
                       else: possible_moves and (not board.BLACK_ATTACKS)

    long = long.concat(bits_to_algebraic(possible_moves, pos, piece, board))

  result = board.remove_moves_in_check(long, color)


proc generate_knight_moves*(board: Board, color: Color): seq[Move] =
  result = generate_piece_moves(board, color, 'N')

proc generate_king_moves*(board: Board, color: Color): seq[Move] =
  result = generate_piece_moves(board, color, 'K')

proc generate_bishop_moves*(board: Board, color: Color): seq[Move] =
  result = generate_piece_moves(board, color, 'B')

proc generate_rook_moves*(board: Board, color: Color): seq[Move] =
  result = generate_piece_moves(board, color, 'R')

proc generate_queen_moves*(board: Board, color: Color): seq[Move] =
  result = generate_piece_moves(board, color, 'Q')


proc pawn_bits_to_algebraic(possible_moves: uint64, color: Color, board: Board,
                            dir: string = "straight", two: bool = false):
                            seq[Move] =
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
          result.add(Move(start: pos, fin: end_pos, algebraic: move_tuple.long, uci: move_tuple.uci))
    else:
      var move_tuple = board.row_column_to_algebraic(pos, end_pos, piece_numbers['P'])
      if ep: move_tuple.long = move_tuple.long & "e.p."
      result.add(Move(start: pos, fin: end_pos, algebraic: move_tuple.long, uci: move_tuple.uci))

    # Sets fin to the next LSB, which will be 0 if there are no bits set.
    fin = possible_moves.firstSetBit()


proc generate_pawn_moves*(board: Board, color: Color): seq[Move] =
  let pawns = board.find_piece(color, 'P')
  var pawn_bits = 0'u64

  for pos in pawns:
    pawn_bits.setBit(((7 - pos.y) * 8 + pos.x))

  # Generates all the one forward moves.
  var possible_moves = if color == WHITE: pawn_bits shl 8 else: pawn_bits shr 8

  # Can only move straight forwards onto empty squares.
  possible_moves = possible_moves and not (board.BLACK_PIECES or board.WHITE_PIECES)
  result = result.concat(pawn_bits_to_algebraic(possible_moves, color, board))

  # Generates all the one forward moves. By shifting the previous possible moves
  # We thus also doubly check that we move through an empty square.
  possible_moves = if color == WHITE: possible_moves shl 8 else: possible_moves shr 8

  # Can only move straight forwards onto empty squares.
  possible_moves = possible_moves and not (board.BLACK_PIECES or board.WHITE_PIECES)

  # Ensures the two moves ends on the right rank.
  possible_moves = if color == WHITE: possible_moves and RANK_4
                   else: possible_moves and RANK_5

  result = result.concat(pawn_bits_to_algebraic(possible_moves, color, board, two=true))
  result = board.remove_moves_in_check(result, color)


proc generate_pawn_captures*(board: Board, color: Color): seq[Move] =
  let pawns = board.find_piece(color, 'P')
  var pawn_bits = 0'u64

  # Ensures that the ep-bit is in the right rank.
  var ep_bit = if color == WHITE: board.BLACK_EP else: board.WHITE_EP

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

  result = result.concat(pawn_bits_to_algebraic(possible_moves, color, board, dir = "left"))

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
  result = result.concat(pawn_bits_to_algebraic(possible_moves, color, board, dir = "right"))
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
  if board.check[color]:
    return

  # Change the board to_move for testing that the generating color doesn't
  # castle through check.
  board.to_move = color

  if kingside and sum(abs(between)) == 0:
    # Before we go ahead and append the move is legal we need to verify
    # that we don't castle through check. Since we remove moves
    # that end in check, and the king moves two during castling,
    # it is sufficient therefore to simply check that moving the king
    # one space in the kingside direction doesn't put us in check.
    var
      alg = if color == WHITE: "Kf1" else: "Kf8"
      uci = if color == WHITE: "e1g1" else: "e8g8"
      test_move = Move(start: (rank, 4), fin: (rank, 5), algebraic: alg)

    if not board.check_move_for_check(test_move, color):
      result.add(Move(start: (rank, 4), fin: (rank, 6), algebraic: "O-O", uci: uci))

  # Slice representing the two spaces between the king and the queenside rook.
  between = board.current_state[rank, 1..3]
  if queenside and sum(abs(between)) == 0:
    # See reasoning above in kingside.
    var
      alg = if color == WHITE: "Kd1" else: "Kd8"
      uci = if color == WHITE: "e1c1" else: "e8c8"
      test_move = Move(start: (rank, 4), fin: (rank, 3), algebraic: alg)

    if not board.check_move_for_check(test_move, color):
      result.add(Move(start: (rank, 4), fin: (rank, 2), algebraic: "O-O-O", uci: uci))

  board.to_move = orig_color
  result = board.remove_moves_in_check(result, color)


proc generate_all_moves*(board: Board, color: Color): seq[Move] =
  result = result.concat(board.generate_queen_moves(color))
  result = result.concat(board.generate_rook_moves(color))
  result = result.concat(board.generate_bishop_moves(color))
  result = result.concat(board.generate_knight_moves(color))
  result = result.concat(board.generate_pawn_moves(color))
  result = result.concat(board.generate_pawn_captures(color))
  result = result.concat(board.generate_king_moves(color))
  result = result.concat(board.generate_castle_moves(color))