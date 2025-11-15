# Priority Task Queue Service - SQLite + p-queue

A Node.js background task queue service that combines **p-queue** for priority-based concurrent task processing with **SQLite** for persistent storage. Features automatic retry logic with configurable retry limits.

## Features

- ✅ **Priority-based processing** – Tasks with higher priority values are processed first
- ✅ **Persistent storage** – All tasks stored in SQLite, survives process restarts
- ✅ **Automatic retries** – Failed tasks automatically retry up to a configurable limit
- ✅ **Concurrent processing** – Process multiple tasks concurrently using p-queue
- ✅ **Background polling** – Continuously monitors database for new tasks
- ✅ **Custom handlers** – Register custom async handlers for different task types
- ✅ **Rate limiting** – Control throughput with configurable concurrency and rate limits
- ✅ **Task metadata** – Track timestamps, error messages, and retry counts

## Installation

1. Clone or navigate to the project directory:
```bash
cd e:\WORK\PQueueSqlite
```

2. Install dependencies:
```bash
npm install
```

## Project Structure

```
src/
├── index.js              # Example usage and demo
├── db.js                 # Database module (SQLite operations)
├── queueService.js       # Queue service (p-queue wrapper)
└── taskHandlers.js       # Example task handlers
tasks.db                  # SQLite database (created on first run)
package.json              # Dependencies and scripts
```

## Database Schema

The SQLite database includes a `tasks` table with:

| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER | Primary key |
| `name` | TEXT | Task type/name |
| `priority` | INTEGER | Priority level (higher = processed first) |
| `status` | TEXT | 'pending', 'processing', 'completed', 'failed' |
| `payload` | TEXT | JSON-serialized task data |
| `max_retries` | INTEGER | Maximum retry attempts |
| `retry_count` | INTEGER | Current retry count |
| `error_message` | TEXT | Last error message |
| `created_at` | DATETIME | Task creation timestamp |
| `updated_at` | DATETIME | Last update timestamp |
| `started_at` | DATETIME | When processing started |
| `completed_at` | DATETIME | When task completed |

## Usage

### Basic Setup

```javascript
const QueueService = require('./src/queueService');
const { addTask } = require('./src/db');

// Create queue service
const queueService = new QueueService({
  concurrency: 5,        // Process 5 tasks in parallel
  pollingInterval: 5000  // Check for new tasks every 5 seconds
});

// Register a handler for a task type
queueService.registerHandler('email', async (payload, task) => {
  console.log(`Sending email to ${payload.email}`);
  // Do work here
});

// Start processing
queueService.start();

// Add a task to the queue
addTask('email', 100, { email: 'user@example.com' }, maxRetries=3);
```

### API Reference

#### Database Module (`src/db.js`)

```javascript
const db = require('./src/db');

// Add a task
const taskId = db.addTask(
  name,           // Task type (string)
  priority,       // Priority level (number, higher = first)
  payload,        // Task data (object, optional)
  maxRetries      // Max retry attempts (number, default: 3)
);

// Get pending tasks (sorted by priority)
const tasks = db.getPendingTasks(limit = 10);

// Get a specific task
const task = db.getTask(taskId);

// Update task status
db.updateTaskStatus(taskId, status, errorMessage);
db.markTaskStarted(taskId);
db.markTaskCompleted(taskId);
db.markTaskFailed(taskId, errorMessage);

// Retry logic
db.incrementRetryCount(taskId, errorMessage);

// Get stats
const stats = db.getStats();
// Returns: { total, pending, processing, completed, failed }

// Clear all tasks
db.clearAllTasks();
```

#### Queue Service Module (`src/queueService.js`)

```javascript
const QueueService = require('./src/queueService');

const queueService = new QueueService({
  concurrency: 5,           // Concurrent tasks (default: 5)
  pollingInterval: 5000,    // Poll interval in ms (default: 5000)
  interval: 1000,           // Rate limit interval
  intervalCap: 10           // Max tasks per interval
});

// Register handler for a task type
queueService.registerHandler(taskName, asyncHandler);

// Control queue
queueService.start();
await queueService.stop();
queueService.pause();
queueService.resume();

// Get stats
const stats = queueService.getStats();
// Returns: { pending, size, isPaused, isRunning }

// Wait for queue to finish
await queueService.waitIdle();
```

### Handler Function Signature

Task handlers are async functions that receive the task payload and metadata:

```javascript
async function myHandler(payload, task) {
  // payload: The data passed when adding the task
  // task: Full task object from database
  
  // Throw error to trigger retry
  if (someCondition) {
    throw new Error('Task failed - will be retried');
  }
  
  // Return on success
  return;
}
```

## Running the Demo

Run the included example that demonstrates:
- Adding tasks with different priorities
- Processing tasks concurrently
- Handling task retries on failure
- Tracking task statistics

```bash
npm start
```

The demo will:
1. Clear previous tasks
2. Add 10 sample tasks with varying priorities
3. Start the queue service
4. Process tasks for 60 seconds
5. Display final statistics

### Example Output

```
╔════════════════════════════════════════════════╗
║   Priority Task Queue - SQLite + p-queue       ║
╚════════════════════════════════════════════════╝

✓ Handler registered for task: email
✓ Handler registered for task: unreliable
✓ Handler registered for task: image
✓ Handler registered for task: api
✓ Handler registered for task: data-import

🚀 Queue service started
⚙️  Processing task #1 (email, priority: 100)
📧 Sending email to: user1@example.com
✅ Task #1 completed successfully

⚙️  Processing task #2 (email, priority: 100)
🎲 Unreliable task random value: 0.45
⚠️  Task #5 failed: Random failure occurred
🔄 Task #5 queued for retry (1/5)
```

## Configuration Tips

### High Throughput
```javascript
const queueService = new QueueService({
  concurrency: 20,
  pollingInterval: 1000,
  intervalCap: 20
});
```

### Low Resource Usage
```javascript
const queueService = new QueueService({
  concurrency: 1,
  pollingInterval: 10000
});
```

### Balanced
```javascript
const queueService = new QueueService({
  concurrency: 5,
  pollingInterval: 5000,
  intervalCap: 10
});
```

## Advanced Usage

### Custom Task Processing

```javascript
// Register handler with error handling
queueService.registerHandler('critical', async (payload, task) => {
  try {
    const result = await criticalOperation(payload);
    console.log('Operation successful:', result);
  } catch (error) {
    console.error('Operation failed:', error);
    throw error; // This will trigger retry
  }
});

// Add critical task with high priority and many retries
addTask('critical', 1000, { data: 'important' }, maxRetries=10);
```

### Batch Processing

```javascript
// Add multiple tasks at once
const taskIds = [];
for (let i = 0; i < 100; i++) {
  taskIds.push(addTask('process', 50, { index: i }));
}

console.log(`Added ${taskIds.length} tasks`);
```

### Monitoring

```javascript
// Periodic monitoring
setInterval(() => {
  const dbStats = getStats();
  const queueStats = queueService.getStats();
  
  console.log('Queue Status:');
  console.log(`  Pending: ${dbStats.pending}`);
  console.log(`  Processing: ${queueStats.pending}`);
  console.log(`  Completed: ${dbStats.completed}`);
  console.log(`  Failed: ${dbStats.failed}`);
}, 5000);
```

## Dependencies

- **p-queue** (v7.2.0) – Priority queue management with concurrency control
- **better-sqlite3** (v8.0.0) – Synchronous SQLite binding for Node.js

## License

MIT

## Notes

- Tasks are processed in-memory after being fetched from the database, so the queue doesn't persist between process restarts unless you re-fetch pending tasks
- Use higher priority values for tasks that should be processed sooner
- Adjust `concurrency` based on your system resources and handler complexity
- Polling is done at intervals; for real-time processing, consider using database triggers or event emitters
