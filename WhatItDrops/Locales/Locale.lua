local _, ns = ...

-- Localization. The English text is the key, so a string with no translation falls back to
-- the English text itself. Each Locales\<code>.lua adds its translations when the client is
-- running that language; enUS/enGB use the English text as written.
ns.L = setmetatable({}, { __index = function(_, k) return k end })
