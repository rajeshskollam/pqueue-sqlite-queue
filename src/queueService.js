const PQueue = require('p-queue').default;
const {
  getPendingTasks,
  getTask,
  markTaskStarted,
  markTaskCompleted,
  incrementRetryCount,
  markTaskFailed
} = require('./db');

/**
 * Queue Service - manages priority-based task processing with retries
 */
class QueueService {
  constructor(options = {}) {
    this.queue = new PQueue({
      concurrency: options.concurrency || 5,
      interval: options.interval || 1000,
      intervalCap: options.intervalCap || 10
    });

    this.pollingInterval = options.pollingInterval || 5000;
    this.taskHandlers = {};
    this.isRunning = false;
    this.pollingTimer = null;
  }

  /**
   * Register a task handler function
   * @param {string} taskName - Name of the task type
   * @param {Function} handler - Async handler function
   */
  registerHandler(taskName, handler) {
    this.taskHandlers[taskName] = handler;
    console.log(`✓ Handler registered for task: ${taskName}`);
  }

  /**
   * Start the background queue processor
   */
  start() {
    if (this.isRunning) {
      console.log('Queue service already running');
      return;
    }

    this.isRunning = true;
    console.log('🚀 Queue service started');
    this.poll();
  }

  /**
   * Stop the background queue processor
   */
  async stop() {
    if (!this.isRunning) {
      console.log('Queue service not running');
      return;
    }

    this.isRunning = false;
    if (this.pollingTimer) {
      clearTimeout(this.pollingTimer);
    }
    
    await this.queue.onIdle();
    console.log('⏹️  Queue service stopped');
  }

  /**
   * Poll for pending tasks and add them to the queue
   */
  async poll() {
    if (!this.isRunning) return;

    try {
      const pendingTasks = await getPendingTasks(10);

      if (pendingTasks.length > 0) {
        console.log(`📋 Found ${pendingTasks.length} pending task(s)`);

        pendingTasks.forEach(task => {
          this.queueTask(task);
        });
      }

      this.pollingTimer = setTimeout(() => this.poll(), this.pollingInterval);
    } catch (error) {
      console.error('❌ Polling error:', error.message);
      this.pollingTimer = setTimeout(() => this.poll(), this.pollingInterval);
    }
  }

  /**
   * Add a task to the p-queue for processing
   * @param {object} task - Task object from database
   */
  queueTask(task) {
    this.queue.add(async () => {
      await this.executeTask(task);
    });
  }

  /**
   * Execute a task with error handling and retry logic
   * @param {object} task - Task object
   */
  async executeTask(task) {
    try {
      await markTaskStarted(task.id);
      console.log(`⚙️  Processing task #${task.id} (${task.name}, priority: ${task.priority})`);

      const handler = this.taskHandlers[task.name];

      if (!handler) {
        throw new Error(`No handler registered for task type: ${task.name}`);
      }

      // Parse payload if it exists
      let payload = null;
      if (task.payload) {
        try {
          payload = JSON.parse(task.payload);
        } catch (e) {
          payload = task.payload;
        }
      }

      // Execute the handler
      await handler(payload, task);

      // Mark as completed
      await markTaskCompleted(task.id);
      console.log(`✅ Task #${task.id} completed successfully`);
    } catch (error) {
      console.error(`⚠️  Task #${task.id} failed:`, error.message);

      // Check if we should retry
      const newRetryCount = await incrementRetryCount(task.id, error.message);

      if (newRetryCount >= task.max_retries) {
        await markTaskFailed(task.id, error.message);
        console.error(`❌ Task #${task.id} permanently failed after ${newRetryCount} retries`);
      } else {
        console.log(`🔄 Task #${task.id} queued for retry (${newRetryCount}/${task.max_retries})`);
      }
    }
  }

  /**
   * Get queue statistics
   * @returns {object} Queue stats
   */
  getStats() {
    return {
      pending: this.queue.pending,
      size: this.queue.size,
      isPaused: this.queue.isPaused,
      isRunning: this.isRunning
    };
  }

  /**
   * Pause the queue
   */
  pause() {
    this.queue.pause();
    console.log('⏸️  Queue paused');
  }

  /**
   * Resume the queue
   */
  resume() {
    this.queue.start();
    console.log('▶️  Queue resumed');
  }

  /**
   * Wait for queue to be idle
   */
  async waitIdle() {
    await this.queue.onIdle();
  }
}

module.exports = QueueService;
