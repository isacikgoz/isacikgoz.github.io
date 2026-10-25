-- Browser entry point for the add-on UI running on tests/harness.lua's WoW mocks.
SIM_UI_MODE = true
dofile((arg[1] or ".") .. "/tests/harness.lua")
if not SIM_EMBEDDED then
    io.stderr:write("sim_game_bridge.lua is for the browser simulator\n")
    os.exit(1)
end
