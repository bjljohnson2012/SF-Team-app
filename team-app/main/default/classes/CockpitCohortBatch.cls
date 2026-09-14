/**
 * Nightly SQL-cohort snapshot. One director per execute so a large book
 * cannot blow heap for another team. without sharing: the job must write
 * every director's snapshot, not only the scheduler's visible roster.
 */
public without sharing class CockpitCohortBatch
    implements Database.Batchable<Id>, Database.Stateful, Schedulable {

    @TestVisible
    private List<Id> onlyDirectors;

    public CockpitCohortBatch() {
    }

    public CockpitCohortBatch(List<Id> directorIds) {
        onlyDirectors = directorIds;
    }

    public Iterable<Id> start(Database.BatchableContext bc) {
        if (onlyDirectors != null) return onlyDirectors;
        return CockpitRosterService.directorIdsForBatch();
    }

    public void execute(Database.BatchableContext bc, List<Id> scope) {
        Date asOf = Date.today();
        for (Id directorId : scope) {
            CockpitCohortService.Filter f = new CockpitCohortService.Filter();
            f.directorId = directorId;
            f.teamMode = CockpitConstants.TEAM_MODE_DIRECTOR;
            f.productType = CockpitConstants.PRODUCT_ALL;
            f.sizeBand = CockpitConstants.SIZE_ALL;
            CockpitCohortService.Page page = CockpitCohortService.buildPage(f);
            List<Cockpit_Cohort_Snapshot__c> rows =
                CockpitCohortService.toSnapshots(directorId, page, asOf);
            if (!rows.isEmpty()) {
                upsert rows External_Id__c;
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new CockpitCohortBatch(), 1);
    }
}
