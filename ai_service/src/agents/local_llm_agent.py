from typing import Dict, List, Optional, Tuple
import json
import asyncio
import logging
import time
import re

from .base_agent import BaseAgent
from ..exceptions import ConfigError
from ..config.agent_config import get_default_model
from ..prompts.prompt_utils import extract_speech

logger = logging.getLogger(__name__)

# torch/transformers是可选依赖：导入失败时工厂仍可正常工作，
# 只有真正创建local代理时才报错
try:
    import torch
    from transformers import AutoTokenizer, AutoModelForCausalLM, pipeline
    has_transformers = True
except ImportError:
    has_transformers = False

class LocalLLMAgent(BaseAgent):
    """本地LLM代理类，使用Transformers库加载本地模型"""

    def __init__(
        self,
        player_id: str,
        name: str,
        model: Optional[str] = None,
        temperature: float = 0.7,
        provider: str = "local",
        **kwargs
    ):
        """
        初始化本地LLM代理。

        Args:
            player_id: 玩家ID
            name: 玩家名称
            model: 模型ID或路径
            temperature: 采样温度
            provider: 提供商标识
            **kwargs: 其他参数
        """
        super().__init__(player_id, name)
        self.model_name = model or get_default_model("local")
        self.temperature = temperature
        self.provider = provider

        logger.info("初始化本地LLM代理 - 玩家ID: %s, 名称: %s, 模型: %s", player_id, name, self.model_name)

        # 检查可选依赖，缺失时给出明确错误
        if not has_transformers:
            logger.error("%s(%s): torch/transformers未安装，无法使用本地模型", player_id, name)
            raise ConfigError("本地LLM代理需要torch和transformers库，请先安装: pip install torch transformers")

        self.tokenizer = None
        self.pipeline = None
        self._is_model_loaded = False

    @property
    def is_model_loaded(self) -> bool:
        """检查模型是否已加载"""
        return self._is_model_loaded

    def _ensure_model_loaded(self) -> None:
        """确保模型已加载"""
        if not self._is_model_loaded:
            self._load_model()

    def _load_model(self) -> None:
        """加载本地模型"""
        try:
            start_time = time.time()
            logger.info("%s(%s): 开始加载模型 %s", self.player_id, self.name, self.model_name)

            # 加载分词器
            self.tokenizer = AutoTokenizer.from_pretrained(self.model_name, trust_remote_code=True)

            # 设备配置
            device = "cuda" if torch.cuda.is_available() else "cpu"
            logger.info("%s(%s): 使用设备: %s", self.player_id, self.name, device)

            # 加载模型
            model = AutoModelForCausalLM.from_pretrained(
                self.model_name,
                device_map=device,
                trust_remote_code=True,
                torch_dtype=torch.float16 if device == "cuda" else torch.float32
            )

            # 创建pipeline
            self.pipeline = pipeline(
                "text-generation",
                model=model,
                tokenizer=self.tokenizer,
                max_new_tokens=2048,
                trust_remote_code=True,
                device_map=device
            )

            self._is_model_loaded = True
            elapsed_time = time.time() - start_time
            logger.info("%s(%s): 模型加载完成，耗时: %.2f秒", self.player_id, self.name, elapsed_time)

        except Exception as e:
            logger.error("%s(%s): 模型加载失败: %s", self.player_id, self.name, e)
            raise

    async def make_decision(
        self,
        game_state: Dict,
        valid_actions: List[str],
        min_bet: Optional[int] = None,
        max_bet: Optional[int] = None
    ) -> Tuple[str, Optional[int], Optional[str]]:
        """
        根据游戏状态做出决策。

        Args:
            game_state: 游戏状态
            valid_actions: 有效动作列表
            min_bet: 最小下注金额
            max_bet: 最大下注金额

        Returns:
            Tuple[str, Optional[int], Optional[str]]: 决策动作、金额和思考过程
        """
        # 确保模型已加载
        if not self._is_model_loaded:
            self._ensure_model_loaded()

        # 生成提示词
        prompt = self._generate_prompt(game_state, valid_actions, min_bet, max_bet)
        logger.debug("%s(%s): 生成提示词:\n%s", self.player_id, self.name, prompt)

        # 记录当前游戏状态
        game_stage = game_state.get('stage', 'unknown')
        pot = game_state.get('pot', 0)
        logger.info("%s(%s): 当前游戏阶段: %s, 底池: %s, 有效动作: %s",
                    self.player_id, self.name, game_stage, pot, valid_actions)

        try:
            # 使用线程池将同步模型推理包装为异步，避免阻塞事件循环
            start_time = time.time()
            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(None, self._generate_response, prompt)

            elapsed_time = time.time() - start_time
            logger.info("%s(%s): 推理完成，耗时: %.2f秒", self.player_id, self.name, elapsed_time)
            logger.debug("%s(%s): 原始响应: %s", self.player_id, self.name, response)

            # 解析决策
            action, amount = self._parse_decision(response, valid_actions, min_bet, max_bet)

            # 验证决策，无效时回退为默认动作
            action, amount = self._sanitize_decision(action, amount, valid_actions, min_bet, max_bet)
            logger.info("%s(%s): 决策结果 - 动作: %s, 金额: %s", self.player_id, self.name, action, amount)

            self.last_speech = extract_speech(response)
            return action, amount, response

        except Exception as e:
            logger.error("%s(%s): 决策生成失败: %s", self.player_id, self.name, e)
            # 出错时使用默认动作（check > call > fold）
            fallback = self._get_default_action(valid_actions)
            logger.warning("%s(%s): 异常时默认选择%s", self.player_id, self.name, fallback)
            return fallback, None, f"决策生成失败: {str(e)}"

    def _generate_response(self, prompt: str) -> str:
        """
        生成模型响应。

        Args:
            prompt: 提示词

        Returns:
            str: 模型响应
        """
        try:
            # 使用pipeline生成响应
            outputs = self.pipeline(
                prompt,
                do_sample=True,
                temperature=self.temperature,
                max_new_tokens=200,  # 限制生成长度
                num_return_sequences=1
            )

            # 提取生成的文本
            generated_text = outputs[0]['generated_text']

            # 移除提示词部分，只保留模型生成的部分
            response = generated_text[len(prompt):].strip()
            return response

        except Exception as e:
            logger.error("%s(%s): 生成响应出错: %s", self.player_id, self.name, e)
            raise

    def _generate_prompt(self, game_state: Dict, valid_actions: List[str], min_bet: Optional[int], max_bet: Optional[int]) -> str:
        """
        生成提示词。

        Args:
            game_state: 游戏状态
            valid_actions: 有效动作列表
            min_bet: 最小下注金额
            max_bet: 最大下注金额

        Returns:
            str: 提示词
        """
        # 解析游戏状态
        stage = game_state.get('stage', 'unknown')
        pot = game_state.get('pot', 0)
        current_player_id = game_state.get('currentPlayerId', '')

        # 获取自己的信息
        try:
            me = next(p for p in game_state['players'] if p['id'] == self.player_id)
            my_bet = me.get('bet', 0)
            my_chips = me.get('chips', 0)
        except (StopIteration, KeyError):
            my_bet = 0
            my_chips = self.chips

        # 获取其他玩家信息
        other_players = [p for p in game_state.get('players', []) if p['id'] != self.player_id]

        # 构建提示词
        prompt = f"""你是一名精通德州扑克的AI玩家，名字是{self.name}。现在请你根据当前游戏情况，做出最优的决策。

游戏信息:
- 阶段: {stage}
- 底池: {pot}筹码
- 你的手牌: {', '.join(self.hand_cards)}
- 公共牌: {', '.join(self.community_cards)}
- 你的位置: {self.position}
- 你的筹码: {my_chips}
- 你当前下注: {my_bet}

其他玩家:
"""
        # 添加其他玩家信息
        for player in other_players:
            player_id = player.get('id', '')
            is_current = player_id == current_player_id
            prompt += f"- {player.get('name', '')}{'(当前行动)' if is_current else ''}: 筹码{player.get('chips', 0)}, 当前下注{player.get('bet', 0)}\n"

        # 添加可选动作
        prompt += f"\n你可以采取的行动: {', '.join(valid_actions)}"
        if 'bet' in valid_actions or 'raise' in valid_actions:
            prompt += f"，下注范围: {min_bet}-{max_bet}"

        # 添加策略指导
        prompt += """

决策策略指导:
1. 如果'check'(让牌)是你的有效行动选项之一，除非你的牌非常弱且没有改善的可能，否则应优先选择check而不是fold(弃牌)。让牌可以让你继续留在游戏中而不需要额外投入筹码。
2. 只有当你认为你的牌赢的机会很小，且需要投入更多筹码(不能check)时，才考虑fold。
3. 做决策时要考虑你的位置、底池赔率和潜在的牌力。
"""

        # 要求输出格式
        prompt += """

请你分析当前牌局情况，根据你的策略做出一个决策。输出格式如下:
```json
{
  "action": "动作名称(fold/check/call/bet/raise之一)",
  "amount": 下注金额(仅当action为bet或raise时需要)
}
```

你的决策:
"""
        return prompt

    def _parse_decision(
        self,
        response: str,
        valid_actions: List[str],
        min_bet: Optional[int],
        max_bet: Optional[int]
    ) -> Tuple[str, Optional[int]]:
        """
        解析模型响应，提取决策。

        Args:
            response: 模型响应
            valid_actions: 有效动作列表
            min_bet: 最小下注金额
            max_bet: 最大下注金额

        Returns:
            Tuple[str, Optional[int]]: 决策动作和金额
        """
        try:
            # 尝试提取JSON
            json_start = response.find('{')
            json_end = response.rfind('}') + 1

            if json_start == -1 or json_end == 0:
                # 没有找到JSON，尝试直接解析文本
                logger.debug("%s(%s): 未找到JSON格式响应，尝试直接解析文本", self.player_id, self.name)
                return self._parse_text_decision(response, valid_actions, min_bet, max_bet)

            json_str = response[json_start:json_end]
            decision = json.loads(json_str)

            # 提取动作
            action = decision.get('action', '').lower()

            # 验证动作有效性
            if action not in valid_actions:
                logger.warning("%s(%s): 无效动作 %s，有效动作: %s", self.player_id, self.name, action, valid_actions)
                action = self._get_default_action(valid_actions)

            # 提取金额(如果需要)
            amount = None
            if action in ['bet', 'raise']:
                amount = decision.get('amount')
                if isinstance(amount, str) and amount.isdigit():
                    amount = int(amount)

                # 验证金额有效性
                if not isinstance(amount, int) or (min_bet is not None and amount < min_bet) or (max_bet is not None and amount > max_bet):
                    logger.warning("%s(%s): 无效金额 %s，范围: %s-%s", self.player_id, self.name, amount, min_bet, max_bet)
                    fallback_amount = amount if isinstance(amount, int) else (min_bet or 0)
                    lower = min_bet if min_bet is not None else fallback_amount
                    upper = max_bet if max_bet is not None else fallback_amount
                    amount = min(max(lower, fallback_amount), upper)

            return action, amount

        except (json.JSONDecodeError, ValueError) as e:
            logger.debug("%s(%s): 解析JSON失败: %s，尝试文本解析", self.player_id, self.name, e)
            return self._parse_text_decision(response, valid_actions, min_bet, max_bet)

    def _parse_text_decision(
        self,
        response: str,
        valid_actions: List[str],
        min_bet: Optional[int],
        max_bet: Optional[int]
    ) -> Tuple[str, Optional[int]]:
        """
        从文本中解析决策。

        Args:
            response: 模型响应
            valid_actions: 有效动作列表
            min_bet: 最小下注金额
            max_bet: 最大下注金额

        Returns:
            Tuple[str, Optional[int]]: 决策动作和金额
        """
        # 将响应转换为小写便于匹配
        response = response.lower()

        # 依次检查是否包含有效动作的关键词
        for action in valid_actions:
            if action in response:
                logger.debug("%s(%s): 从文本中匹配到动作: %s", self.player_id, self.name, action)

                # 如果是下注或加注，尝试提取金额
                amount = None
                if action in ['bet', 'raise']:
                    # 尝试查找数字
                    numbers = re.findall(r'\b(\d+)\b', response)
                    if numbers:
                        # 使用最靠近动作词的数字作为金额
                        action_pos = response.find(action)
                        closest_number = None
                        min_distance = float('inf')

                        for num_str in numbers:
                            num_pos = response.find(num_str)
                            distance = abs(num_pos - action_pos)
                            if distance < min_distance:
                                min_distance = distance
                                closest_number = int(num_str)

                        amount = closest_number

                    # 确保金额在有效范围内
                    if min_bet is not None or max_bet is not None:
                        fallback_amount = amount if amount is not None else (min_bet or 0)
                        lower = min_bet if min_bet is not None else fallback_amount
                        upper = max_bet if max_bet is not None else fallback_amount
                        amount = min(max(lower, fallback_amount), upper)

                return action, amount

        # 没有找到匹配的动作，使用默认动作
        action = self._get_default_action(valid_actions)
        logger.warning("%s(%s): 未找到匹配动作，使用默认动作: %s", self.player_id, self.name, action)
        return action, None
