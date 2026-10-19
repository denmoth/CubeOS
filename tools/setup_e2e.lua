-- End-to-end check of the CubeOS installer (game/install.lua + lib/setup + the real stew) on a clean CraftOS-PC computer:
-- wipes the disk (except /repo and /rom), runs the bootstrap with --from /repo/build/packages and scripted key presses for the
-- minimal profile, then checks the installed system (boot.idx, the account, the installed loader). Result: build/setup-e2e.txt.
-- Run: tools/setup_e2e.sh
local out = {}
local function say(s)
  out[#out + 1] = tostring(s)
  local f = fs.open("/repo/build/setup-e2e.txt", "w")
  f.write(table.concat(out, "\n") .. "\n")
  f.close()
end

for _, name in ipairs(fs.list("/")) do
  if name ~= "repo" and name ~= "rom" then fs.delete("/" .. name) end
end

local K = function(k) return { "key", k } end
local events = {}
local function add(e) events[#events + 1] = e end
local function typ(text) for i = 1, #text do add({ "char", text:sub(i, i) }) end end
local function seen(s) say("screen " .. tostring(s.cur)) end
-- welcome: accept the license; profile: minimal; storage: auto; account: test / pw; summary: install; done: restart
add(seen) add(K(keys.down)) add(K(keys.space)) add(K(keys.enter))
add(seen) add(K(keys.up)) add(K(keys.enter))
add(seen) add(K(keys.enter))
add(seen) typ("Tester") add(K(keys.enter)) add(K(keys.enter)) typ("pw") add(K(keys.enter)) typ("pw") add(K(keys.enter)) add(K(keys.enter))
add(seen) add(function(s) say("plan: " .. #(s.plan_now.steps or {}) .. " steps, " .. tostring(s.plan_now.installed_delta) .. " bytes") end)
add(K(keys.enter))
add(seen) add(function(s) say("account error: " .. tostring(s.account_error)) end) add(K(keys.enter))
local rebooted = false
os.reboot = function() rebooted = true end
local t0 = os.epoch("utc")
-- the bootstrap reads the events with dofile; hand them over through a global
_G.SETUP_E2E_EVENTS = events
local ev = fs.open("/setup_events.lua", "w")
ev.write("return _G.SETUP_E2E_EVENTS")
ev.close()
local oldprint = print
print = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end if #t > 0 and t[1] ~= "" then say("print: " .. table.concat(t, " ")) end end
local ok, err = pcall(loadfile("/repo/game/install.lua", nil, _ENV), "--from", "/repo/build/packages", "--events", "/setup_events.lua")
say("installer finished: ok=" .. tostring(ok) .. " " .. tostring(err or "") .. " rebooted=" .. tostring(rebooted) ..
  " in " .. (os.epoch("utc") - t0) .. " ms")
say("temp folder left: " .. tostring(fs.exists("/.cubeos-setup")))
say("startup.lua: " .. tostring(fs.exists("/startup.lua")) .. ", boot.idx: " .. tostring(fs.exists("/cubeos/var/stew/boot.idx")))
local u = fs.open("/cubeos/sys/cfg/users.conf", "r")
say("users.conf: " .. (u and u.readAll():gsub("%s+", " ") or "missing"))
if u then u.close() end
local sd = fs.open("/cubeos/sys/sec/sudoers.lock", "r")
say("sudoers: " .. (sd and sd.readAll():gsub("%s+", " ") or "missing"))
if sd then sd.close() end
local ok2, rt = pcall(dofile, "/cubeos/sys/boot/runtime.lua")
if ok2 then
  local ok3, a = pcall(function()
    local cfs, auth_mod = rt.import("cfs"), rt.import("boot.auth")
    local fsys = cfs.new({})
    fsys:mount("/", cfs.host("/"))
    local auth = auth_mod.new(fsys, {})
    auth:load()
    return auth:verify("tester", "pw")
  end)
  say("installed system verifies the password: " .. tostring(ok3) .. " " .. tostring(a))
else
  say("runtime: " .. tostring(rt))
end
say(rebooted and ok and "SETUP E2E OK" or "SETUP E2E FAILED")
