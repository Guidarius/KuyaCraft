local T={}
function T.run()
    local App=require('src.app');local Sim=require('src.sim')
    for _,fps in ipairs({30,60,144}) do
        for _,network in ipairs({false,true}) do
            local app=App.create({map='open_fields'});app.noAutoSave=true
            if network then
                local n={ready=true,config=app.world.config,map=app.world.map,submitted={},frames={},status='Test lockstep'}
                function n:poll() end
                function n:submit(tick,commands) self.submitted[tick]=true;self.frames[tick]=commands end
                function n:take(tick) return self.frames[tick] end
                function n:close() end
                app.network=n;app:update(0)
            end
            local id=app.world.players[app.player].hero
            app:command('hold',id)
            for _=1,fps do app:update(1/fps);if app.lastCommandTiming then break end end
            assert(app.lastCommandTiming and app.lastCommandTiming.ticks==(network and 4 or 1),'unexpected input scheduling at '..fps..' FPS')
            assert(app.world.entities[id].order.kind=='hold')
            local state=Sim.serializeCanonical(app.world);app:draw();app:draw();assert(Sim.serializeCanonical(app.world)==state)
            print('INPUT '..fps..' FPS '..(network and 'lockstep' or 'offline')..' acknowledgement '..app.lastCommandTiming.ticks..' ticks / '..app.lastCommandTiming.milliseconds..' ms')
            app:close()
        end
    end
    local app=App.create({map='open_fields'});app.noAutoSave=true
    app:update(.5);assert(app.world.tick==8 and app.accumulator>=.099,'long frame discarded backlog')
    app:update(.000001);assert(app.world.tick==10,'retained backlog did not drain');app:close()
end
return T
