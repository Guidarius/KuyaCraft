# LoveRTS code audit — 2026-10-11

## Revision and scope

Audited `7fc1697` on the Windows desktop with LÖVE 11.5 and Blender 5.1.0.
The main checkout was fast-forwarded from `4da4c0e`; local changes to
`AGENTS.md`, `CLAUDE.md`, and `docs/GIT_WORKFLOW.md` were preserved.

The incoming merge adds the mouse base and modular equipment study: two build
wrappers, Blender models/exporters/verifiers, a motion review generator/viewer,
and documentation. It changes no game runtime code. Source review covered those
additions and the existing multiplayer receive/buffering boundary, with the
project regression suite used for broader coverage. This is not a line-by-line
audit of every existing subsystem.

## Confirmed finding

### P2 — Bound received frame and checksum buffers

Location: `src/net/session.lua:68–75`, with cleanup at `:98–108`.
This defect predates the incoming mouse merge.

The host submission path uses `Lock.submit`, which bounds ticks to a 120-tick
window and limits command batches. The client's `frame` receive path checks only
that the tick is an integer and commands are a table. The `hash` receive path
on either peer accepts any numeric tick. Neither path limits buffered entries.

Consequently, an incompatible, buggy, or deliberately misbehaving connected peer
can continuously grow the receiver's memory using individually valid, small
messages. Far-future frames remain until their exact tick is taken. Fractional
checksum ticks can never match the integer keys pruned by `checksum`. The
one-megabyte per-message limit does not bound cumulative storage.

Reproduced against the actual session module in the pinned LÖVE runtime, using a
stub outbound peer. Receiving 1,000 empty frames at ticks 1,000,001–1,001,000 and
1,000 checksums at ticks 1.5–1,000.5 succeeds. Calling `checksum` every 100 ticks
through tick 2,000 leaves all 2,000 unsolicited entries stored. This exercises
the receiver and pruning directly; it is not a two-PC traffic/load test.

Suggested correction: track consumed tick progress, enforce a bounded permitted
receive window, validate checksum tick cadence and integer range, and impose an
explicit cap on retained entries. Validate frame batch shape/envelopes before
storing them. Reject invalid traffic with the existing session failure path.
Add boundary tests for stale, negative, fractional, far-future, oversized, sparse,
and conflicting messages while keeping valid reordered traffic working.

Minimal reproduction, run from a small LÖVE project with this repository on
`package.path`:

```lua
local N = require('src.net.session')
local net = setmetatable({
    role='client', ready=true, frames={}, submitted={}, hashes={},
    remoteHashes={}, states={}, peer={send=function() end},
}, {__index=N})
for tick=1,1000 do
    net:receive({kind='frame',tick=1000000+tick,commands={}})
    net:receive({kind='hash',tick=tick+.5,hash=string.rep('a',64)})
end
for tick=100,2000,100 do
    net:checksum(tick,string.rep('a',64),'state')
end
local function count(t)
    local n=0
    for _ in pairs(t) do n=n+1 end
    return n
end
assert(count(net.frames)==1000 and count(net.remoteHashes)==1000)
```

## Verification

- Python asset tests: **33 passed**. The first sandboxed run failed to create
  temporary test directories; rerunning with normal temporary-directory access
  passed. That initial setup failure is not a product defect.
- Woodland catalog validation: **passed**.
- Mouse base saved-scene verifier: **passed**, 71 bones, eight sockets, 120
  original actions retained, six clips/243 poses, grounded feet and nonstatic
  hand motion.
- Equipped guard saved-scene verifier: **passed**, six equipped and six bare
  actions retained, 1,448 evaluated triangles, 243 poses. Maximum grip error
  below `1.9e-7`; no blade intersections with the tested surfaces and no equipment
  penetrating the ground.
- Multiplayer buffer reproduction: **confirmed** as described above.
- Full `scripts/test-all.ps1`: results pending at initial report creation.

The Blender checks reopened existing generated `mouse-base-v2` and
`mouse-guard-v1` artifacts with the current verifier scripts. They did not rebuild
the models or rerender the sprites. Geometry checks do not establish aesthetic
quality, shield readability, complete collision freedom, or production readiness.
The mouse study remains separate from the shipping sprite catalog.

## Remaining checks and boundaries

No gameplay fixes, golden updates, performance-budget changes, or source-asset
changes were made. Human motion/art review, actual playtesting, and separate-PC
network validation remain outside this audit. No newly introduced blocking
defect has been confirmed in the incoming mouse tooling; this is limited to the
source and structural checks described above.

Local evidence is retained under ignored `artifacts/audit-20261011-*` paths.
The log prefix covers the full suite, Python tests, both Blender verifiers,
catalog validation, and the local reproduction project.
