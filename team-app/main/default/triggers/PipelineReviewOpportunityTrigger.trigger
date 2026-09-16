/**
 * Keeps Pipeline Review grade fields live between nightly Job A runs.
 * Isolated from the existing Opportunity trigger fleet.
 */
trigger PipelineReviewOpportunityTrigger on Opportunity (after insert, after update) {
    PipelineReviewOpportunityHandler.afterChange(Trigger.new, Trigger.oldMap);
}
