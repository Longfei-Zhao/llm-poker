from typing import Dict, List, Optional, Any, Tuple
import json
import os
import httpx
import asyncio
import time

from .base_agent import BaseAgent
from ..exceptions import APIError

try:
    import torch
    from transformers import AutoTokenizer, AutoModelForCausalLM, pipeline
    has_transformers = True
    print("✅ Transformers库依赖加载成功")
    
    if torch.cuda.is_available():
        print(f"✅ 检测到CUDA设备: {torch.cuda.get_device_name(0)}")
    else:
        print("⚠️ 未检测到CUDA设备，将使用CPU进行推理")
except ImportError:
    has_transformers = False
    print("❌ Transformers库依赖加载失败，本地LLM功能将被禁用")

class LocalLLMAgent(BaseAgent):
    """本地LLM代理类，使用Transformers库加载本地模型"""
    
    def __init__(
        self,
        player_id: str,
        name: str,
        model: str,
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
            provider: 提供商标识(local或aliyun)
            **kwargs: 其他参数
        """
        super().__init__(player_id, name)
        self.model_name = model
        self.temperature = temperature
        self.provider = provider
        
        # 记录初始化信息
        provider_name = "阿里云通义千问" if provider == "aliyun" else "本地LLM"
        print(f"🔧 初始化{provider_name}代理 - 玩家ID: {player_id}, 名称: {name}")
        print(f"📦 模型: {model}, 温度: {temperature}")
        
        # 检查依赖
        if not has_transformers:
            print(f"❌ {player_id}({name}): Transformers库未安装，无法加载本地模型")
            raise ImportError("Transformers库未安装，请使用pip install transformers安装")
        
        self.tokenizer = None
        self.pipeline = None
        self._is_model_loaded = False
        
        # 手牌和公共牌状态
        self.hand_cards = []
        self.community_cards = []
        self.position = ""
        self.chips = 0
        
        print(f"✅ {provider_name}代理初始化完成 - {player_id}({name})")
    
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
            print(f"🔄 {self.player_id}({self.name}): 开始加载模型 {self.model_name}")
            
            # 加载分词器
            print(f"🔄 {self.player_id}({self.name}): 加载分词器...")
            self.tokenizer = AutoTokenizer.from_pretrained(self.model_name, trust_remote_code=True)
            
            # 设备配置
            device = "cuda" if torch.cuda.is_available() else "cpu"
            print(f"🔄 {self.player_id}({self.name}): 使用设备: {device}")
            
            # 加载模型
            print(f"🔄 {self.player_id}({self.name}): 加载模型...")
            model = AutoModelForCausalLM.from_pretrained(
                self.model_name,
                device_map=device,
                trust_remote_code=True,
                torch_dtype=torch.float16 if device == "cuda" else torch.float32
            )
            
            # 创建pipeline
            print(f"🔄 {self.player_id}({self.name}): 创建生成pipeline...")
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
            print(f"✅ {self.player_id}({self.name}): 模型加载完成，耗时: {elapsed_time:.2f}秒")
            
        except Exception as e:
            print(f"❌ {self.player_id}({self.name}): 模型加载失败: {str(e)}")
            raise
    
    def update_state(self, hand_cards: List[str], community_cards: List[str], position: str, chips: int) -> None:
        """
        更新代理状态。
        
        Args:
            hand_cards: 手牌列表
            community_cards: 公共牌列表
            position: 位置标识
            chips: 筹码数量
        """
        self.hand_cards = hand_cards
        self.community_cards = community_cards
        self.position = position
        self.chips = chips
        print(f"📊 {self.player_id}({self.name}): 状态更新 - 手牌: {hand_cards}, 公共牌: {community_cards}, 位置: {position}, 筹码: {chips}")
    
    async def make_decision(
        self, 
        game_state: Dict, 
        valid_actions: List[str],
        min_bet: int,
        max_bet: int
    ) -> Tuple[str, Optional[int]]:
        """
        根据游戏状态做出决策。
        
        Args:
            game_state: 游戏状态
            valid_actions: 有效动作列表
            min_bet: 最小下注金额
            max_bet: 最大下注金额
            
        Returns:
            Tuple[str, Optional[int]]: 决策动作和金额
        """
        # 确保模型已加载
        if not self._is_model_loaded:
            print(f"🔄 {self.player_id}({self.name}): 模型尚未加载，正在加载...")
            self._ensure_model_loaded()
        
        # 生成提示词
        print(f"🔄 {self.player_id}({self.name}): 开始生成决策...")
        prompt = self._generate_prompt(game_state, valid_actions, min_bet, max_bet)
        print(f"📝 {self.player_id}({self.name}): 生成提示词 - 长度: {len(prompt)}")
        
        # 记录当前游戏状态
        game_stage = game_state.get('stage', 'unknown')
        pot = game_state.get('pot', 0)
        print(f"🎮 {self.player_id}({self.name}): 当前游戏阶段: {game_stage}, 底池: {pot}, 有效动作: {valid_actions}")
        
        try:
            # 使用asyncio将模型推理包装为异步
            start_time = time.time()
            print(f"🧠 {self.player_id}({self.name}): 开始模型推理...")
            
            # 在事件循环的线程池中运行模型推理
            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(None, self._generate_response, prompt)
            
            elapsed_time = time.time() - start_time
            print(f"✅ {self.player_id}({self.name}): 推理完成，耗时: {elapsed_time:.2f}秒")
            print(f"💬 {self.player_id}({self.name}): 原始响应: {response}")
            
            # 解析决策
            action, amount = self._parse_decision(response, valid_actions, min_bet, max_bet)
            print(f"📊 {self.player_id}({self.name}): 解析决策结果 - 动作: {action}, 金额: {amount}")
            
            return action, amount
            
        except Exception as e:
            print(f"❌ {self.player_id}({self.name}): 决策生成失败: {str(e)}")
            # 出错时进行随机决策
            if 'fold' in valid_actions:
                print(f"⚠️ {self.player_id}({self.name}): 异常时默认选择fold")
                return 'fold', None
            elif 'check' in valid_actions:
                print(f"⚠️ {self.player_id}({self.name}): 异常时默认选择check")
                return 'check', None
            else:
                print(f"⚠️ {self.player_id}({self.name}): 异常时默认选择call")
                return 'call', None
    
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
            print(f"❌ {self.player_id}({self.name}): 生成响应出错: {str(e)}")
            raise
    
    def _generate_prompt(self, game_state: Dict, valid_actions: List[str], min_bet: int, max_bet: int) -> str:
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
        min_bet: int,
        max_bet: int
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
        print(f"🔍 {self.player_id}({self.name}): 解析决策响应...")
        
        try:
            # 尝试提取JSON
            json_start = response.find('{')
            json_end = response.rfind('}') + 1
            
            if json_start == -1 or json_end == 0:
                # 没有找到JSON，尝试直接解析文本
                print(f"⚠️ {self.player_id}({self.name}): 未找到JSON格式响应，尝试直接解析文本")
                return self._parse_text_decision(response, valid_actions, min_bet, max_bet)
            
            json_str = response[json_start:json_end]
            decision = json.loads(json_str)
            
            # 提取动作
            action = decision.get('action', '').lower()
            
            # 验证动作有效性
            if action not in valid_actions:
                print(f"⚠️ {self.player_id}({self.name}): 无效动作 {action}，有效动作: {valid_actions}")
                action = self._fallback_action(valid_actions)
            
            # 提取金额(如果需要)
            amount = None
            if action in ['bet', 'raise']:
                amount = decision.get('amount')
                if isinstance(amount, str) and amount.isdigit():
                    amount = int(amount)
                
                # 验证金额有效性
                if not isinstance(amount, int) or amount < min_bet or amount > max_bet:
                    print(f"⚠️ {self.player_id}({self.name}): 无效金额 {amount}，范围: {min_bet}-{max_bet}")
                    amount = min(max(min_bet, amount if isinstance(amount, int) else min_bet), max_bet)
            
            return action, amount
            
        except Exception as e:
            print(f"⚠️ {self.player_id}({self.name}): 解析JSON失败: {str(e)}，尝试文本解析")
            return self._parse_text_decision(response, valid_actions, min_bet, max_bet)
    
    def _parse_text_decision(
        self, 
        response: str, 
        valid_actions: List[str],
        min_bet: int,
        max_bet: int
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
        print(f"📝 {self.player_id}({self.name}): 尝试从文本解析决策")
        
        # 将响应转换为小写便于匹配
        response = response.lower()
        
        # 依次检查是否包含有效动作的关键词
        for action in valid_actions:
            if action in response:
                print(f"🔍 {self.player_id}({self.name}): 从文本中匹配到动作: {action}")
                
                # 如果是下注或加注，尝试提取金额
                amount = None
                if action in ['bet', 'raise']:
                    # 尝试查找数字
                    import re
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
                        print(f"🔢 {self.player_id}({self.name}): 从文本中提取金额: {amount}")
                    
                    # 确保金额在有效范围内
                    if amount is None or amount < min_bet or amount > max_bet:
                        amount = min(max(min_bet, amount if amount is not None else min_bet), max_bet)
                        print(f"📊 {self.player_id}({self.name}): 调整金额到有效范围: {amount}")
                
                return action, amount
        
        # 没有找到匹配的动作，使用后备动作
        action = self._fallback_action(valid_actions)
        print(f"⚠️ {self.player_id}({self.name}): 未找到匹配动作，使用后备动作: {action}")
        return action, None
    
    def _fallback_action(self, valid_actions: List[str]) -> str:
        """
        提供后备动作。
        
        Args:
            valid_actions: 有效动作列表
            
        Returns:
            str: 后备动作
        """
        # 使用基类的默认动作选择方法
        return self._get_default_action(valid_actions)

    def _format_game_state(self, game_state: Dict) -> str:
        """格式化游戏状态
        
        Args:
            game_state: 游戏状态字典
            
        Returns:
            str: 格式化后的游戏状态描述
        """
        # 获取当前玩家
        current_player = next(
            (p for p in game_state["players"] if p["id"] == self.player_id),
            None
        )
        if not current_player:
            raise ValueError("在游戏状态中找不到当前玩家")
            
        # 获取其他玩家
        other_players = [
            p for p in game_state["players"]
            if p["id"] != self.player_id and p["isActive"]
        ]
        
        # 构建状态描述
        description = f"""
游戏阶段: {game_state['state']}
底池: {game_state['pot']}
当前最大下注: {game_state['currentBet']}

你的信息:
- 名称: {current_player['name']}
- 筹码: {current_player['chips']}
- 已下注: {current_player['bet']}
- 手牌: {', '.join(current_player['cards'])}
- 位置: {current_player['position']}

公共牌: {', '.join(game_state['communityCards']) if game_state['communityCards'] else '无'}

其他玩家:
"""
        
        for player in other_players:
            description += f"""
- 名称: {player['name']}
- 筹码: {player['chips']}
- 已下注: {player['bet']}
- 位置: {player['position']}
"""
            
        return description 