/**
 * Batch Apex processor for Gong email matching.
 * Processes orphaned Tasks/Events (no WhoId) that have Gong participant emails.
 * Matches emails against existing Contacts/Leads and creates processing result records.
 *
 * Since QueryLocator cannot UNION Task and Event, this batch accepts an activityType
 * parameter. The Task batch chains to the Event batch in finish().
 */
public with sharing class GongEmailProcessorBatch
    implements Database.Batchable<SObject>, Database.Stateful {

    public static final String ACTIVITY_TASK = 'Task';
    public static final String ACTIVITY_EVENT = 'Event';

    private static final String GONG_EMAIL_FIELD = 'Gong__Gong_Participants_Emails__c';

    // Stateful tracking
    private Id runId;
    private String activityType;
    private Integer totalActivities = 0;
    private Integer totalTasks = 0;
    private Integer totalEvents = 0;
    private Integer newContactCount = 0;
    private Integer linkToContactCount = 0;
    private Integer linkToLeadCount = 0;
    private Integer freeEmailCount = 0;
    private Integer invalidEmailCount = 0;
    private Integer internalEmailCount = 0;
    private String errorMessages = '';

    // Track emails already proposed as new contacts across execute() calls
    // to avoid duplicates within the same run
    private Set<String> processedNewEmails = new Set<String>();

    public GongEmailProcessorBatch(String actType, Id runId) {
        this.activityType = actType;
        this.runId = runId;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Update run record with batch job Id
        update new Gong_Processing_Run__c(
            Id = runId,
            Batch_Job_Id__c = bc.getJobId()
        );

        String query;
        if (activityType == ACTIVITY_TASK) {
            query = 'SELECT Id, Subject, AccountId, ' + GONG_EMAIL_FIELD
                  + ' FROM Task'
                  + ' WHERE ' + GONG_EMAIL_FIELD + ' != null'
                  + ' AND AccountId != null'
                  + ' AND WhoId = null';
        } else {
            query = 'SELECT Id, Subject, AccountId, ' + GONG_EMAIL_FIELD
                  + ' FROM Event'
                  + ' WHERE ' + GONG_EMAIL_FIELD + ' != null'
                  + ' AND AccountId != null'
                  + ' AND WhoId = null';
        }

        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        try {
            processScope(scope);
        } catch (Exception e) {
            errorMessages += 'Error in execute: ' + e.getMessage()
                          + ' | Stack: ' + e.getStackTraceString() + '\n';
        }
    }

    private void processScope(List<SObject> scope) {
        // 1. Collect unique cleaned emails from this scope
        Set<String> emailsInScope = new Set<String>();
        for (SObject activity : scope) {
            String emailField = (String) activity.get(GONG_EMAIL_FIELD);
            for (String rawEmail : GongEmailProcessorHelper.parseEmailField(emailField)) {
                String cleaned = GongEmailProcessorHelper.cleanEmail(rawEmail);
                if (GongEmailProcessorHelper.isValidEmail(cleaned)) {
                    emailsInScope.add(cleaned);
                }
            }
        }

        if (emailsInScope.isEmpty()) {
            // Still count activities even if no valid emails
            for (SObject activity : scope) {
                totalActivities++;
                if (activityType == ACTIVITY_TASK) {
                    totalTasks++;
                } else {
                    totalEvents++;
                }
            }
            return;
        }

        // 2. Query matching Contacts (scoped to emails in this batch)
        Map<String, Id> matchedContacts = new Map<String, Id>();
        Map<String, String> matchedContactNames = new Map<String, String>();
        for (Contact c : [SELECT Id, Email, Name FROM Contact
                          WHERE Email IN :emailsInScope]) {
            matchedContacts.put(c.Email.toLowerCase(), c.Id);
            matchedContactNames.put(c.Email.toLowerCase(), c.Name);
        }

        // 3. Query matching Leads (unconverted only)
        Map<String, Id> matchedLeads = new Map<String, Id>();
        Map<String, String> matchedLeadNames = new Map<String, String>();
        for (Lead l : [SELECT Id, Email, Name FROM Lead
                       WHERE Email IN :emailsInScope AND IsConverted = false]) {
            matchedLeads.put(l.Email.toLowerCase(), l.Id);
            matchedLeadNames.put(l.Email.toLowerCase(), l.Name);
        }

        // 4. Process each activity and create result records
        List<Gong_Processing_Result__c> results = new List<Gong_Processing_Result__c>();

        for (SObject activity : scope) {
            Id activityId = activity.Id;
            Id accountId = (Id) activity.get('AccountId');
            String subject = (String) activity.get('Subject');
            String emailField = (String) activity.get(GONG_EMAIL_FIELD);

            totalActivities++;
            if (activityType == ACTIVITY_TASK) {
                totalTasks++;
            } else {
                totalEvents++;
            }

            for (String rawEmail : GongEmailProcessorHelper.parseEmailField(emailField)) {
                String cleaned = GongEmailProcessorHelper.cleanEmail(rawEmail);
                String domain = GongEmailProcessorHelper.extractDomain(cleaned);

                Gong_Processing_Result__c result = new Gong_Processing_Result__c(
                    Gong_Processing_Run__c = runId,
                    Original_Email__c = rawEmail.trim(),
                    Email__c = cleaned,
                    Domain__c = domain,
                    Account__c = accountId,
                    Activity_Id__c = activityId,
                    Activity_Type__c = activityType,
                    Activity_Subject__c = subject != null
                        ? subject.abbreviate(255) : null,
                    Status__c = 'Pending Review'
                );

                // Classify the email
                if (!GongEmailProcessorHelper.isValidEmail(cleaned)) {
                    result.Result_Type__c = 'Invalid Email';
                    result.Status__c = 'Rejected';
                    invalidEmailCount++;
                } else if (GongEmailProcessorHelper.isInternalDomain(domain)) {
                    result.Result_Type__c = 'Internal Email';
                    result.Status__c = 'Rejected';
                    internalEmailCount++;
                } else if (GongEmailProcessorHelper.isFreeDomain(domain)) {
                    result.Result_Type__c = 'Free Email Excluded';
                    result.Status__c = 'Rejected';
                    freeEmailCount++;
                } else if (matchedContacts.containsKey(cleaned)) {
                    result.Result_Type__c = 'Link to Contact';
                    result.Matched_Record_Id__c = matchedContacts.get(cleaned);
                    result.Matched_Record_Name__c = matchedContactNames.get(cleaned);
                    result.Matched_Record_Type__c = 'Contact';
                    linkToContactCount++;
                } else if (matchedLeads.containsKey(cleaned)) {
                    result.Result_Type__c = 'Link to Lead';
                    result.Matched_Record_Id__c = matchedLeads.get(cleaned);
                    result.Matched_Record_Name__c = matchedLeadNames.get(cleaned);
                    result.Matched_Record_Type__c = 'Lead';
                    linkToLeadCount++;
                } else if (!processedNewEmails.contains(cleaned)) {
                    result.Result_Type__c = 'New Contact';
                    Map<String, String> names =
                        GongEmailProcessorHelper.inferNameFromEmail(cleaned);
                    result.First_Name__c = names.get('firstName');
                    result.Last_Name__c = names.get('lastName');
                    processedNewEmails.add(cleaned);
                    newContactCount++;
                } else {
                    // Already proposed in a previous execute() call, skip
                    continue;
                }

                results.add(result);
            }
        }

        // 5. Bulk insert results
        if (!results.isEmpty()) {
            Database.insert(results, false);
        }
    }

    public void finish(Database.BatchableContext bc) {
        // If this was the Task batch, chain to Event batch
        if (activityType == ACTIVITY_TASK) {
            updateRunRecord(false);
            Gong_Processor_Config__mdt config = GongEmailProcessorHelper.getConfig();
            Integer batchSize = config != null && config.Batch_Size__c != null
                ? Integer.valueOf(config.Batch_Size__c) : 200;
            GongEmailProcessorBatch eventBatch =
                new GongEmailProcessorBatch(ACTIVITY_EVENT, runId);
            Database.executeBatch(eventBatch, batchSize);
            return;
        }

        // Event batch - finalize
        updateRunRecord(true);

        // Chain to AI Analyzer if enabled
        Gong_Processor_Config__mdt config = GongEmailProcessorHelper.getConfig();
        if (config != null && config.AI_Enabled__c) {
            GongAIAnalyzerQueueable aiJob = new GongAIAnalyzerQueueable(runId);
            Id jobId = System.enqueueJob(aiJob);
            update new Gong_Processing_Run__c(
                Id = runId,
                Status__c = 'AI Processing',
                AI_Job_Id__c = jobId
            );
        }
    }

    private void updateRunRecord(Boolean isFinal) {
        Gong_Processing_Run__c run;

        // For Event batch, add to existing Task batch counts
        if (activityType == ACTIVITY_EVENT) {
            run = [
                SELECT Total_Activities_Processed__c, Total_Tasks_Processed__c,
                       Total_Events_Processed__c, New_Contacts_Proposed__c,
                       Link_To_Contact_Proposed__c, Link_To_Lead_Proposed__c,
                       Free_Email_Excluded__c, Invalid_Email_Count__c
                FROM Gong_Processing_Run__c WHERE Id = :runId
            ];
            totalActivities += safeInt(run.Total_Activities_Processed__c);
            totalTasks += safeInt(run.Total_Tasks_Processed__c);
            totalEvents += safeInt(run.Total_Events_Processed__c);
            newContactCount += safeInt(run.New_Contacts_Proposed__c);
            linkToContactCount += safeInt(run.Link_To_Contact_Proposed__c);
            linkToLeadCount += safeInt(run.Link_To_Lead_Proposed__c);
            freeEmailCount += safeInt(run.Free_Email_Excluded__c);
            invalidEmailCount += safeInt(run.Invalid_Email_Count__c);
        } else {
            run = new Gong_Processing_Run__c(Id = runId);
        }

        run.Total_Activities_Processed__c = totalActivities;
        run.Total_Tasks_Processed__c = totalTasks;
        run.Total_Events_Processed__c = totalEvents;
        run.New_Contacts_Proposed__c = newContactCount;
        run.Link_To_Contact_Proposed__c = linkToContactCount;
        run.Link_To_Lead_Proposed__c = linkToLeadCount;
        run.Free_Email_Excluded__c = freeEmailCount;
        run.Invalid_Email_Count__c = invalidEmailCount;

        if (isFinal) {
            run.Status__c = String.isBlank(errorMessages) ? 'Completed' : 'Completed';
            if (String.isNotBlank(errorMessages)) {
                run.Error_Message__c = errorMessages.abbreviate(32000);
            }
        }

        update run;
    }

    private static Integer safeInt(Decimal val) {
        return val != null ? val.intValue() : 0;
    }
}
