-- Roadside Emergencies: which form of a counted word a language takes ("1 cow", "3 cows"). Engine-free.
-- Each translation names its own rule (the text rse_plural_rule), so nothing depends on how the game reports its language.
--   "default": one for 1, many otherwise (English, German, French, Spanish, Italian, Portuguese).
--   "eastSlavic": Russian and Ukrainian. one for 1, 21, 31 ... (not 11); few for 2 to 4, 22 to 24 ... (not 12 to 14); many otherwise, 0 too.
--   "polish": one for 1 only; few for 2 to 4, 22 to 24 ... (not 12 to 14); many otherwise.
--   "czech": one for 1; few for 2 to 4; many otherwise.

RsePlural = {}

local function fewEnding(n)
    local last, lastTwo = n % 10, n % 100
    return last >= 2 and last <= 4 and not (lastTwo >= 12 and lastTwo <= 14)
end

-- "one", "few" or "many" for a whole number n under that rule; an unknown rule is "default"
function RsePlural.form(rule, n)
    n = math.abs(math.floor(n or 0))
    if rule == "eastSlavic" then
        if n % 10 == 1 and n % 100 ~= 11 then
            return "one"
        end
        return fewEnding(n) and "few" or "many"
    elseif rule == "polish" then
        if n == 1 then
            return "one"
        end
        return fewEnding(n) and "few" or "many"
    elseif rule == "czech" then
        if n == 1 then
            return "one"
        end
        return (n >= 2 and n <= 4) and "few" or "many"
    end
    return n == 1 and "one" or "many"
end
