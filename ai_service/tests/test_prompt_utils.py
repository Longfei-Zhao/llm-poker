import pytest
from src.prompts.prompt_utils import parse_response, choose_default_action

VALID_ACTIONS = ["fold", "check", "call", "raise"]

# ---------- 第一层：JSON解析 ----------

def test_parse_pure_json():
    """纯JSON响应（如OpenAI response_format=json_object）"""
    response = '{"thinking": "对手下注很大，我的牌力不足", "action": "fold"}'
    action, amount, thinking = parse_response(response, VALID_ACTIONS, 40, 1000)
    assert action == "fold"
    assert amount is None
    assert "牌力不足" in thinking

def test_parse_json_with_raise_amount():
    """JSON响应包含raise和金额"""
    response = '{"thinking": "我有顶对，应该加注施压", "action": "raise", "amount": 120}'
    action, amount, thinking = parse_response(response, VALID_ACTIONS, 40, 1000)
    assert action == "raise"
    assert amount == 120

def test_parse_json_code_block():
    """```json代码块包裹的JSON（Claude/Gemini常见输出格式）"""
    response = """Here is my decision:
```json
{
  "thinking": "位置不利，选择跟注控制底池",
  "action": "call"
}
```"""
    action, amount, thinking = parse_response(response, VALID_ACTIONS, 40, 1000)
    assert action == "call"
    assert amount is None
    assert "控制底池" in thinking

def test_parse_bare_code_block():
    """无语言标记的```代码块"""
    response = "```\n{\"action\": \"check\", \"thinking\": \"免费看牌\"}\n```"
    action, amount, thinking = parse_response(response, VALID_ACTIONS, 40, 1000)
    assert action == "check"
    assert amount is None

def test_parse_json_amount_as_string():
    """JSON中金额为字符串时应转换为整数"""
    response = '{"action": "raise", "amount": "200", "thinking": "半诈唬"}'
    action, amount, thinking = parse_response(response, VALID_ACTIONS, 40, 1000)
    assert action == "raise"
    assert amount == 200

# ---------- 第二层：正则表达式从自由文本提取 ----------

def test_parse_chinese_fold():
    """中文自由文本：弃牌"""
    response = "我的手牌是72o，是最差的起手牌。综合考虑，我决定弃牌。"
    action, amount, thinking = parse_response(response, VALID_ACTIONS, 40, 1000)
    assert action == "fold"
    assert amount is None

def test_parse_chinese_call():
    """中文自由文本：跟注"""
    response = "底池赔率合适，我选择跟注继续看翻牌。"
    action, amount, thinking = parse_response(response, VALID_ACTIONS, 40, 1000)
    assert action == "call"
    assert amount is None

def test_parse_chinese_raise_with_amount():
    """中文自由文本：加注+金额"""
    response = "我有AA，必须加注到300筹码来保护我的牌。"
    action, amount, thinking = parse_response(response, VALID_ACTIONS, 40, 1000)
    assert action == "raise"
    assert amount == 300

def test_parse_english_free_text():
    """英文自由文本"""
    response = "Given the pot odds and my weak holding, I choose fold here."
    action, amount, thinking = parse_response(response, VALID_ACTIONS, 40, 1000)
    assert action == "fold"

def test_parse_deepseek_r1_style():
    """DeepSeek-R1风格：长推理后跟最终决策行"""
    response = """首先分析当前局面。我持有KQ同花，翻牌是K-7-2彩虹面，
我击中了顶对好踢脚。对手在前面位置只是跟注，范围偏弱。
考虑到底池已有150，加注可以获取价值并保护牌力。
胜率估计在70%以上。

最终决策：raise 150"""
    action, amount, thinking = parse_response(response, VALID_ACTIONS, 40, 1000)
    assert action == "raise"
    assert amount == 150
    assert "顶对" in thinking

def test_parse_action_colon_format():
    """action: xxx 键值格式（部分模型不输出完整JSON）"""
    response = "分析：牌面较干。\naction: check"
    action, amount, thinking = parse_response(response, VALID_ACTIONS, 40, 1000)
    assert action == "check"

# ---------- 第三层：默认动作回退 ----------

def test_parse_garbage_falls_back_to_check():
    """完全无法解析时回退默认动作，check优先于fold"""
    response = "嗯嗯嗯……让我想想……"
    action, amount, thinking = parse_response(response, VALID_ACTIONS, 40, 1000)
    assert action == "check"
    assert amount is None

def test_parse_garbage_falls_back_to_call_without_check():
    """无check时回退到call"""
    response = "………………"
    action, amount, thinking = parse_response(response, ["fold", "call", "raise"], 40, 1000)
    assert action == "call"

def test_parse_invalid_action_falls_back():
    """JSON中的动作不在有效动作列表中时回退默认动作"""
    response = '{"action": "allin", "thinking": "全下！"}'
    action, amount, thinking = parse_response(response, ["fold", "check"], 40, 1000)
    assert action == "check"

def test_ordinary_english_word_not_treated_as_action():
    """普通英文单词不应被误识别为动作"""
    response = "The board is very coordinated, many draws possible."
    action, amount, thinking = parse_response(response, VALID_ACTIONS, 40, 1000)
    # 无动作关键词，回退默认动作而不是把"board"之类的词当动作
    assert action == "check"

# ---------- 金额钳制 ----------

def test_raise_amount_clamped_to_max():
    response = '{"action": "raise", "amount": 99999}'
    action, amount, _ = parse_response(response, VALID_ACTIONS, 40, 1000)
    assert action == "raise"
    assert amount == 1000

def test_raise_amount_clamped_to_min():
    response = '{"action": "raise", "amount": 5}'
    action, amount, _ = parse_response(response, VALID_ACTIONS, 40, 1000)
    assert action == "raise"
    assert amount == 40

def test_raise_without_amount_uses_min_bet():
    response = '{"action": "raise", "thinking": "加注"}'
    action, amount, _ = parse_response(response, VALID_ACTIONS, 40, 1000)
    assert action == "raise"
    assert amount == 40

def test_non_raise_action_drops_amount():
    """非raise动作不应携带金额"""
    response = '{"action": "call", "amount": 100}'
    action, amount, _ = parse_response(response, VALID_ACTIONS, 40, 1000)
    assert action == "call"
    assert amount is None

# ---------- 默认动作辅助函数 ----------

def test_choose_default_action_priority():
    assert choose_default_action(["fold", "check", "call"]) == "check"
    assert choose_default_action(["fold", "call", "raise"]) == "call"
    assert choose_default_action(["fold", "raise"]) == "fold"
    assert choose_default_action(["allin"]) == "allin"
    assert choose_default_action([]) == "fold"

# ---------- 数据传输修复 ----------

from src.prompts.prompt_utils import get_position_name, format_game_state, build_prompt

def test_parse_json_with_raw_newlines_in_string():
    """思考字段里带未转义换行的JSON也应按JSON解析，而不是落到正则"""
    response = '{"thinking": "对手加注了。\n但我有坚果，跟注太亏", "action": "raise", "amount": 300}'
    action, amount, thinking = parse_response(response, VALID_ACTIONS, 40, 1000)
    assert action == "raise"
    assert amount == 300
    assert "坚果" in thinking

def test_parse_json_surrounded_by_prose():
    """JSON前后有说明文字且没有代码块时也应提取出JSON"""
    response = 'My decision is below.\n{"thinking": "免费看牌", "action": "check"}\nGood luck!'
    action, amount, thinking = parse_response(response, VALID_ACTIONS, 40, 1000)
    assert action == "check"
    assert thinking == "免费看牌"

def test_regex_fallback_uses_last_mentioned_action():
    """自由文本先复述对手动作，最终决定在末尾，应取最后一次提到的动作"""
    response = "对手在翻牌圈加注了，我的牌太弱，所以弃牌"
    action, amount, thinking = parse_response(response, VALID_ACTIONS, 40, 1000)
    assert action == "fold"

def test_position_names_follow_array_index():
    assert [get_position_name(i, 0, 6) for i in range(6)] == ["BTN", "SB", "BB", "UTG", "HJ", "CO"]
    assert [get_position_name(i, 0, 2) for i in range(2)] == ["BTN", "BB"]

def _state(players, dealer_index):
    return {
        "smallBlind": 5, "bigBlind": 10, "pot": 15, "currentBet": 10,
        "dealerIndex": dealer_index, "communityCards": [], "actionHistory": [],
        "players": players,
    }

def _player(pid, seat, cards=None):
    return {"id": pid, "name": pid, "position": seat, "chips": 1000, "bet": 0,
            "isActive": True, "isAllIn": False, "cards": cards or []}

def test_format_game_state_ignores_seat_numbers():
    """座位号不连续（有人被淘汰）时，位置仍按数组下标和dealerIndex计算"""
    players = [_player("A", 2), _player("B", 5, ["Ah", "Kd"]), _player("C", 8)]
    text = format_game_state(_state(players, 0), "B")
    assert "button: A" in text
    assert "- position: SB" in text
    assert "- position: BB" in text

def test_build_prompt_uses_actual_player_count():
    players = [_player("A", 1), _player("B", 2, ["Ah", "Kd"]), _player("C", 3)]
    prompt = build_prompt(_state(players, 0), "B", VALID_ACTIONS, 20, 1000)
    assert "3-player" in prompt
    assert "8-player" not in prompt

# ---------- 台词与心声 ----------

from src.prompts.prompt_utils import extract_speech

def test_extract_speech_from_json():
    response = '{"thinking": "我有葫芦", "speech": "就这？", "action": "allin"}'
    assert extract_speech(response) == "就这？"

def test_extract_speech_missing_or_empty():
    assert extract_speech('{"action": "fold"}') is None
    assert extract_speech('{"speech": "  ", "action": "fold"}') is None

def test_build_prompt_includes_persona_and_table_talk():
    players = [_player("A", 1), _player("B", 2, ["Ah", "Kd"]), _player("C", 3)]
    state = _state(players, 0)
    state["persona"] = "英伦老绅士，说话客气但阴阳怪气。"
    state["tableTalk"] = [{"name": "C", "stage": "preflop", "speech": "来点刺激的！"}]
    prompt = build_prompt(state, "B", VALID_ACTIONS, 20, 1000)
    assert "英伦老绅士" in prompt
    assert "must not change how you play" in prompt
    assert '- C (Pre-Flop): "来点刺激的！"' in prompt
    assert '"speech"' in prompt
