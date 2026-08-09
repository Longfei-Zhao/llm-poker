const { GameService } = require('../services/game.service');

class GameController {
  constructor() {
    this.gameService = new GameService();
  }

  // 创建新游戏
  async createGame(players) {
    try {
      const game = await this.gameService.createGame(players);
      return game;
    } catch (error) {
      console.error('Error creating game:', error);
      throw error;
    }
  }

  // 开始游戏
  async startGame(gameId) {
    try {
      const game = await this.gameService.startGame(gameId);
      return game;
    } catch (error) {
      console.error('Error starting game:', error);
      throw error;
    }
  }

  // 玩家行动
  async playerAction(gameId, playerId, action, amount = 0) {
    try {
      const gameState = await this.gameService.handlePlayerAction(gameId, playerId, action, amount);
      return gameState;
    } catch (error) {
      console.error('Error handling player action:', error);
      throw error;
    }
  }

  // 获取游戏状态
  async getGameState(gameId) {
    try {
      const gameState = await this.gameService.getGameState(gameId);
      return gameState;
    } catch (error) {
      console.error('Error getting game state:', error);
      throw error;
    }
  }
}

module.exports = { GameController }; 