"""
Lightweight pure Python QR Code (Model 2) SVG generator.
Requires zero external dependencies.
"""

def generate_qr_svg(data: str, size: int = 260) -> str:
    # We can create a pure python QR matrix generator or generate clean SVG modules
    # For robust QR generation without third-party deps:
    # A standard QR matrix encoder (Numeric/Alphanumeric/Byte QR Model 2, Version 2-3, EC Level M)
    try:
        matrix = _make_qr_matrix(data)
    except Exception as e:
        # Fallback to visual representation with embedded URL text
        return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}"><rect width="100%" height="100%" fill="#ffffff" rx="16"/><text x="50%" y="50%" dominant-baseline="middle" text-anchor="middle" font-family="sans-serif" font-size="14" fill="#000000">{data}</text></svg>'

    modules_count = len(matrix)
    padding = 4
    total_size = modules_count + padding * 2
    
    rects = []
    for y in range(modules_count):
        for x in range(modules_count):
            if matrix[y][x]:
                rects.append(f'<rect x="{x + padding}" y="{y + padding}" width="1" height="1" fill="#000000" />')
                
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {total_size} {total_size}" width="{size}" height="{size}" shape-rendering="crispEdges">
  <rect width="100%" height="100%" fill="#ffffff" rx="2" />
  {''.join(rects)}
</svg>'''
    return svg


# Standard QR generator components
def _make_qr_matrix(text: str):
    # Determine version: for URLs like "http://10.10.20.189:8080" (len ~24 chars), Version 2 (25x25) or Version 3 (29x29) byte mode
    data_bytes = text.encode('utf-8')
    data_len = len(data_bytes)
    
    if data_len <= 14:
        version = 1
        size = 21
        total_data_codewords = 16
        ec_codewords = 10
    elif data_len <= 26:
        version = 2
        size = 25
        total_data_codewords = 28
        ec_codewords = 16
    elif data_len <= 42:
        version = 3
        size = 29
        total_data_codewords = 44
        ec_codewords = 26
    elif data_len <= 62:
        version = 4
        size = 33
        total_data_codewords = 64
        ec_codewords = 36
    else:
        version = 5
        size = 37
        total_data_codewords = 86
        ec_codewords = 48

    # Create empty matrix (None means unset)
    matrix = [[None for _ in range(size)] for _ in range(size)]
    reserved = [[False for _ in range(size)] for _ in range(size)]

    # 1. Finder patterns (top-left, top-right, bottom-left)
    def add_finder(start_y, start_x):
        for y in range(7):
            for x in range(7):
                is_black = (y == 0 or y == 6 or x == 0 or x == 6 or (2 <= y <= 4 and 2 <= x <= 4))
                matrix[start_y + y][start_x + x] = is_black
                reserved[start_y + y][start_x + x] = True
        # Separator (white border around finder)
        for y in range(-1, 8):
            for x in range(-1, 8):
                ny, nx = start_y + y, start_x + x
                if 0 <= ny < size and 0 <= nx < size and not reserved[ny][nx]:
                    matrix[ny][nx] = False
                    reserved[ny][nx] = True

    add_finder(0, 0)
    add_finder(0, size - 7)
    add_finder(size - 7, 0)

    # 2. Alignment patterns (for version >= 2)
    if version >= 2:
        align_pos = [6, size - 7]
        for ay in align_pos:
            for ax in align_pos:
                # Skip finders
                if (ay == 6 and ax == 6) or (ay == 6 and ax == size - 7) or (ay == size - 7 and ax == 6):
                    continue
                for dy in range(-2, 3):
                    for dx in range(-2, 3):
                        ny, nx = ay + dy, ax + dx
                        is_black = (abs(dy) == 2 or abs(dx) == 2 or (dy == 0 and dx == 0))
                        matrix[ny][nx] = is_black
                        reserved[ny][nx] = True

    # 3. Timing patterns
    for i in range(8, size - 8):
        if not reserved[6][i]:
            matrix[6][i] = (i % 2 == 0)
            reserved[6][i] = True
        if not reserved[i][6]:
            matrix[i][6] = (i % 2 == 0)
            reserved[i][6] = True

    # 4. Dark module
    matrix[4 * version + 9][8] = True
    reserved[4 * version + 9][8] = True

    # 5. Format info area reserve
    for i in range(9):
        if not reserved[8][i]:
            reserved[8][i] = True
        if not reserved[i][8]:
            reserved[i][8] = True
    for i in range(8):
        if not reserved[8][size - 1 - i]:
            reserved[8][size - 1 - i] = True
        if not reserved[size - 1 - i][8]:
            reserved[size - 1 - i][8] = True

    # Build bitstream: Mode (0100 for Byte) + Count + Data + Terminator + Padding
    bitstream = []
    # Byte mode = 0100
    bitstream.extend([0, 1, 0, 0])
    # Char count (8 bits for v1-9 byte mode)
    for b in format(data_len, '08b'):
        bitstream.append(int(b))
    # Data bits
    for byte in data_bytes:
        for b in format(byte, '08b'):
            bitstream.append(int(b))
    
    # Terminator (up to 4 zeroes)
    max_data_bits = total_data_codewords * 8
    term_len = min(4, max_data_bits - len(bitstream))
    bitstream.extend([0] * term_len)
    
    # Pad to multiple of 8
    while len(bitstream) % 8 != 0:
        bitstream.append(0)
        
    # Pad codewords (0xEC, 0x11)
    pad_bytes = [0xEC, 0x11]
    pad_idx = 0
    while len(bitstream) < max_data_bits:
        for b in format(pad_bytes[pad_idx], '08b'):
            bitstream.append(int(b))
        pad_idx = (pad_idx + 1) % 2

    # Convert to data codewords
    data_codewords = []
    for i in range(0, len(bitstream), 8):
        byte_val = 0
        for j in range(8):
            byte_val = (byte_val << 1) | bitstream[i + j]
        data_codewords.append(byte_val)

    # Reed-Solomon Error Correction Codewords
    ec_bytes = _reed_solomon(data_codewords, ec_codewords)
    all_codewords = data_codewords + ec_bytes

    # Convert all codewords to bit sequence
    final_bits = []
    for cw in all_codewords:
        for b in format(cw, '08b'):
            final_bits.append(int(b))

    # Place data in zigzag
    bit_idx = 0
    x = size - 1
    going_up = True
    while x > 0:
        if x == 6:  # Skip vertical timing column
            x -= 1
        y_range = range(size - 1, -1, -1) if going_up else range(size)
        for y in y_range:
            for dx in [0, -1]:
                curr_x = x + dx
                if not reserved[y][curr_x]:
                    bit = final_bits[bit_idx] if bit_idx < len(final_bits) else 0
                    # Apply Mask 0: (row + col) % 2 == 0
                    mask = ((y + curr_x) % 2 == 0)
                    matrix[y][curr_x] = bool(bit ^ mask)
                    bit_idx += 1
        x -= 2
        going_up = not going_up

    # Add Format Information (Mask 0, EC Level L/M)
    # Format info string for EC Level M, Mask 0: 0x5412 (101010000010010)
    format_bits = [1, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0]
    
    # Place format bits
    # Around top-left finder
    matrix[8][0] = bool(format_bits[0])
    matrix[8][1] = bool(format_bits[1])
    matrix[8][2] = bool(format_bits[2])
    matrix[8][3] = bool(format_bits[3])
    matrix[8][4] = bool(format_bits[4])
    matrix[8][5] = bool(format_bits[5])
    matrix[8][7] = bool(format_bits[6])
    matrix[8][8] = bool(format_bits[7])
    matrix[7][8] = bool(format_bits[8])
    matrix[5][8] = bool(format_bits[9])
    matrix[4][8] = bool(format_bits[10])
    matrix[3][8] = bool(format_bits[11])
    matrix[2][8] = bool(format_bits[12])
    matrix[1][8] = bool(format_bits[13])
    matrix[0][8] = bool(format_bits[14])

    # Around other finders
    for i in range(8):
        matrix[size - 1 - i][8] = bool(format_bits[i])
    for i in range(7):
        matrix[8][size - 7 + i] = bool(format_bits[8 + i])

    # Fill any remaining None with False
    for y in range(size):
        for x_idx in range(size):
            if matrix[y][x_idx] is None:
                matrix[y][x_idx] = False

    return matrix


# Galois Field arithmetic for Reed-Solomon EC
_EXP_TABLE = [0] * 512
_LOG_TABLE = [0] * 256
_x = 1
for _i in range(255):
    _EXP_TABLE[_i] = _x
    _EXP_TABLE[_i + 255] = _x
    _LOG_TABLE[_x] = _i
    _x = (_x << 1) ^ (0x11D if (_x & 0x80) else 0)

def _gf_mul(x, y):
    if x == 0 or y == 0:
        return 0
    return _EXP_TABLE[_LOG_TABLE[x] + _LOG_TABLE[y]]

def _reed_solomon(data, ec_count):
    # Generator polynomial
    gen = [1]
    for i in range(ec_count):
        factor = [1, _EXP_TABLE[i]]
        new_gen = [0] * (len(gen) + 1)
        for j, g in enumerate(gen):
            new_gen[j] ^= _gf_mul(g, factor[0])
            new_gen[j + 1] ^= _gf_mul(g, factor[1])
        gen = new_gen

    # Division
    res = list(data) + [0] * ec_count
    for i in range(len(data)):
        lead = res[i]
        if lead != 0:
            for j in range(len(gen)):
                res[i + j] ^= _gf_mul(gen[j], lead)
    return res[len(data):]
