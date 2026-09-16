/**
 * Enqueues the batch named on a Pipeline_Review_Job__mdt row.
 */
public with sharing class PipelineReviewJobRunner {
    public static Id enqueue(PipelineReviewJobConfig.JobSpec job) {
        if (job == null || String.isBlank(job.jobClass)) return null;
        Integer size = job.batchSize == null ? 200 : job.batchSize;
        if (job.jobClass == 'PipelineReviewGradeBatch') {
            return Database.executeBatch(new PipelineReviewGradeBatch(), size);
        }
        if (job.jobClass == 'PipelineReviewNoteBatch') {
            return Database.executeBatch(new PipelineReviewNoteBatch(), Math.min(size, 15));
        }
        if (job.jobClass == 'PipelineReviewSuggestionBatch') {
            return Database.executeBatch(new PipelineReviewSuggestionBatch(), Math.min(size, 15));
        }
        if (job.jobClass == 'PipelineReviewFocusLock') {
            PipelineReviewFocusLockService.lockWeek(Date.today());
            return null;
        }
        return null;
    }
}
