-- 礼包码码表(#195 / #203 / ADR 0075)。礼包码是一人一码的补偿码,每个码:
--   id         短整数,上线后不可复用(兑换记录只存 id);停用的 id 列进 retired_ids
--   code_hash  规范化后(去空白与连字符、转大写)码的 SHA-256,64 位小写十六进制;
--              码表不存明文 code,出现即加载报错
--   rewards    礼包码奖励的皮肤 product_id 列表(须在 skins.lua 且配了 archive_key)
--   expires_at 可选,墙钟秒;墙钟超过即过期,墙钟取不到不判过期
--   note       工单号或补偿原因,不写玩家昵称
-- 新码一律用 `lua5.4 tools/cli.lua gift-code new` 生成:它只在 codes 列表末尾
-- 追加一条(按 `  codes = {` 与其后第一个 `  },` 行定位,改排版须同步 CLI),
-- 明文码只在终端打印一次。「id → 玩家、明文码、发放日期」记在仓外。
-- 加载期校验见 gift_code_catalog。
local gift_codes = {
  codes = {
    { id = 2, code_hash = "602f521bc1c37fe7b2c7447cfe8b743fac9f5a4cf7630ff3b7ac9227d93e623b", rewards = { 5005 }, expires_at = 1808295571, note = "#200 真机验收测试码(取代停用的 id 1 TEST2026)" },
    { id = 3, code_hash = "c21abe4c2ef544f17f7fc687a1f1e907cc21ec2b85281a2865f22c78f76f9cf1", rewards = { 5005 }, expires_at = 1808297618, note = "批量购买补偿" },
    { id = 4, code_hash = "084c128542441618ed35544b41f89e85964f21fa6c9413af234b74312c977fc4", rewards = { 5005 }, expires_at = 1808297618, note = "批量购买补偿" },
    { id = 5, code_hash = "8859c99b237f7e0a48c93d7f08a3807b95f31de3fd2cff3a443ffc2eea4827f4", rewards = { 5005 }, expires_at = 1808297618, note = "批量购买补偿" },
    { id = 6, code_hash = "146c370640a7cda874e65a7be26719b5fa1333d70ea5d454e681c68059068aa2", rewards = { 5005 }, expires_at = 1808297618, note = "批量购买补偿" },
    { id = 7, code_hash = "09f828ee1c7e58e715f4c1541ea0f9187a12f31493cfeb28ddbe340eeaf005e4", rewards = { 5005 }, expires_at = 1808297618, note = "批量购买补偿" },
    { id = 8, code_hash = "5d4906d707f6280f7bfdb9f57d2f923750f1e070a50f55ecc448ba851c7ab3a1", rewards = { 5005 }, expires_at = 1808297618, note = "批量购买补偿" },
    { id = 9, code_hash = "bfb845f02a71d254c00aa6e6c18df9537574278f574a541980f675124ae156d2", rewards = { 5005 }, expires_at = 1808297618, note = "批量购买补偿" },
    { id = 10, code_hash = "87e9418a83d8c7f5da9867747c1f641b5168814ae9c4b19bced1d42aae8fd466", rewards = { 5005 }, expires_at = 1808297618, note = "批量购买补偿" },
    { id = 11, code_hash = "c944703ea81eb165fc87bc5596a20d4480ace76996d69ae3c102629a5ef14819", rewards = { 5005 }, expires_at = 1808297618, note = "批量购买补偿" },
    { id = 12, code_hash = "b5735a5bd1ab6f26d3bfdaffa22d1ff1af74f9ee7fdcd54c91876b215b5b0c8e", rewards = { 5005 }, expires_at = 1808297618, note = "批量购买补偿" },
    { id = 13, code_hash = "675fe703cddc381b625c97de3a6d4a847a1326cc90881f0c0f900ebd9211034f", rewards = { 5005 }, expires_at = 1808297618, note = "批量购买补偿" },
    { id = 14, code_hash = "901d1c5f7bd39ab973101d7fe280f1425c7551e28f80065b0e9fc0996025d9e5", rewards = { 5005 }, expires_at = 1808297618, note = "批量购买补偿" },
    { id = 15, code_hash = "8579f5802e75d76b5a5164ce251916830d9862d8ea01c6190e94c32cf802293f", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 16, code_hash = "bc6cae8310eb9373d5ef06d4f8b5aef0c14e0089aad499b02ba416e146e21737", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 17, code_hash = "0beef99eacea71a66ac4a19b7a318a5f28843287810cea1d119a420f4302612d", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 18, code_hash = "75253f4ce95477d971a3e6b9ab8facd60bd98956051b0c4287b27e20f3929391", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 19, code_hash = "1b4f031394f1295bce2cb9c5aef1c2d588c46202bef950118eef3de597c86918", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 20, code_hash = "4da5a569297cd3cb74331e11116386c48d1a53a221c3d8a54dbb98d4fb26ce5c", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 21, code_hash = "1f7161287482e623f352e57bfdf5b0c106edb5337a117a069537484e5cc53a4b", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 22, code_hash = "6e419049e74fc9f1d5e6aa7314d0a9d4ae40348a1ec50e59b6fe52314bec0978", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 23, code_hash = "321b5da09bcbfe829874724c2f34937dda1474ef0bef7849ee2367d6b7e7ca15", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 24, code_hash = "c0ec76482fa206140dcd74da04eee5a167079203707d07db13d6eeecc3ad9fed", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 25, code_hash = "941e8b7791cb95ba5df41ef5eb5e9139ffe1b56ba9dd47d8cee40f092cef5583", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 26, code_hash = "832aae0cb8c8b3f8b280b149fb237031031c6971c4c8802288a311d714512df2", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 27, code_hash = "06485a21f6f824ac2736b78cd8819e3ccab9d283fe1f192957f8d730c03ed496", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 28, code_hash = "50e029a05229962d3577a55f7b13d3d202bbeb9ed8ed2f805e57866df12a8484", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 29, code_hash = "1ea537fa122cb20f52d6cf6b56dd7e36f5c56812853e47d7b47f41cf8564da25", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 30, code_hash = "a68d5c40440d89f5452a602367809a27f5f1ebbe4c5377f2db2bd0160d24eac5", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 31, code_hash = "810d760e96d335a98a6a0d6a75ac3bd534e70ae2690d7c5ce97c838b28264ca1", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 32, code_hash = "815ef1a5d1d99d4605724704a491c0c55d2574c2fe3c60805e6d8f848568290f", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 33, code_hash = "88a18c890f332b4a7d97889b2a695b1065766ad168288305f98be229684be3c7", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 34, code_hash = "e4c5e590d0aa9ff79063e56e1cec488076f87cd8a7634513adf489c6cf9e6833", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 35, code_hash = "806253cacfb9f5b48b01fc5c559b66df79c48d11b80a99af8b637da212e1da44", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 36, code_hash = "4b19929f9fca3044d5c29a44c0370ffc11685ea3fa52ef0d2ce61f3c00ff2d37", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 37, code_hash = "ab3fe7f6cb411abf03bf5d5d97058322d3c3cf81e412cde19bcb61a457f44c81", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 38, code_hash = "e10209099126a4cbaaeb1d0e9fa7c44b9a8a638856fcc9b3268551a0c7c9d528", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 39, code_hash = "58e94dcf4a8447d8fc174d6512ecd1134c655c6033b7e99d6cedf3e556f33fc5", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 40, code_hash = "8087166e1d75f91932c13b9f9ee7c9a8cced24b4ccdfe79e97cb1b9f29ed754e", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 41, code_hash = "122abae54ae7849d3803955427f95976b9d5433e69f90df91d80812412663071", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 42, code_hash = "0e6e7509a52939ac3b8476a44609535599fadf04c7a5ede3b62c66e8dcb0288f", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 43, code_hash = "312f3e1c84a5f3ed82d85d014662953c7fe211ec8fdf89bb47af5d1c8dfbdd79", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 44, code_hash = "d5cf20a032a0ff5df5e5d6143a48f93b5438e97072d1c163a6551f4afff7d072", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 45, code_hash = "dad3ad0bfaa082e865078ea6ef6d2692c83fe15bd1a3c587000e57977d4abc85", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 46, code_hash = "76bc06178d535b1a652387dd97e73032b7e9157857836e5dc53e9453761aec65", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 47, code_hash = "62baa4807b1ee340049d95743a8a943cd463ea9738bd4c4f38126fdc6109dfe7", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 48, code_hash = "ac18c4946170d02bd199cc1c1124766c5d92789a07c9636944ea3950bb43528c", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 49, code_hash = "c827034f0ec0900c5503dde88b9de2912a0d1abae8ee163f001a80dc3636d147", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 50, code_hash = "b77660f02ebac89cfaadc3859a20448a1f110137c1cbf0bfdd457f58e870a63e", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 51, code_hash = "3235b411fd0deec7da9b184a792c3f19f20212eb9c1b040f829ae3d6b924f234", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 52, code_hash = "f5282e28015ad755f929c3be5115fb571991e709c44f6268e6a86891e53c832d", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 53, code_hash = "c790f20213290fe3812158ba7f9a680f94570855d1d0cce1ca8c071a993d938c", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 54, code_hash = "a1d2165315952d7045186e73715aded8c469b117bfe554609aff21a6c0352e7f", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 55, code_hash = "6360df65abad569dec0a016448409845bbc2cdee7612beec8d483447e168da0a", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 56, code_hash = "85633da6cbac42683e186c56340f0ac515b8a0025726adca665d04dbd220eb17", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 57, code_hash = "b03821cb8799f99ae4ed5723fdf3c47cd79f962caac5f5a0e76de2c7ca805fbb", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 58, code_hash = "6786e2f3f5e90da751eb8bc1a3aa1817cd0d4874b70f9a1f4acbd9b0224f7dd6", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 59, code_hash = "ecce9b4995a09b8d7be9c68a736e0ec323562143911f0e25e13498549f2ab691", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 60, code_hash = "7ed94ae0d97c0a530cf710398d98683e0a17df2e5f094a09dc389820229c763e", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 61, code_hash = "9c95a88fe1942c0ad1bfc21f3f52e3e61337fab60c7e89f6b98bc33543836eb9", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 62, code_hash = "a400fe8994193b2670c63fbd953b47748e4f7e5e9154ced6bf97e5017704daa2", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 63, code_hash = "9818cd18e47492d5330244c086079aa0153c932a5e4851350ac10a909a51cdda", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 64, code_hash = "4c5d22f468f3fe8c9bba8a23ee1e2746fd9a93e479ffa4cf2a4660e2fc16a68b", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 65, code_hash = "345c296a4fce304da8ca10c0c72f0873a38d3f953775f354a4280b453f2d41af", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 66, code_hash = "2e7c55795425e48308178b1fa6b0de72750750c2aa98ec9377cacec0475767d2", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 67, code_hash = "e93ab480543675023858d9c956156657a31722d62069bcf89bc9c5871c32e571", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 68, code_hash = "39e2e0457a957ec5d010fd846ad7464d17fa3eca4b837f7a42b57dbcdfe7bd55", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 69, code_hash = "88ebd674bc7d86de07a7d0af4c30211bd8a14ce03e8e4af25de00d5466fcb1ae", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 70, code_hash = "9997ee8105d37b6b5d224db43e3666adf148ced671340678849122aacee711be", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 71, code_hash = "8fdc5874db81765f5b4375957042084e6c6e680f11fd2968d22740c6a7419aa9", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 72, code_hash = "dd39e80ccdad2b19549f0638d2b024b33a6b7dabefe869d2504e170ca8604d4e", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 73, code_hash = "2c201b4cd49ecd3a31d498c2167b5f8e34667bb483ee3fb594b380d137899db3", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 74, code_hash = "5717203ad28f150d79ab73917b22b1c9b9c5c3cb4b82cbc8496875aa86650bbb", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 75, code_hash = "15f36791cc91a63716f9321f3a2a23f9230bca15d686e7042fa4eca7272a7375", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 76, code_hash = "6cb15bd4a02a2b80ecdedc037fa9f58396d3d80f9dbb892d8839ee1a1a8107d1", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 77, code_hash = "f2803884d4dcc06edccc7b10d4670ed5372b315e8ba1aa03cc6490e964a6b5cd", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 78, code_hash = "f280b266ac4cfa324c08018d97c66d47addb37a8fd494cf40c5850446c7f6b40", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 79, code_hash = "218f7bd4fca0a310a806fc5ac96440b87551e070fad084ed106c05a8c7b410de", rewards = { 5005 }, expires_at = 1808297619, note = "批量购买补偿" },
    { id = 80, code_hash = "25c0bca49b0d394dd324030861c43fdd27023c8129068617a08f07d2a9564368", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 81, code_hash = "7fd123826d822919f273b60b3fd8be091a4eea90d1d0c5172bdd9ab64904af92", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 82, code_hash = "00b5d55b0eb86f8b18f6659f375238f18217869f9447583244fcba040b45bc83", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 83, code_hash = "86c58b528c0a67e54e0b86340a5d24e320dc55ecffa2b6aff3916854249744ce", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 84, code_hash = "1c09daa0079ca65b6b995e48f3968bff8c0e0446b47a5db5a4b9725e940526fc", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 85, code_hash = "e9362a59f224b7a3e76a781d388fad7034b54101d13b5f667d4a0daff9f09f97", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 86, code_hash = "68702999a17b8ef2eff7206bb70764ce63ce7be31e17401f12186fa58c3616f9", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 87, code_hash = "789a9a99c44a19a4771a11ea9a608112613405eaade67de05d96faefd9ee03e1", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 88, code_hash = "a4471080d18c8cea25e9262e9feec9d17203c9cb077b2d8e78b2d2f9bee02279", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 89, code_hash = "af4344d31c8833269406102f792d90b646454f357018885231af3d5f95047ee4", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 90, code_hash = "d6bc54cfe2ef48fb1b533499a992cd74f2e701fe95acd32bac1aff6b1e620630", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 91, code_hash = "1a12199d0314f5f29ceeed0171a67af80ea96e1e31d774f0f9f06664778d4f6b", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 92, code_hash = "efdaf55a833c24ebd1038c5017aa224b144660cd514375e8a6b98ee7231d7118", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 93, code_hash = "d3d39f27bed9b9aebbccefb7241b11d3c53e42df244adb67346fd81c1df6248f", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 94, code_hash = "f4c9a78f0d93b7b109c5a8e26ca654ec276c3d377a912dffd7d5f9ebc7236b2e", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 95, code_hash = "81630ac12cf95871dfd1d2d5c1c7baee3c399922ed4ab59eba9b8aac0d3fb821", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 96, code_hash = "6b96566c50b6c49cf98ccd619e3e72a01ecdb0299857bad8b6fa51c31821ab3e", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 97, code_hash = "a3ca7cbd0f6d0c4a134c5b60a0c20d6dc935f183205727f9805a9f581a8ea3b9", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 98, code_hash = "e980b63c889cf658951aa68db9000b8531c531987d525dfb3670a15282d7425f", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 99, code_hash = "4735c7a35080219220aae6d862f6fed28d6ff5f417181464664d9abd5c414b0f", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 100, code_hash = "5552e7ea1385991aca60e189b49aaa0311095a289bac949726e53b3a53f0617a", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 101, code_hash = "71c8e4c4c86e62e8bf14834f0ca240572ec74b6181b8424f73228c51b2df4823", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 102, code_hash = "161b2f4699de03d6dcb2d9a9355f1e17840642f2e97f7fed4d06a469e1f91fc7", rewards = { 5005 }, expires_at = 1808297620, note = "批量购买补偿" },
    { id = 103, code_hash = "cc8469ee754dc907160bd55d78bf28ad8a66a3b6e03f47f822cbc98cb5abc5bd", rewards = { 5005 }, expires_at = 1792832446, note = "试玩测试临时码" },
  },
  -- 停用 id,永不再分配:1 = 旧明文测试码 TEST2026(#203 停用)。
  retired_ids = { 1 },
}

-- 兑换记录的 Str 玩家存档 key,存已兑换码 id 的逗号分隔列表。
-- 号码以宿主编辑器配置为准:编辑器存档「礼包码兑换记录」(Str)即 1056(#200 已核实)。
gift_codes.redeem_record_archive_key = 1056

-- 礼包码入口开关:false 时开局压灭基础屏入口按钮及其装饰节点,不路由点击、不挂输入
-- 监听;兑换核心与码表保留,改回 true 即恢复。地图做不到全服每码一次(无服务端
-- 记录),功能暂下线。
gift_codes.entry_enabled = false

-- 兑换结果提示文本(按兑换门面的状态取用);granted 的 %s 为本次发放的皮肤名,顿号分隔。
gift_codes.messages = {
  granted = "兑换成功，获得：%s",
  all_owned = "奖励皮肤已全部拥有",
  invalid_code = "兑换码无效",
  expired = "兑换码已过期",
  already_redeemed = "已兑换过该兑换码",
  archive_unavailable = "存档未开启，暂时无法兑换",
  write_failed = "兑换失败，请稍后重试",
}

return gift_codes
