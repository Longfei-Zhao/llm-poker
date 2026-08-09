require('dotenv').config();

module.exports = {
    // 服务器配置
    PORT: process.env.PORT || 3000,
    
    // AI服务配置
    AI_SERVICE_URL: process.env.AI_SERVICE_URL || 'http://localhost:8000',

    // 游戏配置（盲注唯一来源，引擎和WS层统一从这里读取）
    SMALL_BLIND: parseInt(process.env.SMALL_BLIND, 10) || 5,
    BIG_BLIND: parseInt(process.env.BIG_BLIND, 10) || 10,

    // 日志配置
    LOG_LEVEL: process.env.LOG_LEVEL || 'info',
    
    // 其他配置
    DEBUG: process.env.DEBUG === 'true'
}; 