import {getPerformanceLog} from '../storage/diagnostics';
import {perfFlush, perfMark} from './perf';

test('performance marks are flushed to the diagnostics performance log', async () => {
  perfMark('test.perf.mark', {surface: 'unit'});
  perfFlush();
  const log = await getPerformanceLog();
  expect(log).toContain('test.perf.mark');
  expect(log).toContain('surface');
});
