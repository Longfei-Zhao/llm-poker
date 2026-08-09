require('dotenv').config();

module.exports = {
    // 服务器配置
    PORT: process.env.PORT || 3000,
    
    // AI服务配置
    AI_SERVICE_URL: process.env.AI_SERVICE_URL || 'http://localhost:8000',
    
    // 日志配置
    LOG_LEVEL: process.env.LOG_LEVEL || 'info',
    
    // 其他配置
    DEBUG: process.env.DEBUG === 'true'
}; 