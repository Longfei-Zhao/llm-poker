const axios = require('axios');
const config = require('../config');

class AIService {
    constructor() {
        this.client = axios.create({
            baseURL: config.AI_SERVICE_URL || 'http://localhost:8000',
            // AI服务内部单次调用30秒且带重试，后端必须等得比它久，否则会提前放弃并回退成check/fold
            timeout: config.AI_REQUEST_TIMEOUT_MS
        });
        
        console.log(`AI服务初始化: ${config.AI_SERVICE_URL || 'http://localhost:8000'}`);
    }

    /**
     * 创建AI代理
     * @param {string} playerId - 玩家ID
     * @param {string} name - 玩家名称
     * @param {string} provider - LLM提供商
     * @param {string} [model] - 模型名称（可选）
     * @param {number} [temperature=0.7] - 采样温度（可选）
     * @returns {Promise<Object>} 创建结果
     */
    async createAgent(playerId, name, provider, model = null, temperature = 0.7) {
        try {
            console.log(`尝试创建AI代理: ${name}, provider: ${provider}, model: ${model}`);
            
            const response = await this.client.post('/api/agents', {
                player_id: playerId,
                name,
                provider,
                model,
                temperature
            });
            
            console.log(`AI代理创建成功: ${playerId}`);
            return response.data;
        } catch (error) {
            console.error('创建AI代理失败:', error.message);
            if (error.response) {
                console.error('AI服务响应:', error.response.data);
                console.error('状态码:', error.response.status);
            } else if (error.request) {
                console.error('AI服务请求失败:', '无响应');
            } else {
                console.error('请求设置错误:', error.message);
            }
            
            // 抛出更具体的错误
            if (error.code === 'ECONNREFUSED') {
                throw new Error('无法连接到AI服务，请确保AI服务已启动');
            } else if (error.response && error.response.status === 404) {
                throw new Error('AI服务API路径不存在');
            } else {
                throw new Error(`创建AI代理失败: ${error.message}`);
            }
        }
    }

    /**
     * 获取AI决策
     * @param {string} playerId - 玩家ID
     * @param {Object} gameState - 游戏状态
     * @param {Array<string>} validActions - 有效动作列表
     * @param {number} minBet - 最小下注额
     * @param {number} maxBet - 最大下注额
     * @returns {Promise<{action: string, amount?: number}>} 决策结果
     */
    async getDecision(playerId, gameState, validActions, minBet, maxBet) {
        try {
            console.log(`获取AI决策: 玩家${playerId}, 有效动作: ${validActions.join(', ')}`);
            
            const response = await this.client.post('/api/decision', {
                player_id: playerId,
                game_state: gameState,
                valid_actions: validActions,
                min_bet: minBet,
                max_bet: maxBet
            });
            
            console.log(`AI决策成功: ${playerId}, 动作: ${response.data.action}`);
            
            // 确保即使API响应中缺少某些字段，也能返回完整结构
            const action = response.data.action || 'fold';
            const amount = response.data.amount !== undefined ? response.data.amount : 0;
            const thinking = response.data.thinking || `AI玩家${playerId}使用${gameState.players.find(p => p.id === playerId)?.aiModel || '未知模型'}思考后选择了${action}`;
            
            // 返回思考过程和决策结果；inner是模型原始心声（可能为空），speech是说出口的台词
            return {
                action,
                amount,
                thinking,
                inner: response.data.thinking || null,
                speech: response.data.speech || null
            };
        } catch (error) {
            console.error('获取AI决策失败:', error.message);
            if (error.response) {
                console.error('AI服务响应:', error.response.data);
                console.error('状态码:', error.response.status);
            } else if (error.request) {
                console.error('AI服务请求失败:', '无响应');
            } else {
                console.error('请求设置错误:', error.message);
            }
            
            if (error.code === 'ECONNREFUSED') {
                throw new Error('无法连接到AI服务，请确保AI服务已启动');
            } else {
                throw new Error(`获取AI决策失败: ${error.message}`);
            }
        }
    }

    /**
     * 删除AI代理
     * @param {string} playerId - 玩家ID
     * @returns {Promise<void>}
     */
    async deleteAgent(playerId) {
        try {
            console.log(`尝试删除AI代理: ${playerId}`);
            
            await this.client.delete(`/api/agents/${playerId}`);
            
            console.log(`AI代理删除成功: ${playerId}`);
        } catch (error) {
            console.error('删除AI代理失败:', error.message);
            if (error.response) {
                console.error('AI服务响应:', error.response.data);
                console.error('状态码:', error.response.status);
            } else if (error.request) {
                console.error('AI服务请求失败:', '无响应');
            } else {
                console.error('请求设置错误:', error.message);
            }
            
            throw new Error(`删除AI代理失败: ${error.message}`);
        }
    }

    /**
     * 删除所有AI代理
     * @returns {Promise<void>}
     */
    async deleteAllAgents() {
        try {
            console.log('尝试删除所有AI代理');
            
            // 先获取所有代理
            const agents = await this.listAgents();
            
            // 删除每个代理
            for (const agent of agents) {
                await this.deleteAgent(agent.player_id);
            }
            
            console.log(`成功删除所有AI代理: 共${agents.length}个`);
        } catch (error) {
            console.error('删除所有AI代理失败:', error.message);
            if (error.response) {
                console.error('AI服务响应:', error.response.data);
                console.error('状态码:', error.response.status);
            } else if (error.request) {
                console.error('AI服务请求失败:', '无响应');
            } else {
                console.error('请求设置错误:', error.message);
            }
            
            throw new Error(`删除所有AI代理失败: ${error.message}`);
        }
    }

    /**
     * 检查AI服务健康状态
     * @returns {Promise<boolean>} 服务是否健康
     */
    async checkHealth() {
        try {
            console.log('检查AI服务健康状态');
            
            const response = await this.client.get('/api/health');
            const isHealthy = response.data.status === 'ok';
            
            console.log(`AI服务健康状态: ${isHealthy ? '正常' : '异常'}`);
            return isHealthy;
        } catch (error) {
            console.error('AI服务健康检查失败:', error.message);
            if (error.code === 'ECONNREFUSED') {
                console.error('无法连接到AI服务，请确保AI服务已启动');
            }
            return false;
        }
    }

    /**
     * 获取所有AI代理列表
     * @returns {Promise<Array>} 代理列表
     */
    async listAgents() {
        try {
            console.log('获取AI代理列表');
            
            const response = await this.client.get('/api/agents');
            
            console.log(`获取到${response.data.length}个AI代理`);
            return response.data;
        } catch (error) {
            console.error('获取AI代理列表失败:', error.message);
            if (error.response) {
                console.error('AI服务响应:', error.response.data);
                console.error('状态码:', error.response.status);
            } else if (error.request) {
                console.error('AI服务请求失败:', '无响应');
            } else {
                console.error('请求设置错误:', error.message);
            }
            
            throw new Error(`获取AI代理列表失败: ${error.message}`);
        }
    }
}

module.exports = new AIService(); 