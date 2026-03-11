/**
 * Tests for GongResultApplierBatch.
 * Verifies that approved processing results correctly:
 * - Create new Contact records for "New Contact" results
 * - Update Task/Event WhoId for "Link to Contact/Lead" results
 * - Handle DML errors gracefully
 */
@IsTest
private class GongResultApplierBatchTest {

    /**
     * Helper: creates an Account, Run, and optionally a Contact/Lead for linking.
     */
    private static Account createTestAccount() {
        Account acct = new Account(Name = 'Applier Test Account');
        insert acct;
        return acct;
    }

    private static Gong_Processing_Run__c createRun() {
        Gong_Processing_Run__c run = new Gong_Processing_Run__c(
            Run_Date__c = Datetime.now(),
            Status__c = 'Completed'
        );
        insert run;
        return run;
    }

    // ── New Contact Creation ─────────────────────────────────────────────

    @IsTest
    static void applier_newContactResult_createsContact() {
        Account acct = createTestAccount();
        Gong_Processing_Run__c run = createRun();

        Gong_Processing_Result__c result = new Gong_Processing_Result__c(
            Gong_Processing_Run__c = run.Id,
            Email__c = 'new.person@testcorp.com',
            First_Name__c = 'New',
            Last_Name__c = 'Person',
            Domain__c = 'testcorp.com',
            Account__c = acct.Id,
            Result_Type__c = 'New Contact',
            Status__c = 'Approved'
        );
        insert result;

        Test.startTest();
        Database.executeBatch(new GongResultApplierBatch(), 200);
        Test.stopTest();

        // Verify Contact was created
        List<Contact> contacts = [
            SELECT FirstName, LastName, Email, AccountId, LeadSource
            FROM Contact
            WHERE Email = 'new.person@testcorp.com'
        ];

        System.assertEquals(1, contacts.size(),
            'Should have created exactly one Contact');
        System.assertEquals('New', contacts[0].FirstName);
        System.assertEquals('Person', contacts[0].LastName);
        System.assertEquals(acct.Id, contacts[0].AccountId);
        System.assertEquals('Sales Tool Sourced', contacts[0].LeadSource);

        // Verify result was updated to Applied
        Gong_Processing_Result__c updatedResult = [
            SELECT Status__c, Matched_Record_Id__c, Matched_Record_Type__c
            FROM Gong_Processing_Result__c
            WHERE Id = :result.Id
        ];

        System.assertEquals('Applied', updatedResult.Status__c,
            'Result status should be Applied');
        System.assertNotEquals(null, updatedResult.Matched_Record_Id__c,
            'Matched_Record_Id should be set to new Contact Id');
        System.assertEquals('Contact', updatedResult.Matched_Record_Type__c,
            'Matched_Record_Type should be Contact');
    }

    @IsTest
    static void applier_newContactWithAINames_usesAICleanedNames() {
        Account acct = createTestAccount();
        Gong_Processing_Run__c run = createRun();

        Gong_Processing_Result__c result = new Gong_Processing_Result__c(
            Gong_Processing_Run__c = run.Id,
            Email__c = 'jdoe@testcorp.com',
            First_Name__c = 'J',
            Last_Name__c = 'Doe',
            AI_Cleaned_First_Name__c = 'Jennifer',
            AI_Cleaned_Last_Name__c = 'Doe',
            Domain__c = 'testcorp.com',
            Account__c = acct.Id,
            Result_Type__c = 'New Contact',
            Status__c = 'Approved'
        );
        insert result;

        Test.startTest();
        Database.executeBatch(new GongResultApplierBatch(), 200);
        Test.stopTest();

        List<Contact> contacts = [
            SELECT FirstName, LastName
            FROM Contact
            WHERE Email = 'jdoe@testcorp.com'
        ];

        System.assertEquals(1, contacts.size());
        System.assertEquals('Jennifer', contacts[0].FirstName,
            'Should use AI-cleaned first name when available');
        System.assertEquals('Doe', contacts[0].LastName,
            'Should use AI-cleaned last name when available');
    }

    @IsTest
    static void applier_multipleNewContacts_createsAll() {
        Account acct = createTestAccount();
        Gong_Processing_Run__c run = createRun();

        List<Gong_Processing_Result__c> results = new List<Gong_Processing_Result__c>();
        for (Integer i = 0; i < 5; i++) {
            results.add(new Gong_Processing_Result__c(
                Gong_Processing_Run__c = run.Id,
                Email__c = 'user' + i + '@testcorp.com',
                First_Name__c = 'User',
                Last_Name__c = 'Number' + i,
                Domain__c = 'testcorp.com',
                Account__c = acct.Id,
                Result_Type__c = 'New Contact',
                Status__c = 'Approved'
            ));
        }
        insert results;

        Test.startTest();
        Database.executeBatch(new GongResultApplierBatch(), 200);
        Test.stopTest();

        Integer contactCount = [
            SELECT COUNT()
            FROM Contact
            WHERE Email LIKE 'user%@testcorp.com'
        ];

        System.assertEquals(5, contactCount,
            'Should have created all 5 Contacts');

        List<Gong_Processing_Result__c> updatedResults = [
            SELECT Status__c
            FROM Gong_Processing_Result__c
            WHERE Gong_Processing_Run__c = :run.Id
              AND Status__c = 'Applied'
        ];
        System.assertEquals(5, updatedResults.size(),
            'All 5 results should be Applied');
    }

    // ── Link to Contact ──────────────────────────────────────────────────

    @IsTest
    static void applier_linkToContactTask_updatesTaskWhoId() {
        Account acct = createTestAccount();
        Contact existingContact = new Contact(
            FirstName = 'Existing',
            LastName = 'Contact',
            Email = 'existing@company.com',
            AccountId = acct.Id
        );
        insert existingContact;

        // Create a Task without WhoId (orphaned)
        Task t = new Task(
            Subject = 'Test Task Link',
            AccountId = acct.Id
        );
        insert t;

        Gong_Processing_Run__c run = createRun();

        Gong_Processing_Result__c result = new Gong_Processing_Result__c(
            Gong_Processing_Run__c = run.Id,
            Email__c = 'existing@company.com',
            Domain__c = 'company.com',
            Account__c = acct.Id,
            Activity_Id__c = t.Id,
            Activity_Type__c = 'Task',
            Result_Type__c = 'Link to Contact',
            Matched_Record_Id__c = existingContact.Id,
            Matched_Record_Type__c = 'Contact',
            Status__c = 'Approved'
        );
        insert result;

        Test.startTest();
        Database.executeBatch(new GongResultApplierBatch(), 200);
        Test.stopTest();

        // Verify Task WhoId was updated
        Task updatedTask = [SELECT WhoId FROM Task WHERE Id = :t.Id];
        System.assertEquals(existingContact.Id, updatedTask.WhoId,
            'Task WhoId should be set to the matched Contact');

        // Verify result status
        Gong_Processing_Result__c updatedResult = [
            SELECT Status__c
            FROM Gong_Processing_Result__c
            WHERE Id = :result.Id
        ];
        System.assertEquals('Applied', updatedResult.Status__c);
    }

    @IsTest
    static void applier_linkToContactEvent_updatesEventWhoId() {
        Account acct = createTestAccount();
        Contact existingContact = new Contact(
            FirstName = 'Existing',
            LastName = 'Contact',
            Email = 'existing@company.com',
            AccountId = acct.Id
        );
        insert existingContact;

        // Create an Event without WhoId
        Event e = new Event(
            Subject = 'Test Event Link',
            AccountId = acct.Id,
            DurationInMinutes = 30,
            ActivityDateTime = Datetime.now()
        );
        insert e;

        Gong_Processing_Run__c run = createRun();

        Gong_Processing_Result__c result = new Gong_Processing_Result__c(
            Gong_Processing_Run__c = run.Id,
            Email__c = 'existing@company.com',
            Domain__c = 'company.com',
            Account__c = acct.Id,
            Activity_Id__c = e.Id,
            Activity_Type__c = 'Event',
            Result_Type__c = 'Link to Contact',
            Matched_Record_Id__c = existingContact.Id,
            Matched_Record_Type__c = 'Contact',
            Status__c = 'Approved'
        );
        insert result;

        Test.startTest();
        Database.executeBatch(new GongResultApplierBatch(), 200);
        Test.stopTest();

        Event updatedEvent = [SELECT WhoId FROM Event WHERE Id = :e.Id];
        System.assertEquals(existingContact.Id, updatedEvent.WhoId,
            'Event WhoId should be set to the matched Contact');
    }

    // ── Link to Lead ─────────────────────────────────────────────────────

    @IsTest
    static void applier_linkToLead_updatesTaskWhoId() {
        Account acct = createTestAccount();
        Lead existingLead = new Lead(
            FirstName = 'Lead',
            LastName = 'Person',
            Email = 'lead@prospect.com',
            Company = 'Prospect Inc'
        );
        insert existingLead;

        Task t = new Task(
            Subject = 'Test Task Lead Link',
            AccountId = acct.Id
        );
        insert t;

        Gong_Processing_Run__c run = createRun();

        Gong_Processing_Result__c result = new Gong_Processing_Result__c(
            Gong_Processing_Run__c = run.Id,
            Email__c = 'lead@prospect.com',
            Domain__c = 'prospect.com',
            Account__c = acct.Id,
            Activity_Id__c = t.Id,
            Activity_Type__c = 'Task',
            Result_Type__c = 'Link to Lead',
            Matched_Record_Id__c = existingLead.Id,
            Matched_Record_Type__c = 'Lead',
            Status__c = 'Approved'
        );
        insert result;

        Test.startTest();
        Database.executeBatch(new GongResultApplierBatch(), 200);
        Test.stopTest();

        Task updatedTask = [SELECT WhoId FROM Task WHERE Id = :t.Id];
        System.assertEquals(existingLead.Id, updatedTask.WhoId,
            'Task WhoId should be set to the matched Lead');
    }

    // ── Error Handling ───────────────────────────────────────────────────

    @IsTest
    static void applier_missingMatchedRecordId_marksAsError() {
        Account acct = createTestAccount();

        Task t = new Task(
            Subject = 'Error Test Task',
            AccountId = acct.Id
        );
        insert t;

        Gong_Processing_Run__c run = createRun();

        // Result with blank Matched_Record_Id - should trigger error path
        Gong_Processing_Result__c result = new Gong_Processing_Result__c(
            Gong_Processing_Run__c = run.Id,
            Email__c = 'missing@company.com',
            Domain__c = 'company.com',
            Account__c = acct.Id,
            Activity_Id__c = t.Id,
            Activity_Type__c = 'Task',
            Result_Type__c = 'Link to Contact',
            Matched_Record_Id__c = null,
            Status__c = 'Approved'
        );
        insert result;

        Test.startTest();
        Database.executeBatch(new GongResultApplierBatch(), 200);
        Test.stopTest();

        Gong_Processing_Result__c updatedResult = [
            SELECT Status__c, Error_Message__c
            FROM Gong_Processing_Result__c
            WHERE Id = :result.Id
        ];

        System.assertEquals('Error', updatedResult.Status__c,
            'Result with missing Matched_Record_Id should be marked as Error');
        System.assert(
            String.isNotBlank(updatedResult.Error_Message__c),
            'Error message should be populated'
        );
    }

    @IsTest
    static void applier_missingActivityId_marksAsError() {
        Account acct = createTestAccount();
        Contact c = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@company.com',
            AccountId = acct.Id
        );
        insert c;

        Gong_Processing_Run__c run = createRun();

        // Result with blank Activity_Id - should trigger error path
        Gong_Processing_Result__c result = new Gong_Processing_Result__c(
            Gong_Processing_Run__c = run.Id,
            Email__c = 'test@company.com',
            Domain__c = 'company.com',
            Account__c = acct.Id,
            Activity_Id__c = null,
            Activity_Type__c = 'Task',
            Result_Type__c = 'Link to Contact',
            Matched_Record_Id__c = c.Id,
            Status__c = 'Approved'
        );
        insert result;

        Test.startTest();
        Database.executeBatch(new GongResultApplierBatch(), 200);
        Test.stopTest();

        Gong_Processing_Result__c updatedResult = [
            SELECT Status__c, Error_Message__c
            FROM Gong_Processing_Result__c
            WHERE Id = :result.Id
        ];

        System.assertEquals('Error', updatedResult.Status__c,
            'Result with missing Activity_Id should be marked as Error');
    }

    @IsTest
    static void applier_nonApprovedResults_areNotProcessed() {
        Account acct = createTestAccount();
        Gong_Processing_Run__c run = createRun();

        // Create results with non-Approved statuses
        List<Gong_Processing_Result__c> results = new List<Gong_Processing_Result__c>();
        results.add(new Gong_Processing_Result__c(
            Gong_Processing_Run__c = run.Id,
            Email__c = 'pending@testcorp.com',
            First_Name__c = 'Pending',
            Last_Name__c = 'Person',
            Domain__c = 'testcorp.com',
            Account__c = acct.Id,
            Result_Type__c = 'New Contact',
            Status__c = 'Pending Review'
        ));
        results.add(new Gong_Processing_Result__c(
            Gong_Processing_Run__c = run.Id,
            Email__c = 'rejected@testcorp.com',
            First_Name__c = 'Rejected',
            Last_Name__c = 'Person',
            Domain__c = 'testcorp.com',
            Account__c = acct.Id,
            Result_Type__c = 'New Contact',
            Status__c = 'Rejected'
        ));
        insert results;

        Test.startTest();
        Database.executeBatch(new GongResultApplierBatch(), 200);
        Test.stopTest();

        // Verify no Contacts were created for non-Approved results
        Integer contactCount = [
            SELECT COUNT()
            FROM Contact
            WHERE Email IN ('pending@testcorp.com', 'rejected@testcorp.com')
        ];
        System.assertEquals(0, contactCount,
            'No contacts should be created for non-Approved results');
    }

    @IsTest
    static void applier_noApprovedResults_completesWithoutError() {
        // Run the batch with no approved results at all
        Test.startTest();
        Database.executeBatch(new GongResultApplierBatch(), 200);
        Test.stopTest();

        // Simply verify no exception was thrown
        System.assert(true, 'Batch should complete without error when no data');
    }

    // ── Mixed Results ────────────────────────────────────────────────────

    @IsTest
    static void applier_mixedResultTypes_processesAllCorrectly() {
        Account acct = createTestAccount();

        Contact existingContact = new Contact(
            FirstName = 'Existing',
            LastName = 'Contact',
            Email = 'existing@company.com',
            AccountId = acct.Id
        );
        insert existingContact;

        Task t = new Task(
            Subject = 'Mixed Test Task',
            AccountId = acct.Id
        );
        insert t;

        Gong_Processing_Run__c run = createRun();

        // One "New Contact" and one "Link to Contact"
        List<Gong_Processing_Result__c> results = new List<Gong_Processing_Result__c>();
        results.add(new Gong_Processing_Result__c(
            Gong_Processing_Run__c = run.Id,
            Email__c = 'brand.new@newcorp.com',
            First_Name__c = 'Brand',
            Last_Name__c = 'New',
            Domain__c = 'newcorp.com',
            Account__c = acct.Id,
            Result_Type__c = 'New Contact',
            Status__c = 'Approved'
        ));
        results.add(new Gong_Processing_Result__c(
            Gong_Processing_Run__c = run.Id,
            Email__c = 'existing@company.com',
            Domain__c = 'company.com',
            Account__c = acct.Id,
            Activity_Id__c = t.Id,
            Activity_Type__c = 'Task',
            Result_Type__c = 'Link to Contact',
            Matched_Record_Id__c = existingContact.Id,
            Matched_Record_Type__c = 'Contact',
            Status__c = 'Approved'
        ));
        insert results;

        Test.startTest();
        Database.executeBatch(new GongResultApplierBatch(), 200);
        Test.stopTest();

        // Verify new contact created
        List<Contact> newContacts = [
            SELECT Id FROM Contact WHERE Email = 'brand.new@newcorp.com'
        ];
        System.assertEquals(1, newContacts.size(),
            'New Contact should be created');

        // Verify task linked
        Task updatedTask = [SELECT WhoId FROM Task WHERE Id = :t.Id];
        System.assertEquals(existingContact.Id, updatedTask.WhoId,
            'Task should be linked to existing contact');

        // Verify both results are Applied
        List<Gong_Processing_Result__c> appliedResults = [
            SELECT Status__c
            FROM Gong_Processing_Result__c
            WHERE Gong_Processing_Run__c = :run.Id
              AND Status__c = 'Applied'
        ];
        System.assertEquals(2, appliedResults.size(),
            'Both results should be Applied');
    }
}
