local options=require('src.args').parse(arg or {})
if not (options.test and options['test-jit-defaults']) then require('src.runtime').configure() end
io.stdout:setvbuf('no')
if options.test or options['network-worker'] then
    function love.run()
        local ok,status=xpcall(function()
            if options['network-worker'] then return require('tests.network_process').run(options) end
            return require('tests.runner').run(options)
        end,debug.traceback)
        if not ok then io.stderr:write(tostring(status)..'\n');status=1 end
        return function() return status or 0 end
    end
else
    local app
    function love.load()
        if options.width and options.height then
            assert(love.window.setMode(assert(tonumber(options.width)),assert(tonumber(options.height)),{resizable=true}))
        end
        print('LoveRTS 0.1 | LOVE '..table.concat({love.getVersion()},'.')..' | save directory: '..love.filesystem.getSaveDirectory())
        if options['woodland-viewer'] then
            if not options.width then love.window.setMode(1600,1000,{resizable=true}) end
            app=require('src.woodland_viewer').create(options)
        elseif options['micro-lab'] then app=require('tests.micro_lab').create(options)
        elseif options['ui-benchmark'] then app=require('tests.ui_benchmark').create(options)
        elseif options['asset-test'] or options['asset-benchmark'] then
            app=require('tests.asset_presentation').create(options)
        elseif options['asset-viewer'] then
            app=require('src.asset_viewer').create(require('src.sprites').load())
        elseif options['ui-test'] then
            -- The rendered suite exercises the hero panel, stances, upgrades and abilities, which
            -- live on in the mechanics fixture; it plays the fixture factions on the shipping map.
            options.content=options.content or require('tests.fixture_content')
            app=require('src.app').create(options);require('tests.presentation').run(app)
        elseif not options.smoke then app=require('src.ui.shell').create(options) end
    end
    local frames=0
    function love.update(dt)
        if app then app:update(dt) end
        frames=frames+1
        if options['auto-quit'] and frames>=tonumber(options['auto-quit']) then love.event.quit(0) end
    end
    function love.draw()
        if app then app:draw() else love.graphics.print('LoveRTS is running',40,40) end
        if options['auto-quit'] and not options['asset-benchmark'] and not options['ui-benchmark'] and frames==2 then
            love.graphics.captureScreenshot(function(data)
                local path=options.screenshot or 'artifacts/smoke.png'
                local file=assert(io.open(path,'wb'))
                file:write(data:encode('png'):getString());file:close();print('Screenshot: '..path)
            end)
        end
    end
    function love.keypressed(key) if app then app:keypressed(key) elseif key=='escape' then love.event.quit() end end
    function love.textinput(text) if app and app.textinput then app:textinput(text) end end
    function love.mousemoved(...) if app and app.mousemoved then app:mousemoved(...) end end
    function love.mousepressed(x,y,b,touch,presses) if app then app:mousepressed(x,y,b,presses) end end
    function love.mousereleased(x,y,b) if app and app.mousereleased then app:mousereleased(x,y,b) end end
    function love.wheelmoved(x,y) if app and app.wheelmoved then app:wheelmoved(x,y) end end
    function love.quit() if app and app.close then app:close() end end
    if options['auto-quit'] then
        function love.errorhandler(message)
            io.stderr:write(debug.traceback(tostring(message))..'\n')
            return function() return 1 end
        end
    end
end
