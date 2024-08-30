local os = require("os")
local io = require("io")

os.execute("rm update.log")
os.execute("wget https://github.com/fruarry/oc_scripts/raw/main/daily_e621/ctif/update.log")

os.execute("rm D:/pic/*")
for line in io.lines("update.log") do
    os.execute("wget https://github.com/fruarry/oc_scripts/raw/main/daily_e621/ctif/"..line.." D:/pic/"..line)
end
