-- Optional LuaJIT sampling; all state and wall-clock work stay in tooling.
local P={}
function P.start(mode)
    if mode=='phases' then
        local step=require('src.sim').step;local saved={};local samples={}
        local names={'combatOrders','economy','movement','visibility','finishOrders','combat'};local wanted={}
        for _,name in ipairs(names) do wanted[name]=true end
        for i=1,100 do local name,fn=debug.getupvalue(step,i);if not name then break end
            if wanted[name] then
                saved[#saved+1]={index=i,fn=fn};samples[name]={}
                debug.setupvalue(step,i,function(...)
                    local begin=love.timer.getTime();local result=fn(...);local a=samples[name];a[#a+1]=(love.timer.getTime()-begin)*1000;return result
                end)
            end
        end
        return function()
            for _,entry in ipairs(saved) do debug.setupvalue(step,entry.index,entry.fn) end
            for _,name in ipairs(names) do local a=samples[name];table.sort(a);print(string.format('PHASE %s p50 %.3f p95 %.3f max %.3f',name,a[math.ceil(#a*.5)],a[math.ceil(#a*.95)],a[#a])) end
        end
    end
    local profile=require('jit.profile');local counts={};local states={}
    profile.start('li2',function(thread,samples,state)
        local stack=profile.dumpstack(thread,'pl;',3)
        counts[stack]=(counts[stack] or 0)+samples;states[state]=(states[state] or 0)+samples
    end)
    return function()
        profile.stop();local rows={};local total=0
        for stack,count in pairs(counts) do rows[#rows+1]={stack=stack,count=count};total=total+count end
        table.sort(rows,function(a,b)return a.count>b.count end)
        local lines={}
        for _,state in ipairs({'N','I','C','G','J'}) do lines[#lines+1]=string.format('VM %s %.1f%%',state,100*(states[state] or 0)/math.max(1,total)) end
        for i=1,math.min(20,#rows) do lines[#lines+1]=string.format('%.1f%% %s',100*rows[i].count/math.max(1,total),rows[i].stack) end
        local report=table.concat(lines,'\n');print(report)
        local file=assert(io.open('artifacts/control-profile.txt','wb'));file:write(report);file:close()
    end
end
return P
