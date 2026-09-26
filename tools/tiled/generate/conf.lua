function love.conf(t)
    t.window=false;t.console=true
    for _,name in ipairs({'audio','graphics','joystick','keyboard','mouse','physics','sound','system','touch','video','window'}) do t.modules[name]=false end
end
