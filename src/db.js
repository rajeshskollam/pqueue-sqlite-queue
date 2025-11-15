const sqlite3 = require('sqlite3').verbose();
const path = require('path');

// Initialize database
const dbPath = path.join(__dirname, '..', 'tasks.db');
const db = new sqlite3.Database(dbPath, (err) => {
  if (err) {
    console.error('Error opening database:', err.message);
  }
});

// Enable foreign keys
db.run('PRAGMA foreign_keys = ON');

// Create tables if they don't exist
const createTablesSQL = `
  CREATE TABLE IF NOT EXISTS tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    priority INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'pending',
    payload TEXT,
    max_retries INTEGER NOT NULL DEFAULT 3,
    retry_count INTEGER NOT NULL DEFAULT 0,
    error_message TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    started_at DATETIME,
    completed_at DATETIME
  );

  CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
  CREATE INDEX IF NOT EXISTS idx_tasks_priority ON tasks(priority DESC);
  CREATE INDEX IF NOT EXISTS idx_tasks_created_at ON tasks(created_at);
`;

// Initialize database schema
db.serialize(() => {
  const statements = createTablesSQL.split(';').filter(s => s.trim());
  statements.forEach(sql => {
    if (sql.trim()) {
      db.run(sql);
    }
  });
});

/**
 * Promise wrapper for db.run
 */
function dbRun(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.run(sql, params, function(err) {
      if (err) reject(err);
      else resolve({ lastID: this.lastID, changes: this.changes });
    });
  });
}

/**
 * Promise wrapper for db.get
 */
function dbGet(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.get(sql, params, (err, row) => {
      if (err) reject(err);
      else resolve(row);
    });
  });
}

/**
 * Promise wrapper for db.all
 */
function dbAll(sql, params = []) {
  return new Promise((resolve, reject) => {
    db.all(sql, params, (err, rows) => {
      if (err) reject(err);
      else resolve(rows || []);
    });
  });
}

/**
 * Add a new task to the queue
 * @param {string} name - Task name/type
 * @param {number} priority - Priority level (higher = processed first)
 * @param {object} payload - Task data (optional)
 * @param {number} maxRetries - Max retry attempts (default: 3)
 * @returns {Promise<number>} Task ID
 */
async function addTask(name, priority = 0, payload = null, maxRetries = 3) {
  const sql = `
    INSERT INTO tasks (name, priority, payload, max_retries, status)
    VALUES (?, ?, ?, ?, 'pending')
  `;
  
  const result = await dbRun(sql, [
    name,
    priority,
    payload ? JSON.stringify(payload) : null,
    maxRetries
  ]);
  
  return result.lastID;
}

/**
 * Get pending tasks sorted by priority (descending)
 * @param {number} limit - Max tasks to fetch
 * @returns {Promise<Array>} Array of task objects
 */
function getPendingTasks(limit = 10) {
  const sql = `
    SELECT * FROM tasks 
    WHERE status = 'pending' AND retry_count < max_retries
    ORDER BY priority DESC, created_at ASC
    LIMIT ?
  `;
  
  return dbAll(sql, [limit]);
}

/**
 * Get a task by ID
 * @param {number} taskId - Task ID
 * @returns {Promise<object>} Task object or null
 */
function getTask(taskId) {
  const sql = 'SELECT * FROM tasks WHERE id = ?';
  return dbGet(sql, [taskId]);
}

/**
 * Update task status
 * @param {number} taskId - Task ID
 * @param {string} status - New status ('pending', 'processing', 'completed', 'failed')
 * @param {string} errorMessage - Error message (optional)
 * @returns {Promise}
 */
function updateTaskStatus(taskId, status, errorMessage = null) {
  const sql = `
    UPDATE tasks 
    SET status = ?, error_message = ?, updated_at = CURRENT_TIMESTAMP
    WHERE id = ?
  `;
  
  return dbRun(sql, [status, errorMessage, taskId]);
}

/**
 * Mark task as started
 * @param {number} taskId - Task ID
 * @returns {Promise}
 */
function markTaskStarted(taskId) {
  const sql = `
    UPDATE tasks 
    SET status = 'processing', started_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
    WHERE id = ?
  `;
  
  return dbRun(sql, [taskId]);
}

/**
 * Mark task as completed
 * @param {number} taskId - Task ID
 * @returns {Promise}
 */
function markTaskCompleted(taskId) {
  const sql = `
    UPDATE tasks 
    SET status = 'completed', completed_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
    WHERE id = ?
  `;
  
  return dbRun(sql, [taskId]);
}

/**
 * Increment retry count for a task
 * @param {number} taskId - Task ID
 * @param {string} errorMessage - Error message (optional)
 * @returns {Promise<number>} New retry count
 */
async function incrementRetryCount(taskId, errorMessage = null) {
  const sql = `
    UPDATE tasks 
    SET retry_count = retry_count + 1, 
        status = 'pending',
        error_message = ?,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = ?
  `;
  
  await dbRun(sql, [errorMessage, taskId]);
  
  const task = await getTask(taskId);
  return task.retry_count;
}

/**
 * Mark task as permanently failed (exceeded max retries)
 * @param {number} taskId - Task ID
 * @param {string} errorMessage - Error message
 * @returns {Promise}
 */
function markTaskFailed(taskId, errorMessage) {
  const sql = `
    UPDATE tasks 
    SET status = 'failed', error_message = ?, updated_at = CURRENT_TIMESTAMP
    WHERE id = ?
  `;
  
  return dbRun(sql, [errorMessage, taskId]);
}

/**
 * Get task statistics
 * @returns {Promise<object>} Stats object
 */
async function getStats() {
  const sql = `
    SELECT 
      COUNT(*) as total,
      SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending,
      SUM(CASE WHEN status = 'processing' THEN 1 ELSE 0 END) as processing,
      SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed,
      SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed
    FROM tasks
  `;
  
  return dbGet(sql);
}

/**
 * Clear all tasks from the database
 * @returns {Promise}
 */
function clearAllTasks() {
  return dbRun('DELETE FROM tasks');
}

/**
 * Close database connection
 * @returns {Promise}
 */
function closeDatabase() {
  return new Promise((resolve, reject) => {
    db.close((err) => {
      if (err) reject(err);
      else resolve();
    });
  });
}

module.exports = {
  db,
  addTask,
  getPendingTasks,
  getTask,
  updateTaskStatus,
  markTaskStarted,
  markTaskCompleted,
  incrementRetryCount,
  markTaskFailed,
  getStats,
  clearAllTasks,
  closeDatabase
};
