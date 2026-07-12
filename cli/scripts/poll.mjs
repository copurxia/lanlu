/**
 * 轮询任务直到完成或超时
 */

/**
 * 轮询任务
 * @param {import('./api_client.mjs').LanluApiClient} client
 * @param {number} taskId
 * @param {number} intervalMs
 * @param {number} timeoutMs
 * @param {string} outputMode
 * @returns {Promise<object>}
 */
export async function waitForTask(client, taskId, intervalMs, timeoutMs, outputMode) {
  let maxIter = Math.floor(timeoutMs / intervalMs);
  if (maxIter <= 0) maxIter = 1;

  for (let i = 0; i < maxIter; i++) {
    const body = await client.get(`/api/admin/taskpool/${taskId}`);
    const root = JSON.parse(body);

    const status = root.status ?? '';
    const progress = root.progress ?? 0;
    const message = root.message ?? '';

    if (outputMode === 'text') {
      console.log(`[task ${taskId}] status=${status} progress=${progress}% ${message}`);
    }

    if (status === 'completed' || status === 'failed' || status === 'stopped') {
      return root;
    }

    await sleep(intervalMs);
  }

  throw new Error(`task ${taskId} did not finish within ${timeoutMs}ms`);
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, Number(ms)));
}
