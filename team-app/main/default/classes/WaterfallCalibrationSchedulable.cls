/**
 * Weekly calibration. Trailing eight quarters, every director's AE team.
 */
public with sharing class WaterfallCalibrationSchedulable implements Schedulable {
    public void execute(SchedulableContext sc) {
        run(Date.today());
    }

    public static Integer run(Date asOf) {
        Set<Id> owners = allAeIds();
        if (owners.isEmpty()) return 0;
        WaterfallRateEngine.RateSet rates = WaterfallRateEngine.calibrate(
            owners, CockpitConstants.PRODUCT_ALL, CockpitConstants.SIZE_ALL, asOf);
        return WaterfallRateEngine.persist(rates).size();
    }

    static Set<Id> allAeIds() {
        Set<Id> ids = new Set<Id>();
        for (CockpitRosterService.Member d : CockpitRosterService.listDirectors()) {
            ids.addAll(CockpitRosterService.teamIds(d.userId));
        }
        return ids;
    }
}
