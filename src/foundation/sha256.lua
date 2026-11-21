-- SHA-256(FIPS 180-4)纯 Lua 5.4 实现,用原生 64 位整数位运算,32 位字
-- 以 & 0xffffffff 截断。字节读写只用 string.byte / string.char,不依赖
-- string.pack(宿主沙盒的标准库面未取证)。游戏端(礼包码查码)与 tools(gift-code new 算码
-- 哈希)共用这一份,保证两边结果一致(#203)。
local sha256 = {}

local MASK = 0xffffffff

local K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local H0 = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }

local function _rotr(x, n)
  return ((x >> n) | (x << (32 - n))) & MASK
end

-- 末尾补 0x80、若干 0x00 与 64 位大端比特长度,补到 64 字节整数倍。
local function _pad(message)
  local bit_length = #message * 8
  local zeros = (55 - #message) % 64
  local length_bytes = {}
  for i = 1, 8 do
    length_bytes[i] = string.char((bit_length >> ((8 - i) * 8)) & 0xff)
  end
  return message .. "\128" .. string.rep("\0", zeros) .. table.concat(length_bytes)
end

local function _compress(h, block, offset)
  local w = {}
  for i = 1, 16 do
    local b1, b2, b3, b4 = string.byte(block, offset + (i - 1) * 4, offset + i * 4 - 1)
    w[i] = (b1 << 24) | (b2 << 16) | (b3 << 8) | b4
  end
  for i = 17, 64 do
    local w15, w2 = w[i - 15], w[i - 2]
    local s0 = _rotr(w15, 7) ~ _rotr(w15, 18) ~ (w15 >> 3)
    local s1 = _rotr(w2, 17) ~ _rotr(w2, 19) ~ (w2 >> 10)
    w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & MASK
  end
  local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
  for i = 1, 64 do
    local s1 = _rotr(e, 6) ~ _rotr(e, 11) ~ _rotr(e, 25)
    local ch = (e & f) ~ (~e & g)
    local t1 = (hh + s1 + ch + K[i] + w[i]) & MASK
    local s0 = _rotr(a, 2) ~ _rotr(a, 13) ~ _rotr(a, 22)
    local maj = (a & b) ~ (a & c) ~ (b & c)
    local t2 = (s0 + maj) & MASK
    hh, g, f, e, d, c, b, a = g, f, e, (d + t1) & MASK, c, b, a, (t1 + t2) & MASK
  end
  h[1] = (h[1] + a) & MASK
  h[2] = (h[2] + b) & MASK
  h[3] = (h[3] + c) & MASK
  h[4] = (h[4] + d) & MASK
  h[5] = (h[5] + e) & MASK
  h[6] = (h[6] + f) & MASK
  h[7] = (h[7] + g) & MASK
  h[8] = (h[8] + hh) & MASK
end

-- 字符串(按字节)→ 64 位小写十六进制摘要。
function sha256.hex(message)
  local padded = _pad(message)
  local h = { table.unpack(H0) }
  for offset = 1, #padded, 64 do
    _compress(h, padded, offset)
  end
  return string.format(string.rep("%08x", 8), table.unpack(h))
end

return sha256
