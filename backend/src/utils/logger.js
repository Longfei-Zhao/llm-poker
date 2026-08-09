const config = require('../config');

// 简单的分级日志工具，级别由config.LOG_LEVEL控制
// debug级别用于输出敏感细节（手牌、牌堆等），默认info级别不打印
const LEVELS = { debug: 10, info: 20, warn: 30, error: 40, silent: 99 };
const threshold = LEVELS[(config.LOG_LEVEL || 'info').toLowerCase()] || LEVELS.info;

function log(level, consoleFn, args) {
  if (LEVELS[level] < threshold) return;
  consoleFn(`[${level.toUpperCase()}]`, ...args);
}

module.exports = {
  debug: (...args) => log('debug', console.log, args),
  info: (...args) => log('info', console.log, args),
  warn: (...args) => log('warn', console.warn, args),
  error: (...args) => log('error', console.error, args)
};
