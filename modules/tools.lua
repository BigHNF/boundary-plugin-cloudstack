--
-- Tools Module.
-- [author] Valeriu Paloş <me@vpalos.com>
--
local tools = {}

--
-- Limit a given number x between two boundaries.
-- Either min or max can be nil, to fence on one side only.
--
tools.fence = function(x, min, max)
  return (min and x < min and min) or (max and x > max and max) or x
end

--
-- Encode data in Base64 format.
--
tools.base64 = function(data)
  local _lookup = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  return ((data:gsub('.', function(x)
    local r, b = '', x:byte()
    for i = 8, 1, -1 do
      r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and '1' or '0')
    end
    return r
  end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
    if #x < 6 then
      return ''
    end
    local c = 0
    for i = 1, 6 do
      c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0)
    end
    return _lookup:sub(c + 1, c + 1)
  end) .. ({
    '',
    '==',
    '='
  })[#data % 3 + 1])
end

--
-- URL encode a string (RFC 3986, Section 2.3).
--
tools.urlEncode = function(str)
  local function encode(char)
    return string.format ("%%%02X", string.byte(char))
  end

  local result = tostring(str)
    :gsub("\r?\n", "\r\n")              -- normalize newlines
    :gsub("([^%w%-%.%_%~ ])", encode)   -- encode all chars
    :gsub(" ", "+")                     -- encode spaces

  return result
end

--
-- Export.
--
return tools