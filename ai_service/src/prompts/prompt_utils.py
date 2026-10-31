from typing import Dict, List, Optional, Any, Tuple
import json
import logging
import re
from .card_formatter import format_hand_readable

logger = logging.getLogger(__name__)

def choose_default_action(valid_actions: List[str]) -> str:
    """按优先级选择默认动作：check > call > fold

    Args:
        valid_actions: 有效动作列表

    Returns:
        str: 默认动作
    """
    # 优先选择check，其次call，最后才fold
    if 'check' in valid_actions:
        return 'check'
    elif 'call' in valid_actions:
        return 'call'
    elif 'fold' in valid_actions:
        return 'fold'
    # 如果上面都没有，返回第一个有效动作
    return valid_actions[0] if valid_actions else 'fold'

def get_position_name(seat_index: int, dealer_index: int, total_players: int) -> str:
    """获取玩家相对位置名称，规则与后端引擎的calculateRelativePosition一致

    Args:
        seat_index: 玩家在players数组中的下标（从0开始）
        dealer_index: 庄家在players数组中的下标（从0开始）
        total_players: 玩家总数

    Returns:
        str: 位置名称（BTN、SB、BB等）
    """
    relative_pos = (seat_index - dealer_index + total_players) % total_players

    # 单挑：庄家兼小盲，另一位是大盲
    if total_players == 2:
        return "BTN" if relative_pos == 0 else "BB"

    if relative_pos <= 2:
        return ("BTN", "SB", "BB")[relative_pos]
    # 盲注后第一位总是UTG，其余位置从按钮往前倒数
    if relative_pos == 3:
        return "UTG"
    from_button = total_players - relative_pos
    names = ("CO", "HJ", "MP", "UTG+1")
    return names[from_button - 1] if from_button <= len(names) else f"P{relative_pos}"

def format_game_state(game_state: Dict, player_id: str) -> str:
    """格式化游戏状态

    Args:
        game_state: 游戏状态字典
        player_id: 玩家ID

    Returns:
        str: 格式化后的游戏状态描述

    Raises:
        ValueError: 在游戏状态中找不到当前玩家
    """
    players = game_state["players"]

    # 获取当前玩家
    current_index = next(
        (i for i, p in enumerate(players) if p["id"] == player_id),
        None
    )
    if current_index is None:
        raise ValueError("在游戏状态中找不到当前玩家")
    current_player = players[current_index]

    # 获取总玩家数和庄家索引；dealerIndex是players数组下标，位置必须按数组下标算，
    # 不能用座位号position（有人淘汰或座位不连续时两者对不上）
    total_players = len(players)
    dealer_index = game_state["dealerIndex"]
    dealer_name = players[dealer_index]["name"] if 0 <= dealer_index < total_players else "unknown"

    # 获取其他玩家（保留数组下标用于计算位置）
    other_players = [
        (i, p) for i, p in enumerate(players)
        if p["id"] != player_id and p["isActive"]
    ]

    # 获取当前玩家的位置名称
    current_position_name = get_position_name(current_index, dealer_index, total_players)

    # 格式化玩家手牌为可读格式
    readable_hand = format_hand_readable(current_player['cards'])

    # 格式化公共牌为可读格式
    community_cards = game_state['communityCards']
    readable_community_cards = format_hand_readable(community_cards) if community_cards else 'none'

    # 构建状态描述
    description = f"""
small blind: {game_state['smallBlind']}
big blind: {game_state['bigBlind']}
pot: {game_state['pot']}
current bet: {game_state['currentBet']}
button: {dealer_name}

your information:
- name: {current_player['name']}
- chips: {current_player['chips']}
- bet: {current_player['bet']}
- hand: {readable_hand}
- position: {current_position_name}

community cards: {readable_community_cards}

other players:
"""

    for index, player in other_players:
        position_name = get_position_name(index, dealer_index, total_players)
        all_in_note = " (ALL-IN)" if player.get("isAllIn") else ""

        description += f"""
- name: {player['name']}
- chips: {player['chips']}{all_in_note}
- bet: {player['bet']}
- position: {position_name}
"""

    return description

def format_action_history(game_state: Dict) -> str:
    """格式化行动历史

    Args:
        game_state: 游戏状态字典

    Returns:
        str: 格式化后的行动历史描述
    """
    if not game_state.get("actionHistory"):
        return "action history: none"

    # 创建玩家ID到名称的映射
    player_map = {p["id"]: p["name"] for p in game_state["players"]}

    history_description = "action history:\n"

    # 阶段名称映射
    stage_names = {
        "preflop": "Pre-Flop",
        "flop": "Flop",
        "turn": "Turn",
        "river": "River",
        "showdown": "Showdown"
    }

    for stage_history in game_state["actionHistory"]:
        stage = stage_history["stage"]
        stage_name = stage_names.get(stage, stage.capitalize())

        history_description += f"\n## {stage_name}\n"

        if not stage_history.get("actions"):
            history_description += "No actions recorded\n"
            continue

        for action in stage_history["actions"]:
            player_id = action["playerId"]
            player_name = player_map.get(player_id, f"Player {player_id}")
            position = action.get("playerPosition", "")
            action_type = action["action"]
            amount = action.get("amount", 0)
            is_all_in = action.get("isAllIn", False)

            # 格式化行动描述
            if position:
                player_info = f"{player_name} ({position})"
            else:
                player_info = player_name

            if action_type == "fold":
                action_description = "folds"
            elif action_type == "check":
                action_description = "checks"
            elif action_type == "call":
                action_description = f"calls {amount}"
            elif action_type == "raise":
                action_description = f"raises to {amount}"
            elif action_type == "smallBlind":
                action_description = f"posts small blind {amount}"
            elif action_type == "bigBlind":
                action_description = f"posts big blind {amount}"
            else:
                action_description = f"{action_type} {amount}"

            if is_all_in:
                action_description += " (ALL-IN)"

            history_description += f"- {player_info}: {action_description}\n"

    return history_description

def format_table_talk(game_state: Dict) -> str:
    """格式化本手牌里其他玩家说出口的台词（心声不会出现在这里）

    Args:
        game_state: 游戏状态字典

    Returns:
        str: 台词记录描述
    """
    talk = game_state.get("tableTalk") or []
    if not talk:
        return "table talk this hand: none"

    stage_names = {"preflop": "Pre-Flop", "flop": "Flop", "turn": "Turn", "river": "River"}
    lines = ["table talk this hand (said out loud, everyone heard it):"]
    for item in talk:
        stage = stage_names.get(item.get("stage", ""), item.get("stage", ""))
        lines.append(f'- {item.get("name", "?")} ({stage}): "{item.get("speech", "")}"')
    return "\n".join(lines)

def build_prompt(
    game_state: Dict,
    player_id: str,
    valid_actions: List[str],
    min_bet: int,
    max_bet: int
) -> str:
    """构建决策提示词

    Args:
        game_state: 游戏状态
        player_id: 玩家ID
        valid_actions: 有效的动作列表
        min_bet: 最小下注额
        max_bet: 最大下注额

    Returns:
        str: 决策提示词
    """
    state_description = format_game_state(game_state, player_id)

    # 构建行动历史描述
    action_history_description = format_action_history(game_state)
    table_talk_description = format_table_talk(game_state)

    player_count = len(game_state["players"])

    # 人设只影响说话方式，不影响打法
    persona = game_state.get("persona")
    persona_description = f"""
your character at this table:
{persona}
Your character only shapes how you talk. It must not change how you play: make the best poker decision you can.
""" if persona else ""

    prompt = f"""
You are a professional Texas Hold'em player.
You are playing in a {player_count}-player Texas Hold'em game.
Assess the current situation and decide what kind of action to make.
{persona_description}
game state:
{state_description}

{action_history_description}

{table_talk_description}

you can take actions:
{', '.join(valid_actions)}

if you choose raise, the range of bet is:
- min: {min_bet} (this is the minimum total bet amount on the table)
- max: {max_bet} (this is your maximum possible total bet amount)

Please note that these are TOTAL bet amounts, not additional amounts. Your current bet is included in these numbers.

Please output your decision in JSON format, as follows:
{{
  "thinking": "your private inner monologue, in Chinese, first person, under 150 characters",
  "speech": "what you say out loud at the table, in Chinese, under 40 characters, or an empty string",
  "action": "fold|check|call|raise|allin",
  "amount": number (only when action is raise)
}}

Note:
1. Only choose the given valid actions
2. If 'check' is available in your valid actions, you should prefer it over 'fold'
3. If you choose raise, the amount must be in the range of min and max bet
4. Must output valid JSON format
5. "thinking" is private: no other player ever sees it. "speech" is heard by everyone at the table, so it can be trash talk, table banter or a bluff, and it never has to match your real hand
"""

    # 完整提示词包含手牌信息，只在DEBUG级别输出
    logger.debug("LLM接收到的完整提示词:\n%s", prompt)

    return prompt

# 中文动作映射
_CN_ACTION_MAP = {
    "弃牌": "fold",
    "跟注": "call",
    "加注": "raise",
    "提高": "raise",  # 有时模型会用"提高"表示raise
    "让牌": "check",
    "全下": "allin",
}

def _strip_code_blocks(text: str) -> str:
    """移除Markdown代码块标记"""
    cleaned = re.sub(r'```(?:json|javascript|python)?[\r\n]?', '', text)
    return cleaned.replace('```', '')

def _extract_json(response_text: str) -> Optional[Dict]:
    """尝试从响应文本中提取JSON对象，失败返回None"""
    candidates = []
    if "```json" in response_text:
        candidates.append(response_text.split("```json")[1].split("```")[0].strip())
    elif "```" in response_text:
        parts = response_text.split("```")
        if len(parts) > 1:
            candidates.append(parts[1].strip())
    candidates.append(response_text)
    # 模型常在JSON前后加说明文字，取第一个{到最后一个}之间的部分再试一次
    start, end = response_text.find("{"), response_text.rfind("}")
    if 0 <= start < end:
        candidates.append(response_text[start:end + 1])

    for candidate in candidates:
        try:
            # strict=False允许字符串里出现未转义的换行，模型写中文长思考时经常这样输出
            data = json.loads(candidate, strict=False)
            if isinstance(data, dict):
                return data
        except json.JSONDecodeError:
            continue
    return None

def _extract_action_from_text(response_text: str, valid_actions: Optional[List[str]]) -> Optional[str]:
    """用正则表达式从自由文本中提取动作"""
    action_patterns = [
        r"action[\"']?\s*[:=]\s*[\"']?([a-z]+)[\"']?",   # action: "fold"
        r"最终决策[:：]\s*([a-z]+)",                       # 最终决策：fold
        r"我?(?:选择|决定)(?:进行)?[\s:：]?([a-z]+)",      # 我选择fold
        r"我的(?:决策|行动|动作)是[\s:：]?([a-z]+)",       # 我的决策是fold
        r"I (?:choose|decide to) ([a-z]+)",              # I choose fold
        r"决定(弃牌|跟注|加注|让牌|全下)",                  # 决定加注
        r"(弃牌|跟注|加注|让牌|全下)",                     # 直接中文动作名
    ]

    for pattern in action_patterns:
        # 取最后一次匹配：思考里会先复述对手动作（"对手加注了"），最终决定一般在末尾
        matches = list(re.finditer(pattern, response_text, re.IGNORECASE))
        if not matches:
            continue
        action_match = matches[-1]

        # 取最后一个成功匹配的捕获组
        action = action_match.group(action_match.lastindex).lower()
        logger.debug("模式'%s'匹配到动作文本: '%s'", pattern, action)

        # 检查是否是中文动作
        if action in _CN_ACTION_MAP:
            action = _CN_ACTION_MAP[action]

        # 对齐到有效动作
        if valid_actions:
            for valid_action in valid_actions:
                if valid_action in action or action in valid_action:
                    return valid_action
        return action

    # 模式都没匹配到，检查动作关键词是否出现在文本中
    for cn_action, en_action in _CN_ACTION_MAP.items():
        if cn_action in response_text:
            logger.debug("从文本中检测到中文动作: %s -> %s", cn_action, en_action)
            return en_action

    lowered = response_text.lower()
    for keyword in ("fold", "check", "call", "raise", "allin"):
        if keyword in lowered:
            logger.debug("从文本中检测到英文动作关键词: %s", keyword)
            return keyword

    return None

def _extract_amount_from_text(response_text: str) -> Optional[int]:
    """用正则表达式从自由文本中提取下注金额"""
    amount_patterns = [
        r"amount[\"']?\s*[:=]\s*(\d+)",            # amount: 100
        r"(?:[加提]注|raise)\s?to\s?(\d+)",         # 加注to 100
        r"(?:[加提]注|raise)[\s:：]?(\d+)",         # 加注100
        r"(\d+)\s?筹码",                           # 100筹码
        r"金额[\s:：]?(\d+)",                       # 金额：100
        r"(\d+)\s?chips",                          # 100 chips
        r"最终决策[\s:：]?[a-z]+\s+(\d+)",          # 最终决策：raise 100
        r"加注.*?(\d+)",                           # 加注...100
        r"下注.*?(\d+)",                           # 下注...100
    ]

    for pattern in amount_patterns:
        amount_match = re.search(pattern, response_text, re.IGNORECASE)
        if amount_match:
            try:
                # 金额在最后一个成功匹配的捕获组
                return int(amount_match.group(amount_match.lastindex))
            except ValueError:
                continue
    return None

def _extract_thinking_from_text(response_text: str) -> Optional[str]:
    """从自由文本中提取思考过程段落"""
    thinking_patterns = [
        r"思考过程[:：]?\s*([\s\S]+?)(?=\n\s*(?:动作|行动|决策|Action|我决定|我选择|最终|result)|\Z)",
        r"理由[:：]?\s*([\s\S]+?)(?=\n\s*(?:动作|行动|决策|Action|我决定|我选择|最终|result)|\Z)",
        r"分析[:：]?\s*([\s\S]+?)(?=\n\s*(?:动作|行动|决策|Action|我决定|我选择|最终|result)|\Z)",
        r"thinking[:：]?\s*([\s\S]+?)(?=\n\s*(?:action|decision|result)|\Z)",
        r"analysis[:：]?\s*([\s\S]+?)(?=\n\s*(?:action|decision|result)|\Z)"
    ]

    for pattern in thinking_patterns:
        match = re.search(pattern, response_text, re.IGNORECASE | re.DOTALL)
        if match:
            return match.group(1).strip()
    return None

def _clean_thinking(thinking: str) -> str:
    """清理思考过程中的Markdown格式和残留JSON字符"""
    thinking = _strip_code_blocks(thinking)
    # 移除多余的空行
    thinking = re.sub(r'\n\s*\n', '\n\n', thinking)
    # 移除单独的{}行
    thinking = re.sub(r'^\s*[\{\}]\s*$', '', thinking, flags=re.MULTILINE)
    return thinking.strip()

def extract_speech(response_text: str, max_len: int = 80) -> Optional[str]:
    """从LLM响应中提取说出口的台词，没有则返回None"""
    if not response_text:
        return None
    speech = None
    data = _extract_json(response_text)
    if data is not None and isinstance(data.get("speech"), str):
        speech = data["speech"]
    else:
        match = re.search(r'"speech"\s*:\s*"([^"]*)"', response_text)
        if match:
            speech = match.group(1)
    if speech is None:
        return None
    speech = speech.strip()
    return speech[:max_len] or None

def parse_response(response_text: str, valid_actions=None, min_bet=None, max_bet=None) -> Tuple[str, Optional[int], Optional[str]]:
    """
    解析LLM响应，提取动作和下注金额

    解析分三层回退：
    1. JSON解析（含```json代码块）
    2. 正则表达式从自由文本提取（含中文动作）
    3. 默认动作（check > call > fold）

    参数:
        response_text: LLM返回的文本响应
        valid_actions: 有效的动作列表
        min_bet: 最小下注金额
        max_bet: 最大下注金额

    返回:
        tuple: (动作, 金额, 思考过程)
    """
    thinking = None
    action = None
    amount = None

    logger.debug("解析响应长度: %d 字符", len(response_text))

    # 第一层：尝试解析为JSON
    response_data = _extract_json(response_text)
    if response_data is not None:
        logger.debug("JSON解析成功: %s", response_data)
        action = str(response_data.get("action", "")).lower() or None
        amount = response_data.get("amount")
        if isinstance(amount, str):
            amount = int(amount) if amount.isdigit() else None
        elif isinstance(amount, float):
            amount = int(amount)
        elif not isinstance(amount, (int, type(None))):
            amount = None
        thinking = response_data.get("thinking")

        # 如果提取到JSON但没有thinking字段，保留清理后的原始响应
        if thinking is None:
            thinking = _strip_code_blocks(response_text)
    else:
        # 第二层：JSON解析失败，用正则表达式从文本中提取
        logger.debug("JSON解析失败，尝试使用正则表达式解析")

        action = _extract_action_from_text(response_text, valid_actions)
        amount = _extract_amount_from_text(response_text)

        # 如果是raise但没找到金额，尝试使用响应中的最后一个数字
        if action == "raise" and amount is None:
            all_numbers = re.findall(r'\d+', response_text)
            if all_numbers:
                amount = int(all_numbers[-1])
                logger.debug("从响应中提取到数字作为金额: %d", amount)

        # 提取思考过程，找不到则使用清理后的完整响应
        thinking = _extract_thinking_from_text(response_text)
        if thinking is None:
            thinking = _strip_code_blocks(response_text)

    # 提取到的动作不在有效动作列表中时，先尝试就近修正，再回退默认动作
    if valid_actions and action and action not in valid_actions:
        logger.warning("提取到的动作'%s'不在有效动作列表%s中", action, valid_actions)
        closest_action = next(
            (va for va in valid_actions if va in action or action in va),
            None
        )
        if closest_action:
            logger.debug("修正动作'%s'为'%s'", action, closest_action)
            action = closest_action
        else:
            action = choose_default_action(valid_actions)
            logger.warning("无法匹配有效动作，使用默认动作: %s", action)

    # 第三层：仍然没有提取到动作，使用默认动作
    if not action and valid_actions:
        action = choose_default_action(valid_actions)
        logger.warning("未能从响应中提取动作，使用默认动作: %s", action)

    # 非raise动作不携带金额
    if action != "raise":
        amount = None

    # 验证并钳制金额
    if action == "raise":
        if amount is not None:
            if min_bet is not None and amount < min_bet:
                logger.warning("下注金额%d小于最小下注额%d，调整为最小下注额", amount, min_bet)
                amount = min_bet
            if max_bet is not None and amount > max_bet:
                logger.warning("下注金额%d大于最大下注额%d，调整为最大下注额", amount, max_bet)
                amount = max_bet
        elif min_bet is not None:
            logger.warning("raise动作没有指定金额，使用最小下注额: %d", min_bet)
            amount = min_bet

    # 最终清理思考过程内容
    if thinking:
        thinking = _clean_thinking(thinking)

    logger.debug("最终解析结果: 动作=%s, 金额=%s", action, amount)
    return action, amount, thinking
