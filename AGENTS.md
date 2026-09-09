# LoveRTS development rules

- Read ROADMAP.md and STATUS.md before changing architecture. Keep milestone claims evidence-based.
- Authoritative gameplay lives in src/sim and must not call LÖVE, OS, filesystem, network, or wall-clock APIs.
- Advance simulation only through Sim.step(world, commands). Human, bot, replay, and network actions use the same commands.
- Use bounded integer arithmetic, ticks, the project PRNG, stable entity IDs, and explicit processing order. Never let unordered table traversal determine gameplay.
- Presentation reads simulation state. Animation and cosmetic randomness never determine damage, movement, visibility, or cooldowns.
- Include all future-affecting state in snapshots and canonical serialization. Keep render and transport state outside it.
- Run scripts/test.ps1 after gameplay changes. Add regression scenarios for changed behavior. Never silently bless changed golden replay results.
- Keep generated runtimes, screenshots, logs, exports, and packages outside tracked source. Export scripts and source asset recipes are tracked.
- Keep factions data-driven; do not mutate shared definitions at runtime. Prefer focused mechanics over generic frameworks.
- Report tests actually performed separately from tests requiring another PC or human playtesting.
- At the end of completed work, commit all pending project source, tests, documentation and configuration changes by default, without asking for confirmation. Review the staged contents first; keep secrets and ignored generated artifacts out of commits. Preserve existing work and report any failed checks. Push when requested; never force-push or rewrite published history without explicit authorization.
