/**
 * Reads Pipeline_Review_Job__mdt and decides what the single hourly
 * dispatcher should enqueue. Cadence changes need no deploy.
 */
public with sharing class PipelineReviewJobConfig {
    public class JobSpec {
        public String developerName;
        public String jobClass;
        public Integer batchSize;
        public Boolean enabled;
        public Integer hourEt;
        public String daysOfWeek;
    }

    public static List<JobSpec> due(Datetime nowUtc) {
        List<JobSpec> out = new List<JobSpec>();
        if (nowUtc == null) nowUtc = System.now();
        DateTime et = toEt(nowUtc);
        Integer hour = Integer.valueOf(et.format('HH', 'America/New_York'));
        String dow = et.format('EEE', 'America/New_York'); // Mon
        List<Pipeline_Review_Job__mdt> rows;
        try {
            rows = [
                SELECT DeveloperName, Enabled__c, Hour_ET__c, Days_Of_Week__c, Batch_Size__c, Job_Class__c
                FROM Pipeline_Review_Job__mdt
            ];
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'Pipeline_Review_Job__mdt unavailable: ' + e.getTypeName() + ' ' + e.getMessage());
            return out;
        }
        for (Pipeline_Review_Job__mdt row : rows) {
            try {
                if (row.Enabled__c != true) continue;
                if (row.Hour_ET__c != null && Integer.valueOf(row.Hour_ET__c) != hour) continue;
                if (!dayMatches(row.Days_Of_Week__c, dow)) continue;
                JobSpec spec = new JobSpec();
                spec.developerName = row.DeveloperName;
                spec.jobClass = row.Job_Class__c;
                spec.batchSize = row.Batch_Size__c == null ? 200 : Integer.valueOf(row.Batch_Size__c);
                spec.enabled = true;
                spec.hourEt = row.Hour_ET__c == null ? null : Integer.valueOf(row.Hour_ET__c);
                spec.daysOfWeek = row.Days_Of_Week__c;
                out.add(spec);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'Pipeline_Review_Job__mdt row skipped: ' + row.DeveloperName + ' '
                    + e.getTypeName() + ' ' + e.getMessage());
            }
        }
        return out;
    }

    public static Boolean dayMatches(String configured, String dow) {
        if (String.isBlank(configured) || configured.trim() == '*') return true;
        return configured.toLowerCase().contains(dow.toLowerCase().left(3));
    }

    @TestVisible
    static DateTime toEt(DateTime utc) {
        return utc;
    }
}
