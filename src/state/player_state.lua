-- Player state mixin source.
-- The actual player_state methods (status/balance/deity/location ops) are
-- now installed onto the Game class by `src/app/compose_game.lua` to honour the
-- Dependency Rule: state (L7) must not depend on player (L5).
--
-- This empty table is kept so `src/state/game_state.lua` can still `require` it
-- and call `_install_mixin(...)` as a no-op, preserving the existing wiring.
-- See docs/decisions.md ADR 0001.
return {}

