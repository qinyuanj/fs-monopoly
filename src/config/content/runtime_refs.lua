local refs = {}

refs.images = require("src.config.content.runtime_ref_images")

refs.audio = {
-- 音效资源 ID 来自策划原稿抽取。
    cash_receive = 3814,
    mountain_stun = 5112,
    hospital_shock = 5112,
    mine_blast = 5112,
    tax_wave = 5112,
    move_step_pounce = 5083,
    bankruptcy_slam = 4232,
    generic_negative = 5112,
    turn_started = 4233,
}

refs.effects = {
-- 特效资源 ID 来自策划原稿抽取。
    item_stop_highlight = 2346,
    upgrade_land_smoke = 4286,
    cash_burst = 3414,
    mountain_stun = 1973,
    hospital_shock = 4185,
    mine_blast = 1288,
    tax_wave = 2165,
    rich_deity = 4845,
    angel_deity = 2359,
    bankruptcy_slam = 4278,
}

refs.board_feedback = {
    item_stop_highlight = {
        effect_id_ref = "item_stop_highlight",
        scale = 1.8,
        duration = 1.2,
        volume = 1.0,
        allow_missing_resource = true,
    },
    upgrade_land_smoke = {
        effect_id_ref = "upgrade_land_smoke",
        sound_id_ref = "cash_receive",
        scale = 3.0,
        duration = 1.0,
        volume = 1.0,
        followup_sounds = {
            { delay = 0.6, sound_id_ref = "turn_started", duration = 1.0, volume = 1.0 },
        },
        allow_missing_resource = true,
    },
    cash_burst = {
        effect_id_ref = "cash_burst",
        sound_id_ref = "cash_receive",
        scale = 1.6,
        duration = 0.6,
        volume = 1.0,
        bind_to_player = true,
        socket_name = "Bip001",
        bind_offset = "v3_cash_fx_head_offset",
        allow_missing_resource = true,
    },
    mountain_stun = {
        effect_id_ref = "mountain_stun",
        sound_id_ref = "mountain_stun",
        scale = 1.6,
        duration = 1.2,
        volume = 1.0,
        allow_missing_resource = true,
    },
    hospital_shock = {
        effect_id_ref = "hospital_shock",
        sound_id_ref = "hospital_shock",
        scale = 1.8,
        duration = 1.2,
        volume = 1.0,
        allow_missing_resource = true,
    },
    mine_blast = {
        effect_id_ref = "mine_blast",
        sound_id_ref = "mine_blast",
        scale = 2.0,
        duration = 1.0,
        volume = 1.0,
        allow_missing_resource = true,
    },
    tax_wave = {
        effect_id_ref = "tax_wave",
        sound_id_ref = "tax_wave",
        scale = 1.6,
        duration = 1.0,
        volume = 1.0,
        allow_missing_resource = true,
    },
    rich_deity = {
        effect_id_ref = "rich_deity",
        scale = 1.4,
        duration = 2.0,
        volume = 1.0,
        bind_to_player = true,
        socket_name = "Bip001",
        bind_offset = "v3_one",
        allow_missing_resource = true,
    },
    angel_deity = {
        effect_id_ref = "angel_deity",
        scale = 1.4,
        duration = 2.0,
        volume = 1.0,
        bind_to_player = true,
        socket_name = "Bip001",
        bind_offset = "v3_one",
        allow_missing_resource = true,
    },
    move_step_pounce = {
        sound_id_ref = "move_step_pounce",
        duration = 0.4,
        volume = 0.9,
        allow_missing_resource = true,
    },
    bankruptcy_slam = {
        effect_id_ref = "bankruptcy_slam",
        sound_id_ref = "bankruptcy_slam",
        duration = 1.0,
        volume = 1.0,
        allow_missing_resource = true,
    },
    generic_negative = {
        sound_id_ref = "generic_negative",
        duration = 0.8,
        volume = 1.0,
        allow_missing_resource = true,
    },
    turn_started = {
        sound_id_ref = "turn_started",
        duration = 0.8,
        volume = 1.0,
        allow_missing_resource = true,
    },
}

refs.skins = {
    ["5003"] = 1073913977,
    ["5004"] = 1073905737,
    ["5005"] = 1073909878,
    ["5006"] = 1073901580,
}

-- 兼容兜底：宿主没有 reset_model 时，脱下皮肤才退回这个默认 creature key。
refs.default_creature = 1

refs.synthetic_ai = {
    names = {
        [1] = "红绒绒",
        [2] = "黄澄澄",
        [3] = "蓝盖盖",
        [4] = "紫圈圈",
    },
    unit_keys = { 9000601, 9000602, 9000603, 9000604, 9000605, 9000607 },
}

return refs

