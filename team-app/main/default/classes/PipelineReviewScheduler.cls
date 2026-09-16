/**
 * Single scheduled-Apex slot for Pipeline Review. Hourly. What is due
 * comes from Pipeline_Review_Job__mdt, not from additional cron jobs.
 */
public with sharing class PipelineReviewScheduler implements Schedulable {
    public static final String JOB_NAME = 'Pipeline Review Dispatcher';
    public static final String CRON = '0 0 * * * ?';
    @TestVisible static Integer scheduledCountOverride;

    public void execute(SchedulableContext sc) {
        for (PipelineReviewJobConfig.JobSpec job : PipelineReviewJobConfig.due(System.now())) {
            PipelineReviewJobRunner.enqueue(job);
        }
    }

    /**
     * Idempotent register. Counts JobType=7 first. Does not schedule when
     * the org is already at the 100-job cap. Call from a manager action only.
     */
    public static Id ensureScheduled() {
        Integer scheduled = scheduledCountOverride != null
            ? scheduledCountOverride
            : [
                SELECT COUNT()
                FROM CronTrigger
                WHERE State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
                  AND CronJobDetail.JobType = '7'
            ];
        if (scheduled >= 100) {
            throw new AuraHandledException('Scheduled Apex is full (100). RevOps must reclaim a slot.');
        }
        for (CronTrigger ct : [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
              AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING')
        ]) {
            if (!Test.isRunningTest()) return ct.Id;
        }
        String jobName = Test.isRunningTest() ? JOB_NAME + ' ' + String.valueOf(System.now().getTime()) : JOB_NAME;
        return System.schedule(jobName, CRON, new PipelineReviewScheduler());
    }
}
