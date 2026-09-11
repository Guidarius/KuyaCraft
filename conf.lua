function love.conf(t)
    t.identity = 'LoveRTS'
    t.version = '11.5'
    -- love.exe would pop a separate console window next to the game, which a packaged
    -- build should not do. Development and the test harness use lovec.exe, which is a
    -- console application and keeps its output regardless of this setting.
    t.console = false
    t.window.title = 'LoveRTS | deterministic skirmish prototype'
    t.window.width, t.window.height = 1280, 800
    t.window.resizable = true
    t.modules.physics = false
    t.modules.joystick = false
    t.modules.audio = true
    -- Nothing in the project uses video decoding or touch input; skip their init cost.
    t.modules.video = false
    t.modules.touch = false
    local options = require('src.args').parse(arg or {})
    if options.test or options['network-worker'] then
        t.window = nil
        t.modules.window = false
        t.modules.graphics = false
        t.modules.audio = false
        t.modules.sound = false
    end
end
