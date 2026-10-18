-- Daily sign-in coin rewards, indexed by sign-in day (1..7). The host calendar
-- panel owns day progression and triggers RewardDay{N}; the Lua side only grants
-- the coins for the claimed day. Source: 蛋仔策划案--大富翁 签到表.
return {
  500,
  1000,
  2000,
  4000,
  6000,
  8000,
  10000,
}

