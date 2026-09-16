/**
 * Nightly actuals for the current period and the next period.
 */
public with sharing class WaterfallActualSchedulable implements Schedulable {
    public void execute(SchedulableContext sc) {
        run(Date.today());
    }

    public static Integer run(Date asOf) {
        Set<Id> owners = allAeIds();
        if (owners.isEmpty()) return 0;
        Date asOfDay = asOf == null ? Date.today() : asOf;
        Integer n = persistPeriod(owners, asOfDay);
        n += persistPeriod(owners, WaterfallConstants.shiftPeriod(asOfDay, 1));
        return n;
    }

    static Integer persistPeriod(Set<Id> owners, Date asOf) {
        WaterfallActualEngine.ActualSet actuals = WaterfallActualEngine.measure(
            owners, CockpitConstants.PRODUCT_ALL, CockpitConstants.SIZE_ALL, asOf);
        return WaterfallActualEngine.persist(actuals).size();
    }

    static Set<Id> allAeIds() {
        Set<Id> ids = new Set<Id>();
        for (CockpitRosterService.Member d : CockpitRosterService.listDirectors()) {
            ids.addAll(CockpitRosterService.teamIds(d.userId));
        }
        return ids;
    }
}
