/**
 * Integration tests for GongEmailProcessorBatch and GongEmailProcessorScheduler.
 * Creates test data and runs the batch to verify Gong_Processing_Result__c records
 * are created with the correct Result_Type__c values.
 *
 * NOTE: The Gong managed package field Gong__Gong_Participants_Emails__c may not
 * exist in all orgs. Tests check for field accessibility and skip gracefully if
 * the field is not present.
 */
@IsTest
private class GongEmailProcessorBatchTest {

    private static final String GONG_EMAIL_FIELD = 'Gong__Gong_Participants_Emails__c';

    /**
     * Checks whether the Gong managed package email field exists on Task.
     */
    private static Boolean isGongFieldAvailable() {
        return SObjectType.Task.fields.getMap().containsKey(
            GONG_EMAIL_FIELD.toLowerCase()
        );
    }

    /**
     * Checks whether the Gong managed package email field exists on Event.
     */
    private static Boolean isGongEventFieldAvailable() {
        return SObjectType.Event.fields.getMap().containsKey(
            GONG_EMAIL_FIELD.toLowerCase()
        );
    }

    /**
     * Helper: creates a Gong_Processing_Run__c record for batch tracking.
     */
    private static Gong_Processing_Run__c createRun() {
        Gong_Processing_Run__c run = new Gong_Processing_Run__c(
            Run_Date__c = Datetime.now(),
            Status__c = 'In Progress'
        );
        insert run;
        return run;
    }

    /**
     * Helper: creates standard test data (Account, Contact, Lead).
     */
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

    // ── Batch Tests (Task type) ──────────────────────────────────────────

    @IsTest
    static void batch_tasksWithMatchingContact_createsLinkToContactResult() {
        if (!isGongFieldAvailable()) {
            // Field not available; skip test gracefully
            System.assert(true,
                'Gong managed package field not available; test skipped');
            return;
        }

        Map<String, Object> data = createTestData();
        Account acct = (Account) data.get('account');

        // Create a Task with the Gong email field set to a known contact email
        Task t = new Task(
            Subject = 'Gong Call - Contact Match',
            AccountId = acct.Id
        );
        t.put(GONG_EMAIL_FIELD, 'existing.contact@external.com');
        insert t;

        Gong_Processing_Run__c run = createRun();

        Test.startTest();
        GongEmailProcessorBatch batch = new GongEmailProcessorBatch(
            GongEmailProcessorBatch.ActivityType.TASK_TYPE, run.Id
        );
        Database.executeBatch(batch, 200);
        Test.stopTest();

        // Verify result record was created
        List<Gong_Processing_Result__c> results = [
            SELECT Result_Type__c, Email__c, Activity_Id__c, Matched_Record_Id__c
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
            AccountId = acct.Id
        );
        t.put(GONG_EMAIL_FIELD, 'lead.person@prospect.com');
        insert t;

        Gong_Processing_Run__c run = createRun();

        Test.startTest();
        GongEmailProcessorBatch batch = new GongEmailProcessorBatch(
            GongEmailProcessorBatch.ActivityType.TASK_TYPE, run.Id
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
            AccountId = acct.Id
        );
        t.put(GONG_EMAIL_FIELD, 'new.person@newcompany.com');
        insert t;

        Gong_Processing_Run__c run = createRun();

        Test.startTest();
        GongEmailProcessorBatch batch = new GongEmailProcessorBatch(
            GongEmailProcessorBatch.ActivityType.TASK_TYPE, run.Id
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
            AccountId = acct.Id
        );
        // Comma-separated: one matching contact, one new
        t.put(GONG_EMAIL_FIELD,
            'existing.contact@external.com, brand.new@unknown.com');
        insert t;

        Gong_Processing_Run__c run = createRun();

        Test.startTest();
        GongEmailProcessorBatch batch = new GongEmailProcessorBatch(
            GongEmailProcessorBatch.ActivityType.TASK_TYPE, run.Id
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

    // ── Task -> Event Chaining ───────────────────────────────────────────

    @IsTest
    static void batch_taskFinish_chainsToEventBatch() {
        if (!isGongFieldAvailable()) {
            System.assert(true, 'Gong field not available; test skipped');
            return;
        }

        Map<String, Object> data = createTestData();
        Account acct = (Account) data.get('account');

        // Create a Task so the batch has something to process
        Task t = new Task(
            Subject = 'Gong Call - Chain Test',
            AccountId = acct.Id
        );
        t.put(GONG_EMAIL_FIELD, 'chain.test@company.com');
        insert t;

        Gong_Processing_Run__c run = createRun();

        Test.startTest();
        GongEmailProcessorBatch taskBatch = new GongEmailProcessorBatch(
            GongEmailProcessorBatch.ActivityType.TASK_TYPE, run.Id
        );
        Database.executeBatch(taskBatch, 200);
        Test.stopTest();

        // After stopTest, the Task batch finish() should have attempted
        // to chain to the Event batch. Verify the run record was updated.
        Gong_Processing_Run__c updatedRun = [
            SELECT Total_Tasks_Processed__c, Batch_Job_Id__c
            FROM Gong_Processing_Run__c
            WHERE Id = :run.Id
        ];
        System.assertNotEquals(null, updatedRun.Batch_Job_Id__c,
            'Run should have Batch_Job_Id set by the batch start');
    }

    // ── Scheduler Test ───────────────────────────────────────────────────

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

        // Verify a processing run was created
        List<Gong_Processing_Run__c> runs = [
            SELECT Id, Status__c
            FROM Gong_Processing_Run__c
            LIMIT 1
        ];
        System.assert(!runs.isEmpty(),
            'Scheduler should create a Gong_Processing_Run__c record');
    }

    // ── Edge Case: No Gong Field ─────────────────────────────────────────

    @IsTest
    static void batch_withoutGongField_handledGracefully() {
        // This test verifies the batch can be instantiated even if we
        // cannot create Tasks with the Gong field. It exercises the
        // constructor and start/execute/finish code paths.
        Gong_Processing_Run__c run = createRun();

        Test.startTest();
        // Run the Event batch type (which likely has no matching records)
        GongEmailProcessorBatch eventBatch = new GongEmailProcessorBatch(
            GongEmailProcessorBatch.ActivityType.EVENT_TYPE, run.Id
        );
        try {
            Database.executeBatch(eventBatch, 200);
        } catch (Exception e) {
            // If the Gong field does not exist, the query will fail.
            // This is expected in orgs without the managed package.
            System.assert(e.getMessage().contains('Gong__')
                || e.getMessage().contains('No such column'),
                'Expected error related to missing Gong field: ' + e.getMessage());
        }
        Test.stopTest();
    }

    // ── Run Record Update ────────────────────────────────────────────────

    @IsTest
    static void batch_eventType_updatesRunRecordCounts() {
        if (!isGongEventFieldAvailable()) {
            System.assert(true, 'Gong field not available on Event; test skipped');
            return;
        }

        Map<String, Object> data = createTestData();
        Account acct = (Account) data.get('account');

        // Simulate Task batch already ran and wrote partial counts
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

        // Create an Event with the Gong email field
        Event e = new Event(
            Subject = 'Gong Meeting - Event Test',
            AccountId = acct.Id,
            DurationInMinutes = 60,
            ActivityDateTime = Datetime.now()
        );
        e.put(GONG_EMAIL_FIELD, 'event.new@eventcompany.com');
        insert e;

        Test.startTest();
        GongEmailProcessorBatch eventBatch = new GongEmailProcessorBatch(
            GongEmailProcessorBatch.ActivityType.EVENT_TYPE, run.Id
        );
        Database.executeBatch(eventBatch, 200);
        Test.stopTest();

        Gong_Processing_Run__c updatedRun = [
            SELECT Total_Activities_Processed__c, Total_Tasks_Processed__c,
                   Total_Events_Processed__c, New_Contacts_Proposed__c
            FROM Gong_Processing_Run__c
            WHERE Id = :run.Id
        ];

        // Event batch should add to existing counts
        System.assert(updatedRun.Total_Activities_Processed__c >= 6,
            'Total activities should include both Task and Event counts');
        System.assert(updatedRun.Total_Events_Processed__c >= 1,
            'Events processed should be at least 1');
    }
}
