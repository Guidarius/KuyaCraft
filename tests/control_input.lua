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
    -- Backlog contract. A frame delta is clamped to 0.25 s before it reaches the fixed
    -- 20 Hz accumulator, so a stall -- an asset upload, a window drag, a GC pause --
    -- cannot turn into a catch-up spiral that stalls the next frame in turn. Time beyond
    -- the clamp is deliberately lost: in offline play a cosmetic gap is preferable to a
    -- freeze. Ticks themselves are never skipped or reordered, only produced more slowly.
    -- Pinned to normal pacing: this asserts the fixed-rate accumulator's contract, and
    -- App.create loads whatever speed happens to be saved on this machine.
    local app=App.create({map='open_fields'});app.noAutoSave=true
    app.settings.gameSpeed=2
    app:update(.5)
    assert(app.world.tick==5,'a 0.5 s frame must clamp to 0.25 s of simulation, got tick '..app.world.tick)
    assert(app.accumulator<.05,'clamped frame left a backlog: '..app.accumulator)
    -- Under the clamp, a frame still drains completely and leaves its remainder queued.
    app:update(.17)
    assert(app.world.tick==8,'sub-clamp frame did not drain, got tick '..app.world.tick)
    assert(app.accumulator>=.019 and app.accumulator<.05,'remainder not retained: '..app.accumulator)
    app:update(.031)
    assert(app.world.tick==9,'retained backlog did not drain');app:close()
end
return T
