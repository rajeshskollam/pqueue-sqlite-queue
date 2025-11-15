const QueueService = require('./queueService');
const { addTask, getStats, clearAllTasks, closeDatabase } = require('./db');
const {
  handleEmailTask,
  handleUnreliableTask,
  handleImageTask,
  handleApiTask,
  handleDataImportTask
} = require('./taskHandlers');

async function main() {
  console.log('╔════════════════════════════════════════════════╗');
  console.log('║   Priority Task Queue - SQLite + p-queue       ║');
  console.log('╚════════════════════════════════════════════════╝\n');

  // Clear previous tasks
  clearAllTasks();

  // Initialize queue service
  const queueService = new QueueService({
    concurrency: 3,           // Process 3 tasks concurrently
    pollingInterval: 2000,    // Check for new tasks every 2 seconds
    interval: 1000,           // Rate limit interval
    intervalCap: 10           // Max tasks per interval
  });

  // Register task handlers
  queueService.registerHandler('email', handleEmailTask);
  queueService.registerHandler('unreliable', handleUnreliableTask);
  queueService.registerHandler('image', handleImageTask);
  queueService.registerHandler('api', handleApiTask);
  queueService.registerHandler('data-import', handleDataImportTask);

  // Add sample tasks with different priorities
  console.log('📝 Adding tasks to queue...\n');

  // High priority tasks
  await addTask('email', 100, { email: 'user1@example.com' }, 2);
  await addTask('email', 95, { email: 'user2@example.com' }, 2);

  // Medium priority tasks with retries
  await addTask('unreliable', 50, { data: 'test' }, 5);
  await addTask('unreliable', 50, { data: 'test2' }, 5);
  await addTask('api', 60, { url: 'https://api.example.com/data' }, 3);

  // Lower priority tasks
  await addTask('image', 30, { filename: 'photo.jpg' }, 2);
  await addTask('data-import', 20, { source: 'csv-file.csv' }, 3);

  // Another high priority email
  await addTask('email', 100, { email: 'urgent@example.com' }, 2);

  // API call that will fail and retry
  await addTask('api', 70, { url: 'https://api.example.com/fail' }, 4);

  const stats = await getStats();
  console.log(`\n📊 Initial queue stats:`);
  console.log(`   Total: ${stats.total}, Pending: ${stats.pending}, Processing: ${stats.processing}`);
  console.log(`   Completed: ${stats.completed}, Failed: ${stats.failed}\n`);

  // Start the queue service
  queueService.start();

  // Log queue stats every 10 seconds
  const statsInterval = setInterval(async () => {
    const stats = await getStats();
    const qStats = queueService.getStats();
    console.log(`\n📈 Stats - DB: pending=${stats.pending}, completed=${stats.completed}, failed=${stats.failed} | Queue: pending=${qStats.pending}, size=${qStats.size}`);
  }, 10000);

  // Run for 60 seconds then stop
  console.log('⏱️  Running for 60 seconds...\n');
  
  await new Promise(resolve => {
    setTimeout(async () => {
      clearInterval(statsInterval);
      
      console.log('\n\n⏹️  Stopping queue service...');
      await queueService.stop();
      
      // Final stats
      const finalStats = await getStats();
      console.log('\n╔════════════════════════════════════════════════╗');
      console.log('║              Final Statistics                  ║');
      console.log('╚════════════════════════════════════════════════╝');
      console.log(`Total tasks: ${finalStats.total}`);
      console.log(`Completed: ${finalStats.completed}`);
      console.log(`Failed: ${finalStats.failed}`);
      console.log(`Still pending: ${finalStats.pending}`);
      console.log('');
      
      // Close database
      await closeDatabase();
      
      resolve();
    }, 60000);
  });
}

main().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});

// Graceful shutdown
process.on('SIGINT', async () => {
  console.log('\n\n⏹️  Shutting down...');
  process.exit(0);
});
