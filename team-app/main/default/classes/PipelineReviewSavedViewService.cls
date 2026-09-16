/**
 * Saved Pipeline Review views. One default per user. Shared views are
 * read-only to everyone but the owner. Unknown JSON keys are ignored.
 */
public with sharing class PipelineReviewSavedViewService {
    public class ViewDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String definitionJson;
        @AuraEnabled public Boolean isShared;
        @AuraEnabled public Boolean isDefault;
        @AuraEnabled public Decimal sortOrder;
        @AuraEnabled public Boolean canEdit;
    }

    @AuraEnabled
    public static List<ViewDTO> listViews() {
        List<ViewDTO> out = new List<ViewDTO>();
        Id uid = UserInfo.getUserId();
        for (Pipeline_Saved_View__c row : [
            SELECT Id, View_Name__c, Definition_JSON__c, Is_Shared__c, Is_Default__c, Sort_Order__c, OwnerId
            FROM Pipeline_Saved_View__c
            WHERE OwnerId = :uid OR Is_Shared__c = true
            ORDER BY Sort_Order__c NULLS LAST, View_Name__c
        ]) {
            out.add(toDto(row, uid));
        }
        return out;
    }

    @AuraEnabled
    public static ViewDTO saveView(Id viewId, String name, String definitionJson, Boolean isShared, Boolean isDefault, Decimal sortOrder) {
        Id uid = UserInfo.getUserId();
        Pipeline_Saved_View__c row;
        if (viewId != null) {
            row = [
                SELECT Id, OwnerId FROM Pipeline_Saved_View__c WHERE Id = :viewId LIMIT 1
            ];
            if (row.OwnerId != uid) {
                throw new AuraHandledException('Only the owner can edit this view.');
            }
        } else {
            row = new Pipeline_Saved_View__c(OwnerId = uid);
        }
        String jsonBody = normalizeJson(definitionJson);
        row.View_Name__c = name;
        row.Definition_JSON__c = jsonBody;
        row.Is_Shared__c = isShared == true;
        row.Is_Default__c = isDefault == true;
        row.Sort_Order__c = sortOrder;
        upsert row;
        if (isDefault == true) {
            List<Pipeline_Saved_View__c> siblings = [
                SELECT Id, Is_Default__c
                FROM Pipeline_Saved_View__c
                WHERE OwnerId = :uid AND Id != :row.Id AND Is_Default__c = true
            ];
            for (Pipeline_Saved_View__c s : siblings) s.Is_Default__c = false;
            if (!siblings.isEmpty()) update siblings;
        }
        return toDto([
            SELECT Id, View_Name__c, Definition_JSON__c, Is_Shared__c, Is_Default__c, Sort_Order__c, OwnerId
            FROM Pipeline_Saved_View__c WHERE Id = :row.Id LIMIT 1
        ], uid);
    }

    @AuraEnabled
    public static void deleteView(Id viewId) {
        Pipeline_Saved_View__c row = [
            SELECT Id, OwnerId FROM Pipeline_Saved_View__c WHERE Id = :viewId LIMIT 1
        ];
        if (row.OwnerId != UserInfo.getUserId()) {
            throw new AuraHandledException('Only the owner can delete this view.');
        }
        delete row;
    }

    @AuraEnabled
    public static ViewDTO duplicateView(Id viewId) {
        Pipeline_Saved_View__c src = [
            SELECT View_Name__c, Definition_JSON__c, Sort_Order__c
            FROM Pipeline_Saved_View__c WHERE Id = :viewId LIMIT 1
        ];
        return saveView(null, src.View_Name__c + ' copy', src.Definition_JSON__c, false, false, src.Sort_Order__c);
    }

    @TestVisible
    static String normalizeJson(String raw) {
        if (String.isBlank(raw)) return '{"v":1}';
        try {
            Object parsed = JSON.deserializeUntyped(raw);
            if (!(parsed instanceof Map<String, Object>)) return '{"v":1}';
            Map<String, Object> m = (Map<String, Object>) parsed;
            if (!m.containsKey('v')) m.put('v', 1);
            return JSON.serialize(m);
        } catch (Exception e) {
            return '{"v":1}';
        }
    }

    private static ViewDTO toDto(Pipeline_Saved_View__c row, Id uid) {
        ViewDTO d = new ViewDTO();
        d.id = row.Id;
        d.name = row.View_Name__c;
        d.definitionJson = row.Definition_JSON__c;
        d.isShared = row.Is_Shared__c;
        d.isDefault = row.Is_Default__c;
        d.sortOrder = row.Sort_Order__c;
        d.canEdit = row.OwnerId == uid;
        return d;
    }
}
