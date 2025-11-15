/**
 * Example task handlers
 */

// Simple task handler - just logs and succeeds
async function handleEmailTask(payload, task) {
  console.log(`  📧 Sending email to: ${payload.email}`);
  await new Promise(resolve => setTimeout(resolve, 500));
  console.log(`  ✓ Email sent to ${payload.email}`);
}

// Unreliable task handler - fails randomly (for testing retries)
async function handleUnreliableTask(payload, task) {
  const random = Math.random();
  console.log(`  🎲 Unreliable task random value: ${random.toFixed(2)}`);
  
  if (random < 0.6) {
    throw new Error('Random failure occurred');
  }
  
  console.log(`  ✓ Unreliable task succeeded`);
}

// Image processing task - simulates longer processing
async function handleImageTask(payload, task) {
  console.log(`  🖼️  Processing image: ${payload.filename}`);
  
  // Simulate image processing (5 seconds)
  await new Promise(resolve => setTimeout(resolve, 5000));
  
  console.log(`  ✓ Image ${payload.filename} processed`);
}

// API call task
async function handleApiTask(payload, task) {
  console.log(`  🌐 Calling API: ${payload.url}`);
  
  // Simulate API call
  await new Promise(resolve => setTimeout(resolve, 1000));
  
  if (payload.url.includes('fail')) {
    throw new Error(`API returned error status`);
  }
  
  console.log(`  ✓ API call to ${payload.url} completed`);
}

// Data import task
async function handleDataImportTask(payload, task) {
  console.log(`  📊 Importing data from: ${payload.source}`);
  
  await new Promise(resolve => setTimeout(resolve, 2000));
  
  console.log(`  ✓ Data imported from ${payload.source}`);
}

module.exports = {
  handleEmailTask,
  handleUnreliableTask,
  handleImageTask,
  handleApiTask,
  handleDataImportTask
};
