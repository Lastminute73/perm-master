/**
 * Batch class that applies approved Gong processing results.
 * - "New Contact" results: Creates Contact records
 * - "Link to Contact/Lead" results: Updates the Task/Event WhoId
 *
 * Run via anonymous Apex:
 *   Database.executeBatch(new GongResultApplierBatch(), 200);
 */
public with sharing class GongResultApplierBatch
    implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Email__c, First_Name__c, Last_Name__c,
                   AI_Cleaned_First_Name__c, AI_Cleaned_Last_Name__c,
                   Account__c, Activity_Id__c, Activity_Type__c,
                   Result_Type__c, Matched_Record_Id__c
            FROM Gong_Processing_Result__c
            WHERE Status__c = 'Approved'
            ORDER BY Result_Type__c
        ]);
    }

    public void execute(Database.BatchableContext bc,
                        List<Gong_Processing_Result__c> scope) {

        List<Contact> contactsToCreate = new List<Contact>();
        List<Gong_Processing_Result__c> newContactResults =
            new List<Gong_Processing_Result__c>();
        List<Gong_Processing_Result__c> linkResults =
            new List<Gong_Processing_Result__c>();

        for (Gong_Processing_Result__c result : scope) {
            if (result.Result_Type__c == 'New Contact') {
                // Use AI-cleaned names if available, otherwise inferred names
                String firstName = String.isNotBlank(result.AI_Cleaned_First_Name__c)
                    ? result.AI_Cleaned_First_Name__c : result.First_Name__c;
                String lastName = String.isNotBlank(result.AI_Cleaned_Last_Name__c)
                    ? result.AI_Cleaned_Last_Name__c : result.Last_Name__c;

                Contact c = new Contact(
                    FirstName = firstName,
                    LastName = lastName,
                    Email = result.Email__c,
                    AccountId = result.Account__c,
                    LeadSource = 'Sales Tool Sourced'
                );
                contactsToCreate.add(c);
                newContactResults.add(result);
            } else if (result.Result_Type__c == 'Link to Contact'
                    || result.Result_Type__c == 'Link to Lead') {
                linkResults.add(result);
            }
        }

        // Create new Contacts
        if (!contactsToCreate.isEmpty()) {
            List<Database.SaveResult> saveResults =
                Database.insert(contactsToCreate, false);
            for (Integer i = 0; i < saveResults.size(); i++) {
                Gong_Processing_Result__c result = newContactResults[i];
                if (saveResults[i].isSuccess()) {
                    result.Status__c = 'Applied';
                    result.Matched_Record_Id__c = saveResults[i].getId();
                    result.Matched_Record_Type__c = 'Contact';
                } else {
                    result.Status__c = 'Error';
                    result.Error_Message__c = formatErrors(saveResults[i].getErrors());
                }
            }
            update newContactResults;
        }

        // Link activities to existing Contacts/Leads
        if (!linkResults.isEmpty()) {
            List<Task> tasksToUpdate = new List<Task>();
            List<Event> eventsToUpdate = new List<Event>();

            for (Gong_Processing_Result__c result : linkResults) {
                if (String.isBlank(result.Matched_Record_Id__c)
                    || String.isBlank(result.Activity_Id__c)) {
                    result.Status__c = 'Error';
                    result.Error_Message__c = 'Missing Matched Record Id or Activity Id';
                    continue;
                }

                if (result.Activity_Type__c == 'Task') {
                    tasksToUpdate.add(new Task(
                        Id = result.Activity_Id__c,
                        WhoId = result.Matched_Record_Id__c
                    ));
                } else {
                    eventsToUpdate.add(new Event(
                        Id = result.Activity_Id__c,
                        WhoId = result.Matched_Record_Id__c
                    ));
                }
            }

            // Update Tasks
            Map<Id, String> taskErrors = new Map<Id, String>();
            if (!tasksToUpdate.isEmpty()) {
                List<Database.SaveResult> taskSaveResults =
                    Database.update(tasksToUpdate, false);
                for (Integer i = 0; i < taskSaveResults.size(); i++) {
                    if (!taskSaveResults[i].isSuccess()) {
                        taskErrors.put(
                            tasksToUpdate[i].Id,
                            formatErrors(taskSaveResults[i].getErrors())
                        );
                    }
                }
            }

            // Update Events
            Map<Id, String> eventErrors = new Map<Id, String>();
            if (!eventsToUpdate.isEmpty()) {
                List<Database.SaveResult> eventSaveResults =
                    Database.update(eventsToUpdate, false);
                for (Integer i = 0; i < eventSaveResults.size(); i++) {
                    if (!eventSaveResults[i].isSuccess()) {
                        eventErrors.put(
                            eventsToUpdate[i].Id,
                            formatErrors(eventSaveResults[i].getErrors())
                        );
                    }
                }
            }

            // Update result statuses
            for (Gong_Processing_Result__c result : linkResults) {
                if (result.Status__c == 'Error') {
                    continue; // Already marked as error
                }
                Id activityId = Id.valueOf(result.Activity_Id__c);
                String errorMsg = taskErrors.containsKey(activityId)
                    ? taskErrors.get(activityId)
                    : eventErrors.get(activityId);

                if (errorMsg != null) {
                    result.Status__c = 'Error';
                    result.Error_Message__c = errorMsg;
                } else {
                    result.Status__c = 'Applied';
                }
            }
            update linkResults;
        }
    }

    public void finish(Database.BatchableContext bc) {
        // No post-processing needed
    }

    private String formatErrors(List<Database.Error> errors) {
        List<String> messages = new List<String>();
        for (Database.Error err : errors) {
            messages.add(err.getStatusCode() + ': ' + err.getMessage());
        }
        return String.join(messages, '; ');
    }
}
