local f = fs.open("/repo/build/probe.txt", "w")
f.write(tostring(_VERSION) .. "|" .. tostring(_HOST) .. "|goto:" .. tostring(load("goto x ::x::") ~= nil) .. "|unpack:" .. tostring(unpack ~= nil) .. "|tunpack:" .. tostring(table.unpack ~= nil) .. "|loadenv:" .. tostring(load("return 1", "x", "t", {}) ~= nil) .. "|setfenv:" .. tostring(setfenv ~= nil))
f.close()
os.shutdown()
