function love.conf(t)
    t.identity = 'LoveRTS'
    t.version = '11.5'
    t.console = true
    t.window.title = 'LoveRTS | deterministic skirmish prototype'
    t.window.width, t.window.height = 1280, 800
    t.window.resizable = true
    t.modules.physics = false
    t.modules.joystick = false
    t.modules.audio = true
    local options = require('src.args').parse(arg or {})
    if options.test or options['network-worker'] then
        t.window = nil
        t.modules.window = false
        t.modules.graphics = false
        t.modules.audio = false
        t.modules.sound = false
    end
end
