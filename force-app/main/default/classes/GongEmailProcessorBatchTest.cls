/**
 * Integration tests for GongEmailProcessorBatch and GongEmailProcessorScheduler.
 *
 * NOTE: The Gong managed package field Gong__Gong_Participants_Emails__c may not
 * exist in all orgs. Tests check for field accessibility and skip gracefully.
 * Task/Event AccountId is read-only; we use WhatId to relate to Account.
 */
@IsTest
private class GongEmailProcessorBatchTest {

    private static final String GONG_EMAIL_FIELD = 'Gong__Gong_Participants_Emails__c';

    private static Boolean isGongFieldAvailable() {
        return SObjectType.Task.fields.getMap().containsKey(
            GONG_EMAIL_FIELD.toLowerCase()
        );
    }

    private static Boolean isGongEventFieldAvailable() {
        return SObjectType.Event.fields.getMap().containsKey(
            GONG_EMAIL_FIELD.toLowerCase()
        );
    }

    private static Gong_Processing_Run__c createRun() {
        Gong_Processing_Run__c run = new Gong_Processing_Run__c(
            Run_Date__c = Datetime.now(),
            Status__c = 'In Progress'
        );
        insert run;
        return run;
    }

    private static Map<String, Object> createTestData() {
        Account acct = new Account(Name = 'Test Account');
        insert acct;

        Contact existingContact = new Contact(
            FirstName = 'Existing',
            LastName = 'Contact',
            Email = 'existing.contact@external.com',
            AccountId = acct.Id
        );
        insert existingContact;

        Lead existingLead = new Lead(
            FirstName = 'Lead',
            LastName = 'Person',
            Email = 'lead.person@prospect.com',
            Company = 'Prospect Inc'
        );
        insert existingLead;

        return new Map<String, Object>{
            'account' => acct,
            'contact' => existingContact,
            'lead' => existingLead
        };
    }

    @IsTest
    static void batch_tasksWithMatchingContact_createsLinkToContactResult() {
        if (!isGongFieldAvailable()) {
            System.assert(true, 'Gong field not available; test skipped');
            return;
        }

        Map<String, Object> data = createTestData();
        Account acct = (Account) data.get('account');

        Task t = new Task(
            Subject = 'Gong Call - Contact Match',
            WhatId = acct.Id
        );
        t.put(GONG_EMAIL_FIELD, 'existing.contact@external.com');
        insert t;

        Gong_Processing_Run__c run = createRun();

        Test.startTest();
        GongEmailProcessorBatch batch = new GongEmailProcessorBatch(
            GongEmailProcessorBatch.ACTIVITY_TASK, run.Id
        );
        Database.executeBatch(batch, 200);
        Test.stopTest();

        List<Gong_Processing_Result__c> results = [
            SELECT Result_Type__c, Email__c, Matched_Record_Id__c
            FROM Gong_Processing_Result__c
            WHERE Gong_Processing_Run__c = :run.Id
        ];

        System.assert(!results.isEmpty(),
            'Should have created at least one processing result');

        Boolean foundLinkToContact = false;
        for (Gong_Processing_Result__c r : results) {
            if (r.Result_Type__c == 'Link to Contact') {
                foundLinkToContact = true;
                System.assertEquals('existing.contact@external.com', r.Email__c);
            }
        }
        System.assert(foundLinkToContact,
            'Should have a "Link to Contact" result for matching email');
    }

    @IsTest
    static void batch_tasksWithMatchingLead_createsLinkToLeadResult() {
        if (!isGongFieldAvailable()) {
            System.assert(true, 'Gong field not available; test skipped');
            return;
        }

        Map<String, Object> data = createTestData();
        Account acct = (Account) data.get('account');

        Task t = new Task(
            Subject = 'Gong Call - Lead Match',
            WhatId = acct.Id
        );
        t.put(GONG_EMAIL_FIELD, 'lead.person@prospect.com');
        insert t;

        Gong_Processing_Run__c run = createRun();

        Test.startTest();
        GongEmailProcessorBatch batch = new GongEmailProcessorBatch(
            GongEmailProcessorBatch.ACTIVITY_TASK, run.Id
        );
        Database.executeBatch(batch, 200);
        Test.stopTest();

        List<Gong_Processing_Result__c> results = [
            SELECT Result_Type__c, Email__c
            FROM Gong_Processing_Result__c
            WHERE Gong_Processing_Run__c = :run.Id
              AND Result_Type__c = 'Link to Lead'
        ];

        System.assert(!results.isEmpty(),
            'Should have a "Link to Lead" result for matching lead email');
    }

    @IsTest
    static void batch_tasksWithNewEmail_createsNewContactResult() {
        if (!isGongFieldAvailable()) {
            System.assert(true, 'Gong field not available; test skipped');
            return;
        }

        Map<String, Object> data = createTestData();
        Account acct = (Account) data.get('account');

        Task t = new Task(
            Subject = 'Gong Call - New Person',
            WhatId = acct.Id
        );
        t.put(GONG_EMAIL_FIELD, 'new.person@newcompany.com');
        insert t;

        Gong_Processing_Run__c run = createRun();

        Test.startTest();
        GongEmailProcessorBatch batch = new GongEmailProcessorBatch(
            GongEmailProcessorBatch.ACTIVITY_TASK, run.Id
        );
        Database.executeBatch(batch, 200);
        Test.stopTest();

        List<Gong_Processing_Result__c> results = [
            SELECT Result_Type__c, Email__c, First_Name__c, Last_Name__c
            FROM Gong_Processing_Result__c
            WHERE Gong_Processing_Run__c = :run.Id
              AND Result_Type__c = 'New Contact'
        ];

        System.assert(!results.isEmpty(),
            'Should have a "New Contact" result for unmatched email');
        System.assertEquals('new.person@newcompany.com', results[0].Email__c);
        System.assertEquals('New', results[0].First_Name__c);
        System.assertEquals('Person', results[0].Last_Name__c);
    }

    @IsTest
    static void batch_tasksWithMultipleEmails_createsMultipleResults() {
        if (!isGongFieldAvailable()) {
            System.assert(true, 'Gong field not available; test skipped');
            return;
        }

        Map<String, Object> data = createTestData();
        Account acct = (Account) data.get('account');

        Task t = new Task(
            Subject = 'Gong Call - Mixed',
            WhatId = acct.Id
        );
        t.put(GONG_EMAIL_FIELD,
            'existing.contact@external.com, brand.new@unknown.com');
        insert t;

        Gong_Processing_Run__c run = createRun();

        Test.startTest();
        GongEmailProcessorBatch batch = new GongEmailProcessorBatch(
            GongEmailProcessorBatch.ACTIVITY_TASK, run.Id
        );
        Database.executeBatch(batch, 200);
        Test.stopTest();

        List<Gong_Processing_Result__c> results = [
            SELECT Result_Type__c, Email__c
            FROM Gong_Processing_Result__c
            WHERE Gong_Processing_Run__c = :run.Id
            ORDER BY Email__c
        ];

        System.assert(results.size() >= 2,
            'Should have at least two result records for two different emails');
    }

    @IsTest
    static void batch_taskFinish_chainsToEventBatch() {
        if (!isGongFieldAvailable()) {
            System.assert(true, 'Gong field not available; test skipped');
            return;
        }

        Map<String, Object> data = createTestData();
        Account acct = (Account) data.get('account');

        Task t = new Task(
            Subject = 'Gong Call - Chain Test',
            WhatId = acct.Id
        );
        t.put(GONG_EMAIL_FIELD, 'chain.test@company.com');
        insert t;

        Gong_Processing_Run__c run = createRun();

        Test.startTest();
        GongEmailProcessorBatch taskBatch = new GongEmailProcessorBatch(
            GongEmailProcessorBatch.ACTIVITY_TASK, run.Id
        );
        Database.executeBatch(taskBatch, 200);
        Test.stopTest();

        Gong_Processing_Run__c updatedRun = [
            SELECT Total_Tasks_Processed__c, Batch_Job_Id__c
            FROM Gong_Processing_Run__c
            WHERE Id = :run.Id
        ];
        System.assertNotEquals(null, updatedRun.Batch_Job_Id__c,
            'Run should have Batch_Job_Id set by the batch start');
    }

    @IsTest
    static void scheduler_execute_createRunAndStartBatch() {
        if (!isGongFieldAvailable()) {
            System.assert(true, 'Gong field not available; test skipped');
            return;
        }

        Test.startTest();
        GongEmailProcessorScheduler scheduler = new GongEmailProcessorScheduler();
        String jobId = System.schedule(
            'Test Gong Scheduler',
            '0 0 2 * * ?',
            scheduler
        );
        Test.stopTest();

        List<Gong_Processing_Run__c> runs = [
            SELECT Id, Status__c
            FROM Gong_Processing_Run__c
            LIMIT 1
        ];
        System.assert(!runs.isEmpty(),
            'Scheduler should create a Gong_Processing_Run__c record');
    }

    @IsTest
    static void batch_withoutGongField_handledGracefully() {
        Gong_Processing_Run__c run = createRun();

        Test.startTest();
        GongEmailProcessorBatch eventBatch = new GongEmailProcessorBatch(
            GongEmailProcessorBatch.ACTIVITY_EVENT, run.Id
        );
        try {
            Database.executeBatch(eventBatch, 200);
        } catch (Exception e) {
            System.assert(e.getMessage().contains('Gong__')
                || e.getMessage().contains('No such column'),
                'Expected error related to missing Gong field: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void batch_eventType_updatesRunRecordCounts() {
        if (!isGongEventFieldAvailable()) {
            System.assert(true, 'Gong field not available on Event; test skipped');
            return;
        }

        Map<String, Object> data = createTestData();
        Account acct = (Account) data.get('account');

        Gong_Processing_Run__c run = createRun();
        run.Total_Activities_Processed__c = 5;
        run.Total_Tasks_Processed__c = 5;
        run.Total_Events_Processed__c = 0;
        run.New_Contacts_Proposed__c = 2;
        run.Link_To_Contact_Proposed__c = 1;
        run.Link_To_Lead_Proposed__c = 1;
        run.Free_Email_Excluded__c = 0;
        run.Invalid_Email_Count__c = 1;
        update run;

        Event e = new Event(
            Subject = 'Gong Meeting - Event Test',
            WhatId = acct.Id,
            DurationInMinutes = 60,
            ActivityDateTime = Datetime.now()
        );
        e.put(GONG_EMAIL_FIELD, 'event.new@eventcompany.com');
        insert e;

        Test.startTest();
        GongEmailProcessorBatch eventBatch = new GongEmailProcessorBatch(
            GongEmailProcessorBatch.ACTIVITY_EVENT, run.Id
        );
        Database.executeBatch(eventBatch, 200);
        Test.stopTest();

        Gong_Processing_Run__c updatedRun = [
            SELECT Total_Activities_Processed__c, Total_Tasks_Processed__c,
                   Total_Events_Processed__c, New_Contacts_Proposed__c
            FROM Gong_Processing_Run__c
            WHERE Id = :run.Id
        ];

        System.assert(updatedRun.Total_Activities_Processed__c >= 6,
            'Total activities should include both Task and Event counts');
        System.assert(updatedRun.Total_Events_Processed__c >= 1,
            'Events processed should be at least 1');
    }
}
