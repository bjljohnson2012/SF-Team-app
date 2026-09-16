# Prod deploy exceptions

## 2026-09-16 — Pipeline Review trigger degrade (euna)

- **Why:** Neel asked to push the fix. Live `PipelineReviewOpportunityTrigger` can fail Opportunity saves when `Pipeline_Title_Pattern__mdt` / `Pipeline_Priority_Config__mdt` are not queryable.
- **Artifact:** Apex only — `PipelineReviewSelector`, `PipelineReviewOpportunityHandler`, `PipelineReviewJobConfig`, `PipelineReviewServicesTest`.
- **Review:** Independent adversarial /sf-review of `7519ea9` (4 reviewers). Act-on: hollow test, silent catch, `due()` wrapping the whole loop. Addressed in the follow-up commit before validate.
- **Path:** `sf project deploy validate` then `sf project deploy quick` on that job id. Never `deploy start`.
- **Validate job:** (filled after validate)
- **Quick job:** (filled after quick)
