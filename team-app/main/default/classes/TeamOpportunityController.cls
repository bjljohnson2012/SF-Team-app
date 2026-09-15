/**
 * Backs the Team Opportunity Insights LWC on the GTM - Team Johnson home page:
 * lists open opportunities owned by anyone in the running director's role
 * hierarchy, and produces an LLM summary for a single opportunity on demand.
 */
public with sharing class TeamOpportunityController {
    public class OpportunityDto {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String accountName;
        @AuraEnabled public String stageName;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Date closeDate;
        @AuraEnabled public String ownerName;
    }

    @AuraEnabled(cacheable=true)
    public static List<OpportunityDto> getDirectorOpportunities() {
        Set<Id> roleIds = getRoleHierarchy(UserInfo.getUserRoleId());
        List<OpportunityDto> result = new List<OpportunityDto>();
        if (roleIds.isEmpty()) {
            return result;
        }
        for (Opportunity o : [
            SELECT Id, Name, Account.Name, StageName, Amount, CloseDate, Owner.Name
            FROM Opportunity
            WHERE Owner.UserRoleId IN :roleIds AND IsClosed = false
            WITH SECURITY_ENFORCED
            ORDER BY CloseDate ASC
            LIMIT 200
        ]) {
            OpportunityDto d = new OpportunityDto();
            d.id = o.Id;
            d.name = o.Name;
            d.accountName = (o.Account != null) ? o.Account.Name : null;
            d.stageName = o.StageName;
            d.amount = o.Amount;
            d.closeDate = o.CloseDate;
            d.ownerName = (o.Owner != null) ? o.Owner.Name : null;
            result.add(d);
        }
        return result;
    }

    @AuraEnabled
    public static String summarizeOpportunity(Id opportunityId) {
        if (opportunityId == null) {
            throw new AuraHandledException('An opportunity id is required.');
        }
        List<Opportunity> opps = [
            SELECT Id, Name, StageName, Amount, CloseDate, Probability, Type, LeadSource,
                   NextStep, Description, Account.Name, Account.Industry, Owner.Name
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (opps.isEmpty()) {
            throw new AuraHandledException('Opportunity not found or not accessible.');
        }
        try {
            return AnthropicService.complete(buildPrompt(opps[0]));
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @TestVisible
    private static String buildPrompt(Opportunity o) {
        return 'You are a sales assistant helping a sales director. Summarize the following Salesforce '
            + 'opportunity in 4-6 sentences. Cover what the deal is, its current status and health, any '
            + 'risks, and a concrete suggested next step. Be specific and concise.\n\n'
            + 'Opportunity: ' + o.Name + '\n'
            + 'Account: ' + ((o.Account != null) ? o.Account.Name : 'N/A') + '\n'
            + 'Industry: ' + ((o.Account != null) ? String.valueOf(o.Account.Industry) : 'N/A') + '\n'
            + 'Stage: ' + o.StageName + '\n'
            + 'Amount: ' + ((o.Amount == null) ? 'unknown' : String.valueOf(o.Amount)) + '\n'
            + 'Probability: ' + String.valueOf(o.Probability) + '%\n'
            + 'Close Date: ' + String.valueOf(o.CloseDate) + '\n'
            + 'Type: ' + String.valueOf(o.Type) + '\n'
            + 'Lead Source: ' + String.valueOf(o.LeadSource) + '\n'
            + 'Owner: ' + ((o.Owner != null) ? o.Owner.Name : 'N/A') + '\n'
            + 'Next Step: ' + String.valueOf(o.NextStep) + '\n'
            + 'Description: ' + String.valueOf(o.Description) + '\n';
    }

    /**
     * Returns the given role plus every role beneath it in the hierarchy.
     * Built by walking ParentRoleId downward so no role ids are hardcoded.
     */
    @TestVisible
    private static Set<Id> getRoleHierarchy(Id topRoleId) {
        Set<Id> roleIds = new Set<Id>();
        if (topRoleId == null) {
            return roleIds;
        }
        roleIds.add(topRoleId);
        Map<Id, List<Id>> childrenByParent = new Map<Id, List<Id>>();
        for (UserRole r : [SELECT Id, ParentRoleId FROM UserRole WHERE ParentRoleId != null]) {
            if (!childrenByParent.containsKey(r.ParentRoleId)) {
                childrenByParent.put(r.ParentRoleId, new List<Id>());
            }
            childrenByParent.get(r.ParentRoleId).add(r.Id);
        }
        List<Id> queue = new List<Id>{ topRoleId };
        while (!queue.isEmpty()) {
            Id current = queue.remove(0);
            List<Id> children = childrenByParent.get(current);
            if (children != null) {
                for (Id childId : children) {
                    if (!roleIds.contains(childId)) {
                        roleIds.add(childId);
                        queue.add(childId);
                    }
                }
            }
        }
        return roleIds;
    }
}
